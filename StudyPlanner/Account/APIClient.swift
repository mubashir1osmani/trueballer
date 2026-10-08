import Foundation

/// Talks to the StudyPlanner Worker. Only note text, course names, the time
/// and the timezone are ever sent; tasks, grades and calendars stay on device.
struct APIClient {
    static let baseURL: URL = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? ""
        return URL(string: raw) ?? URL(string: "http://localhost:8787")!
    }()

    var token: String?
    var session: URLSession = .shared

    enum Failure: Error, Equatable {
        case unauthorized
        case consentRequired
        case upgradeRequired(feature: String)
        case quotaExceeded(limit: Int)
        case declined
        case unavailable
        case offline
    }

    struct SignInResponse: Decodable { let token: String; let expiresAt: Int; let isNewUser: Bool }

    struct PlanInfo: Decodable, Equatable {
        let id: String
        let name: String
        let dailyRequests: Int
        let features: [String]
    }

    struct Me: Decodable, Equatable {
        let plan: PlanInfo
        let usedToday: Int
        let aiConsent: Bool
    }

    struct NoteRequest: Encodable {
        let note: String
        let courses: [String]
        let now: String
        let timeZone: String

        init(note: String, courses: [String], now: Date = .now, timeZone: TimeZone = .current) {
            self.note = note
            self.courses = courses
            self.now = ISO8601DateFormatter.withOffset(timeZone).string(from: now)
            self.timeZone = timeZone.identifier
        }
    }

    struct CloudTask: Decodable {
        let title: String
        let courseName: String
        let dateTime: String
        let estimatedMinutes: Int
    }

    struct CaptureResult: Decodable {
        let supported: Bool
        let clarification: String
        let tasks: [CloudTask]
    }

    struct BraindumpResult: Decodable {
        let tasks: [CloudTask]
        let studyTime: String
        let blockMinutes: Int
        let dailyCapMinutes: Int
        let remindersMentioned: Bool
        let remindersEnabled: Bool
        let reminderLeadMinutes: Int
        let dayStartMinutes: Int
        let dayEndMinutes: Int
        let sleepHours: Double
    }

    private struct AIEnvelope<T: Decodable>: Decodable { let result: T; let remaining: Int }
    private struct ErrorBody: Decodable { let error: String; let feature: String?; let limit: Int? }

    func signIn(provider: String, idToken: String, nonce: String) async throws -> SignInResponse {
        try await send("POST", "v1/auth/signin", body: ["provider": provider, "idToken": idToken, "nonce": nonce])
    }

    func me() async throws -> Me { try await send("GET", "v1/me") }

    func setConsent(_ granted: Bool) async throws {
        struct Ack: Decodable { let aiConsent: Bool }
        let _: Ack = try await send("POST", "v1/me/consent", body: ["granted": granted])
    }

    func deleteAccount() async throws {
        struct Empty: Decodable {}
        let _: Empty? = try await sendOptional("DELETE", "v1/me")
    }

    func capture(_ request: NoteRequest) async throws -> (CaptureResult, remaining: Int) {
        let envelope: AIEnvelope<CaptureResult> = try await send("POST", "v1/ai/capture", body: request)
        return (envelope.result, envelope.remaining)
    }

    func braindump(_ request: NoteRequest) async throws -> (BraindumpResult, remaining: Int) {
        let envelope: AIEnvelope<BraindumpResult> = try await send("POST", "v1/ai/braindump", body: request)
        return (envelope.result, envelope.remaining)
    }

    // MARK: Transport

    private func send<T: Decodable>(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws -> T {
        guard let value: T = try await sendOptional(method, path, body: body) else { throw Failure.unavailable }
        return value
    }

    private func sendOptional<T: Decodable>(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws -> T? {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 45
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Failure.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 204 { return nil }
        guard (200..<300).contains(status) else { throw Self.failure(status: status, data: data) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func failure(status: Int, data: Data) -> Failure {
        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        switch (status, body?.error) {
        case (401, _): return .unauthorized
        case (403, "consent_required"): return .consentRequired
        case (402, _): return .upgradeRequired(feature: body?.feature ?? "")
        case (429, _): return .quotaExceeded(limit: body?.limit ?? 0)
        case (422, "declined"): return .declined
        default: return .unavailable
        }
    }
}

extension ISO8601DateFormatter {
    static func withOffset(_ timeZone: TimeZone) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

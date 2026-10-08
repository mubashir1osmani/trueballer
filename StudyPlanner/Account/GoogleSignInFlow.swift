import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Google sign-in through the system browser sheet with PKCE, so the app
/// needs no third-party SDK. Uses Google's iOS OAuth client, whose redirect is
/// the reversed client ID scheme registered in Info.plist.
@MainActor
final class GoogleSignInFlow: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum FlowError: Error { case cancelled, failed }

    private let clientID: String
    private let redirectScheme: String

    init?(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        guard let clientID = info["GoogleClientID"] as? String, !clientID.isEmpty,
              let scheme = info["GoogleRedirectScheme"] as? String, !scheme.hasSuffix(".unset") else { return nil }
        self.clientID = clientID
        self.redirectScheme = scheme
        super.init()
    }

    /// Returns Google's ID token and the raw nonce whose hash it carries.
    func run() async throws -> (idToken: String, nonce: String) {
        let verifier = AccountStore.randomNonce(length: 64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
        let nonce = AccountStore.randomNonce()
        let state = AccountStore.randomNonce()
        let redirectURI = "\(redirectScheme):/oauth2redirect"

        var auth = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        auth.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "nonce", value: AccountStore.sha256(nonce)),
            .init(name: "prompt", value: "select_account"),
        ]

        let callback = try await authenticate(url: auth.url!, scheme: redirectScheme)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else { throw FlowError.failed }

        var exchange = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        exchange.httpMethod = "POST"
        exchange.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "code", value: code),
            .init(name: "code_verifier", value: verifier),
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "redirect_uri", value: redirectURI),
        ]
        exchange.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: exchange)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FlowError.failed }
        struct TokenResponse: Decodable { let id_token: String }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        return (token.id_token, nonce)
    }

    private func authenticate(url: URL, scheme: String) async throws -> URL {
        let result = await webAuthentication(url: url, scheme: scheme, anchor: self)
        return try result.get()
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// Runs ASWebAuthenticationSession without `withChecked*Continuation`.
/// Built with Xcode 26, those link a Swift 6.2 runtime entry point that
/// iOS 18.0 doesn't ship, so the app crashed the moment sign-in started.
/// A stream delivers the one callback using API every iOS 17+ has.
@MainActor
private func webAuthentication(
    url: URL, scheme: String, anchor: ASWebAuthenticationPresentationContextProviding
) async -> Result<URL, GoogleSignInFlow.FlowError> {
    let (stream, delivery) = AsyncStream.makeStream(of: Result<URL, GoogleSignInFlow.FlowError>.self, bufferingPolicy: .bufferingNewest(1))
    let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
        if let callback { delivery.yield(.success(callback)) }
        else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { delivery.yield(.failure(.cancelled)) }
        else { delivery.yield(.failure(.failed)) }
        delivery.finish()
    }
    session.presentationContextProvider = anchor
    session.prefersEphemeralWebBrowserSession = true
    if !session.start() {
        delivery.yield(.failure(.failed))
        delivery.finish()
    }
    for await result in stream { return result }
    return .failure(.failed)
}

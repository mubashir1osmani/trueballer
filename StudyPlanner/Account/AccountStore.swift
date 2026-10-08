import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI

/// Signed-in state, plan, and the student's cloud-AI choice. Notes are sent
/// to Claude only when the student is signed in, has agreed on the consent
/// screen, and has not turned cloud AI off in Settings.
@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var token: String? = Keychain.read("session")
    @Published private(set) var me: APIClient.Me?
    @Published var cloudAIEnabled: Bool = UserDefaults.standard.object(forKey: "cloudAIEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(cloudAIEnabled, forKey: "cloudAIEnabled") }
    }
    @Published var errorMessage: String?
    /// Why the last AI draft didn't come from Claude, shown once on the preview.
    @Published var lastNotice: CloudAI.Notice?
    @Published private(set) var isWorking = false

    var isSignedIn: Bool { token != nil }
    var canUseCloudAI: Bool { isSignedIn && cloudAIEnabled && me?.aiConsent == true }
    var needsConsent: Bool { isSignedIn && me?.aiConsent == false }
    var client: APIClient { APIClient(token: token) }

    func has(_ feature: String) -> Bool { me?.plan.features.contains(feature) ?? false }

    func refresh() async {
        guard isSignedIn else { me = nil; return }
        do {
            me = try await client.me()
        } catch APIClient.Failure.unauthorized {
            signOut()
        } catch {
            // Keep the last known plan when offline.
        }
    }

    // MARK: Sign in with Apple

    private var pendingNonce: String?

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        pendingNonce = nonce
        request.requestedScopes = []
        request.nonce = Self.sha256(nonce)
    }

    func completeApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Apple sign-in didn't finish. Please try again."
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = pendingNonce else {
                errorMessage = "Apple sign-in didn't return a token."
                return
            }
            await finishSignIn(provider: "apple", idToken: idToken, nonce: nonce)
        }
    }

    // MARK: Sign in with Google (system browser, PKCE, no SDK)

    func signInWithGoogle() async {
        guard let flow = GoogleSignInFlow() else {
            errorMessage = "Google sign-in isn't set up in this build yet."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let (idToken, nonce) = try await flow.run()
            await finishSignIn(provider: "google", idToken: idToken, nonce: nonce)
        } catch GoogleSignInFlow.FlowError.cancelled {
        } catch {
            errorMessage = "Google sign-in didn't finish. Please try again."
        }
    }

    // MARK: Session

    private func finishSignIn(provider: String, idToken: String, nonce: String) async {
        isWorking = true
        defer { isWorking = false; pendingNonce = nil }
        do {
            let response = try await APIClient().signIn(provider: provider, idToken: idToken, nonce: nonce)
            Keychain.write(response.token, for: "session")
            token = response.token
            await refresh()
        } catch APIClient.Failure.offline {
            errorMessage = "You're offline. Connect to the internet to sign in."
        } catch {
            errorMessage = "Sign-in couldn't be confirmed. Please try again."
        }
    }

    func setConsent(_ granted: Bool) async {
        do {
            try await client.setConsent(granted)
            await refresh()
        } catch {
            errorMessage = "Your choice couldn't be saved. Please try again."
        }
    }

    func signOut() {
        Keychain.delete("session")
        token = nil
        me = nil
    }

    func deleteAccount() async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.deleteAccount()
            signOut()
            return true
        } catch {
            errorMessage = "Your account couldn't be deleted right now. Please try again."
            return false
        }
    }

    // MARK: Nonce

    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

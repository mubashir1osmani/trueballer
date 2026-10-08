import AuthenticationServices
import SwiftUI

/// Sign-in sheet. Signing in is optional: the app works fully without an
/// account, and an account only adds Claude reading your notes.
struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var account: AccountStore

    var body: some View {
        ZStack {
            AuraBackground()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.body.weight(.semibold))
                            .padding(10).background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 20)

                Spacer()

                VStack(alignment: .leading, spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22).fill(.ultraThinMaterial).frame(width: 72, height: 72)
                        Image(systemName: "sparkles").font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .symbolEffect(.pulse, options: .repeating)
                    }
                    .entrance(0)
                    Text("Your notes,\nturned into a plan.")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                        .entrance(1)
                    Text("Sign in so Claude can read your sticky notes and pull out deadlines. You review every task before it's saved.")
                        .font(.title3).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .entrance(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)

                Spacer()

                VStack(spacing: 12) {
                    SignInWithAppleButton(.continue) { request in
                        account.prepareAppleRequest(request)
                    } onCompletion: { result in
                        Task { await account.completeApple(result) }
                    }
                    .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .entrance(3)

                    Button { Task { await account.signInWithGoogle() } } label: {
                        HStack(spacing: 10) {
                            Text("G").font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(LinearGradient(colors: [.blue, .red, .yellow, .green], startPoint: .topLeading, endPoint: .bottomTrailing))
                            Text("Continue with Google").font(.system(size: 19, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("signin.google")
                    .entrance(4)

                    Label("Your tasks, grades and calendar never leave this phone.", systemImage: "lock.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .entrance(5)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .disabled(account.isWorking)
                .overlay { if account.isWorking { ProgressView().controlSize(.large) } }
            }
        }
        .onChange(of: account.isSignedIn) { if account.isSignedIn { dismiss() } }
        #if DEBUG
        .task {
            // DEBUG: AUTO_GOOGLE=1 starts Google sign-in so a simulator run can
            // exercise the web session without UI automation.
            if ProcessInfo.processInfo.environment["AUTO_GOOGLE"] == "1" {
                try? await Task.sleep(for: .seconds(1))
                await account.signInWithGoogle()
            }
        }
        #endif
        .alert("Sign-in", isPresented: Binding(get: { account.errorMessage != nil }, set: { if !$0 { account.errorMessage = nil } })) {
            Button("OK") { account.errorMessage = nil }
        } message: { Text(account.errorMessage ?? "") }
    }
}

#Preview {
    SignInView().environmentObject(AccountStore())
}

import SwiftUI

/// Shown once after sign-in, before any note is sent to Claude. States
/// exactly what leaves the phone and who processes it.
struct ConsentView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var account: AccountStore
    @State private var saving = false

    var body: some View {
        ZStack {
            AuraBackground().opacity(0.6)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Before Claude reads your notes")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .padding(.top, 40)
                        .entrance(0)

                    VStack(spacing: 12) {
                        row("paperplane.fill", "What's sent", "Only the note you organize, your course names, and today's date and time zone.", order: 1)
                        row("iphone", "What stays here", "Tasks, grades, focus history, and your calendar never leave this phone.", order: 2)
                        row("building.columns.fill", "Who reads it", "Anthropic's Claude, through our server. Anthropic doesn't train on it and deletes it within 30 days. We don't store your notes at all.", order: 3)
                        row("checkmark.shield.fill", "You stay in charge", "Claude only suggests. Nothing is saved until you confirm it, and you can turn this off in Settings any time.", order: 4)
                    }

                    VStack(spacing: 10) {
                        Button {
                            saving = true
                            Task { await account.setConsent(true); saving = false; dismiss() }
                        } label: {
                            Text("Turn on Claude").font(.headline)
                                .frame(maxWidth: .infinity).frame(height: 54)
                                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 16))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("consent.agree")

                        Button("Not now") {
                            account.cloudAIEnabled = false
                            dismiss()
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 8)
                    }
                    .disabled(saving)
                    .entrance(5)
                }
                .padding(24)
            }
        }
        .interactiveDismissDisabled(saving)
    }

    private func row(_ icon: String, _ title: String, _ detail: String, order: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(AppTheme.accent).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .entrance(order)
    }
}

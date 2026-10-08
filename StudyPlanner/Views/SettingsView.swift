import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allSettings: [UserSettings]

    var body: some View {
        NavigationStack {
            Form {
                if let settings = allSettings.first {
                    SettingsFormContent(settings: settings)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                // Fallback; RootView normally creates this at launch.
                if allSettings.isEmpty {
                    modelContext.insert(UserSettings())
                }
            }
        }
    }
}

private struct SettingsFormContent: View {
    @Bindable var settings: UserSettings
    @EnvironmentObject private var notifications: NotificationService
    @State private var showingPlan = false
    @State private var showingProgress = false

    var body: some View {
        AccountSection()

        Section {
            Button { showingProgress = true } label: {
                Label("Grades and progress", systemImage: "chart.line.uptrend.xyaxis")
            }
            .accessibilityIdentifier("settings.progress")
        } footer: {
            Text("Course grades and logged focus time. This stays in Settings until it is part of the daily loop.")
        }
        .sheet(isPresented: $showingProgress) {
            ProgressTabView(showsDismiss: true)
        }

        Section {
            Button { showingPlan = true } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("How you plan").foregroundStyle(.primary)
                    Text(settings.planNote.isEmpty ? "Say when you study, how long, and when to be reminded." : settings.planNote)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .accessibilityIdentifier("plan.open")
        } footer: {
            Text("Your words set the hours, the block length, and reminders. Suggestions follow that.")
        }
        .sheet(isPresented: $showingPlan) { PlanMyWayView(settings: settings) }

        Section {
            DatePicker("Day starts", selection: $settings.workdayStart, displayedComponents: .hourAndMinute)
            DatePicker("Day ends", selection: $settings.workdayEnd, displayedComponents: .hourAndMinute)
        } header: {
            Text("Working hours")
        } footer: {
            Text("Study blocks are only suggested inside these hours.")
        }

        Section {
            Stepper(value: $settings.sleepTargetHours, in: 5...12, step: 0.5) {
                HStack {
                    Text("Sleep target")
                    Spacer()
                    Text("\(settings.sleepTargetHours, specifier: "%.1f") h")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Rest")
        } footer: {
            Text("The planner won't schedule work that cuts into your sleep target.")
        }

        Section {
            Toggle("Due-date reminders", isOn: remindersBinding)
            if settings.remindersEnabled {
                Picker("Remind me", selection: $settings.reminderLeadMinutes) {
                    Text("30 minutes before").tag(30)
                    Text("1 hour before").tag(60)
                    Text("2 hours before").tag(120)
                    Text("1 day before").tag(24 * 60)
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            if notifications.authorizationStatus == .denied {
                Text("Notifications are off for StudyPlanner in iOS Settings. Turn them on there to get reminders.")
            } else {
                Text("One calm reminder per task, before it's due. Nothing else.")
            }
        }
    }

    /// Enabling requests permission first; the toggle only sticks if granted.
    private var remindersBinding: Binding<Bool> {
        Binding {
            settings.remindersEnabled
        } set: { enabled in
            guard enabled else {
                settings.remindersEnabled = false
                return
            }
            Task {
                settings.remindersEnabled = await notifications.requestPermission()
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [UserSettings.self], inMemory: true)
}

/// Sign-in, plan, the Claude switch, and account deletion.
private struct AccountSection: View {
    @EnvironmentObject private var account: AccountStore
    @State private var showingSignIn = false
    @State private var showingPlans = false
    @State private var showingConsent = false
    @State private var confirmingDelete = false

    var body: some View {
        Section {
            if account.isSignedIn {
                Button { showingPlans = true } label: {
                    HStack {
                        Label("Plan", systemImage: "sparkles")
                        Spacer()
                        Text(account.me?.plan.name ?? "Free").foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("account.plans")
                Toggle("Claude reads my notes", isOn: claudeBinding)
                    .accessibilityIdentifier("account.cloudAI")
                Button("Sign out") { account.signOut() }
                Button("Delete account", role: .destructive) { confirmingDelete = true }
            } else {
                Button { showingSignIn = true } label: {
                    Label("Sign in to use Claude", systemImage: "person.crop.circle.badge.plus")
                }
                .accessibilityIdentifier("account.signin")
            }
        } header: {
            Text("Account")
        } footer: {
            Text(account.isSignedIn
                 ? "When on, notes you organize are sent to Claude. Tasks, grades, and your calendar always stay on this phone."
                 : "Optional. Without an account, notes are read on this phone.")
        }
        .sheet(isPresented: $showingSignIn) { SignInView() }
        .sheet(isPresented: $showingPlans) { PlansView() }
        .sheet(isPresented: $showingConsent) { ConsentView() }
        .confirmationDialog("Delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await account.deleteAccount() } }
        } message: {
            Text("This removes your sign-in, plan and usage history from our server. Your tasks and notes on this phone are not affected.")
        }
        .onChange(of: account.isSignedIn) { if account.needsConsent { showingConsent = true } }
        .onChange(of: account.me) { if account.needsConsent && account.cloudAIEnabled { showingConsent = true } }
    }

    private var claudeBinding: Binding<Bool> {
        Binding {
            account.cloudAIEnabled && account.me?.aiConsent == true
        } set: { on in
            account.cloudAIEnabled = on
            if on && account.me?.aiConsent != true { showingConsent = true }
        }
    }
}

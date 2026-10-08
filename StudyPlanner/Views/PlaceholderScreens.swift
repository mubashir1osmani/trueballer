import SwiftUI

/// Gear button that opens Settings; lives on the Today screen.
struct SettingsToolbarButton: ToolbarContent {
    @State private var showingSettings = false

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settings.open")
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
}

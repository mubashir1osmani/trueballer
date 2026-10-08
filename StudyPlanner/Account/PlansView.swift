import SwiftUI

/// Plan comparison. Purchases go through the App Store (StoreKit) once the
/// products exist in App Store Connect; until then upgrade buttons explain
/// that paid plans are coming, and the server keeps every account on Free.
struct PlansView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var account: AccountStore
    @State private var selected = "plus"
    @State private var showingComingSoon = false

    struct Tier: Identifiable {
        let id: String
        let name: String
        let price: String
        let model: String
        let perks: [String]
        let colors: [Color]
    }

    private let tiers: [Tier] = [
        Tier(id: "free", name: "Free", price: "$0", model: "Claude Haiku",
             perks: ["15 note reads a day", "Turn sticky notes into tasks", "Fast and light"],
             colors: [Color(white: 0.55), Color(white: 0.4)]),
        Tier(id: "plus", name: "Plus", price: "$4.99/mo", model: "Claude Sonnet",
             perks: ["60 note reads a day", "Sharper deadline and course matching", "Weekly review of how your time went"],
             colors: [Color(red: 0.05, green: 0.55, blue: 0.50), Color(red: 0.20, green: 0.75, blue: 0.62)]),
        Tier(id: "pro", name: "Pro", price: "$9.99/mo", model: "Claude Opus",
             perks: ["150 note reads a day", "Planning coach you can talk to", "Everything in Plus"],
             colors: [Color(red: 0.40, green: 0.25, blue: 0.85), Color(red: 0.75, green: 0.35, blue: 0.85)]),
    ]

    private var currentPlan: String { account.me?.plan.id ?? "free" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Pick how much help you want.")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .entrance(0)
                    if let me = account.me {
                        usageMeter(used: me.usedToday, limit: me.plan.dailyRequests).entrance(1)
                    }
                    ForEach(Array(tiers.enumerated()), id: \.element.id) { index, tier in
                        card(tier).entrance(index + 2)
                    }
                    Text("Plans renew monthly through the App Store and can be cancelled any time in your Apple account settings. Every plan keeps your data on this phone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(AppTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .safeAreaInset(edge: .bottom) { cta }
            .alert("Paid plans are almost here", isPresented: $showingComingSoon) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Upgrades will open through the App Store soon. Free keeps working in the meantime.")
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func card(_ tier: Tier) -> some View {
        let isSelected = selected == tier.id
        return Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { selected = tier.id } } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tier.name).font(.title2.bold())
                    if tier.id == currentPlan {
                        Text("CURRENT").font(.caption2.weight(.heavy)).tracking(1)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.white.opacity(0.25), in: Capsule())
                    }
                    Spacer()
                    Text(tier.price).font(.headline)
                }
                Text(tier.model).font(.subheadline.weight(.semibold)).opacity(0.85)
                if isSelected {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(tier.perks, id: \.self) { perk in
                            Label(perk, systemImage: "checkmark.circle.fill").font(.subheadline)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: tier.colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(isSelected ? 0.9 : 0), lineWidth: 2))
            .scaleEffect(isSelected ? 1 : 0.98)
            .shadow(color: tier.colors[0].opacity(isSelected ? 0.4 : 0), radius: 18, y: 8)
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func usageMeter(used: Int, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(used) of \(limit) reads").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            ProgressView(value: Double(min(used, limit)), total: Double(max(limit, 1))).tint(AppTheme.accent)
        }
        .padding(16)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var cta: some View {
        if selected != currentPlan && selected != "free" {
            Button { showingComingSoon = true } label: {
                Text("Upgrade to \(tiers.first { $0.id == selected }?.name ?? "")").font(.headline)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, 20).padding(.bottom, 8)
            .background(.bar)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

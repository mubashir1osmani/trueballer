import SwiftUI

/// Slow, breathing color field used behind the account screens. iOS 18 gets a
/// true mesh gradient; iOS 17 gets drifting blurred orbs. Both hold still when
/// Reduce Motion is on.
struct AuraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private var palette: [Color] {
        scheme == .dark
            ? [Color(red: 0.02, green: 0.10, blue: 0.12), Color(red: 0.04, green: 0.30, blue: 0.30), Color(red: 0.16, green: 0.12, blue: 0.34)]
            : [Color(red: 0.86, green: 0.97, blue: 0.94), Color(red: 0.36, green: 0.80, blue: 0.72), Color(red: 0.70, green: 0.74, blue: 0.98)]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            if #available(iOS 18.0, *) {
                mesh(t)
            } else {
                orbs(t)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    @available(iOS 18.0, *)
    private func mesh(_ t: Double) -> some View {
        let wobble = { (phase: Double) in Float(sin(t * 0.35 + phase) * 0.12) }
        let (a, b, c) = (palette[0], palette[1], palette[2])
        return MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5 + wobble(0), 0.5 + wobble(1.7)], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [a, b, a, c, b, a, a, c, b]
        )
    }

    private func orbs(_ t: Double) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                palette[0]
                Circle().fill(palette[1]).frame(width: size.width * 0.9)
                    .offset(x: cos(t * 0.3) * 60, y: -size.height * 0.2 + sin(t * 0.25) * 40)
                Circle().fill(palette[2]).frame(width: size.width * 0.8)
                    .offset(x: sin(t * 0.22) * 70, y: size.height * 0.25 + cos(t * 0.3) * 50)
            }
            .blur(radius: 80)
        }
    }
}

/// Lifts and fades content in on first appearance, staggered by `order`.
struct Entrance: ViewModifier {
    var order: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(Double(order) * 0.08)) { shown = true }
            }
    }
}

extension View {
    func entrance(_ order: Int) -> some View { modifier(Entrance(order: order)) }
}

/// Springy press feedback for custom buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

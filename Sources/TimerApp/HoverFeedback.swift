import SwiftUI

extension EnvironmentValues {
    /// Bumped whenever the panel opens or resizes. A still cursor gets no exit event when the
    /// panel moves or swaps controls beneath it, so hover states clear here and re-light on the
    /// next pointer movement.
    @Entry var hoverReset = 0
}

extension View {
    /// Pure SwiftUI hover: no extra AppKit views inside the glass, whose interactive
    /// response would otherwise make the whole panel brighten.
    func trackingHover(_ action: @escaping (Bool) -> Void) -> some View {
        modifier(HoverModifier(action: action))
    }
}

private struct HoverModifier: ViewModifier {
    let action: (Bool) -> Void
    @Environment(\.hoverReset) private var reset

    func body(content: Content) -> some View {
        content
            // Continuous updates also catch a cursor that was already inside when the view appeared.
            .onContinuousHover { phase in
                switch phase {
                case .active: action(true)
                case .ended: action(false)
                }
            }
            .onChange(of: reset) { action(false) }
            .onDisappear { action(false) }
    }
}

struct QuietHoverButtonStyle: ButtonStyle {
    var horizontalPadding: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        QuietHoverButton(configuration: configuration, horizontalPadding: horizontalPadding)
    }
}

/// Hover state lives in a real view; @State on a ButtonStyle is not reliably retained.
private struct QuietHoverButton: View {
    let configuration: ButtonStyleConfiguration
    let horizontalPadding: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, horizontalPadding == 0 ? 0 : 5)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(isEnabled ? (configuration.isPressed ? 0.16 : (isHovered ? 0.09 : 0)) : 0))
                    .allowsHitTesting(false)
            }
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .trackingHover { isHovered = $0 }
    }
}

import SwiftUI

/// Passive hover decoration: no layout changes, repeated animation, or extra hit targets.
struct ControlHoverFeedback: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(isEnabled && isHovered ? 0.07 : 0))
                    .padding(-3)
                    .allowsHitTesting(false)
            }
            .onHover { isHovered = $0 }
    }
}

struct QuietHoverButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    var horizontalPadding: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
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
            .onHover { isHovered = $0 }
    }
}

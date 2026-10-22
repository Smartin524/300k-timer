import SwiftUI

/// Borderless button with press feedback only; no hover effect, so the glass panel stays still.
struct QuietButtonStyle: ButtonStyle {
    var horizontalPadding: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        QuietButton(configuration: configuration, horizontalPadding: horizontalPadding)
    }
}

private struct QuietButton: View {
    let configuration: ButtonStyleConfiguration
    let horizontalPadding: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, horizontalPadding == 0 ? 0 : 5)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(isEnabled && configuration.isPressed ? 0.16 : 0))
                    .allowsHitTesting(false)
            }
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

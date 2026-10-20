import AppKit
import TimerCore

/// A static, image-only status item; color and fill communicate the running state.
@MainActor
final class StatusSymbolController {
    private let imageView = StatusImageView()
    private weak var button: NSStatusBarButton?
    private var phase: FocusPhase = .idle

    init(button: NSStatusBarButton) {
        self.button = button
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        button.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 22),
            imageView.heightAnchor.constraint(equalToConstant: 22)
        ])

    }

    func setPhase(_ phase: FocusPhase) {
        self.phase = phase
        updateAppearance()
    }

    private func updateAppearance() {
        let name = phase == .running ? "hourglass.bottomhalf.filled" : "hourglass"
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 19, weight: .medium))
        // Let the native status button choose white/dark ink against the actual menu bar.
        if phase == .idle {
            symbol?.isTemplate = true
            imageView.isHidden = true
            button?.image = symbol
            button?.imagePosition = .imageOnly
        } else {
            button?.image = nil
            imageView.isHidden = false
            imageView.image = symbol
            // Softened toward white so the state reads without shouting in the menu bar.
            let base: NSColor = phase == .running ? .systemGreen : .systemOrange
            imageView.contentTintColor = base.blended(withFraction: 0.35, of: .white) ?? base
        }
        button?.setAccessibilityLabel("300k Timer，" + phase.title)
        button?.toolTip = phase.title + " · 点击打开"

    }
}

private final class StatusImageView: NSImageView {
    // Keep the status button's native click and highlight handling.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

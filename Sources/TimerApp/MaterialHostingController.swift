import AppKit
import SwiftUI

/// Keep the system backdrop at the window root, outside SwiftUI's compositing
/// and clipping. The hosting view contains only the controls and text.
@MainActor
final class MaterialHostingController<Content: View>: NSViewController {
    private let hostingView: NSHostingView<Content>

    init(rootView: Content) {
        hostingView = NSHostingView(rootView: rootView)
        hostingView.focusRingType = .none
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(rootView:)") }

    override func loadView() {
        // The popover material stays still while content redraws; the macOS 26+ glass
        // re-composited on every timer update, which read as the whole panel flickering.
        let surface = RoundedPopoverMaterial()
        surface.material = .popover
        surface.blendingMode = .behindWindow
        surface.state = .active
        // The popover material alone reads gray in light mode; a white wash brightens it.
        let wash = LightWash()
        wash.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(wash)
        NSLayoutConstraint.activate([
            wash.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            wash.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            wash.topAnchor.constraint(equalTo: surface.topAnchor),
            wash.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])
        surface.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: surface.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])
        view = surface
    }
}

private final class RoundedPopoverMaterial: NSVisualEffectView {
    private var maskedSize: NSSize = .zero

    override func layout() {
        super.layout()
        // Replacing the mask forces the effect to re-render; only do it when the size changes.
        guard bounds.width > 0, bounds.height > 0, bounds.size != maskedSize else { return }
        maskedSize = bounds.size
        // Mask the native effect itself, without flattening it in a SwiftUI layer.
        maskImage = NSImage(size: bounds.size, flipped: false) { [bounds] _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
            return true
        }
    }
}

/// Semi-opaque white over the material in light mode only; dark mode keeps the plain material.
private final class LightWash: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.backgroundColor = isDark ? nil : NSColor.white.withAlphaComponent(0.6).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

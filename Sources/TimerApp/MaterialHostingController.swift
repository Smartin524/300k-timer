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
        let surface: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 14
            // A static backdrop: the panel itself must not light up under the pointer.
            if #available(macOS 27.0, *) { glass.effectIsInteractive = false }
            // Match the backing's silhouette to the glass, so the window shadow
            // follows the rounded panel instead of exposing rectangular corners.
            glass.wantsLayer = true
            glass.layer?.cornerRadius = glass.cornerRadius
            glass.layer?.cornerCurve = .continuous
            glass.layer?.masksToBounds = true
            // contentView is the documented way to embed content in the effect.
            glass.contentView = hostingView
            surface = glass
        } else {
            let material = RoundedPopoverMaterial()
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            material.addSubview(hostingView)
            surface = material
        }
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
    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }
        // Mask the native effect itself, without flattening it in a SwiftUI layer.
        maskImage = NSImage(size: bounds.size, flipped: false) { [bounds] _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
            return true
        }
    }
}

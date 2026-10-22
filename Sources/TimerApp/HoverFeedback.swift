import AppKit
import SwiftUI

extension View {
    /// Reliable hover for a non-activating panel. SwiftUI's onHover only reacts to edge crossings,
    /// so it misses changes when the panel moves, resizes, hides, or swaps controls under a still
    /// cursor, and may not fire while the app is inactive. This re-checks the real cursor position.
    func trackingHover(_ action: @escaping (Bool) -> Void) -> some View {
        overlay(HoverTracker(onChange: action).allowsHitTesting(false))
    }
}

private struct HoverTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> HoverTrackingView {
        let view = HoverTrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: HoverTrackingView, context: Context) {
        view.onChange = onChange
    }
}

private final class HoverTrackingView: NSView {
    var onChange: ((Bool) -> Void)?
    private var isHovered = false
    private var observers: [NSObjectProtocol] = []

    // Purely observational: clicks pass through to the control underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // AppKit calls this whenever the view's geometry or visible rect changes.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        refresh()
    }

    override func mouseEntered(with event: NSEvent) { refresh() }
    override func mouseExited(with event: NSEvent) { refresh() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if let window {
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                         NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                         NSWindow.didChangeOcclusionStateNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                })
            }
        }
        refresh()
    }

    private func refresh() {
        let hovered: Bool
        if let window, window.isVisible, window.occlusionState.contains(.visible), !isHiddenOrHasHiddenAncestor {
            hovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        } else {
            hovered = false
        }
        guard hovered != isHovered else { return }
        isHovered = hovered
        // Report outside SwiftUI's update pass.
        DispatchQueue.main.async { [weak self] in self?.onChange?(hovered) }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
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

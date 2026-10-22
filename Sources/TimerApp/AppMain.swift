import AppKit
import SwiftUI
import Combine
import TimerCore
import Carbon.HIToolbox

@main
struct TimerApplication {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = FocusStore()
    private var statusItem: NSStatusItem!
    private var statusSymbol: StatusSymbolController!
    private var panel: FocusPanel!
    private var panelSizing: AnyCancellable?
    private var outsideClickMonitor: Any?
    private var subscription: AnyCancellable?
    private var noticeSizing: AnyCancellable?
    private var wasteSizing: AnyCancellable?
    private var historySizing: AnyCancellable?
    private var pendingPanelRequest = false
    private var toggleHotKey: GlobalHotKey?
    /// The panel was raised by an automatic pause, not by the user.
    private var panelShownForPause = false
    private var briefDismissal: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        LoginItem.ensureEnabled()
        // ⌥T starts or pauses from anywhere, the same as the panel's main button.
        toggleHotKey = GlobalHotKey(keyCode: kVK_ANSI_T, modifiers: optionKey) { [weak self] in self?.store.toggle() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.title = ""
            button.imagePosition = .noImage
            statusSymbol = StatusSymbolController(button: button)
        }
        panel = FocusPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "300k Timer"
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.contentViewController = MaterialHostingController(rootView: PanelView(store: store, dismissPanel: { [weak self] in self?.panel.orderOut(nil) }))
        panelSizing = store.$showsSettings.sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizePanel() }
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.panel.orderOut(nil)
        }
        subscription = store.$state.map(\.phase).removeDuplicates().sink { [weak self] phase in
            self?.statusSymbol.setPhase(phase)
        }
        noticeSizing = store.$pauseNotice.sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizePanel() }
        }
        wasteSizing = store.$showsWasteTime.sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizePanel() }
        }
        historySizing = store.$showsHistory.sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizePanel() }
        }
        store.onAutomaticPause = { [weak self] brief in
            guard let self else { return }
            self.store.showsSettings = false
            self.store.showsWasteTime = false
            self.showPanel()
            self.panelShownForPause = true
            guard brief else { return }
            let dismissal = DispatchWorkItem { [weak self] in self?.hidePanelShownForPause() }
            self.briefDismissal = dismissal
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: dismissal)
        }
        store.onAutomaticResume = { [weak self] in self?.hidePanelShownForPause() }
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let launchSource = launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        let isBackgroundLaunch = launchSource == keyAELaunchedAsLogInItem || launchSource == keyAELaunchedAsServiceItem
        // A manual cold launch must display the panel, just like reopening the running app.
        if pendingPanelRequest || CommandLine.arguments.contains("--show-panel") || !isBackgroundLaunch {
            showPanel()
        }
    }

    @objc private func togglePanel() {
        if panel.isVisible { panel.orderOut(nil) } else { showPanel() }
    }

    private func showPanel() {
        guard panel != nil else {
            // URL-open events may arrive before applicationDidFinishLaunching creates the panel.
            pendingPanelRequest = true
            return
        }
        pendingPanelRequest = false
        panelShownForPause = false
        briefDismissal?.cancel()
        store.refreshDay()
        store.hoverReset += 1
        resizePanel()
        positionPanel()
        // Keep the browser frontmost while inspecting statistics or handling a pause.
        // Activating this accessory app would interrupt foreground-only tracking.
        panel.makeKeyAndOrderFront(nil)
    }

    private func hidePanelShownForPause() {
        guard panelShownForPause else { return }
        panelShownForPause = false
        panel.orderOut(nil)
    }

    private func positionPanel() {
        guard let screen = statusItem?.button?.window?.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let anchor: NSRect?
        if let button = statusItem?.button, let window = button.window {
            // The button's bounds, not its hosting window, define the actual menu-bar anchor.
            anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        } else {
            anchor = nil
        }
        let centerX = anchor?.midX ?? visible.maxX - panel.frame.width / 2 - 6
        let x = min(max(centerX - panel.frame.width / 2, visible.minX + 6), visible.maxX - panel.frame.width - 6)
        // Attach the panel directly to the bottom of the menu-bar button, with no artificial gap.
        let top = anchor?.minY ?? visible.maxY
        panel.setFrameOrigin(NSPoint(x: x, y: top - panel.frame.height))
    }

    private func resizePanel() {
        guard let view = panel?.contentViewController?.view else { return }
        if panel.isVisible { store.hoverReset += 1 }
        panel.setContentSize(view.fittingSize)
        panel.invalidateShadow()
        if panel.isVisible { positionPanel() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "timer300k" }) { showPanel() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { store.shutdown() }
}

// A real panel stays available when menu-bar items move or become hidden behind the notch.
private final class FocusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

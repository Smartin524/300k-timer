import ServiceManagement
import SwiftUI

/// Open at login through the system's own login-item registry (System Settings → 登录项).
@MainActor
enum LoginItem {
    private static let defaultAppliedKey = "loginItemDefaultApplied"

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Enabled once by default; later choices, here or in System Settings, are respected.
    static func applyDefault() {
        guard !UserDefaults.standard.bool(forKey: defaultAppliedKey) else { return }
        UserDefaults.standard.set(true, forKey: defaultAppliedKey)
        set(true)
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("300k Timer login item change failed: %@", error.localizedDescription)
        }
        return isEnabled
    }
}

struct LoginItemToggle: View {
    @State private var isOn = LoginItem.isEnabled

    var body: some View {
        Toggle("开机时打开", isOn: Binding(get: { isOn }, set: { isOn = LoginItem.set($0) }))
            .toggleStyle(.switch).controlSize(.mini)
            .onAppear { isOn = LoginItem.isEnabled }
    }
}

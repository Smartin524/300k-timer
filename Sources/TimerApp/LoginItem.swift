import ServiceManagement

/// Always open at login, through the system's login-item registry (System Settings → 登录项).
@MainActor
enum LoginItem {
    static func ensureEnabled() {
        // Only register when absent, so a pending approval is not prompted again on every launch.
        guard [.notRegistered, .notFound].contains(SMAppService.mainApp.status) else { return }
        do { try SMAppService.mainApp.register() } catch {
            NSLog("300k Timer login item registration failed: %@", error.localizedDescription)
        }
    }
}

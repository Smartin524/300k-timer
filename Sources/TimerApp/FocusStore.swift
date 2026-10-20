import AppKit
import Combine
import CoreGraphics
import TimerCore

@MainActor
final class FocusStore: ObservableObject {
    @Published private(set) var state: FocusState
    @Published private(set) var storageError: String?
    /// Unreadable records must never be replaced; a failed write is retried on the next save.
    private var loadFailed = false
    @Published private(set) var websiteWarning: String?
    private let chromeMonitor = ChromeMonitor()
    private var runGeneration = 0
    @Published var showsSettings = false
    @Published var pauseNotice: String?
    /// `brief`: show the reason only momentarily (website pauses need no decision).
    var onAutomaticPause: ((_ brief: Bool) -> Void)?
    var onAutomaticResume: (() -> Void)?
    private var timer: Timer?
    private var tickCount = 0
    private var monitoringStartedAt: Date?
    private var lastObservedInput = Date.distantPast
    private var resumeEligibleAfter = Date().addingTimeInterval(-3)
    private var browserTimer: Timer?
    private var browserGeneration = 0
    private var lastBrowserSave = Date()
    private var lastBrowserObservation: (date: Date, blocked: Bool)?
    private var wasteTracker = WasteTimeTracker()
    @Published private(set) var wasteSite: WasteSite?
    @Published var showsWasteTime = false
    private var isSleeping = false
    private var isLocked = false
    private var isSessionActive = true
    private var globalInputMonitor: Any?
    private var localInputMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("300k Timer", isDirectory: true)
        fileURL = directory.appendingPathComponent("focus-state.json")
        var initial = FocusState()
        var loadError: String?
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                initial = try JSONDecoder().decode(FocusState.self, from: Data(contentsOf: fileURL))
            }
        } catch { loadError = "记录读取失败，请保留原始文件并检查磁盘权限。" }
        initial.recoverAfterLaunch()
        state = initial
        storageError = loadError
        loadFailed = loadError != nil
        // Catch a night's sleep that happened while the app was closed.
        noteInput()
        scheduleTimer(running: false)
        // Mouse and scroll monitoring does not require keyboard monitoring permission.
        let pointerEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown,
            .otherMouseDown, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]
        globalInputMonitor = NSEvent.addGlobalMonitorForEvents(matching: pointerEvents) { [weak self] _ in
            self?.observeActivity()
        }
        localInputMonitor = NSEvent.addLocalMonitorForEvents(matching: pointerEvents.union([.keyDown, .flagsChanged])) { [weak self] event in
            self?.observeActivity()
            return event
        }
        let center = NSWorkspace.shared.notificationCenter
        func observe(_ event: NSNotification.Name, action: @escaping @MainActor (FocusStore) -> Void) {
            observers.append(center.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
                // Handle synchronously: willSleep must pause and save before the system sleeps.
                MainActor.assumeIsolated {
                    guard let self else { return }
                    action(self)
                }
            })
        }
        observe(NSWorkspace.willSleepNotification) {
            $0.isSleeping = true
            $0.interruptBrowserObservation()
            $0.pause(reason: "电脑已休眠。", automatic: true, alert: false, resumeOnActivity: true)
        }
        observe(NSWorkspace.didWakeNotification) {
            $0.isSleeping = false
            $0.refreshDay()
            $0.attemptAutomaticResume()
        }
        observe(NSWorkspace.sessionDidResignActiveNotification) {
            $0.isSessionActive = false
            $0.interruptBrowserObservation()
            $0.pause(reason: "已切换用户。", automatic: true, alert: false, resumeOnActivity: true)
        }
        observe(NSWorkspace.sessionDidBecomeActiveNotification) {
            $0.isSessionActive = true
            $0.refreshDay()
            $0.attemptAutomaticResume()
        }
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append(DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isLocked = locked
                    if locked {
                        self.interruptBrowserObservation()
                        self.pause(reason: "屏幕已锁定。", automatic: true, alert: false, resumeOnActivity: true)
                    } else {
                        self.refreshDay()
                        self.attemptAutomaticResume()
                    }
                }
            })
        }
        observe(NSWorkspace.didActivateApplicationNotification) {
            $0.interruptBrowserObservation()
            $0.inspectBrowser()
        }
        browserTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.inspectBrowser() }
        }
        browserTimer?.tolerance = 0.2
        persist()
    }

    var today: TimeInterval { state.todaySeconds() }
    var totalSeconds: TimeInterval { state.secondsByDay.values.reduce(0, +) }
    var dailyRecords: [(day: String, seconds: TimeInterval)] {
        state.studySecondsByDay().filter { $0.value > 0 }
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, seconds: $0.value) }
    }
    func toggle() {
        if state.isRunning { pause(reason: "已暂停", automatic: false) }
        else { resume() }
    }

    func resume() {
        guard !state.isRunning else { return }
        noteInput()
        pauseNotice = nil
        runGeneration += 1
        monitoringStartedAt = Date()
        state.start(at: Date())
        scheduleTimer(running: true)
        persist()
    }

    func updateSettings(_ update: (inout FocusSettings) -> Void) {
        update(&state.settings)
        persist()
    }

    func pause(reason: String, automatic: Bool, alert: Bool = true, briefAlert: Bool = false,
               credit: Bool = true, resumeOnActivity: Bool = false) {
        if !automatic { state.cancelAutomaticResume() }
        guard state.isRunning else {
            scheduleTimer(running: false)
            persist()
            return
        }
        resumeEligibleAfter = Date()
        runGeneration += 1
        state.pause(at: Date(), reason: reason, automatic: automatic, creditUntilPause: credit, resumeOnActivity: resumeOnActivity)
        scheduleTimer(running: false)
        persist()
        if automatic && alert {
            pauseNotice = reason
            onAutomaticPause?(briefAlert)
        }
    }

    private func scheduleTimer(running: Bool) {
        timer?.invalidate()
        let interval: TimeInterval = running ? 1 : (state.resumeWhenActive == true ? 2 : 30)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = interval <= 2 ? 0.2 : 3
    }

    private func tick() {
        tickCount += 1
        noteInput()
        if !state.isRunning { refreshDay() }
        if state.isRunning {
            // A single event-source counter can disagree with actual hardware activity.
            // Any recent source is sufficient evidence that the user is still present.
            let hardwareIdle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .null)
            let sessionIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
            let now = Date()
            let idle = min(hardwareIdle, sessionIdle, max(0, now.timeIntervalSince(lastObservedInput)))
            if IdlePolicy.shouldPause(systemIdle: idle, runDuration: now.timeIntervalSince(monitoringStartedAt ?? now), threshold: Double(state.settings.idleMinutes * 60)) {
                state.discardIdleTime(since: now.addingTimeInterval(-idle))
                pause(reason: "连续 \(state.settings.idleMinutes) 分钟没有键鼠操作。", automatic: true, credit: false, resumeOnActivity: true)
                return
            }
            if let previous = state.lastTick, Date().timeIntervalSince(previous) > 15 {
                pause(reason: "检测到电脑休眠或计时中断，已暂停。", automatic: true, credit: false, resumeOnActivity: true)
                return
            }
            state.tick(at: Date())
            if tickCount % 10 == 0 { persist() }
        } else {
            attemptAutomaticResume()
            objectWillChange.send()
        }
    }

    func keepPaused() {
        state.cancelAutomaticResume()
        pauseNotice = nil
        runGeneration += 1
        scheduleTimer(running: false)
        persist()
    }

    func refreshDay() {
        if state.refreshStudyDay(at: Date()) {
            pauseNotice = nil
            persist()
        }
    }

    private func observeActivity() {
        // Pointer events arrive at display rate; half-second resolution is plenty for idle checks.
        let now = Date()
        guard now.timeIntervalSince(lastObservedInput) >= 0.5 else { return }
        lastObservedInput = now
        noteInput(at: now)
        guard state.resumeWhenActive == true, !state.isRunning else { return }
        // Let a local button action (especially "keep paused") finish first.
        Task { @MainActor [weak self] in self?.attemptAutomaticResume() }
    }

    private func attemptAutomaticResume() {
        let now = Date()
        // A night's sleep clears the session and cancels resuming before it is considered.
        noteInput(at: now)
        guard state.resumeWhenActive == true, !state.isRunning, !loadFailed,
              !isSleeping, !isLocked, isSessionActive else { return }
        let idle = inputIdle(at: now)
        guard AutomaticResumePolicy.shouldResume(waiting: state.resumeWhenActive == true,
            sessionAvailable: !isSleeping && !isLocked && isSessionActive,
            idle: idle, now: now, eligibleAfter: resumeEligibleAfter) else { return }
        refreshDay()
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome" else {
            resume()
            onAutomaticResume?()
            return
        }
        // Use the shared browser observation; when it is stale (checks stop while idle),
        // read the tab now so returning activity resumes without waiting for a later poll.
        guard let observation = lastBrowserObservation, now.timeIntervalSince(observation.date) < 3 else {
            inspectBrowser()
            return
        }
        guard !observation.blocked else { return }
        resume()
        onAutomaticResume?()
    }

    private func inputIdle(at now: Date) -> TimeInterval {
        min(CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .null),
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null),
            max(0, now.timeIntervalSince(lastObservedInput)))
    }

    /// Feed the latest input time to sleep detection.
    private func noteInput(at now: Date = Date()) {
        let idle = inputIdle(at: now)
        guard idle.isFinite, idle >= 0, state.observeInput(at: now.addingTimeInterval(-idle)) else { return }
        pauseNotice = nil
        scheduleTimer(running: state.isRunning)
        persist()
    }

    private func recordWaste(site: WasteSite?, at now: Date = Date()) {
        var ledger = state.wasteTime ?? WasteTimeState()
        wasteTracker.observe(at: now, site: site, idle: inputIdle(at: now), state: &ledger)
        if ledger != state.wasteTime { state.wasteTime = ledger }
        if wasteSite != wasteTracker.activeSite { wasteSite = wasteTracker.activeSite }
        if now.timeIntervalSince(lastBrowserSave) >= 10 {
            lastBrowserSave = now
            persist()
        }
    }

    /// Callers that change timing state persist themselves; recordWaste saves at most every 10 s.
    private func interruptBrowserObservation() {
        browserGeneration += 1
        lastBrowserObservation = nil
        recordWaste(site: nil)
    }

    private func inspectBrowser() {
        let now = Date()
        guard !isSleeping, !isLocked, isSessionActive,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome",
              inputIdle(at: now) < 300 else {
            lastBrowserObservation = nil
            recordWaste(site: nil, at: now)
            return
        }
        let generation = browserGeneration
        chromeMonitor.inspect { [weak self] address, error in
            guard let self, generation == self.browserGeneration,
                  !self.isSleeping, !self.isLocked, self.isSessionActive,
                  NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome" else { return }
            if let error {
                self.websiteWarning = error == -1743
                    ? "网站检测需要授权：系统设置 → 隐私与安全性 → 自动化 → 允许访问 Chrome"
                    : "暂时无法检测 Chrome 当前标签页"
                self.lastBrowserObservation = nil
                self.recordWaste(site: nil)
                return
            }
            self.websiteWarning = nil
            guard let address, !address.isEmpty else {
                self.lastBrowserObservation = nil
                self.recordWaste(site: nil)
                return
            }
            let blockedSite = DistractionPolicy.siteName(for: address)
            self.lastBrowserObservation = (Date(), blockedSite != nil)
            self.recordWaste(site: WasteSite.match(address))
            if self.state.isRunning, let blockedSite {
                self.pause(reason: "正在浏览\(blockedSite)。", automatic: true, briefAlert: true)
            } else {
                self.attemptAutomaticResume()
            }
        }
    }

    func shutdown() {
        if let globalInputMonitor { NSEvent.removeMonitor(globalInputMonitor) }
        if let localInputMonitor { NSEvent.removeMonitor(localInputMonitor) }
        globalInputMonitor = nil
        localInputMonitor = nil
        timer?.invalidate()
        browserTimer?.invalidate()
        interruptBrowserObservation()
        state.prepareForShutdown(at: Date())
        persist()
    }

    private func persist() {
        // Do not replace unreadable original data with a blank state.
        guard !loadFailed else { return }
        do {
            try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
            if storageError != nil { storageError = nil }
        } catch { storageError = "保存失败，将在下次保存时重试：\(error.localizedDescription)" }
    }

}

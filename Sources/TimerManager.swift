import Foundation
import Combine
import UserNotifications
import AppKit

class TimerManager: ObservableObject {
    @Published var timeRemaining: TimeInterval
    @Published var totalTime: TimeInterval
    @Published var isRunning = false
    @Published var currentPhase: Phase = .work
    @Published var workSessionsCompleted: Int = 0
    @Published var isBlockingActive = false

    enum Phase: String {
        case work = "Focus"
        case shortBreak = "Short Break"
        case longBreak = "Long Break"
    }

    private var timer: AnyCancellable?
    private var sessionStartTime: Date?
    private var elapsedBeforePause: TimeInterval = 0
    private var lastResumeTime: Date?
    private var settingsSubscriptions = Set<AnyCancellable>()

    var sessionStore: SessionStore?
    var settings: AppSettings? {
        didSet { observeSettingsChanges() }
    }

    // MARK: - Computed durations from settings

    private var workDuration: TimeInterval {
        (settings?.workMinutes ?? 25) * 60
    }

    private var shortBreakDuration: TimeInterval {
        (settings?.shortBreakMinutes ?? 5) * 60
    }

    private var longBreakDuration: TimeInterval {
        (settings?.longBreakMinutes ?? 15) * 60
    }

    private var sessionsBeforeLongBreak: Int {
        settings?.sessionsBeforeLongBreak ?? 4
    }

    init() {
        self.totalTime = 25 * 60
        self.timeRemaining = 25 * 60
        requestNotificationPermission()
    }

    /// Call after connecting settings to sync initial durations
    func applySettings() {
        guard !isRunning && elapsedBeforePause == 0 else { return }
        setTimeForCurrentPhase()
    }

    // MARK: - Display

    var progress: Double {
        guard totalTime > 0 else { return 0 }
        return 1.0 - (timeRemaining / totalTime)
    }

    var timeString: String {
        let total = Int(timeRemaining)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Whether the timer is actively counting or paused mid-session
    var isActive: Bool {
        isRunning || timeRemaining < totalTime
    }

    var menuBarTimeText: String {
        if !isRunning {
            return "⏸ \(timeString)"
        }
        return timeString
    }

    var currentCyclePosition: Int {
        (workSessionsCompleted % sessionsBeforeLongBreak) + 1
    }

    // MARK: - Controls

    func start() {
        if sessionStartTime == nil {
            sessionStartTime = Date()
        }
        lastResumeTime = Date()
        isRunning = true
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
        updateBlocking()
    }

    func pause() {
        if let resumeTime = lastResumeTime {
            elapsedBeforePause += Date().timeIntervalSince(resumeTime)
        }
        lastResumeTime = nil
        isRunning = false
        timer?.cancel()
        timer = nil
    }

    func reset() {
        timer?.cancel()
        timer = nil
        isRunning = false
        elapsedBeforePause = 0
        lastResumeTime = nil
        sessionStartTime = nil
        setTimeForCurrentPhase()
        // Always unblock on full reset
        if isBlockingActive {
            isBlockingActive = false
            DispatchQueue.global(qos: .userInitiated).async {
                SiteBlocker.unblockAll()
            }
        }
    }

    func skip() {
        timer?.cancel()
        timer = nil
        isRunning = false
        elapsedBeforePause = 0
        lastResumeTime = nil
        sessionStartTime = nil
        advancePhase()
        updateBlocking()
    }

    // MARK: - Private

    private func tick() {
        guard let resumeTime = lastResumeTime else { return }
        let currentElapsed = elapsedBeforePause + Date().timeIntervalSince(resumeTime)
        timeRemaining = max(0, totalTime - currentElapsed)

        if timeRemaining <= 0 {
            completePhase()
        }
    }

    private func completePhase() {
        timer?.cancel()
        timer = nil
        isRunning = false

        // Record the completed session
        if let start = sessionStartTime {
            let sessionType: WorkSession.SessionType = switch currentPhase {
            case .work: .work
            case .shortBreak: .shortBreak
            case .longBreak: .longBreak
            }
            let session = WorkSession(
                startTime: start,
                durationMinutes: totalTime / 60.0,
                type: sessionType
            )
            sessionStore?.addSession(session)
        }

        elapsedBeforePause = 0
        lastResumeTime = nil
        sessionStartTime = nil

        // Notify user
        sendNotification()
        if settings?.soundEnabled ?? true {
            NSSound(named: "Glass")?.play()
        }

        // Move to next phase
        advancePhase()
        updateBlocking()

        // Auto-start if enabled
        if let settings = settings {
            let shouldAutoStart: Bool
            switch currentPhase {
            case .work:
                shouldAutoStart = settings.autoStartWork
            case .shortBreak, .longBreak:
                shouldAutoStart = settings.autoStartBreaks
            }
            if shouldAutoStart {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.start()
                }
            }
        }
    }

    private func advancePhase() {
        switch currentPhase {
        case .work:
            workSessionsCompleted += 1
            if workSessionsCompleted % sessionsBeforeLongBreak == 0 {
                currentPhase = .longBreak
            } else {
                currentPhase = .shortBreak
            }
        case .shortBreak, .longBreak:
            currentPhase = .work
        }
        setTimeForCurrentPhase()
    }

    private func setTimeForCurrentPhase() {
        switch currentPhase {
        case .work:
            totalTime = workDuration
        case .shortBreak:
            totalTime = shortBreakDuration
        case .longBreak:
            totalTime = longBreakDuration
        }
        timeRemaining = totalTime
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Site Blocking

    /// Watch for changes to blocking-related settings and re-apply mid-session
    private func observeSettingsChanges() {
        settingsSubscriptions.removeAll()
        guard let settings = settings else { return }

        // Debounce all blocking-related changes (0.8s) so rapid edits
        // (e.g. adding multiple domains) coalesce into one blocking call
        settings.$blockedSites
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(800), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reapplyBlockingIfNeeded() }
            .store(in: &settingsSubscriptions)

        settings.$siteBlockingEnabled
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reapplyBlockingIfNeeded() }
            .store(in: &settingsSubscriptions)

        settings.$blockDuringBreaks
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reapplyBlockingIfNeeded() }
            .store(in: &settingsSubscriptions)
    }

    /// Called when settings change mid-session — forces a full re-apply
    private func reapplyBlockingIfNeeded() {
        guard isActive else { return }
        // Reset flag so updateBlocking will re-apply with the new domain list
        if isBlockingActive {
            isBlockingActive = false
        }
        updateBlocking()
    }

    func updateBlocking() {
        guard let settings = settings,
              settings.siteBlockingEnabled,
              !settings.blockedSites.isEmpty else {
            if isBlockingActive {
                isBlockingActive = false
                DispatchQueue.global(qos: .userInitiated).async {
                    SiteBlocker.unblockAll()
                }
            }
            return
        }

        let shouldBlock: Bool
        switch currentPhase {
        case .work:
            shouldBlock = isActive
        case .shortBreak, .longBreak:
            shouldBlock = settings.blockDuringBreaks && isActive
        }

        if shouldBlock && !isBlockingActive {
            isBlockingActive = true
            let domains = settings.blockedSites
            DispatchQueue.global(qos: .userInitiated).async {
                SiteBlocker.block(domains: domains)
            }
        } else if !shouldBlock && isBlockingActive {
            isBlockingActive = false
            DispatchQueue.global(qos: .userInitiated).async {
                SiteBlocker.unblockAll()
            }
        }
    }

    private func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Lock-In"
        // Notification is about the phase that just COMPLETED (before advancePhase)
        switch currentPhase {
        case .work:
            content.body = "Great focus session! Time for a break."
        case .shortBreak, .longBreak:
            content.body = "Break's over — ready to focus?"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

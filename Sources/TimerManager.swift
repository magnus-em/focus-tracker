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

    // Label for the current / upcoming session
    @Published var currentLabel: String = ""
    // Label of the session that just finished (shown in the completion panel)
    @Published var lastCompletedLabel: String? = nil

    // Flow-decision state
    @Published var isAwaitingFlowDecision = false
    @Published var flowDecisionCountdown = 10

    // Pause auto-finalize state
    @Published var pauseStartedAt: Date? = nil
    @Published var pauseRemainingSeconds: Double = 0
    private var pauseStaleSubscription: AnyCancellable?

    enum Phase: String {
        case work = "Focus"
        case shortBreak = "Short Break"
        case longBreak = "Long Break"
    }

    private var timer: AnyCancellable?
    private var flowCountdownSubscription: AnyCancellable?
    private var sessionStartTime: Date?
    private var elapsedBeforePause: TimeInterval = 0
    private var lastResumeTime: Date?
    private var settingsSubscriptions = Set<AnyCancellable>()
    private let completionPanel = CompletionPanel()
    private var tickCount = 0
    private static let checkpointKey = "timerCheckpoint"

    var sessionStore: SessionStore?
    var settings: AppSettings? {
        didSet { observeSettingsChanges() }
    }

    // MARK: - Computed durations

    private var workDuration: TimeInterval { (settings?.workMinutes ?? 25) * 60 }
    private var shortBreakDuration: TimeInterval { (settings?.shortBreakMinutes ?? 5) * 60 }
    private var longBreakDuration: TimeInterval { (settings?.longBreakMinutes ?? 15) * 60 }
    private var sessionsBeforeLongBreak: Int { settings?.sessionsBeforeLongBreak ?? 4 }

    init() {
        self.totalTime = 25 * 60
        self.timeRemaining = 25 * 60
        requestNotificationPermission()
    }

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
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var isActive: Bool { isRunning || timeRemaining < totalTime }

    var menuBarTimeText: String {
        isRunning ? timeString : "⏸ \(timeString)"
    }

    var currentCyclePosition: Int {
        (workSessionsCompleted % sessionsBeforeLongBreak) + 1
    }

    // MARK: - Controls

    func start() {
        cancelPauseGrace()
        if sessionStartTime == nil { sessionStartTime = Date() }
        lastResumeTime = Date()
        isRunning = true
        tickCount = 0
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
        updateBlocking()
        saveCheckpoint()
    }

    func pause() {
        if let resumeTime = lastResumeTime {
            elapsedBeforePause += Date().timeIntervalSince(resumeTime)
        }
        lastResumeTime = nil
        isRunning = false
        timer?.cancel()
        timer = nil
        saveCheckpoint()
        // Only arm auto-finalize for work phases that have meaningful elapsed time
        if currentPhase == .work && sessionStartTime != nil {
            startPauseGrace()
        }
    }

    // MARK: - Pause auto-finalize

    private var pauseGraceSeconds: Double {
        Double(max(1, settings?.pauseGraceMinutes ?? 10)) * 60
    }

    private func startPauseGrace() {
        pauseStartedAt = Date()
        pauseRemainingSeconds = pauseGraceSeconds
        pauseStaleSubscription = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tickPauseGrace() }
    }

    private func tickPauseGrace() {
        guard let started = pauseStartedAt else { return }
        let elapsed = Date().timeIntervalSince(started)
        pauseRemainingSeconds = max(0, pauseGraceSeconds - elapsed)
        if pauseRemainingSeconds <= 0 {
            finalizeStalePause()
        }
    }

    private func cancelPauseGrace() {
        pauseStaleSubscription?.cancel()
        pauseStaleSubscription = nil
        pauseStartedAt = nil
        pauseRemainingSeconds = 0
    }

    /// Save the partial work session and return to idle. Called when the
    /// pause grace runs out — bathroom break safe, leaving the desk auto-ends.
    private func finalizeStalePause() {
        cancelPauseGrace()
        let elapsed = elapsedBeforePause
        if elapsed >= 60, currentPhase == .work, let start = sessionStartTime {
            sessionStore?.addSession(WorkSession(
                startTime: start,
                durationMinutes: elapsed / 60.0,
                type: .work,
                label: currentLabel.isEmpty ? nil : currentLabel
            ))
        }
        currentLabel = ""
        elapsedBeforePause = 0
        lastResumeTime = nil
        sessionStartTime = nil
        clearCheckpoint()
        setTimeForCurrentPhase()
        unblockIfNeeded()
        sendStaleEndedNotification()
    }

    private func sendStaleEndedNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Focus"
        content.body = "Paused too long — session ended and saved."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    /// Convenience for the global hotkey — toggle between running and paused
    /// without affecting committed-sessions state. If timer is idle, no-op.
    func toggleRunPause() {
        if isRunning { pause() }
        else if isActive { start() }
    }

    func reset() {
        if isAwaitingFlowDecision {
            cancelFlowDecision()
            setTimeForCurrentPhase()
            unblockIfNeeded()
            return
        }

        cancelPauseGrace()

        var elapsed = elapsedBeforePause
        if let resumeTime = lastResumeTime { elapsed += Date().timeIntervalSince(resumeTime) }

        timer?.cancel()
        timer = nil
        isRunning = false

        if elapsed >= 60, currentPhase == .work, let start = sessionStartTime {
            sessionStore?.addSession(WorkSession(
                startTime: start,
                durationMinutes: elapsed / 60.0,
                type: .work,
                label: currentLabel.isEmpty ? nil : currentLabel
            ))
        }

        currentLabel = ""
        elapsedBeforePause = 0
        lastResumeTime = nil
        sessionStartTime = nil
        clearCheckpoint()
        setTimeForCurrentPhase()
        unblockIfNeeded()
    }

    func skip() {
        if isAwaitingFlowDecision {
            takeBreak()
            return
        }

        cancelPauseGrace()

        // Capture partial elapsed time so a skipped work session still counts.
        var elapsed = elapsedBeforePause
        if let resumeTime = lastResumeTime { elapsed += Date().timeIntervalSince(resumeTime) }

        timer?.cancel()
        timer = nil
        isRunning = false

        if elapsed >= 60, currentPhase == .work, let start = sessionStartTime {
            sessionStore?.addSession(WorkSession(
                startTime: start,
                durationMinutes: elapsed / 60.0,
                type: .work,
                label: currentLabel.isEmpty ? nil : currentLabel
            ))
        }

        currentLabel = ""
        elapsedBeforePause = 0
        lastResumeTime = nil
        sessionStartTime = nil
        clearCheckpoint()
        advancePhase()
        updateBlocking()
    }

    func adjustDuration(by minutes: Double) {
        let newRemaining = timeRemaining + minutes * 60
        guard newRemaining > 5 else { completePhase(); return }
        totalTime = max(60, totalTime + minutes * 60)
        timeRemaining = newRemaining
    }

    func setSessionDuration(_ minutes: Double) {
        guard !isActive else { return }
        totalTime = minutes * 60
        timeRemaining = minutes * 60
    }

    // MARK: - Flow decision

    func keepGoing() {
        cancelFlowDecision()
        workSessionsCompleted += 1
        currentLabel = ""
        setTimeForCurrentPhase()
        start()
    }

    func takeBreak() {
        cancelFlowDecision()
        currentLabel = ""
        advancePhase()
        updateBlocking()
        handleAutoStart()
    }

    private func cancelFlowDecision() {
        isAwaitingFlowDecision = false
        flowCountdownSubscription?.cancel()
        flowCountdownSubscription = nil
        completionPanel.dismiss()
    }

    private func startFlowCountdown() {
        flowDecisionCountdown = 10
        flowCountdownSubscription = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.flowDecisionCountdown -= 1
                if self.flowDecisionCountdown <= 0 { self.takeBreak() }
            }
    }

    // MARK: - Private timer logic

    private func tick() {
        guard let resumeTime = lastResumeTime else { return }
        let elapsed = elapsedBeforePause + Date().timeIntervalSince(resumeTime)
        timeRemaining = max(0, totalTime - elapsed)
        if timeRemaining <= 0 { completePhase(); return }
        tickCount += 1
        if tickCount % 60 == 0 { saveCheckpoint() } // every 30 seconds
    }

    private func completePhase() {
        timer?.cancel()
        timer = nil
        isRunning = false

        if let start = sessionStartTime {
            let sessionType: WorkSession.SessionType = switch currentPhase {
            case .work: .work
            case .shortBreak: .shortBreak
            case .longBreak: .longBreak
            }
            sessionStore?.addSession(WorkSession(
                startTime: start,
                durationMinutes: totalTime / 60.0,
                type: sessionType,
                label: currentLabel.isEmpty ? nil : currentLabel
            ))
        }

        elapsedBeforePause = 0
        lastResumeTime = nil
        sessionStartTime = nil
        clearCheckpoint()

        sendNotification()
        if settings?.soundEnabled ?? true { NSSound(named: "Glass")?.play() }

        if currentPhase == .work {
            lastCompletedLabel = currentLabel.isEmpty ? nil : currentLabel
            isAwaitingFlowDecision = true
            startFlowCountdown()
            completionPanel.show(timer: self)
        } else {
            advancePhase()
            updateBlocking()
            handleAutoStart()
        }
    }

    private func advancePhase() {
        switch currentPhase {
        case .work:
            workSessionsCompleted += 1
            currentPhase = workSessionsCompleted % sessionsBeforeLongBreak == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            currentPhase = .work
        }
        setTimeForCurrentPhase()
    }

    private func setTimeForCurrentPhase() {
        switch currentPhase {
        case .work:      totalTime = workDuration
        case .shortBreak: totalTime = shortBreakDuration
        case .longBreak:  totalTime = longBreakDuration
        }
        timeRemaining = totalTime
    }

    private func handleAutoStart() {
        guard let settings else { return }
        let should: Bool = switch currentPhase {
        case .work: settings.autoStartWork
        case .shortBreak, .longBreak: settings.autoStartBreaks
        }
        if should {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.start() }
        }
    }

    private func unblockIfNeeded() {
        guard isBlockingActive else { return }
        isBlockingActive = false
        DispatchQueue.global(qos: .userInitiated).async { SiteBlocker.unblockAll() }
    }

    // MARK: - Site blocking

    private func observeSettingsChanges() {
        settingsSubscriptions.removeAll()
        guard let settings else { return }

        settings.$blockedSites
            .dropFirst().removeDuplicates()
            .debounce(for: .milliseconds(800), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reapplyBlockingIfNeeded() }
            .store(in: &settingsSubscriptions)

        settings.$siteBlockingEnabled
            .dropFirst().removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reapplyBlockingIfNeeded() }
            .store(in: &settingsSubscriptions)

        settings.$blockDuringBreaks
            .dropFirst().removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reapplyBlockingIfNeeded() }
            .store(in: &settingsSubscriptions)
    }

    private func reapplyBlockingIfNeeded() {
        guard isActive else { return }
        if isBlockingActive { isBlockingActive = false }
        updateBlocking()
    }

    func updateBlocking() {
        guard let settings, settings.siteBlockingEnabled, !settings.blockedSites.isEmpty else {
            unblockIfNeeded()
            return
        }
        let shouldBlock: Bool = switch currentPhase {
        case .work: isActive
        case .shortBreak, .longBreak: settings.blockDuringBreaks && isActive
        }
        if shouldBlock && !isBlockingActive {
            isBlockingActive = true
            let domains = settings.blockedSites
            DispatchQueue.global(qos: .userInitiated).async { SiteBlocker.block(domains: domains) }
        } else if !shouldBlock && isBlockingActive {
            unblockIfNeeded()
        }
    }

    // MARK: - Crash/kill recovery checkpoint

    private func saveCheckpoint() {
        guard currentPhase == .work, let start = sessionStartTime else {
            clearCheckpoint(); return
        }
        var data: [String: Any] = [
            "sessionStartTime": start.timeIntervalSince1970,
            "elapsedBeforePause": elapsedBeforePause,
            "totalTime": totalTime,
            "currentLabel": currentLabel
        ]
        if let resume = lastResumeTime {
            data["lastResumeTime"] = resume.timeIntervalSince1970
        }
        UserDefaults.standard.set(data, forKey: Self.checkpointKey)
    }

    private func clearCheckpoint() {
        UserDefaults.standard.removeObject(forKey: Self.checkpointKey)
    }

    /// Called at launch. If the app was killed mid-session, saves the partial work time.
    func recoverPartialSession(into store: SessionStore) {
        guard let data = UserDefaults.standard.dictionary(forKey: Self.checkpointKey) else { return }
        clearCheckpoint()

        guard let startEpoch = data["sessionStartTime"] as? Double,
              let elapsed0 = data["elapsedBeforePause"] as? Double else { return }

        var elapsed = elapsed0
        if let resumeEpoch = data["lastResumeTime"] as? Double {
            // It was running when killed — add time from last resume up to now
            elapsed += Date().timeIntervalSince(Date(timeIntervalSince1970: resumeEpoch))
        }
        if let total = data["totalTime"] as? Double {
            elapsed = min(elapsed, total)
        }
        guard elapsed >= 60 else { return }

        let label = data["currentLabel"] as? String
        store.addSession(WorkSession(
            startTime: Date(timeIntervalSince1970: startEpoch),
            durationMinutes: elapsed / 60.0,
            type: .work,
            label: label?.isEmpty == false ? label : nil
        ))
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Focus"
        content.body = switch currentPhase {
        case .work: "Great session! Keep going or take a break?"
        case .shortBreak, .longBreak: "Break's over — ready to focus?"
        }
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}

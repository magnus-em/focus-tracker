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

    @Published var currentLabel: String = ""
    @Published var lastCompletedLabel: String? = nil

    @Published var pauseStartedAt: Date? = nil
    @Published var pauseRemainingSeconds: Double = 0
    private var pauseStaleSubscription: AnyCancellable?

    enum Phase {
        case work, shortBreak, longBreak
        var displayName: String { self == .work ? "Focus" : "Break" }
    }

    private var timer: AnyCancellable?
    private var sessionStartTime: Date?
    private var elapsedBeforePause: TimeInterval = 0
    private var lastResumeTime: Date?
    private var settingsSubscriptions = Set<AnyCancellable>()
    private let completionPanel = CompletionPanel()
    private var tickCount = 0
    private static let checkpointKey = "timerCheckpoint"

    var sessionStore: SessionStore?
    var settings: AppSettings? { didSet { observeSettingsChanges() } }

    private var workDuration: TimeInterval { (settings?.workMinutes ?? 25) * 60 }
    private var breakDuration: TimeInterval { (settings?.shortBreakMinutes ?? 10) * 60 }

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
    var isOnBreak: Bool { currentPhase != .work }

    var menuBarTimeText: String {
        isRunning ? timeString : "⏸ \(timeString)"
    }

    var currentElapsedSeconds: TimeInterval {
        var elapsed = elapsedBeforePause
        if let resume = lastResumeTime { elapsed += Date().timeIntervalSince(resume) }
        return elapsed
    }

    var currentInProgressSession: WorkSession? {
        guard isActive, currentPhase == .work, let start = sessionStartTime else { return nil }
        return WorkSession(
            startTime: start,
            durationMinutes: currentElapsedSeconds / 60.0,
            type: .work,
            label: currentLabel.isEmpty ? nil : currentLabel
        )
    }

    var currentInProgressBreak: WorkSession? {
        guard isActive, isOnBreak, let start = sessionStartTime else { return nil }
        return WorkSession(
            startTime: start,
            durationMinutes: currentElapsedSeconds / 60.0,
            type: .shortBreak,
            label: nil
        )
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
        if currentPhase == .work && sessionStartTime != nil {
            startPauseGrace()
        }
    }

    func toggleRunPause() {
        if isRunning { pause() }
        else if isActive { start() }
    }

    func reset() {
        cancelPauseGrace()
        var elapsed = elapsedBeforePause
        if let resumeTime = lastResumeTime { elapsed += Date().timeIntervalSince(resumeTime) }
        timer?.cancel()
        timer = nil
        isRunning = false

        if currentPhase == .work, elapsed >= 60, let start = sessionStartTime {
            sessionStore?.addSession(WorkSession(
                startTime: start, durationMinutes: elapsed / 60.0,
                type: .work, label: currentLabel.isEmpty ? nil : currentLabel
            ))
        } else if isOnBreak, elapsed >= 60, let start = sessionStartTime {
            sessionStore?.addSession(WorkSession(
                startTime: start, durationMinutes: elapsed / 60.0,
                type: .shortBreak, label: nil
            ))
        }

        currentLabel = ""
        elapsedBeforePause = 0
        lastResumeTime = nil
        sessionStartTime = nil
        clearCheckpoint()
        currentPhase = .work
        setTimeForCurrentPhase()
        unblockIfNeeded()
    }

    func skip() {
        cancelPauseGrace()
        var elapsed = elapsedBeforePause
        if let resumeTime = lastResumeTime { elapsed += Date().timeIntervalSince(resumeTime) }
        timer?.cancel()
        timer = nil
        isRunning = false

        if currentPhase == .work, elapsed >= 60, let start = sessionStartTime {
            sessionStore?.addSession(WorkSession(
                startTime: start, durationMinutes: elapsed / 60.0,
                type: .work, label: currentLabel.isEmpty ? nil : currentLabel
            ))
        } else if isOnBreak, elapsed >= 60, let start = sessionStartTime {
            sessionStore?.addSession(WorkSession(
                startTime: start, durationMinutes: elapsed / 60.0, type: .shortBreak, label: nil
            ))
        }

        currentLabel = ""
        elapsedBeforePause = 0
        lastResumeTime = nil
        sessionStartTime = nil
        clearCheckpoint()
        currentPhase = .work
        setTimeForCurrentPhase()
        updateBlocking()
    }

    func startManualBreak(minutes: Double) {
        cancelPauseGrace()
        var elapsed = elapsedBeforePause
        if let resumeTime = lastResumeTime { elapsed += Date().timeIntervalSince(resumeTime) }
        timer?.cancel()
        timer = nil
        isRunning = false

        if elapsed >= 60, currentPhase == .work, let start = sessionStartTime {
            sessionStore?.addSession(WorkSession(
                startTime: start, durationMinutes: elapsed / 60.0,
                type: .work, label: currentLabel.isEmpty ? nil : currentLabel
            ))
        }

        currentLabel = ""
        elapsedBeforePause = 0
        lastResumeTime = nil
        sessionStartTime = nil
        clearCheckpoint()
        currentPhase = .shortBreak
        totalTime = minutes * 60
        timeRemaining = totalTime
        updateBlocking()
        start()
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

    // MARK: - Pause grace

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
        if pauseRemainingSeconds <= 0 { finalizeStalePause() }
    }

    private func cancelPauseGrace() {
        pauseStaleSubscription?.cancel()
        pauseStaleSubscription = nil
        pauseStartedAt = nil
        pauseRemainingSeconds = 0
    }

    private func finalizeStalePause() {
        cancelPauseGrace()
        let elapsed = elapsedBeforePause
        if elapsed >= 60, currentPhase == .work, let start = sessionStartTime {
            sessionStore?.addSession(WorkSession(
                startTime: start, durationMinutes: elapsed / 60.0,
                type: .work, label: currentLabel.isEmpty ? nil : currentLabel
            ))
        }
        currentLabel = ""
        elapsedBeforePause = 0
        lastResumeTime = nil
        sessionStartTime = nil
        clearCheckpoint()
        currentPhase = .work
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

    // MARK: - Timer logic

    private func tick() {
        guard let resumeTime = lastResumeTime else { return }
        let elapsed = elapsedBeforePause + Date().timeIntervalSince(resumeTime)
        timeRemaining = max(0, totalTime - elapsed)
        if timeRemaining <= 0 { completePhase(); return }
        tickCount += 1
        if tickCount % 60 == 0 { saveCheckpoint() }
    }

    private func completePhase() {
        timer?.cancel()
        timer = nil
        isRunning = false

        if let start = sessionStartTime {
            let type: WorkSession.SessionType = currentPhase == .work ? .work : .shortBreak
            sessionStore?.addSession(WorkSession(
                startTime: start, durationMinutes: totalTime / 60.0,
                type: type, label: currentPhase == .work ? (currentLabel.isEmpty ? nil : currentLabel) : nil
            ))
        }

        elapsedBeforePause = 0
        lastResumeTime = nil
        sessionStartTime = nil
        clearCheckpoint()

        if settings?.soundEnabled ?? true { NSSound(named: "Glass")?.play() }

        if currentPhase == .work {
            let capturedDuration = totalTime   // "Keep Going" reuses the same length
            lastCompletedLabel = currentLabel.isEmpty ? nil : currentLabel
            currentLabel = ""
            workSessionsCompleted += 1
            sendNotification(breakStarting: false)

            completionPanel.show(label: lastCompletedLabel) { [weak self] action in
                guard let self else { return }
                switch action {
                case .keepGoing:
                    self.currentPhase = .work
                    self.totalTime = capturedDuration
                    self.timeRemaining = capturedDuration
                    self.updateBlocking()
                    self.start()
                case .takeBreak:
                    self.currentPhase = .shortBreak
                    self.totalTime = self.breakDuration
                    self.timeRemaining = self.breakDuration
                    self.updateBlocking()
                    self.start()
                case .timedOut:
                    // Only auto-start break on timeout if the user has that setting on
                    if self.settings?.autoBreakEnabled ?? false {
                        self.currentPhase = .shortBreak
                        self.totalTime = self.breakDuration
                        self.timeRemaining = self.breakDuration
                        self.updateBlocking()
                        self.start()
                    } else {
                        self.currentPhase = .work
                        self.setTimeForCurrentPhase()
                        self.updateBlocking()
                    }
                }
            }

            // While panel is visible the timer sits idle in work state
            currentPhase = .work
            setTimeForCurrentPhase()
            updateBlocking()
        } else {
            currentLabel = ""
            currentPhase = .work
            setTimeForCurrentPhase()
            updateBlocking()
            sendNotification(breakStarting: false)
            handleAutoStart()
        }
    }

    private func setTimeForCurrentPhase() {
        switch currentPhase {
        case .work: totalTime = workDuration
        case .shortBreak, .longBreak: totalTime = breakDuration
        }
        timeRemaining = totalTime
    }

    private func handleAutoStart() {
        guard let settings, settings.autoStartWork else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.start() }
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
            unblockIfNeeded(); return
        }
        let shouldBlock = isOnBreak ? (settings.blockDuringBreaks && isActive) : isActive
        if shouldBlock && !isBlockingActive {
            isBlockingActive = true
            let domains = settings.blockedSites
            DispatchQueue.global(qos: .userInitiated).async { SiteBlocker.block(domains: domains) }
        } else if !shouldBlock && isBlockingActive {
            unblockIfNeeded()
        }
    }

    // MARK: - Checkpoint

    private func saveCheckpoint() {
        guard currentPhase == .work, let start = sessionStartTime else { clearCheckpoint(); return }
        var data: [String: Any] = [
            "sessionStartTime": start.timeIntervalSince1970,
            "elapsedBeforePause": elapsedBeforePause,
            "totalTime": totalTime,
            "currentLabel": currentLabel
        ]
        if let resume = lastResumeTime { data["lastResumeTime"] = resume.timeIntervalSince1970 }
        UserDefaults.standard.set(data, forKey: Self.checkpointKey)
    }

    private func clearCheckpoint() {
        UserDefaults.standard.removeObject(forKey: Self.checkpointKey)
    }

    func saveOnQuit() {
        // Flush checkpoint to disk immediately before the process exits.
        saveCheckpoint()
        UserDefaults.standard.synchronize()
    }

    func recoverPartialSession(into store: SessionStore) {
        guard let data = UserDefaults.standard.dictionary(forKey: Self.checkpointKey) else { return }
        clearCheckpoint()

        guard let startEpoch  = data["sessionStartTime"]    as? Double,
              let elapsed0    = data["elapsedBeforePause"]  as? Double,
              let total       = data["totalTime"]            as? Double else { return }

        // Compute how much time had elapsed, including any dead time while the app was quit.
        var elapsed = elapsed0
        let wasRunning = data["lastResumeTime"] != nil
        if let resumeEpoch = data["lastResumeTime"] as? Double {
            elapsed += Date().timeIntervalSince(Date(timeIntervalSince1970: resumeEpoch))
        }

        let label = (data["currentLabel"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let remaining = total - elapsed

        // If the session would have finished while the app was dead, save it as completed.
        if elapsed >= total {
            if total >= 60 {
                store.addSession(WorkSession(
                    startTime: Date(timeIntervalSince1970: startEpoch),
                    durationMinutes: total / 60.0, type: .work, label: label
                ))
            }
            return
        }

        // Session still has time left — restore the live timer state.
        currentPhase       = .work
        totalTime          = total
        timeRemaining      = remaining
        elapsedBeforePause = elapsed
        sessionStartTime   = Date(timeIntervalSince1970: startEpoch)
        currentLabel       = label ?? ""

        if wasRunning {
            // Auto-resume after a short delay so the UI and settings are fully initialised.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.start()
            }
        }
        // If it was paused before the kill, leave it in the paused state.
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(breakStarting: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "Focus"
        content.body = breakStarting
            ? "Session complete — \(Int((settings?.shortBreakMinutes ?? 10)))m break starting."
            : currentPhase == .work
                ? "Break over — ready to focus?"
                : "Session complete."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}

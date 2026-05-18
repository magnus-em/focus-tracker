import Foundation
import SwiftData
import Combine
import UserNotifications

#if canImport(UIKit)
import UIKit
#endif

/// Platform-agnostic focus-timer engine usable on iOS/iPadOS (and conceptually
/// macOS, though the macOS app currently uses its own TimerManager with
/// site-blocking and AppKit integrations).
///
/// The engine owns no UI. It exposes published state, mutates a SwiftData
/// store on session completion, and persists a tiny checkpoint so a partial
/// session can resume after force-quit / crash.
@MainActor
public final class FocusTimerEngine: ObservableObject {

    // MARK: - Public state

    public enum Phase: String, Sendable {
        case work, breakPhase
        public var displayName: String { self == .work ? "Focus" : "Break" }
        public var isBreak: Bool { self == .breakPhase }
    }

    @Published public private(set) var phase: Phase = .work
    @Published public private(set) var totalTime: TimeInterval
    @Published public private(set) var timeRemaining: TimeInterval
    @Published public private(set) var isRunning: Bool = false

    @Published public var currentLabel: String = ""
    @Published public var currentBreakKinds: [BreakKind] = []
    @Published public private(set) var lastCompletedLabel: String? = nil
    @Published public private(set) var workSessionsCompletedToday: Int = 0

    /// Live elapsed seconds for the current session — even while paused.
    @Published public private(set) var elapsedSeconds: TimeInterval = 0

    // MARK: - Settings hook

    public struct Settings {
        public var workMinutes: Double
        public var breakMinutes: Double
        public var dailyGoalHours: Int
        public var autoStartBreaks: Bool
        public var autoStartWork: Bool
        public var pauseGraceMinutes: Int

        public init(workMinutes: Double = 25, breakMinutes: Double = 10,
                    dailyGoalHours: Int = 4, autoStartBreaks: Bool = true,
                    autoStartWork: Bool = false, pauseGraceMinutes: Int = 10) {
            self.workMinutes = workMinutes
            self.breakMinutes = breakMinutes
            self.dailyGoalHours = dailyGoalHours
            self.autoStartBreaks = autoStartBreaks
            self.autoStartWork = autoStartWork
            self.pauseGraceMinutes = pauseGraceMinutes
        }
    }

    public var settings: Settings { didSet { applySettingsIfIdle() } }

    // MARK: - Private state

    private let container: ModelContainer
    private var context: ModelContext { ModelContext(container) }
    private var ticker: AnyCancellable?
    private var sessionStartTime: Date?
    private var elapsedBeforePause: TimeInterval = 0
    private var lastResumeTime: Date?
    private static let checkpointKey = "focusTimerEngineCheckpoint"

    // MARK: - Init

    public init(container: ModelContainer, settings: Settings = .init()) {
        self.container = container
        self.settings = settings
        self.totalTime = settings.workMinutes * 60
        self.timeRemaining = settings.workMinutes * 60
        recoverPartialSession()
        recomputeTodayCount()
        requestNotificationPermission()

        #if canImport(UIKit)
        // Resume / refresh state when the app comes back from background.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.didBecomeActive() }
        }
        #endif
    }

    // MARK: - Notifications

    private static let notifIdentifier = "focusTimerCompletion"

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Schedule a local notification at the expected completion moment so the
    /// user hears the bell even if the app is backgrounded or the screen is off.
    private func scheduleCompletionNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notifIdentifier])
        guard timeRemaining > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = phase == .work ? "Focus complete" : "Break over"
        content.body = phase == .work
            ? "Session finished — \(Int(settings.breakMinutes)) min break ready when you are."
            : "Back to focus."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeRemaining, repeats: false)
        let req = UNNotificationRequest(identifier: Self.notifIdentifier, content: content, trigger: trigger)
        center.add(req)
    }

    private func cancelCompletionNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notifIdentifier])
    }

    // MARK: - Computed

    public var isActive: Bool { isRunning || timeRemaining < totalTime }
    public var isOnBreak: Bool { phase.isBreak }

    public var progress: Double {
        guard totalTime > 0 else { return 0 }
        return 1.0 - (timeRemaining / totalTime)
    }

    public var timeString: String {
        let total = max(0, Int(timeRemaining))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Public controls

    public func start() {
        if sessionStartTime == nil { sessionStartTime = Date() }
        lastResumeTime = Date()
        isRunning = true
        ticker = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
        saveCheckpoint()
        scheduleCompletionNotification()
    }

    public func pause() {
        if let resume = lastResumeTime {
            elapsedBeforePause += Date().timeIntervalSince(resume)
        }
        lastResumeTime = nil
        isRunning = false
        ticker?.cancel(); ticker = nil
        saveCheckpoint()
        cancelCompletionNotification()
    }

    public func toggleRunPause() {
        if isRunning { pause() } else { start() }
    }

    /// Stop the timer. Saves partial work if ≥ 1 minute elapsed.
    public func stop() {
        finalize(saveAsCompleted: false)
    }

    /// Skip forward — saves a partial break if ≥ 5 minutes, then returns to
    /// work-idle. During work this behaves like stop().
    public func skip() {
        if phase.isBreak {
            finalize(saveAsCompleted: false, minBreakMinutes: 5)
        } else {
            finalize(saveAsCompleted: false)
        }
    }

    /// Quick presets while idle (15 / 25 / 45 / 60 min etc.).
    public func setSessionDuration(_ minutes: Double) {
        guard !isActive else { return }
        totalTime = minutes * 60
        timeRemaining = minutes * 60
    }

    /// Mid-session ±N minute nudge.
    public func adjustDuration(by minutes: Double) {
        let newRemaining = timeRemaining + minutes * 60
        guard newRemaining > 5 else { completePhase(); return }
        totalTime = max(60, totalTime + minutes * 60)
        timeRemaining = newRemaining
        if isRunning { scheduleCompletionNotification() }
    }

    /// Take-a-break from idle (or interrupting work) — saves partial work
    /// first, then runs a break of `minutes` with the chosen kinds.
    public func startManualBreak(minutes: Double, kinds: [BreakKind] = []) {
        // Save any partial work first.
        if phase == .work, let start = sessionStartTime {
            let elapsed = currentElapsedSeconds
            if elapsed >= 60 {
                insertSession(WorkSession(
                    startTime: start, durationMinutes: elapsed / 60.0,
                    type: .work, label: currentLabel.isEmpty ? nil : currentLabel
                ))
            }
        }
        resetSessionState()
        phase = .breakPhase
        currentBreakKinds = kinds
        totalTime = minutes * 60
        timeRemaining = totalTime
        start()
    }

    // MARK: - Private machinery

    private var currentElapsedSeconds: TimeInterval {
        var e = elapsedBeforePause
        if let resume = lastResumeTime { e += Date().timeIntervalSince(resume) }
        return e
    }

    private func tick() {
        guard let resume = lastResumeTime else { return }
        let elapsed = elapsedBeforePause + Date().timeIntervalSince(resume)
        elapsedSeconds = elapsed
        timeRemaining = max(0, totalTime - elapsed)
        if timeRemaining <= 0 { completePhase() }
    }

    private func completePhase() {
        ticker?.cancel(); ticker = nil
        isRunning = false

        if let start = sessionStartTime {
            let type: WorkSession.SessionType = phase == .work ? .work : .shortBreak
            insertSession(WorkSession(
                startTime: start,
                durationMinutes: totalTime / 60.0,
                type: type,
                label: phase == .work ? (currentLabel.isEmpty ? nil : currentLabel) : nil,
                breakKinds: phase == .work ? nil : (currentBreakKinds.isEmpty ? nil : currentBreakKinds)
            ))
        }

        if phase == .work {
            lastCompletedLabel = currentLabel.isEmpty ? nil : currentLabel
            workSessionsCompletedToday += 1
            resetSessionState(clearLabel: true)
            if settings.autoStartBreaks {
                phase = .breakPhase
                totalTime = settings.breakMinutes * 60
                timeRemaining = totalTime
                start()
            } else {
                phase = .work
                totalTime = settings.workMinutes * 60
                timeRemaining = totalTime
            }
        } else {
            resetSessionState(clearLabel: true)
            currentBreakKinds = []
            phase = .work
            totalTime = settings.workMinutes * 60
            timeRemaining = totalTime
            if settings.autoStartWork { start() }
        }
    }

    /// `minBreakMinutes` lets skip-during-break ignore tiny break flicks.
    private func finalize(saveAsCompleted: Bool, minBreakMinutes: Double = 1.0) {
        ticker?.cancel(); ticker = nil
        isRunning = false
        cancelCompletionNotification()
        let elapsed = currentElapsedSeconds

        if let start = sessionStartTime {
            let mins = elapsed / 60.0
            let threshold = phase.isBreak ? minBreakMinutes : 1.0
            if mins >= threshold {
                let type: WorkSession.SessionType = phase == .work ? .work : .shortBreak
                insertSession(WorkSession(
                    startTime: start, durationMinutes: mins,
                    type: type,
                    label: phase == .work ? (currentLabel.isEmpty ? nil : currentLabel) : nil,
                    breakKinds: phase == .work ? nil : (currentBreakKinds.isEmpty ? nil : currentBreakKinds)
                ))
            }
        }

        resetSessionState(clearLabel: true)
        currentBreakKinds = []
        phase = .work
        totalTime = settings.workMinutes * 60
        timeRemaining = totalTime
    }

    private func resetSessionState(clearLabel: Bool = false) {
        elapsedBeforePause = 0
        lastResumeTime = nil
        sessionStartTime = nil
        elapsedSeconds = 0
        if clearLabel { currentLabel = "" }
        clearCheckpoint()
    }

    private func applySettingsIfIdle() {
        guard !isActive else { return }
        switch phase {
        case .work:
            totalTime = settings.workMinutes * 60
        case .breakPhase:
            totalTime = settings.breakMinutes * 60
        }
        timeRemaining = totalTime
    }

    private func insertSession(_ s: WorkSession) {
        let ctx = context
        ctx.insert(StoredWorkSession(value: s))
        try? ctx.save()
        if s.type == .work {
            recomputeTodayCount()
        }
    }

    private func recomputeTodayCount() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let descriptor = FetchDescriptor<StoredWorkSession>(
            predicate: #Predicate { $0.startTime >= start && $0.typeRaw == "work" }
        )
        let count = (try? context.fetch(descriptor).count) ?? 0
        workSessionsCompletedToday = count
    }

    // MARK: - Checkpoint

    private func saveCheckpoint() {
        guard phase == .work, let start = sessionStartTime else {
            clearCheckpoint(); return
        }
        var data: [String: Any] = [
            "sessionStartTime": start.timeIntervalSince1970,
            "elapsedBeforePause": elapsedBeforePause,
            "totalTime": totalTime,
            "currentLabel": currentLabel
        ]
        if let r = lastResumeTime { data["lastResumeTime"] = r.timeIntervalSince1970 }
        UserDefaults.standard.set(data, forKey: Self.checkpointKey)
    }

    private func clearCheckpoint() {
        UserDefaults.standard.removeObject(forKey: Self.checkpointKey)
    }

    private func recoverPartialSession() {
        guard let data = UserDefaults.standard.dictionary(forKey: Self.checkpointKey),
              let startEpoch = data["sessionStartTime"] as? Double,
              let elapsed0 = data["elapsedBeforePause"] as? Double,
              let total = data["totalTime"] as? Double
        else { return }
        clearCheckpoint()

        var elapsed = elapsed0
        let wasRunning = data["lastResumeTime"] != nil
        if let r = data["lastResumeTime"] as? Double {
            elapsed += Date().timeIntervalSince(Date(timeIntervalSince1970: r))
        }
        let label = (data["currentLabel"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        if elapsed >= total {
            if total >= 60 {
                let ctx = context
                ctx.insert(StoredWorkSession(value: WorkSession(
                    startTime: Date(timeIntervalSince1970: startEpoch),
                    durationMinutes: total / 60.0,
                    type: .work,
                    label: label
                )))
                try? ctx.save()
            }
            return
        }

        phase = .work
        totalTime = total
        timeRemaining = total - elapsed
        elapsedBeforePause = elapsed
        sessionStartTime = Date(timeIntervalSince1970: startEpoch)
        currentLabel = label ?? ""
        if wasRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.start()
            }
        }
    }

    private func didBecomeActive() {
        // Reconcile elapsed against wall-clock — fixes drift while suspended.
        if isRunning, let resume = lastResumeTime {
            let elapsed = elapsedBeforePause + Date().timeIntervalSince(resume)
            elapsedSeconds = elapsed
            timeRemaining = max(0, totalTime - elapsed)
            if timeRemaining <= 0 { completePhase() }
        }
        recomputeTodayCount()
    }
}

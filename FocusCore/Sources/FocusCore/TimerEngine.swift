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
    /// Use the main context so inserts immediately trigger `@Query` updates
    /// in SwiftUI views. Creating a fresh ModelContext per save would commit
    /// to the same store but the view layer's context wouldn't always
    /// refresh in time.
    private var context: ModelContext { container.mainContext }
    private var ticker: AnyCancellable?
    public let stateSync: TimerStateSync
    public let localBroadcast: LocalTimerBroadcast
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
        self.stateSync = TimerStateSync(container: container)
        self.localBroadcast = LocalTimerBroadcast(deviceID: stateSync.deviceID)
        recoverPartialSession()
        recomputeTodayCount()
        requestNotificationPermission()

        // Listen for remote changes from other devices via CloudKit.
        stateSync.onRemoteChange = { [weak self] state in
            self?.applyRemoteState(state)
        }
        // Listen for instant local broadcasts (same wifi).
        localBroadcast.onMessage = { [weak self] msg in
            self?.applyRemoteMessage(msg)
        }
        // On launch, if a remote timer is already running, adopt it.
        // version > 0 guards against adopting a default-initialised record.
        if let s = stateSync.currentState(),
           s.deviceID != stateSync.deviceID,
           s.version > 0,
           s.phase != StoredTimerState.Phase.idle {
            applyRemoteState(s)
        }

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
        let center = UNUserNotificationCenter.current()
        // Cancel future + clear any already-delivered (so if user comes back
        // after a stale notification fired, it disappears from the lock
        // screen / notification center once we realize the state is paused).
        center.removePendingNotificationRequests(withIdentifiers: [Self.notifIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.notifIdentifier])
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
        pushSharedState()
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
        pushSharedState()
    }

    // MARK: - Cross-device state sync

    /// We no longer use a time-based "ignore round-trip" gate — the version
    /// counter in StoredTimerState + the deviceID stamp give us a definitive
    /// answer for "is this our own echo" or "is this newer than what we have".
    /// The old 3s gate was actively harmful: if a peer pushed a newer state
    /// within 3s of our push, we'd drop it.

    private func pushSharedState() {
        let sharedPhase: StoredTimerState.Phase
        switch phase {
        case .work:       sharedPhase = isActive ? .work : .idle
        case .breakPhase: sharedPhase = isActive ? .breakPhase : .idle
        }
        let kinds = currentBreakKinds
        let label = currentLabel
        let start = sessionStartTime
        let total = totalTime
        let isRun = isRunning
        let remaining = timeRemaining
        let endTime = isRun ? Date().addingTimeInterval(remaining) : nil

        // 1) Instant: broadcast to same-wifi peers.
        let msg = LocalTimerBroadcast.Message(
            deviceID: stateSync.deviceID,
            phase: sharedPhase.rawValue,
            isRunning: isRun,
            totalSeconds: total,
            label: label,
            breakKindsRaw: kinds.map(\.rawValue),
            startTime: start,
            endTime: endTime,
            remainingSeconds: remaining,
            timestamp: Date()
        )
        localBroadcast.send(msg)

        // 2) Durable: write to CloudKit-backed SwiftData (catches devices that aren't reachable).
        stateSync.push { state in
            state.phase = sharedPhase
            state.isRunning = isRun
            state.totalSeconds = total
            state.label = label
            state.breakKindsRaw = kinds.map(\.rawValue)
            state.startTime = start
            state.endTime = endTime
            state.remainingSeconds = remaining
        }
    }

    private func pushIdleEverywhere() {
        let msg = LocalTimerBroadcast.Message(
            deviceID: stateSync.deviceID,
            phase: "idle",
            isRunning: false,
            totalSeconds: 0,
            label: "",
            breakKindsRaw: [],
            startTime: Date?.none,
            endTime: Date?.none,
            remainingSeconds: 0,
            timestamp: Date()
        )
        localBroadcast.send(msg)
        stateSync.pushIdle()
    }

    /// Apply a state message received via the instant local broadcast.
    /// (Multipeer messages are self-filtered against `deviceID == self`, so we
    /// don't need the version gate here — only TimerStateSync's CloudKit path
    /// needs it.)
    private func applyRemoteMessage(_ msg: LocalTimerBroadcast.Message) {
        guard let phaseEnum = StoredTimerState.Phase(rawValue: msg.phase) else { return }
        if phaseEnum == .idle {
            ticker?.cancel(); ticker = nil
            isRunning = false
            elapsedBeforePause = 0
            lastResumeTime = nil
            sessionStartTime = nil
            elapsedSeconds = 0
            phase = .work
            totalTime = settings.workMinutes * 60
            timeRemaining = totalTime
            currentLabel = ""
            currentBreakKinds = []
            cancelCompletionNotification()
            return
        }
        phase = (phaseEnum == .work) ? .work : .breakPhase
        totalTime = msg.totalSeconds
        currentLabel = msg.label
        currentBreakKinds = msg.breakKindsRaw.compactMap { BreakKind(rawValue: $0) }
        sessionStartTime = msg.startTime
        if msg.isRunning, let end = msg.endTime, end.timeIntervalSinceNow > -5 {
            // "Running" with end far in the past = stale snapshot from a peer
            // we hadn't synced with in a while. Don't start a ticker that will
            // immediately auto-complete and possibly insert a phantom session.
            let remaining = max(0, end.timeIntervalSinceNow)
            timeRemaining = remaining
            elapsedBeforePause = totalTime - remaining
            lastResumeTime = Date()
            isRunning = true
            ticker?.cancel()
            ticker = Timer.publish(every: 0.5, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.tick() }
            scheduleCompletionNotification()
        } else {
            timeRemaining = msg.remainingSeconds
            elapsedBeforePause = totalTime - msg.remainingSeconds
            lastResumeTime = nil
            isRunning = false
            ticker?.cancel(); ticker = nil
            cancelCompletionNotification()
        }
    }

    private func applyRemoteState(_ state: StoredTimerState) {
        let remotePhase = state.phase
        if remotePhase == .idle {
            // Remote stopped — stop locally without saving (we trust remote to have saved).
            ticker?.cancel(); ticker = nil
            isRunning = false
            elapsedBeforePause = 0
            lastResumeTime = nil
            sessionStartTime = nil
            elapsedSeconds = 0
            phase = .work
            totalTime = settings.workMinutes * 60
            timeRemaining = totalTime
            currentLabel = ""
            currentBreakKinds = []
            cancelCompletionNotification()
            return
        }

        // Mirror state.
        phase = (remotePhase == .work) ? .work : .breakPhase
        totalTime = state.totalSeconds
        currentLabel = state.label
        currentBreakKinds = state.breakKinds
        sessionStartTime = state.startTime

        if state.isRunning, let end = state.endTime, end.timeIntervalSinceNow > -5 {
            // See note in applyRemoteMessage: stale running-snapshots with
            // endTime far in the past would otherwise auto-complete and
            // possibly insert a phantom session. Treat those as paused/idle.
            let remaining = max(0, end.timeIntervalSinceNow)
            timeRemaining = remaining
            elapsedBeforePause = totalTime - remaining
            lastResumeTime = Date()
            isRunning = true
            ticker?.cancel()
            ticker = Timer.publish(every: 0.5, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.tick() }
            scheduleCompletionNotification()
        } else {
            // Paused remotely (or stale "running" with past endTime — same
            // outcome: don't tick, just show frozen.)
            timeRemaining = state.remainingSeconds
            elapsedBeforePause = totalTime - state.remainingSeconds
            lastResumeTime = nil
            isRunning = false
            ticker?.cancel(); ticker = nil
            cancelCompletionNotification()
        }
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
        // No push here — idle preset change is local until Start.
    }

    /// Mid-session ±N minute nudge.
    public func adjustDuration(by minutes: Double) {
        let newRemaining = timeRemaining + minutes * 60
        guard newRemaining > 5 else { completePhase(); return }
        totalTime = max(60, totalTime + minutes * 60)
        timeRemaining = newRemaining
        if isRunning { scheduleCompletionNotification() }
        pushSharedState()
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
        // start() already pushes state
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
        pushIdleEverywhere()

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
        pushIdleEverywhere()
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
        // Dedup: when the same timer completes on Mac + iPad simultaneously,
        // each device's engine calls insertSession independently. Look up
        // any existing session within ±3s of this startTime with the same
        // type + label and skip the insert if it's already there. CloudKit
        // doesn't support unique constraints so this is the safest spot.
        let start = s.startTime
        let lower = start.addingTimeInterval(-3)
        let upper = start.addingTimeInterval(3)
        let typeRaw = s.type.rawValue
        let descriptor = FetchDescriptor<StoredWorkSession>(
            predicate: #Predicate { existing in
                existing.startTime >= lower &&
                existing.startTime <= upper &&
                existing.typeRaw == typeRaw
            }
        )
        if let dupes = try? ctx.fetch(descriptor),
           dupes.contains(where: { $0.label == s.label }) {
            return
        }
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
        // 1) Reconcile with shared state — another device may have paused
        //    or stopped while we were backgrounded. Read what's already in the
        //    local CloudKit mirror, AND re-check after a short delay because
        //    silent-push driven CloudKit imports can land moments after
        //    `didBecomeActive` fires.
        if let shared = stateSync.currentState(),
           shared.deviceID != stateSync.deviceID,
           shared.version > 0 {
            applyRemoteState(shared)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.stateSync.pokeForRemote()
        }

        // 2) If the timer is no longer running for any reason (just got
        //    paused above, or local pause we forgot to clean up), wipe
        //    any pending OR already-delivered completion notification.
        if !isRunning {
            cancelCompletionNotification()
        }

        // 3) Reconcile elapsed against wall-clock — fixes drift while suspended.
        if isRunning, let resume = lastResumeTime {
            let elapsed = elapsedBeforePause + Date().timeIntervalSince(resume)
            elapsedSeconds = elapsed
            timeRemaining = max(0, totalTime - elapsed)
            if timeRemaining <= 0 { completePhase() }
        }
        recomputeTodayCount()
    }
}

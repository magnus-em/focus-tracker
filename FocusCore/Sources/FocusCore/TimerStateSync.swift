import Foundation
import SwiftData
import Combine

/// Bidirectional live-timer state sync.
///
/// Each device (Mac, iPad) constructs one of these. It polls the
/// SwiftData store every 2 seconds for changes to the single
/// `StoredTimerState` record. If the latest record was authored by
/// a *different* device and is newer than what we last saw, we fire
/// `onRemoteChange` so the local timer engine can mirror it.
///
/// On local actions (start/pause/stop/adjust), call `push(_:)`. It
/// writes a new state and stamps it with our deviceID so we ignore
/// it when it bounces back via CloudKit.
///
/// Latency: typically 5-30 seconds for changes to propagate via
/// CloudKit. Not designed for tight back-and-forth — designed so
/// you can start a timer on one device and pick it up on the other.
/// Caller must invoke methods from the main thread (mainContext requires it).
public final class TimerStateSync: ObservableObject, @unchecked Sendable {
    private let container: ModelContainer
    public let deviceID: String
    private var poller: AnyCancellable?
    private var lastSeenUpdatedAt: Date = .distantPast

    public var onRemoteChange: ((StoredTimerState) -> Void)?

    private var remoteChangeObserver: NSObjectProtocol?

    public init(container: ModelContainer) {
        self.container = container
        self.deviceID = Self.persistedDeviceID()

        // Initialize lastSeen from whatever's already in the store
        // so we don't fire onRemoteChange for our own prior writes.
        if let existing = currentState() {
            lastSeenUpdatedAt = existing.updatedAt
        }

        // React the *moment* CloudKit's import lands rather than waiting for
        // the 2s poll. This is what makes background → foreground transitions
        // feel instant: pause-from-other-device shows up right after iOS
        // delivers the silent push that woke us.
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkForRemote()
        }

        start()
    }

    deinit {
        if let o = remoteChangeObserver {
            NotificationCenter.default.removeObserver(o)
        }
    }

    public func start() {
        guard poller == nil else { return }
        poller = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.checkForRemote() }
    }

    public func stop() {
        poller?.cancel()
        poller = nil
    }

    public func currentState() -> StoredTimerState? {
        let ctx = ModelContext(container)
        return (try? ctx.fetch(FetchDescriptor<StoredTimerState>()))?.first
    }

    /// Push a state update. Caller is given a mutable `StoredTimerState`
    /// to set fields on; we handle the persistence + metadata stamping.
    public func push(_ apply: (StoredTimerState) -> Void) {
        let ctx = ModelContext(container)
        let existing = (try? ctx.fetch(FetchDescriptor<StoredTimerState>()))?.first
        let record = existing ?? StoredTimerState()
        if existing == nil { ctx.insert(record) }
        apply(record)
        record.updatedAt = Date()
        record.deviceID = deviceID
        try? ctx.save()
        lastSeenUpdatedAt = record.updatedAt
    }

    /// Convenience: clear the state to idle.
    public func pushIdle() {
        push { state in
            state.phase = .idle
            state.isRunning = false
            state.endTime = nil
            state.remainingSeconds = 0
            state.totalSeconds = 0
            state.label = ""
            state.breakKindsRaw = []
            state.startTime = nil
        }
    }

    private func checkForRemote() {
        guard let state = currentState() else { return }
        // Ignore our own writes coming back round-trip.
        guard state.deviceID != deviceID else {
            lastSeenUpdatedAt = max(lastSeenUpdatedAt, state.updatedAt)
            return
        }
        guard state.updatedAt > lastSeenUpdatedAt else { return }
        lastSeenUpdatedAt = state.updatedAt
        onRemoteChange?(state)
    }

    private static func persistedDeviceID() -> String {
        let key = "focusCore.timerSync.deviceID"
        if let v = UserDefaults.standard.string(forKey: key) { return v }
        let v = UUID().uuidString
        UserDefaults.standard.set(v, forKey: key)
        return v
    }
}

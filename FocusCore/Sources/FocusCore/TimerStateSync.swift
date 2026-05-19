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
    /// High-water mark for what we've already applied. Persisted across launches
    /// so we don't re-apply stale CloudKit pulls of a state we previously saw.
    private var lastSeenVersion: Int
    private static let lastSeenVersionKey = "focusCore.timerSync.lastSeenVersion"

    public var onRemoteChange: ((StoredTimerState) -> Void)?

    /// Fired after a debounced post-import dedup pass so the host app can
    /// refresh any caches/views that show session totals.
    public var onPostImportSettled: (() -> Void)?

    private var remoteChangeObserver: NSObjectProtocol?
    private var dedupWorkItem: DispatchWorkItem?

    public init(container: ModelContainer) {
        self.container = container
        self.deviceID = Self.persistedDeviceID()
        self.lastSeenVersion = UserDefaults.standard.integer(forKey: Self.lastSeenVersionKey)
        print("[TimerStateSync] init deviceID=\(deviceID.prefix(8)) lastSeenVersion=\(lastSeenVersion)")

        // Initialize lastSeen from whatever's already in the store
        // so we don't fire onRemoteChange for our own prior writes.
        if let existing = currentState() {
            lastSeenVersion = max(lastSeenVersion, existing.version)
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
            self?.scheduleDedupAfterImport()
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

    /// Force a remote-state check right now. Useful from `didBecomeActive`
    /// after a delay, when CloudKit's silent-push driven import may have
    /// landed between when the app foregrounded and now.
    public func pokeForRemote() {
        checkForRemote()
    }

    /// Returns the *most authoritative* state in the local store. If CloudKit
    /// has somehow created duplicate rows of the singleton (it has no unique
    /// constraint), we keep the one with the highest version (causal tip).
    public func currentState() -> StoredTimerState? {
        let ctx = ModelContext(container)
        guard let rows = try? ctx.fetch(FetchDescriptor<StoredTimerState>()),
              !rows.isEmpty else { return nil }
        return rows.max(by: { stateLess($0, $1) })
    }

    /// Strict ordering: `(version, updatedAt, deviceID)`. The deviceID tiebreak
    /// is a total order — two devices that happen to push the same version+time
    /// will agree on which one wins.
    private func stateLess(_ a: StoredTimerState, _ b: StoredTimerState) -> Bool {
        if a.version != b.version { return a.version < b.version }
        if a.updatedAt != b.updatedAt { return a.updatedAt < b.updatedAt }
        return a.deviceID < b.deviceID
    }

    /// Push a state update. Caller is given a mutable `StoredTimerState`
    /// to set fields on; we handle the persistence + metadata stamping +
    /// monotonic version bump.
    public func push(_ apply: (StoredTimerState) -> Void) {
        let ctx = ModelContext(container)
        let rows = (try? ctx.fetch(FetchDescriptor<StoredTimerState>())) ?? []
        // Keep the causally-newest row; delete any other duplicates so future
        // reads are deterministic.
        let existing = rows.max(by: { stateLess($0, $1) })
        for r in rows where r !== existing { ctx.delete(r) }
        let record = existing ?? StoredTimerState()
        if existing == nil { ctx.insert(record) }
        apply(record)
        let priorVersion = max(record.version, lastSeenVersion)
        record.version = priorVersion + 1
        record.updatedAt = Date()
        record.deviceID = deviceID
        try? ctx.save()
        lastSeenVersion = record.version
        UserDefaults.standard.set(lastSeenVersion, forKey: Self.lastSeenVersionKey)
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
        // Own-writes that come back via CloudKit echo: just update the
        // high-water mark and skip — but DON'T skip on version equality
        // alone, because a peer could have authored a state with the same
        // version we did (concurrent push). Total order resolves that.
        if state.deviceID == deviceID && state.version <= lastSeenVersion {
            return
        }
        guard state.version > lastSeenVersion else { return }
        lastSeenVersion = state.version
        UserDefaults.standard.set(lastSeenVersion, forKey: Self.lastSeenVersionKey)
        // Don't fire onRemoteChange for our own state coming back — even if
        // the version bumped (shouldn't, since we already set lastSeenVersion
        // on push). Belt-and-suspenders.
        guard state.deviceID != deviceID else { return }
        onRemoteChange?(state)
    }

    /// Debounce a strict-dedup pass for ~3s after CloudKit reports new
    /// remote changes. Strict match (whole-second startTime + type + label
    /// + duration to 0.01 min) means we only ever collapse byte-identical
    /// rows — the exact failure mode where Mac and iPad both insert a row
    /// for the same broadcast-driven event with different UUIDs.
    private func scheduleDedupAfterImport() {
        dedupWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let removed = FocusMigration.dedupeWorkSessions(container: self.container)
            if removed > 0 {
                print("[TimerStateSync] post-import dedup removed \(removed) duplicate session(s)")
            }
            self.onPostImportSettled?()
        }
        dedupWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: item)
    }

    private static func persistedDeviceID() -> String {
        let key = "focusCore.timerSync.deviceID"
        if let v = UserDefaults.standard.string(forKey: key) { return v }
        let v = UUID().uuidString
        UserDefaults.standard.set(v, forKey: key)
        return v
    }
}

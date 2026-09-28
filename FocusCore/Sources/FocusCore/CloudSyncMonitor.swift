import Foundation
import CoreData
import Combine

/// Tracks the health of SwiftData's CloudKit mirroring from its own event
/// stream. An iCloud account probe can succeed while the mirror itself is
/// failing (e.g. entitlement errors at setup), which is how the Mac once went
/// months without syncing unnoticed — so health is judged from these events.
@MainActor
public final class CloudSyncMonitor: ObservableObject {
    public static let shared = CloudSyncMonitor()

    public struct Snapshot: Codable, Equatable {
        public var lastSetup: Date?
        public var lastImport: Date?
        public var lastExport: Date?
        public var lastErrorDate: Date?
        public var lastErrorMessage: String?
        /// True when the most recent event of any kind failed.
        public var lastEventFailed = false
    }

    public enum Health: Equatable {
        case unknown, healthy, stale, failing
    }

    @Published public private(set) var snapshot: Snapshot

    /// No successful import for this long counts as stale.
    public static let staleAfter: TimeInterval = 3 * 24 * 3600

    private static let defaultsKey = "cloudSyncMonitor.snapshot"
    private var observer: NSObjectProtocol?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = saved
        } else {
            snapshot = Snapshot()
        }
    }

    /// Call once at launch, before the ModelContainer starts syncing.
    public func start() {
        guard observer == nil else { return }
        // object: nil — SwiftData owns the NSPersistentCloudKitContainer, so
        // we can't name it; it's the only one in the process.
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.endDate != nil else { return }
            let type = event.type
            let succeeded = event.succeeded
            let end = event.endDate ?? Date()
            let message = event.error.map(Self.describe)
            MainActor.assumeIsolated {
                self?.record(type: type, succeeded: succeeded, end: end, errorMessage: message)
            }
        }
    }

    public var health: Health {
        let s = snapshot
        if s.lastEventFailed { return .failing }
        guard let last = s.lastImport ?? s.lastSetup else { return .unknown }
        return Date().timeIntervalSince(last) > Self.staleAfter ? .stale : .healthy
    }

    private func record(type: NSPersistentCloudKitContainer.EventType, succeeded: Bool,
                        end: Date, errorMessage: String?) {
        var s = snapshot
        let name: String
        switch type {
        case .setup: name = "setup"; if succeeded { s.lastSetup = end }
        case .import: name = "import"; if succeeded { s.lastImport = end }
        case .export: name = "export"; if succeeded { s.lastExport = end }
        @unknown default: name = "unknown"
        }
        s.lastEventFailed = !succeeded
        if !succeeded {
            s.lastErrorDate = end
            s.lastErrorMessage = "\(name): \(errorMessage ?? "unknown error")"
            SyncLog.event("ckMirrorFailed", ["type": name, "error": errorMessage ?? ""])
        }
        snapshot = s
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    nonisolated private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.localizedDescription) (\(ns.domain) \(ns.code))"
    }
}

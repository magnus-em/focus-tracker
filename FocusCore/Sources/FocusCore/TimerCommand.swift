import Foundation
import SwiftData

public struct TimerCommand: Equatable, Sendable {
    public enum Action: String, Sendable {
        case switchTo, stop, startBreak
    }

    public let id: UUID
    public let createdAt: Date
    public let action: Action
    public let label: String
    public let minutes: Double

    /// Commands older than this when first seen are ignored — a device that
    /// was off for a day shouldn't replay yesterday's switches.
    public static let maxAge: TimeInterval = 12 * 3600
    private static let lastAppliedKey = "focusCore.timerCommands.lastApplied"

    public static func send(_ action: Action, label: String = "", minutes: Double = 0,
                            deviceID: String, container: ModelContainer) {
        let ctx = ModelContext(container)
        let row = StoredTimerCommand()
        row.actionRaw = action.rawValue
        row.label = label
        row.minutes = minutes
        row.deviceID = deviceID
        ctx.insert(row)
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        try? ctx.delete(model: StoredTimerCommand.self, where: #Predicate { $0.createdAt < cutoff })
        try? ctx.save()
        SyncLog.event("cmdSend", ["action": action.rawValue, "label": label, "minutes": minutes])
    }

    /// New commands since the last call, oldest first. Marks them consumed.
    /// A command is skipped when the shared timer state was written after it:
    /// some device already acted on it (or the user did something newer).
    public static func takePending(container: ModelContainer, stateUpdatedAt: Date?) -> [TimerCommand] {
        let d = UserDefaults.standard
        let floor = max(d.double(forKey: lastAppliedKey), Date().addingTimeInterval(-maxAge).timeIntervalSince1970)
        let since = Date(timeIntervalSince1970: floor)
        let ctx = ModelContext(container)
        let rows = (try? ctx.fetch(FetchDescriptor<StoredTimerCommand>(
            predicate: #Predicate { $0.createdAt > since },
            sortBy: [SortDescriptor(\.createdAt)]
        ))) ?? []
        guard let newest = rows.last else { return [] }
        d.set(newest.createdAt.timeIntervalSince1970, forKey: lastAppliedKey)
        return rows.compactMap { r in
            guard let action = Action(rawValue: r.actionRaw) else { return nil }
            if let s = stateUpdatedAt, s > r.createdAt {
                SyncLog.event("cmdSuperseded", ["action": r.actionRaw, "label": r.label])
                return nil
            }
            return TimerCommand(id: r.id, createdAt: r.createdAt, action: action,
                                label: r.label, minutes: r.minutes)
        }
    }

    /// Call on startup so commands issued before this device ever ran
    /// aren't replayed.
    public static func markSeenIfFirstRun() {
        let d = UserDefaults.standard
        if d.object(forKey: lastAppliedKey) == nil {
            d.set(Date().timeIntervalSince1970, forKey: lastAppliedKey)
        }
    }
}

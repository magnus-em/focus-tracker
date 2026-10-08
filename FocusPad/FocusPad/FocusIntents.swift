import AppIntents
import UIKit
import FocusCore

/// Siri / Shortcuts / Action Button / Spotlight entry points. They only
/// append a `TimerCommand` (timestamped now); whichever device is running
/// the timer applies it, so a suspended phone with stale timer state can't
/// clobber the session on the Mac.
struct FocusCategory: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static var defaultQuery = FocusCategoryQuery()

    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct FocusCategoryQuery: EntityStringQuery {
    private var tags: [String] { UserDefaults.standard.stringArray(forKey: "tags") ?? [] }

    func entities(for identifiers: [String]) async throws -> [FocusCategory] {
        identifiers.map(FocusCategory.init)
    }

    func entities(matching string: String) async throws -> [FocusCategory] {
        tags.filter { $0.localizedCaseInsensitiveContains(string) }.map(FocusCategory.init)
    }

    func suggestedEntities() async throws -> [FocusCategory] {
        tags.map(FocusCategory.init)
    }
}

@MainActor
enum FocusCommandSender {
    static func send(_ action: TimerCommand.Action, label: String = "", minutes: Double = 0) async {
        TimerCommand.send(action, label: label, minutes: minutes,
                          deviceID: TimerStateSync.persistedDeviceID(),
                          container: FocusPadApp.sharedContainer)
        if let engine = FocusPadApp.liveEngine, UIApplication.shared.applicationState == .active {
            engine.stateSync.pokeForRemote()
            return
        }
        // Launched in the background just for this intent: stay alive long
        // enough for the CloudKit mirror to export the command.
        let task = UIApplication.shared.beginBackgroundTask(withName: "focusCommandExport")
        try? await Task.sleep(for: .seconds(12))
        if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
    }
}

struct SwitchFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Focus"
    static var description = IntentDescription("Start tracking a category. Whatever was being tracked is saved up to now.")

    @Parameter(title: "Category") var category: FocusCategory

    static var parameterSummary: some ParameterSummary { Summary("Switch to \(\.$category)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await FocusCommandSender.send(.switchTo, label: category.id)
        return .result(dialog: "Tracking \(category.id).")
    }
}

struct StopFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Focus Timer"
    static var description = IntentDescription("Stop and save whatever is being tracked.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await FocusCommandSender.send(.stop)
        return .result(dialog: "Stopped.")
    }
}

struct TakeBreakIntent: AppIntent {
    static var title: LocalizedStringResource = "Take a Break"
    static var description = IntentDescription("Save the current focus and start a break.")

    @Parameter(title: "Minutes", default: 10, inclusiveRange: (5, 480)) var minutes: Int

    static var parameterSummary: some ParameterSummary { Summary("Take a \(\.$minutes) minute break") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await FocusCommandSender.send(.startBreak, minutes: Double(minutes))
        return .result(dialog: "Break for \(minutes) minutes.")
    }
}

struct FocusShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SwitchFocusIntent(),
            phrases: [
                "Switch to \(\.$category) in \(.applicationName)",
                "Track \(\.$category) in \(.applicationName)",
                "Switch \(.applicationName) category",
            ],
            shortTitle: "Switch",
            systemImageName: "arrow.triangle.swap"
        )
        AppShortcut(
            intent: StopFocusIntent(),
            phrases: ["Stop tracking in \(.applicationName)"],
            shortTitle: "Stop",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: TakeBreakIntent(),
            phrases: ["Take a break in \(.applicationName)"],
            shortTitle: "Break",
            systemImageName: "cup.and.saucer.fill"
        )
    }
}

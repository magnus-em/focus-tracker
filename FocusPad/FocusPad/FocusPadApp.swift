import SwiftUI
import SwiftData
import FocusCore

@main
struct FocusPadApp: App {
    let container: ModelContainer
    @StateObject private var settings: PadSettings
    @StateObject private var engine: FocusTimerEngine

    init() {
        // Honor the iCloud sync toggle stored in defaults — falls back to local
        // if CloudKit init fails (no network / not signed in / etc.).
        let useCloud = UserDefaults.standard.object(forKey: "cloudKitSyncEnabled") as? Bool ?? true
        let c: ModelContainer
        do {
            c = try FocusModelContainer.make(cloudKitSync: useCloud)
        } catch {
            print("[FocusPad] CloudKit init failed, falling back to local: \(error)")
            c = try! FocusModelContainer.make(cloudKitSync: false)
        }
        self.container = c

        let s = PadSettings()
        _settings = StateObject(wrappedValue: s)
        _engine = StateObject(wrappedValue: FocusTimerEngine(
            container: c,
            settings: s.engineSettings
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(engine)
        }
        .modelContainer(container)
    }
}

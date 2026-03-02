import SwiftUI

@main
struct LockInApp: App {
    @StateObject private var timerManager: TimerManager
    @StateObject private var sessionStore: SessionStore
    @StateObject private var settings: AppSettings

    init() {
        let store = SessionStore()
        let appSettings = AppSettings()
        let timer = TimerManager()
        timer.sessionStore = store
        timer.settings = appSettings
        timer.applySettings()

        _sessionStore = StateObject(wrappedValue: store)
        _settings = StateObject(wrappedValue: appSettings)
        _timerManager = StateObject(wrappedValue: timer)

        // Clean up any stale /etc/hosts entries from a previous crash
        SiteBlocker.cleanupIfNeeded()

        // Ensure cleanup on app quit
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            if SiteBlocker.hasStaleEntries() {
                SiteBlocker.unblockAll()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverContent(
                timerManager: timerManager,
                sessionStore: sessionStore,
                settings: settings
            )
        } label: {
            if timerManager.isActive {
                Text(timerManager.menuBarTimeText)
            } else {
                Image(systemName: "circle.fill")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

struct PopoverContent: View {
    @ObservedObject var timerManager: TimerManager
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var settings: AppSettings
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Image(systemName: "timer").tag(0)
                Image(systemName: "chart.bar.fill").tag(1)
                Image(systemName: "gearshape.fill").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 2)

            ZStack(alignment: .top) {
                TimerView(timer: timerManager, store: sessionStore, settings: settings)
                    .opacity(selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 0)
                StatsView(store: sessionStore)
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 1)
                SettingsView(settings: settings, timer: timerManager, store: sessionStore)
                    .opacity(selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 2)
            }

            Divider()

            Button("Quit Lock-In") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
        }
        .frame(width: 300)
    }
}

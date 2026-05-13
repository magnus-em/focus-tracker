import SwiftUI

// Held at file scope so the hotkey survives for the app's lifetime,
// regardless of SwiftUI's struct lifecycle.
private var _pauseHotKey: GlobalHotKey?

@main
struct LockInApp: App {
    @StateObject private var timerManager: TimerManager
    @StateObject private var sessionStore: SessionStore
    @StateObject private var settings: AppSettings
    @StateObject private var problemStore: ProblemStore
    @StateObject private var scratchStore: ScratchStore

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
        _problemStore = StateObject(wrappedValue: ProblemStore())
        _scratchStore = StateObject(wrappedValue: ScratchStore())

        // Clean up any stale /etc/hosts entries from a previous crash
        SiteBlocker.cleanupIfNeeded()

        // Global hotkey: ⌃⌥Space toggles pause/resume.
        _pauseHotKey = GlobalHotKey(
            keyCode: GlobalHotKey.spaceKey,
            modifiers: GlobalHotKey.controlModifier | GlobalHotKey.optionModifier
        ) { [weak timer] in
            timer?.toggleRunPause()
        }

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
                settings: settings,
                problemStore: problemStore,
                scratchStore: scratchStore
            )
        } label: {
            if timerManager.isActive {
                Text(timerManager.menuBarTimeText)
            } else {
                Image(systemName: "lock.fill")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

struct PopoverContent: View {
    @ObservedObject var timerManager: TimerManager
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var problemStore: ProblemStore
    @ObservedObject var scratchStore: ScratchStore
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Image(systemName: "timer").tag(0)
                Image(systemName: "chart.bar.fill").tag(1)
                Image(systemName: "checklist").tag(2)
                Image(systemName: "brain.head.profile").tag(3)
                Image(systemName: "gearshape.fill").tag(4)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 2)

            Group {
                switch selectedTab {
                case 0: TimerView(timer: timerManager, store: sessionStore, settings: settings)
                case 1: StatsView(store: sessionStore, settings: settings)
                case 2: ProblemsView(store: problemStore, settings: settings)
                case 3: ScratchpadView(store: scratchStore)
                default: SettingsView(settings: settings, timer: timerManager, store: sessionStore)
                }
            }
            .frame(height: 430)

            Divider()

            Button("Quit Focus") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
        }
        .frame(width: 300)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

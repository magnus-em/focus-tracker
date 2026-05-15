import SwiftUI

private var _pauseHotKey: GlobalHotKey?

@main
struct FocusApp: App {
    @StateObject private var timerManager: TimerManager
    @StateObject private var sessionStore: SessionStore
    @StateObject private var settings: AppSettings
    @StateObject private var problemStore: ProblemStore
    @StateObject private var scratchStore: ScratchStore
    @StateObject private var commitmentStore: CommitmentStore
    @StateObject private var dayStore: DayStore
    @StateObject private var dashboardController: DashboardWindowController

    init() {
        let store = SessionStore()
        let appSettings = AppSettings()
        let timer = TimerManager()
        timer.recoverPartialSession(into: store)
        timer.sessionStore = store
        timer.settings = appSettings
        timer.applySettings()

        _sessionStore        = StateObject(wrappedValue: store)
        _settings            = StateObject(wrappedValue: appSettings)
        _timerManager        = StateObject(wrappedValue: timer)
        _problemStore        = StateObject(wrappedValue: ProblemStore())
        _scratchStore        = StateObject(wrappedValue: ScratchStore())
        _commitmentStore     = StateObject(wrappedValue: CommitmentStore())
        _dayStore            = StateObject(wrappedValue: DayStore())
        _dashboardController = StateObject(wrappedValue: DashboardWindowController())

        SiteBlocker.cleanupIfNeeded()

        _pauseHotKey = GlobalHotKey(
            keyCode: GlobalHotKey.spaceKey,
            modifiers: GlobalHotKey.controlModifier | GlobalHotKey.optionModifier
        ) { [weak timer] in
            timer?.toggleRunPause()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            timer.saveOnQuit()
            if SiteBlocker.hasStaleEntries() { SiteBlocker.unblockAll() }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverContent(
                timerManager: timerManager,
                sessionStore: sessionStore,
                settings: settings,
                problemStore: problemStore,
                scratchStore: scratchStore,
                commitmentStore: commitmentStore,
                dayStore: dayStore,
                openDashboard: { [self] in
                    dashboardController.open(
                        sessionStore: sessionStore,
                        problemStore: problemStore,
                        settings: settings,
                        dayStore: dayStore,
                        timerManager: timerManager
                    )
                }
            )
        } label: {
            if timerManager.isActive {
                Text(timerManager.menuBarTimeText)
            } else {
                Image(systemName: "scope")
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
    @ObservedObject var commitmentStore: CommitmentStore
    @ObservedObject var dayStore: DayStore
    let openDashboard: () -> Void

    @State private var selectedTab = 0
    @State private var showCommitment = false
    // Prevents onAppear re-triggering commitment (and microphone requests) after each session end
    @AppStorage("lastCommitmentPromptDay") private var lastCommitmentPromptDay: Double = 0

    var body: some View {
        popoverBody
            .background(.clear)
            .frame(width: 300)
            .popoverBackground()
            .onAppear {
                // Only prompt once per calendar day — prevents the microphone dialog
                // from reappearing every time the popover reopens after a session ends.
                let todayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
                if dayStore.isDayStarted && settings.needsCommitmentToday
                    && lastCommitmentPromptDay < todayStart {
                    lastCommitmentPromptDay = todayStart
                    showCommitment = true
                }
            }
    }

    private func tabChipButton(icon: String, tag: Int) -> some View {
        let selected = selectedTab == tag
        return Button { selectedTab = tag } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: selected ? .semibold : .regular))
                .frame(width: 44, height: 30)
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.secondary))
        }
        .buttonStyle(.plain)
        .glassTabChip(selected: selected)
    }

    private var popoverBody: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    tabChipButton(icon: "timer", tag: 0)
                    tabChipButton(icon: "chart.bar.fill", tag: 1)
                    tabChipButton(icon: "checklist", tag: 2)
                    tabChipButton(icon: "brain.head.profile", tag: 3)
                    tabChipButton(icon: "gearshape.fill", tag: 4)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 2)

                Group {
                    switch selectedTab {
                    case 0: TimerView(
                        timer: timerManager, store: sessionStore, settings: settings,
                        dayStore: dayStore, showCommitment: $showCommitment
                    )
                    case 1: StatsView(store: sessionStore, settings: settings)
                    case 2: ProblemsView(store: problemStore, settings: settings)
                    case 3: ScratchpadView(store: scratchStore)
                    default: SettingsView(settings: settings, timer: timerManager, store: sessionStore)
                    }
                }
                .frame(height: 480)

                Divider()

                HStack {
                    Button {
                        openDashboard()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.expand.diagonal")
                                .font(.system(size: 10))
                            Text("Dashboard")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button("Quit Focus") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            if showCommitment {
                CommitmentView(settings: settings, oathStore: commitmentStore, isShowing: $showCommitment)
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    .zIndex(10)
            }
        }
    }
}

import SwiftUI
import SwiftData
import FocusCore

private var _pauseHotKey: GlobalHotKey?

/// Shared SwiftData container — local-only for now. Flip `cloudKitSync: true`
/// once the iCloud entitlement is wired up via Xcode project + provisioning.
/// Reads UserDefaults key `cloudKitSyncEnabled` so you can toggle without rebuilding.
/// Default ON — flip to false if signing isn't set up yet.
private let focusContainer: ModelContainer = {
    let useCloud = UserDefaults.standard.object(forKey: "cloudKitSyncEnabled") as? Bool ?? true
    do {
        return try FocusModelContainer.make(cloudKitSync: useCloud)
    } catch {
        // If CloudKit init fails (no entitlement, no signing), fall back to local-only.
        print("[FocusContainer] CloudKit init failed, falling back to local: \(error)")
        return try! FocusModelContainer.make(cloudKitSync: false)
    }
}()

private func runOneShotMigration() {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let appDir = appSupport.appendingPathComponent("Focus")
    try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
    let result = FocusMigration.migrateIfNeeded(container: focusContainer, appSupportDir: appDir)
    if !result.alreadyMigrated {
        print("[FocusMigration] sessions=\(result.sessions) problems=\(result.problems) homework=\(result.homework) days=\(result.dayRecords) scratch=\(result.scratch)")
    }
}

@main
struct FocusApp: App {
    @StateObject private var timerManager: TimerManager
    @StateObject private var sessionStore: SessionStore
    @StateObject private var settings: AppSettings
    @StateObject private var problemStore: ProblemStore
    @StateObject private var homeworkStore: HomeworkStore
    @StateObject private var scratchStore: ScratchStore
    @StateObject private var dayStore: DayStore
    @StateObject private var dashboardController: DashboardWindowController
    @StateObject private var onboardingController: OnboardingWindowController

    init() {
        runOneShotMigration()

        let store = SessionStore(container: focusContainer)
        let appSettings = AppSettings()
        let timer = TimerManager()
        timer.recoverPartialSession(into: store)
        timer.sessionStore = store
        timer.settings = appSettings
        timer.applySettings()

        _sessionStore        = StateObject(wrappedValue: store)
        _settings            = StateObject(wrappedValue: appSettings)
        _timerManager        = StateObject(wrappedValue: timer)
        _problemStore        = StateObject(wrappedValue: ProblemStore(container: focusContainer))
        _homeworkStore       = StateObject(wrappedValue: HomeworkStore(container: focusContainer))
        _scratchStore        = StateObject(wrappedValue: ScratchStore(container: focusContainer))
        _dayStore            = StateObject(wrappedValue: DayStore(container: focusContainer))
        _dashboardController = StateObject(wrappedValue: DashboardWindowController())
        let onboarding = OnboardingWindowController()
        _onboardingController = StateObject(wrappedValue: onboarding)

        SiteBlocker.cleanupIfNeeded()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil, queue: .main
        ) { _ in
            if !appSettings.hasCompletedOnboarding {
                onboarding.open(settings: appSettings)
            }
        }

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
                homeworkStore: homeworkStore,
                scratchStore: scratchStore,
                dayStore: dayStore,
                openDashboard: { [self] in
                    dashboardController.open(
                        sessionStore: sessionStore,
                        problemStore: problemStore,
                        settings: settings,
                        dayStore: dayStore,
                        timerManager: timerManager
                    )
                },
                openOnboarding: { [self] in
                    onboardingController.open(settings: settings)
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
    @ObservedObject var homeworkStore: HomeworkStore
    @ObservedObject var scratchStore: ScratchStore
    @ObservedObject var dayStore: DayStore
    let openDashboard: () -> Void
    let openOnboarding: () -> Void

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
                    case 2: ProblemsView(store: problemStore, homeworkStore: homeworkStore, settings: settings)
                    case 3: ScratchpadView(store: scratchStore)
                    default: SettingsView(settings: settings, timer: timerManager, store: sessionStore, openOnboarding: openOnboarding)
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
                CommitmentView(settings: settings, isShowing: $showCommitment)
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    .zIndex(10)
            }
        }
    }
}

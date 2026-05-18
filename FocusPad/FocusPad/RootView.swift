import SwiftUI
import FocusCore

/// Sidebar destination IDs. Keeping these as a small enum lets the sidebar
/// double as both a NavigationSplitView selection AND a compact tab fallback.
enum PadTab: String, Identifiable, CaseIterable, Hashable {
    case timer, overview, daylog, problems, homework, scratch, stats, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .timer:    return "Timer"
        case .overview: return "Overview"
        case .daylog:   return "Day Log"
        case .problems: return "Problems"
        case .homework: return "Homework"
        case .scratch:  return "Scratchpad"
        case .stats:    return "Stats"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .timer:    return "timer"
        case .overview: return "rectangle.3.group"
        case .daylog:   return "calendar.day.timeline.left"
        case .problems: return "checkmark.circle"
        case .homework: return "book"
        case .scratch:  return "list.bullet.rectangle"
        case .stats:    return "chart.bar.xaxis"
        case .settings: return "gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .timer:    return FocusColors.focusRed
        case .overview: return FocusColors.focusRed
        case .daylog:   return .indigo
        case .problems: return .blue
        case .homework: return .green
        case .scratch:  return .yellow
        case .stats:    return .purple
        case .settings: return .gray
        }
    }
}

struct RootView: View {
    @State private var selection: PadTab? = .timer
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            NavigationStack {
                destination(for: selection ?? .timer)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(FocusColors.focusRed)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach([PadTab.timer, .overview, .daylog]) { tab in
                    sidebarRow(tab)
                }
            }
            Section("Capture") {
                ForEach([PadTab.problems, .homework, .scratch]) { tab in
                    sidebarRow(tab)
                }
            }
            Section("Analytics") {
                ForEach([PadTab.stats, .settings]) { tab in
                    sidebarRow(tab)
                }
            }
        }
        .navigationTitle("Focus")
        .listStyle(.sidebar)
    }

    private func sidebarRow(_ tab: PadTab) -> some View {
        Label {
            Text(tab.label)
        } icon: {
            Image(systemName: tab.symbol)
                .foregroundStyle(tab.tint)
        }
        .tag(tab as PadTab?)
    }

    @ViewBuilder
    private func destination(for tab: PadTab) -> some View {
        switch tab {
        case .timer:    TimerScreen()
        case .overview: DashboardScreen()
        case .daylog:   DayLogScreen()
        case .problems: ProblemsScreen()
        case .homework: HomeworkScreen()
        case .scratch:  ScratchpadScreen()
        case .stats:    StatsScreen()
        case .settings: SettingsScreen()
        }
    }
}

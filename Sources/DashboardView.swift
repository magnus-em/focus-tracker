import AppKit
import SwiftUI

// MARK: - Window controller

class DashboardWindowController: ObservableObject {
    private var window: NSWindow?

    func open(sessionStore: SessionStore, problemStore: ProblemStore, settings: AppSettings, dayStore: DayStore, timerManager: TimerManager) {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = DashboardView(sessionStore: sessionStore, problemStore: problemStore, settings: settings, dayStore: dayStore, timerManager: timerManager)
        let vc = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: vc)
        w.title = "Focus"
        w.setContentSize(NSSize(width: 740, height: 560))
        w.minSize = NSSize(width: 640, height: 440)
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

// MARK: - Shared log event type

private struct DayEvent: Identifiable {
    enum Kind {
        case focus(WorkSession)
        case breakSession(WorkSession)
        case problem(ProblemEntry)
        case inProgressFocus(start: Date, elapsedMinutes: Double, label: String?)
        case inProgressBreak(start: Date, elapsedMinutes: Double)
    }
    let id: String
    let time: Date
    let kind: Kind
}

// MARK: - Shared formatters

private func fmtMins(_ m: Double) -> String {
    let h = Int(m) / 60, mn = Int(m) % 60
    return h > 0 ? "\(h)h \(mn)m" : "\(Int(m))m"
}

private func fmtHours(_ h: Double) -> String {
    h >= 1 ? String(format: "%.1fh", h) : "\(Int(h * 60))m"
}

// MARK: - Dashboard

struct DashboardView: View {
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var problemStore: ProblemStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var dayStore: DayStore
    @ObservedObject var timerManager: TimerManager

    @State private var editingEvent: DayEvent? = nil

    private let red   = Color(red: 0.96, green: 0.36, blue: 0.36)
    private let blue  = Color(red: 0.27, green: 0.62, blue: 0.83)
    private let green = Color(red: 0.25, green: 0.72, blue: 0.53)
    private let amber = Color(red: 0.98, green: 0.70, blue: 0.18)

    private var todayEvents: [DayEvent] {
        let cal = Calendar.current
        let focus = sessionStore.sessions
            .filter { $0.type == .work && cal.isDateInToday($0.startTime) }
            .map { DayEvent(id: $0.id.uuidString, time: $0.startTime, kind: .focus($0)) }
        let breaks = sessionStore.sessions
            .filter { $0.type.isBreak && cal.isDateInToday($0.startTime) }
            .map { DayEvent(id: $0.id.uuidString + "-b", time: $0.startTime, kind: .breakSession($0)) }
        let problems = problemStore.problems
            .filter { cal.isDateInToday($0.date) }
            .map { DayEvent(id: $0.id.uuidString, time: $0.date, kind: .problem($0)) }

        var inProgress: [DayEvent] = []
        if let live = timerManager.currentInProgressSession, cal.isDateInToday(live.startTime) {
            inProgress.append(DayEvent(
                id: "in-progress",
                time: live.startTime,
                kind: .inProgressFocus(
                    start: live.startTime,
                    elapsedMinutes: live.durationMinutes,
                    label: live.label
                )
            ))
        }
        if let liveBreak = timerManager.currentInProgressBreak, cal.isDateInToday(liveBreak.startTime) {
            inProgress.append(DayEvent(
                id: "in-progress-break",
                time: liveBreak.startTime,
                kind: .inProgressBreak(
                    start: liveBreak.startTime,
                    elapsedMinutes: liveBreak.durationMinutes
                )
            ))
        }

        return (inProgress + focus + breaks + problems).sorted { $0.time > $1.time }
    }

    private var todayProblemCount: Int {
        problemStore.problems.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    var body: some View {
        HStack(spacing: 0) {
            leftPanel.frame(width: 244)
            Divider()
            rightPanel
        }
        .glassChrome()
        .frame(minWidth: 640, minHeight: 440)
        .sheet(item: $editingEvent) { event in
            EventEditSheet(
                event: event, settings: settings,
                sessionStore: sessionStore, problemStore: problemStore
            )
        }
    }

    // MARK: - Left: Today's log

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TODAY'S LOG")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(todayDateString)
                    .font(.system(size: 14, weight: .semibold))
                if let start = dayStore.todayRecord?.dayStart {
                    HStack(spacing: 3) {
                        Image(systemName: "sunrise").font(.system(size: 9))
                        Text(clockStr(start))
                        if let end = dayStore.todayRecord?.dayEnd {
                            Text("→")
                            Image(systemName: "moon").font(.system(size: 9))
                            Text(clockStr(end))
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                }
                if !settings.todayCommitment.isEmpty {
                    Text("\u{201C}\(settings.todayCommitment)\u{201D}")
                        .font(.system(size: 10).italic())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            let events = todayEvents
            if events.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("Nothing logged yet today")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Text("Sessions and problems\nappear here as you work.")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(events) { event in
                            EventRow(event: event, onTap: { editingEvent = event })
                            Divider().padding(.leading, 54)
                        }
                    }
                }
            }

            Divider()
            HStack {
                Label(fmtMins(sessionStore.todayWorkMinutes), systemImage: "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(red)
                Spacer()
                if sessionStore.todayBreakMinutes >= 1 {
                    Label(fmtMins(sessionStore.todayBreakMinutes), systemImage: "cup.and.saucer")
                        .font(.system(size: 10))
                        .foregroundStyle(blue)
                    Spacer()
                }
                Label("\(todayProblemCount)", systemImage: "checkmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }

    // MARK: - Right: Stats + insights

    private var rightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                statCards
                problemProgressSection
                weeklySection
                focusSplitSection
                HStack(alignment: .top, spacing: 10) {
                    insightsSection
                    weakAreasSection
                }
                lifetimeSection
            }
            .padding(14)
        }
    }

    // MARK: - Stat cards

    private var statCards: some View {
        HStack(spacing: 8) {
            dashCard(value: fmtMins(sessionStore.todayWorkMinutes), label: "Today's Focus", icon: "timer", color: red)
            if settings.dailyGoal > 0 {
                let pct = min(1.0, sessionStore.todayWorkMinutes / 60.0 / Double(settings.dailyGoal))
                let met = pct >= 1.0
                dashCard(
                    value: String(format: "%.0f%%", pct * 100),
                    label: "of \(settings.dailyGoal)h goal",
                    icon: met ? "checkmark.seal.fill" : "target",
                    color: met ? green : blue
                )
            } else {
                dashCard(value: fmtMins(sessionStore.todayBreakMinutes), label: "On Break", icon: "cup.and.saucer.fill", color: blue)
            }
            dashCard(value: "\(sessionStore.currentStreak)d", label: "Streak", icon: "flame.fill", color: .orange)
            dashCard(value: fmtHours(sessionStore.totalWorkHours), label: "Total Hours", icon: "clock.fill", color: blue)
        }
    }

    // MARK: - Problem progress

    private var problemProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("PROBLEM PROGRESS")

            ForEach(ProblemDomain.allCases, id: \.self) { domain in
                let count = problemStore.count(for: domain)
                let goal  = domain == .quant ? settings.quantGoal : settings.sweGoal
                let pct: Double = goal > 0 ? min(1, Double(count) / Double(goal)) : 0
                let col: Color  = domain == .quant ? blue : green

                HStack(spacing: 8) {
                    Text(domain.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(col)
                        .frame(width: 34, alignment: .leading)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(col.opacity(0.1))
                            if goal > 0 {
                                Capsule().fill(col.opacity(0.85))
                                    .frame(width: g.size.width * CGFloat(pct))
                                    .animation(.spring(response: 0.5), value: pct)
                            }
                        }
                    }
                    .frame(height: 6)
                    Text(goal > 0 ? "\(count)/\(goal)" : "\(count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
            }

            HStack(spacing: 0) {
                ForEach(problemStore.countByDifficulty(), id: \.difficulty) { item in
                    VStack(spacing: 1) {
                        Text("\(item.count)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(item.difficulty.color)
                        Text(item.difficulty.rawValue)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
                Divider().frame(height: 28)
                let rate = problemStore.cleanSolveRate
                VStack(spacing: 1) {
                    Text(String(format: "%.0f%%", rate * 100))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(rate >= 0.8 ? .green : rate >= 0.5 ? amber : .red)
                    Text("clean")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                Divider().frame(height: 28)
                VStack(spacing: 1) {
                    Text("\(problemStore.problemStreak)d")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                    Text("streak")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .glassCard(cornerRadius: 10)
    }

    // MARK: - 14-day chart

    private var weeklySection: some View {
        let summaries = sessionStore.dailySummaries(last: 14)
        let maxMins = max(1, summaries.map { $0.totalWorkMinutes }.max() ?? 1)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("LAST 14 DAYS")
                Spacer()
                Text(fmtMins(sessionStore.last7DaysMinutes) + " this week")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(summaries, id: \.id) { day in
                    let isToday = Calendar.current.isDateInToday(day.date)
                    VStack(spacing: 2) {
                        if day.totalWorkMinutes > 0 {
                            Text(shortMins(day.totalWorkMinutes))
                                .font(.system(size: 7, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(" ").font(.system(size: 7))
                        }
                        RoundedRectangle(cornerRadius: 2)
                            .fill(day.totalWorkMinutes > 0
                                  ? red.opacity(isToday ? 1.0 : 0.55)
                                  : Color.secondary.opacity(0.1))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(4, CGFloat(day.totalWorkMinutes / maxMins) * 50))
                        Text(weekdayLetter(day.date))
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(isToday ? red : Color.secondary.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 68)
        }
        .padding(12)
        .glassCard(cornerRadius: 10)
    }

    // MARK: - Focus split

    private var focusSplitSection: some View {
        let start = Calendar.current.date(byAdding: .day, value: -6,
            to: Calendar.current.startOfDay(for: Date()))!
        let split = sessionStore.minutesByTag(since: start)
        let total = split.reduce(0.0) { $0 + $1.minutes }

        return VStack(alignment: .leading, spacing: 8) {
            sectionLabel("FOCUS SPLIT — LAST 7 DAYS")
            if total == 0 {
                Text("No tagged sessions this week.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.08))
                        HStack(spacing: 0) {
                            ForEach(split, id: \.tag) { entry in
                                Rectangle()
                                    .fill(tagColor(entry.tag))
                                    .frame(width: geo.size.width * CGFloat(entry.minutes / total))
                            }
                        }
                        .clipShape(Capsule())
                    }
                }
                .frame(height: 10)

                VStack(spacing: 4) {
                    ForEach(split, id: \.tag) { entry in
                        HStack(spacing: 6) {
                            Circle().fill(tagColor(entry.tag)).frame(width: 6, height: 6)
                            Text(entry.tag).font(.system(size: 11))
                            Spacer()
                            Text(fmtMins(entry.minutes))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("\(Int(entry.minutes / total * 100))%")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 10)
    }

    // MARK: - Insights

    private var insightsSection: some View {
        let delta = sessionStore.last7DaysMinutes - sessionStore.prior7DaysMinutes
        let hasPrior = sessionStore.prior7DaysMinutes > 0

        return VStack(alignment: .leading, spacing: 8) {
            sectionLabel("INSIGHTS")
            VStack(spacing: 6) {
                let consistency = sessionStore.consistencyScore(days: 14)
                iRow("Consistency (14d)", "\(Int(consistency * 100))%",
                     color: consistency >= 0.8 ? .green : consistency >= 0.5 ? .orange : .red)
                iRow("Avg session",  fmtMins(sessionStore.averageSessionMinutes(last: 20)))
                iRow("Best day",     fmtMins(sessionStore.bestDayMinutes))
                iRow("Best week",    fmtHours(sessionStore.bestWeekMinutes / 60.0))
                iRow("Best streak",  "\(sessionStore.bestStreak)d")
                if hasPrior {
                    iRow("vs last week",
                         (delta >= 0 ? "+" : "") + fmtMins(delta),
                         color: delta >= 0 ? .green : .red)
                }
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 10)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Weak areas

    private var weakAreasSection: some View {
        let weak = problemStore.weakestCategories(limit: 4)

        return VStack(alignment: .leading, spacing: 8) {
            sectionLabel("WEAK AREAS")
            if weak.isEmpty {
                Text("Log 2+ problems per category to see weak spots.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 5) {
                    ForEach(weak, id: \.category) { item in
                        HStack(spacing: 6) {
                            Circle().fill(scoreColor(item.avgScore)).frame(width: 6, height: 6)
                            Text(item.category)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Text("\(item.count)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.quaternary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 10)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Lifetime

    private var lifetimeSection: some View {
        HStack(spacing: 0) {
            lStat("\(sessionStore.totalWorkSessions)", "Sessions")
            lStat(fmtHours(sessionStore.totalWorkHours), "Hours")
            lStat("\(problemStore.totalCount)", "Problems")
            lStat("\(sessionStore.bestStreak)d", "Best Streak",
                  icon: "trophy.fill", iconColor: Color(red: 1, green: 0.75, blue: 0.2))
        }
        .padding(10)
        .glassCard(cornerRadius: 10)
    }

    // MARK: - Helpers

    private func dashCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(color)
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.07))
        .cornerRadius(10)
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(.secondary)
    }

    private func iRow(_ label: String, _ value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(color)
        }
    }

    private func lStat(_ value: String, _ label: String, icon: String? = nil, iconColor: Color = .primary) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                if let icon { Image(systemName: icon).font(.system(size: 9)).foregroundStyle(iconColor) }
                Text(value).font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag.lowercased() {
        case "quant": return blue
        case "swe":   return green
        case "ai", "ai/ml": return Color(red: 0.65, green: 0.4, blue: 0.9)
        default:      return Color(red: 0.30, green: 0.78, blue: 0.74)
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        score < 0.7 ? .red : score < 1.4 ? amber : green
    }

    private var todayDateString: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date())
    }

    private func clockStr(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mma"; return f.string(from: d)
    }

    private func weekdayLetter(_ date: Date) -> String {
        let idx = Calendar.current.component(.weekday, from: date) - 1
        return ["S","M","T","W","T","F","S"][idx]
    }

    private func shortMins(_ m: Double) -> String {
        let h = Int(m) / 60
        return h > 0 ? "\(h)h" : "\(Int(m))m"
    }
}

// MARK: - Pulsing dot for in-progress events

private struct PulsingDot: View {
    let color: Color
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(on ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

// MARK: - Today's log event row

private struct EventRow: View {
    let event: DayEvent
    let onTap: () -> Void

    @State private var isHovered = false
    private let red  = Color(red: 0.96, green: 0.36, blue: 0.36)
    private let blue = Color(red: 0.27, green: 0.62, blue: 0.83)

    private var isEditable: Bool {
        switch event.kind {
        case .focus, .problem: return true
        case .breakSession, .inProgressFocus, .inProgressBreak: return false
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(timeStr)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 10)

            switch event.kind {
            case .focus(let s):       focusRow(s)
            case .breakSession(let s): breakRow(s)
            case .problem(let p):     problemRow(p)
            case .inProgressFocus(_, let mins, let label): inProgressRow(mins: mins, label: label)
            case .inProgressBreak(_, let mins): inProgressBreakRow(mins: mins)
            }

            if isHovered && isEditable {
                Image(systemName: "pencil")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered && isEditable ? Color.secondary.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { if isEditable { onTap() } }
    }

    private var timeStr: String {
        let f = DateFormatter(); f.dateFormat = "h:mm"
        return f.string(from: event.time)
    }

    private func inProgressRow(mins: Double, label: String?) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(red)
                .frame(width: 3, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(label.flatMap { $0.isEmpty ? nil : $0 } ?? "Focus")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    PulsingDot(color: red)
                }
                Text(fmtMins(mins) + " · in progress")
                    .font(.system(size: 10))
                    .foregroundStyle(red.opacity(0.8))
            }
            Spacer()
        }
    }

    private func inProgressBreakRow(mins: Double) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(blue)
                .frame(width: 3, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("Break")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(blue)
                        .lineLimit(1)
                    PulsingDot(color: blue)
                }
                Text(fmtMins(mins) + " · in progress")
                    .font(.system(size: 10))
                    .foregroundStyle(blue.opacity(0.8))
            }
            Spacer()
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 10))
                .foregroundStyle(blue.opacity(0.4))
        }
    }

    private func focusRow(_ s: WorkSession) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(red.opacity(0.7))
                .frame(width: 3, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.label.flatMap { $0.isEmpty ? nil : $0 } ?? "Focus")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(fmtMins(s.durationMinutes))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func breakRow(_ s: WorkSession) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(blue.opacity(0.5))
                .frame(width: 3, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("Break")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(blue)
                    .lineLimit(1)
                Text(fmtMins(s.durationMinutes))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 10))
                .foregroundStyle(blue.opacity(0.4))
        }
    }

    private func problemRow(_ p: ProblemEntry) -> some View {
        HStack(spacing: 8) {
            Circle().fill(p.confidence.color).frame(width: 7, height: 7)
            Text(p.title.isEmpty ? (p.categories.first ?? "Problem") : p.title)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()
            Text(String(p.difficulty.rawValue.prefix(1)))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(p.difficulty.color)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(p.difficulty.color.opacity(0.1))
                .cornerRadius(3)
        }
    }
}

// MARK: - Edit sheet

private struct EventEditSheet: View {
    let event: DayEvent
    @ObservedObject var settings: AppSettings
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var problemStore: ProblemStore
    @Environment(\.dismiss) private var dismiss

    private let red = Color(red: 0.96, green: 0.36, blue: 0.36)

    @State private var selectedLabel = ""
    @State private var selectedConfidence: Confidence = .solid
    @State private var selectedDifficulty: ProblemDifficulty = .medium

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Edit Entry")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                switch event.kind {
                case .focus(let s):        sessionFields(s)
                case .problem(let p):      problemFields(p)
                case .breakSession:        EmptyView()
                case .inProgressFocus:     EmptyView()
                case .inProgressBreak:     EmptyView()
                }
            }
            .padding(16)

            Spacer(minLength: 0)
        }
        .frame(width: 280)
        .onAppear {
            switch event.kind {
            case .focus(let s):
                selectedLabel = s.label ?? ""
            case .problem(let p):
                selectedConfidence = p.confidence
                selectedDifficulty = p.difficulty
            case .breakSession, .inProgressFocus, .inProgressBreak:
                break
            }
        }
    }

    @ViewBuilder
    private func sessionFields(_ s: WorkSession) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "timer").font(.system(size: 11)).foregroundStyle(red)
            Text(clockStr(s.startTime) + " · " + fmtMins(s.durationMinutes))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 7) {
            sheetLabel("CATEGORY")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    let noneSelected = selectedLabel.isEmpty
                    Button("None") { selectedLabel = "" }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(noneSelected ? Color.secondary.opacity(0.18) : Color.secondary.opacity(0.07))
                        .foregroundStyle(noneSelected ? .primary : .secondary)
                        .cornerRadius(6).buttonStyle(.plain)
                    ForEach(settings.tags, id: \.self) { tag in
                        let sel = selectedLabel == tag
                        Button(tag) { selectedLabel = sel ? "" : tag }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(sel ? red.opacity(0.15) : Color.secondary.opacity(0.07))
                            .foregroundStyle(sel ? red : .secondary)
                            .cornerRadius(6).buttonStyle(.plain)
                    }
                }
            }
        }

        saveButton {
            sessionStore.updateLabel(id: s.id, label: selectedLabel.isEmpty ? nil : selectedLabel)
        }
    }

    @ViewBuilder
    private func problemFields(_ p: ProblemEntry) -> some View {
        if !p.title.isEmpty {
            Text(p.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }

        VStack(alignment: .leading, spacing: 7) {
            sheetLabel("CONFIDENCE")
            HStack(spacing: 6) {
                ForEach(Confidence.allCases, id: \.self) { conf in
                    let sel = selectedConfidence == conf
                    Button(conf.rawValue) { selectedConfidence = conf }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(sel ? conf.color.opacity(0.15) : Color.secondary.opacity(0.07))
                        .foregroundStyle(sel ? conf.color : .secondary)
                        .cornerRadius(6).buttonStyle(.plain)
                }
            }
        }

        VStack(alignment: .leading, spacing: 7) {
            sheetLabel("DIFFICULTY")
            HStack(spacing: 6) {
                ForEach(ProblemDifficulty.allCases, id: \.self) { diff in
                    let sel = selectedDifficulty == diff
                    Button(diff.rawValue) { selectedDifficulty = diff }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(sel ? diff.color.opacity(0.15) : Color.secondary.opacity(0.07))
                        .foregroundStyle(sel ? diff.color : .secondary)
                        .cornerRadius(6).buttonStyle(.plain)
                }
            }
        }

        saveButton {
            var updated = p
            updated.confidence = selectedConfidence
            updated.difficulty = selectedDifficulty
            problemStore.update(updated)
        }
    }

    private func saveButton(action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            Text("Save")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(red)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func sheetLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(.secondary)
    }

    private func clockStr(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mma"; return f.string(from: d)
    }
}

import AppKit
import FocusCore
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
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())

    private let red   = Color(red: 0.96, green: 0.36, blue: 0.36)
    private let blue  = Color(red: 0.27, green: 0.62, blue: 0.83)
    private let green = Color(red: 0.25, green: 0.72, blue: 0.53)
    private let amber = Color(red: 0.98, green: 0.70, blue: 0.18)

    private var isSelectedDayToday: Bool { Calendar.current.isDateInToday(selectedDay) }

    private var selectedDayRecord: DayRecord? { dayStore.record(for: selectedDay) }

    private var selectedDayFocusSessions: [WorkSession] {
        let cal = Calendar.current
        return sessionStore.sessions.filter {
            $0.type == .work && cal.isDate($0.startTime, inSameDayAs: selectedDay)
        }
    }

    private var selectedDayBreakSessions: [WorkSession] {
        let cal = Calendar.current
        return sessionStore.sessions.filter {
            $0.type.isBreak && cal.isDate($0.startTime, inSameDayAs: selectedDay)
        }
    }

    private var selectedDayFocusMinutes: Double {
        selectedDayFocusSessions.reduce(0) { $0 + $1.durationMinutes }
    }

    private var selectedDayBreakMinutes: Double {
        selectedDayBreakSessions.reduce(0) { $0 + $1.durationMinutes }
    }

    private var selectedDayProblemCount: Int {
        let cal = Calendar.current
        return problemStore.problems.filter { cal.isDate($0.date, inSameDayAs: selectedDay) }.count
    }

    private var selectedDayEvents: [DayEvent] {
        let cal = Calendar.current
        let focus = selectedDayFocusSessions
            .map { DayEvent(id: $0.id.uuidString, time: $0.startTime, kind: .focus($0)) }
        let breaks = selectedDayBreakSessions
            .map { DayEvent(id: $0.id.uuidString + "-b", time: $0.startTime, kind: .breakSession($0)) }
        let problems = problemStore.problems
            .filter { cal.isDate($0.date, inSameDayAs: selectedDay) }
            .map { DayEvent(id: $0.id.uuidString, time: $0.date, kind: .problem($0)) }

        var inProgress: [DayEvent] = []
        if isSelectedDayToday {
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
        }

        return (inProgress + focus + breaks + problems).sorted { $0.time > $1.time }
    }

    private func shiftSelectedDay(by days: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: days, to: selectedDay) {
            let todayStart = Calendar.current.startOfDay(for: Date())
            selectedDay = min(Calendar.current.startOfDay(for: next), todayStart)
        }
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

    // MARK: - Left: Selected day's log

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(isSelectedDayToday ? "TODAY'S LOG" : "DAY LOG")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    dayNavButton(systemImage: "chevron.left") { shiftSelectedDay(by: -1) }
                    dayNavButton(systemImage: "chevron.right",
                                 disabled: isSelectedDayToday) { shiftSelectedDay(by: 1) }
                }
                Text(dayHeaderString(selectedDay))
                    .font(.system(size: 14, weight: .semibold))
                if let rec = selectedDayRecord, let start = rec.dayStart {
                    HStack(spacing: 3) {
                        Image(systemName: "sunrise").font(.system(size: 9))
                        Text(clockStr(start))
                        if let end = rec.dayEnd {
                            Text("→")
                            Image(systemName: "moon").font(.system(size: 9))
                            Text(clockStr(end))
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                }
                if isSelectedDayToday, !settings.todayCommitment.isEmpty {
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

            let events = selectedDayEvents
            if events.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text(isSelectedDayToday ? "Nothing logged yet today" : "No activity logged")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
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
                Label(fmtMins(selectedDayFocusMinutes), systemImage: "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(red)
                Spacer()
                if selectedDayBreakMinutes >= 1 {
                    Label(fmtMins(selectedDayBreakMinutes), systemImage: "cup.and.saucer")
                        .font(.system(size: 10))
                        .foregroundStyle(blue)
                    Spacer()
                }
                Label("\(selectedDayProblemCount)", systemImage: "checkmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }

    @ViewBuilder
    private func dayNavButton(systemImage: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(disabled ? Color.secondary.opacity(0.4) : Color.secondary)
                .frame(width: 22, height: 18)
                .background(Color.secondary.opacity(disabled ? 0.04 : 0.08))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func dayHeaderString(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today · " + shortDate(d) }
        if cal.isDateInYesterday(d) { return "Yesterday · " + shortDate(d) }
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
        return f.string(from: d)
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    // MARK: - Right: Stats + insights

    private var rightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                dayTimelineSection
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

    // MARK: - Day timeline

    private var dayTimelineSection: some View {
        let focus = selectedDayFocusSessions
        let breaks = selectedDayBreakSessions

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("DAY TIMELINE")
                Spacer()
                Text(dayHeaderString(selectedDay))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if focus.isEmpty && breaks.isEmpty {
                Text(isSelectedDayToday ? "No sessions yet today." : "No sessions on this day.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            } else {
                DayTimelineCanvas(
                    day: selectedDay,
                    focus: focus,
                    breaks: breaks,
                    livefocus: isSelectedDayToday ? timerManager.currentInProgressSession : nil,
                    liveBreak: isSelectedDayToday ? timerManager.currentInProgressBreak : nil,
                    red: red, blue: blue
                )
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 10)
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
        case .focus, .problem, .breakSession: return true
        case .inProgressFocus, .inProgressBreak: return false
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
                HStack(spacing: 5) {
                    Text("Break")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(blue)
                        .lineLimit(1)
                    if let kinds = s.breakKinds, !kinds.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(kinds) { k in
                                Image(systemName: k.icon)
                                    .font(.system(size: 9))
                                    .foregroundStyle(blue.opacity(0.85))
                            }
                        }
                    }
                }
                Text(breakSubtitle(s))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 10))
                .foregroundStyle(blue.opacity(0.4))
        }
    }

    private func breakSubtitle(_ s: WorkSession) -> String {
        let mins = fmtMins(s.durationMinutes)
        if let kinds = s.breakKinds, !kinds.isEmpty {
            return mins + " · " + kinds.map(\.displayName).joined(separator: ", ")
        }
        return mins
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
    @State private var selectedBreakKinds: Set<BreakKind> = []

    private let blue = Color(red: 0.27, green: 0.62, blue: 0.83)

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
                case .breakSession(let s): breakFields(s)
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
            case .breakSession(let s):
                selectedBreakKinds = Set(s.breakKinds ?? [])
            case .inProgressFocus, .inProgressBreak:
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
    private func breakFields(_ s: WorkSession) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "cup.and.saucer").font(.system(size: 11)).foregroundStyle(blue)
            Text(clockStr(s.startTime) + " · " + fmtMins(s.durationMinutes))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 7) {
            sheetLabel("TYPE")
            HStack(spacing: 6) {
                ForEach(BreakKind.allCases) { kind in
                    let sel = selectedBreakKinds.contains(kind)
                    Button {
                        if sel { selectedBreakKinds.remove(kind) }
                        else   { selectedBreakKinds.insert(kind) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: kind.icon).font(.system(size: 10))
                            Text(kind.displayName).font(.system(size: 11, weight: .medium))
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(sel ? blue.opacity(0.15) : Color.secondary.opacity(0.07))
                    .foregroundStyle(sel ? blue : .secondary)
                    .cornerRadius(6).buttonStyle(.plain)
                }
            }
        }

        saveButton {
            let ordered = BreakKind.allCases.filter { selectedBreakKinds.contains($0) }
            sessionStore.updateBreakKinds(id: s.id, kinds: ordered)
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

// MARK: - Day timeline canvas

private struct DayTimelineCanvas: View {
    let day: Date
    let focus: [WorkSession]
    let breaks: [WorkSession]
    let livefocus: WorkSession?
    let liveBreak: WorkSession?
    let red: Color
    let blue: Color

    private struct Block {
        let start: Date
        let end: Date
        let label: String
        let subtitle: String?
        let color: Color
        let isLive: Bool
    }

    private var blocks: [Block] {
        var out: [Block] = []
        for s in focus {
            let end = s.startTime.addingTimeInterval(s.durationMinutes * 60)
            out.append(Block(
                start: s.startTime, end: end,
                label: s.label?.isEmpty == false ? s.label! : "Focus",
                subtitle: fmtDuration(s.durationMinutes),
                color: red, isLive: false
            ))
        }
        for s in breaks {
            let end = s.startTime.addingTimeInterval(s.durationMinutes * 60)
            let kindStr = (s.breakKinds ?? []).map(\.displayName).joined(separator: ", ")
            out.append(Block(
                start: s.startTime, end: end,
                label: kindStr.isEmpty ? "Break" : kindStr,
                subtitle: fmtDuration(s.durationMinutes),
                color: blue, isLive: false
            ))
        }
        if let live = livefocus {
            let end = live.startTime.addingTimeInterval(live.durationMinutes * 60)
            out.append(Block(
                start: live.startTime, end: end,
                label: live.label?.isEmpty == false ? live.label! : "Focus",
                subtitle: fmtDuration(live.durationMinutes) + " · live",
                color: red, isLive: true
            ))
        }
        if let live = liveBreak {
            let end = live.startTime.addingTimeInterval(live.durationMinutes * 60)
            out.append(Block(
                start: live.startTime, end: end,
                label: "Break",
                subtitle: fmtDuration(live.durationMinutes) + " · live",
                color: blue, isLive: true
            ))
        }
        return out.sorted { $0.start < $1.start }
    }

    private var hourRange: (start: Int, end: Int) {
        let cal = Calendar.current
        guard let first = blocks.map(\.start).min(),
              let last = blocks.map(\.end).max() else { return (8, 18) }
        var s = cal.component(.hour, from: first)
        var e = cal.component(.hour, from: last)
        if cal.component(.minute, from: last) > 0 { e += 1 }
        s = max(0, s - 1)
        e = min(24, e + 1)
        if e - s < 8 { e = min(24, s + 8) }
        return (s, e)
    }

    private let rowHeight: CGFloat = 22
    private let leftCol: CGFloat = 38

    var body: some View {
        let range = hourRange
        let totalHours = range.end - range.start
        let height = CGFloat(totalHours) * rowHeight

        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(range.start..<range.end, id: \.self) { h in
                    Text(hourLabel(h))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: leftCol, height: rowHeight, alignment: .trailing)
                }
            }

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<totalHours, id: \.self) { i in
                        Rectangle()
                            .fill(Color.secondary.opacity(0.06))
                            .frame(height: 0.5)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    }
                }
                .frame(height: height)
                .background(Color.secondary.opacity(0.03))
                .cornerRadius(4)

                GeometryReader { geo in
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                        block(b, range: range, totalHeight: height, width: geo.size.width)
                    }
                }
                .frame(height: height)
            }
        }
    }

    private func block(_ b: Block, range: (start: Int, end: Int), totalHeight: CGFloat, width: CGFloat) -> some View {
        let totalSeconds = Double(range.end - range.start) * 3600.0
        let cal = Calendar.current
        let rangeStartDate = cal.date(bySettingHour: range.start, minute: 0, second: 0, of: day)!
        let startOffset = b.start.timeIntervalSince(rangeStartDate)
        let duration = b.end.timeIntervalSince(b.start)
        let y = max(0, CGFloat(startOffset / totalSeconds) * totalHeight)
        let h = max(8, CGFloat(duration / totalSeconds) * totalHeight)

        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 4)
                .fill(b.color.opacity(b.isLive ? 0.85 : 0.75))
                .overlay(
                    HStack(spacing: 4) {
                        Text(b.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let sub = b.subtitle, h >= 18 {
                            Text("· \(sub)")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 5)
                )
        }
        .frame(width: width, height: h)
        .offset(y: y)
    }

    private func hourLabel(_ h: Int) -> String {
        let mod = h % 12 == 0 ? 12 : h % 12
        let ampm = h < 12 ? "a" : "p"
        return "\(mod)\(ampm)"
    }

    private func fmtDuration(_ m: Double) -> String {
        let h = Int(m) / 60, mn = Int(m) % 60
        return h > 0 ? "\(h)h \(mn)m" : "\(Int(m))m"
    }
}

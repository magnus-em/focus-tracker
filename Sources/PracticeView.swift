import AppKit
import FocusCore
import SwiftUI

// MARK: - Window controller

/// Standalone "Practice Mode" window. Same pattern as DashboardWindowController:
/// open/refocus, don't release on close (so the same instance persists across
/// open cycles and we don't lose the in-flight attempt if the user accidentally
/// hits the red dot).
@MainActor
class PracticeWindowController: ObservableObject {
    private var window: NSWindow?

    func open(store: PracticeStore, homeworkStore: HomeworkStore, problem: Stat110Problem? = nil) {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if let p = problem, !store.isActive { store.start(problem: p) }
            return
        }
        let view = PracticeView(store: store, homeworkStore: homeworkStore, initialProblem: problem)
        let vc = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: vc)
        w.title = "Practice Mode"
        w.setContentSize(NSSize(width: 580, height: 680))
        w.minSize = NSSize(width: 500, height: 580)
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

// MARK: - Main view

struct PracticeView: View {
    @ObservedObject var store: PracticeStore
    @ObservedObject var homeworkStore: HomeworkStore
    let initialProblem: Stat110Problem?

    @State private var showSolvedSheet = false
    @State private var showStuckSheet = false
    @State private var showMonteCarloSheet = false
    @State private var showPicker = false

    var body: some View {
        Group {
            if store.isActive {
                activeView
            } else {
                idleView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if let p = initialProblem, !store.isActive {
                store.start(problem: p)
            }
        }
        .sheet(isPresented: $showSolvedSheet) {
            SolvedSheet(store: store, isPresented: $showSolvedSheet)
        }
        .sheet(isPresented: $showStuckSheet) {
            StuckSheet(store: store, isPresented: $showStuckSheet)
        }
        .sheet(isPresented: $showMonteCarloSheet) {
            MonteCarloSheet(store: store, isPresented: $showMonteCarloSheet)
        }
        .sheet(isPresented: $showPicker) {
            PracticeProblemPicker(homeworkStore: homeworkStore, isPresented: $showPicker) { p in
                store.start(problem: p)
            }
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header — friendlier, less wall-of-text
                VStack(alignment: .leading, spacing: 2) {
                    Text("Practice Mode")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Stat 110 — 20-minute productive struggle. Pick up where you left off or start something new.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                // Primary action — start a fresh problem from the catalog
                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Browse Stat 110 catalog").fontWeight(.semibold)
                        Spacer()
                        if !homeworkStore.dueForReview.isEmpty {
                            // Subtle review-due chip — discoverable, not nagging
                            Text("\(homeworkStore.dueForReview.count) due")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.20)))
                                .foregroundStyle(.orange)
                        }
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12)))
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                // Resume in-progress homework (Stat 110 problems already started
                // but not solid yet). This is the user's main mid-session
                // workflow — pick a problem they're already working on, not
                // a new one from the catalog.
                if !inProgressHomework.isEmpty {
                    continueWorkingSection
                }

                Divider()

                todayStatsRow

                if !groupedRecentSessions.isEmpty {
                    recentAttemptsList
                } else {
                    Text("No practice sessions logged yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Continue working

    /// Homework items linked to the Stat 110 catalog that the user hasn't
    /// nailed yet — anything that isn't `.solid` confidence, or that's
    /// explicitly flagged needsReview. Sorted by review-due first, then
    /// most-recently-touched.
    private var inProgressHomework: [HomeworkProblem] {
        homeworkStore.items
            .filter { $0.catalogID != nil }
            .filter { $0.confidence != .solid || $0.needsReview }
            .sorted { lhs, rhs in
                // Due-for-review first, then by most-recent date desc
                switch (lhs.isDueForReview, rhs.isDueForReview) {
                case (true, false): return true
                case (false, true): return false
                default: return lhs.date > rhs.date
                }
            }
    }

    private var continueWorkingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("CONTINUE WORKING")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(inProgressHomework.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            VStack(spacing: 4) {
                ForEach(inProgressHomework.prefix(8)) { hw in
                    continueRow(hw)
                }
            }
        }
    }

    private func continueRow(_ hw: HomeworkProblem) -> some View {
        let canResume = hw.catalogID.flatMap { Stat110Catalog.problem(id: $0) } != nil
        return HStack(spacing: 8) {
            Circle()
                .fill(confidenceColor(hw.confidence))
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(hw.title.isEmpty ? hw.source : hw.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if hw.isDueForReview {
                        Text("DUE")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.6)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.orange.opacity(0.22)))
                            .foregroundStyle(.orange)
                    }
                }
                Text("\(hw.source) · \(hw.confidence.rawValue)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            if canResume, let catID = hw.catalogID,
               let problem = Stat110Catalog.problem(id: catID) {
                Button {
                    store.start(problem: problem)
                } label: {
                    Text("Resume")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.16)))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.gray.opacity(0.05)))
    }

    private var todayStatsRow: some View {
        HStack(spacing: 14) {
            statCard(label: "Today", value: "\(store.sessionsToday)", sub: "sessions")
            statCard(label: "Solved", value: String(format: "%.0f%%", store.solveRateToday * 100), sub: "solve rate")
            statCard(label: "Time", value: fmtMins(store.minutesToday), sub: "active")
        }
    }

    private func statCard(label: String, value: String, sub: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(sub).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
    }

    /// Group attempts by catalogID (or by title for freeform problems)
    /// so the same problem worked twice doesn't look like a logging bug.
    /// Each group shows the latest attempt's stats + a count badge.
    private var groupedRecentSessions: [(key: String, latest: StoredDrillAttempt, count: Int, totalMinutes: Double)] {
        var buckets: [String: [StoredDrillAttempt]] = [:]
        var order: [String] = []
        for a in store.attempts {
            let key = a.catalogID ?? "freeform:\(a.title)"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(a)
        }
        return order.compactMap { key in
            let attempts = buckets[key] ?? []
            guard let latest = attempts.max(by: { $0.startTime < $1.startTime }) else { return nil }
            let total = attempts.reduce(0.0) { $0 + $1.activeSeconds / 60.0 }
            return (key: key, latest: latest, count: attempts.count, totalMinutes: total)
        }
    }

    private var recentAttemptsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RECENT SESSIONS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(groupedRecentSessions.prefix(20), id: \.key) { g in
                    groupedAttemptRow(latest: g.latest, count: g.count, totalMinutes: g.totalMinutes)
                }
            }
        }
    }

    private func groupedAttemptRow(latest a: StoredDrillAttempt, count: Int, totalMinutes: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: outcomeIcon(a.outcome))
                .foregroundStyle(outcomeColor(a.outcome))
                .font(.system(size: 11))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(a.title.isEmpty ? a.source : a.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    if count > 1 {
                        Text("×\(count)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.16)))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(a.source) · \(fmtMins(totalMinutes))" +
                     (a.hintsPeeked > 0 ? " · \(a.hintsPeeked) hint\(a.hintsPeeked == 1 ? "" : "s")" : "") +
                     (a.monteCarloUsed ? " · MC" : ""))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Text(relativeDate(a.startTime))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05)))
    }

    // MARK: - Active

    private var activeView: some View {
        VStack(spacing: 16) {
            // Header — problem identity
            VStack(spacing: 4) {
                if let p = store.activeProblem {
                    Text(p.sourceLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(p.title)
                        .font(.system(size: 14, weight: .medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                    if let url = problemURL(p) {
                        Link(destination: url) {
                            Label("Open PDF", systemImage: "doc.text")
                                .font(.system(size: 10))
                        }
                    }
                }
            }

            Divider()

            // Big clock + zone
            VStack(spacing: 6) {
                Text(elapsedString)
                    .font(.system(size: 56, weight: .light, design: .monospaced))
                    .foregroundStyle(store.zone.color)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: elapsedString)

                Text(store.zone.label.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(store.zone.color)

                Text(store.zone.coachingLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .frame(height: 32)
            }
            .padding(.vertical, 6)

            zoneBar

            if store.shouldSuggestBreak {
                burnoutBanner
            }

            HStack(spacing: 14) {
                counterChip(label: "Hints peeked", value: "\(store.hintsPeeked)")
                counterChip(label: "Monte Carlo", value: store.monteCarloUsed ? "used" : "—")
                counterChip(label: "Status", value: store.isPaused ? "paused" : "running")
            }

            Spacer(minLength: 8)

            actionButtons

            Button("Discard session") {
                store.discardActive()
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .buttonStyle(.plain)
        }
    }

    private var zoneBar: some View {
        GeometryReader { geo in
            let total: TimeInterval = 30 * 60
            let frac = min(1.0, store.elapsedSeconds / total)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.12))
                    .frame(height: 6)
                HStack(spacing: 0) {
                    Capsule().fill(PracticeStore.Zone.green.color.opacity(0.5))
                        .frame(width: geo.size.width * (15.0 / 30.0), height: 6)
                    Capsule().fill(PracticeStore.Zone.yellow.color.opacity(0.5))
                        .frame(width: geo.size.width * (5.0 / 30.0), height: 6)
                    Capsule().fill(PracticeStore.Zone.red.color.opacity(0.5))
                        .frame(width: geo.size.width * (10.0 / 30.0), height: 6)
                }
                Capsule().fill(store.zone.color)
                    .frame(width: geo.size.width * frac, height: 6)
                    .animation(.linear(duration: 0.5), value: frac)
            }
        }
        .frame(height: 6)
    }

    private var burnoutBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "leaf.fill")
            Text("\(store.burstCount) sessions in this burst. Consider a 10-min walk after this one.")
                .font(.system(size: 11))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    private func counterChip(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium)).tracking(0.6)
                .foregroundStyle(.tertiary)
            Text(value).font(.system(size: 13, weight: .semibold, design: .monospaced))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06)))
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button {
                showSolvedSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Solved!").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.18)))
                .foregroundStyle(Color.green)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button {
                    store.isPaused ? store.resume() : store.pause()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: store.isPaused ? "play.fill" : "pause.fill")
                        Text(store.isPaused ? "Resume" : "Pause")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.10)))
                }
                .buttonStyle(.plain)

                Button {
                    store.peekHint()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb")
                        Text("Peek hint")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(nudgeColor.opacity(0.12)))
                    .foregroundStyle(nudgeColor)
                }
                .buttonStyle(.plain)
                .help("Look at ONLY the first line of the solution. Then close it.")
            }

            HStack(spacing: 8) {
                Button {
                    showMonteCarloSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "function")
                        Text("Monte Carlo")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(nudgeColor.opacity(0.12)))
                    .foregroundStyle(nudgeColor)
                }
                .buttonStyle(.plain)

                Button {
                    showStuckSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle")
                        Text("Log & move on")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var nudgeColor: Color {
        switch store.zone {
        case .green:  return .secondary
        case .yellow: return PracticeStore.Zone.yellow.color
        case .red:    return PracticeStore.Zone.red.color
        }
    }

    // MARK: - Helpers

    private var elapsedString: String {
        let s = Int(store.elapsedSeconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func problemURL(_ p: Stat110Problem) -> URL? {
        guard let set = Stat110Catalog.problemSet(number: p.setNumber) else { return nil }
        return URL(string: set.pdfURL)
    }

    private func outcomeIcon(_ o: DrillOutcome) -> String {
        switch o {
        case .solved:  return "checkmark.circle.fill"
        case .stuck:   return "exclamationmark.circle"
        case .skipped: return "arrow.right.circle"
        }
    }

    private func outcomeColor(_ o: DrillOutcome) -> Color {
        switch o {
        case .solved:  return .green
        case .stuck:   return .orange
        case .skipped: return .secondary
        }
    }

    private func confidenceIcon(_ c: Confidence) -> String {
        switch c {
        case .solid:     return "checkmark.seal.fill"
        case .shaky:     return "questionmark.circle"
        case .struggled: return "exclamationmark.triangle.fill"
        }
    }

    private func confidenceColor(_ c: Confidence) -> Color {
        switch c {
        case .solid:     return .green
        case .shaky:     return .orange
        case .struggled: return .red
        }
    }

    private func fmtMins(_ m: Double) -> String {
        let total = Int(m * 60)
        return String(format: "%dm %02ds", total / 60, total % 60)
    }

    private func relativeDate(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: - Solved sheet

private struct SolvedSheet: View {
    @ObservedObject var store: PracticeStore
    @Binding var isPresented: Bool

    @State private var confidence: Confidence = .solid
    @State private var difficulty: ProblemDifficulty = .medium
    @State private var needsReview: Bool = false
    @State private var notes: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Locked in.")
                .font(.system(size: 18, weight: .semibold))
            Text("This gets logged to your homework list so the review queue can resurface it later.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            // Confidence — uses the same enum the homework section uses
            VStack(alignment: .leading, spacing: 6) {
                Text("Confidence")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(Confidence.allCases, id: \.self) { c in
                        confidenceButton(c)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Difficulty")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(ProblemDifficulty.allCases, id: \.self) { d in
                        difficultyButton(d)
                    }
                }
            }

            Toggle(isOn: $needsReview) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Add to review queue")
                        .font(.system(size: 12, weight: .medium))
                    Text("Resurface this in Practice Mode on the schedule below.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            // Default to needs-review iff confidence isn't .solid — but
            // let the user override either way.
            .onChange(of: confidence) { _, new in
                needsReview = (new != .solid)
            }

            Text("Key insight (optional)")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            TextEditor(text: $notes)
                .font(.system(size: 12))
                .frame(height: 80)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.06)))

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button {
                    store.finishSolved(confidence: confidence,
                                       difficulty: difficulty,
                                       needsReview: needsReview,
                                       notes: notes)
                    isPresented = false
                } label: {
                    Text("Log Solve").fontWeight(.semibold)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(0.18)))
                        .foregroundStyle(Color.green)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            // Default review-flag from initial confidence (.solid → off)
            needsReview = (confidence != .solid)
        }
    }

    private func confidenceButton(_ c: Confidence) -> some View {
        let selected = confidence == c
        let tint: Color = {
            switch c {
            case .solid: return .green
            case .shaky: return .orange
            case .struggled: return .red
            }
        }()
        return Button { confidence = c } label: {
            Text(c.rawValue)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? tint.opacity(0.22) : Color.gray.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? tint : .clear, lineWidth: 1))
                .foregroundStyle(selected ? tint : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func difficultyButton(_ d: ProblemDifficulty) -> some View {
        let selected = difficulty == d
        return Button { difficulty = d } label: {
            Text(d.rawValue)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.accentColor : .clear, lineWidth: 1))
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stuck sheet

private struct StuckSheet: View {
    @ObservedObject var store: PracticeStore
    @Binding var isPresented: Bool
    @State private var notes: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Moving on is a skill.")
                .font(.system(size: 18, weight: .semibold))
            Text("This problem will get added to your review queue so you come back to it in a day with fresh eyes.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("What blocked you? (optional)")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            TextEditor(text: $notes)
                .font(.system(size: 12))
                .frame(height: 80)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.06)))

            VStack(spacing: 6) {
                Button {
                    store.finishStuck(notes: notes)
                    isPresented = false
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Log as Stuck — add to review queue")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.14)))
                    .foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain)

                Button {
                    store.finishSkipped(notes: notes)
                    isPresented = false
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.circle")
                        Text("Skip — not in my toolkit yet")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

// MARK: - Monte Carlo sheet

private struct MonteCarloSheet: View {
    @ObservedObject var store: PracticeStore
    @Binding var isPresented: Bool
    @State private var copied = false

    private let template: String = """
    # Monte Carlo template — formalize the rules, then simulate.
    # Goal: when the closed-form math is opaque, let empirical
    # structure reveal it. Print the running average; if it
    # converges to a clean fraction, you've found the answer.
    import random

    TRIALS = 100_000

    def run_one_trial():
        # TODO: encode ONE play of the random process here.
        # Return True if the event you care about happened.
        return random.random() < 0.5

    hits = sum(run_one_trial() for _ in range(TRIALS))
    p = hits / TRIALS
    print(f"P(event) ≈ {p:.5f}   ({hits}/{TRIALS})")
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pivot to simulation")
                .font(.system(size: 18, weight: .semibold))
            Text("Often the act of formalizing the rules in code makes the math obvious. Copy this template, edit `run_one_trial`, run it. We'll mark this session as having used MC.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            ScrollView {
                Text(template)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 260)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.06)))

            HStack {
                Button(copied ? "Copied!" : "Copy template") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(template, forType: .string)
                    copied = true
                    store.markMonteCarlo()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        copied = false
                    }
                }
                Spacer()
                Button("Done") {
                    store.markMonteCarlo()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}

// MARK: - Problem picker

private struct PracticeProblemPicker: View {
    @ObservedObject var homeworkStore: HomeworkStore
    @Binding var isPresented: Bool
    let onPick: (Stat110Problem) -> Void

    @State private var query: String = ""
    @State private var expandedSets: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pick a problem to practice")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Cancel") { isPresented = false }
            }
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 8)

            TextField("Search…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Stat110Catalog.all) { set in
                        let problems = filteredProblems(set)
                        if !problems.isEmpty {
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedSets.contains(set.setNumber) || !query.isEmpty },
                                    set: { v in
                                        if v { expandedSets.insert(set.setNumber) }
                                        else { expandedSets.remove(set.setNumber) }
                                    }
                                )
                            ) {
                                ForEach(problems) { p in
                                    Button {
                                        onPick(p)
                                        isPresented = false
                                    } label: {
                                        HStack(alignment: .top, spacing: 8) {
                                            Text(p.kind == .homework ? "HW \(p.number)" : "SP \(p.number)")
                                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 56, alignment: .leading)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(p.title)
                                                    .font(.system(size: 12))
                                                    .multilineTextAlignment(.leading)
                                                if let t = p.topic {
                                                    Text(t).font(.system(size: 10)).foregroundStyle(.tertiary)
                                                }
                                            }
                                            Spacer()
                                            // Status from homework store
                                            if let hw = homeworkStore.items.first(where: { $0.catalogID == p.id }) {
                                                statusPill(hw)
                                            }
                                        }
                                        .padding(.vertical, 5).padding(.horizontal, 8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            } label: {
                                Text(set.title).font(.system(size: 13, weight: .semibold))
                                    .padding(.vertical, 6)
                            }
                            .padding(.horizontal, 16)
                            Divider()
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .frame(width: 500, height: 560)
    }

    @ViewBuilder
    private func statusPill(_ hw: HomeworkProblem) -> some View {
        let (label, color): (String, Color) = {
            if hw.isDueForReview { return ("Due", .orange) }
            switch hw.confidence {
            case .solid:     return ("✓", .green)
            case .shaky:     return ("Shaky", .orange)
            case .struggled: return ("Struggled", .red)
            }
        }()
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private func filteredProblems(_ set: Stat110ProblemSet) -> [Stat110Problem] {
        guard !query.isEmpty else { return set.problems }
        let q = query.lowercased()
        return set.problems.filter {
            $0.title.lowercased().contains(q)
                || ($0.topic?.lowercased().contains(q) ?? false)
                || $0.number.contains(q)
        }
    }
}

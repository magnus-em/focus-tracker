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

    // Quote stays stable for the duration of a problem — only changes
    // when the user navigates to a new problem. Avoids the "churn" the
    // user pushed back on. Seed is the catalog id, so it's deterministic
    // per problem.
    @State private var lastZone: PracticeStore.Zone = .green
    // Polya "things to try" expansion — auto-opens at red, manually-
    // togglable in yellow.
    @State private var polyaExpanded: Bool = false
    // How many progressive solution steps have been revealed. 0 = nothing
    // shown, 1 = first step visible, etc. Resets to 0 on problem change.
    @State private var hintsRevealed: Int = 0
    // User-controlled font scale for the practice mode UI. Persisted so
    // the choice survives across launches. Range: 0.8 to 1.6.
    @AppStorage("practice.fontScale") private var fontScale: Double = 1.0

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
        let dailyQuote = PracticeQuotes.pick(.idleScreen,
                                             seed: Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header — friendlier, less wall-of-text. Daily quote
                // keyed off the calendar day so it's stable across
                // opens within a day but rotates each day.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Practice")
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                    Text(dailyQuote.text)
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !dailyQuote.author.isEmpty {
                        Text("— \(dailyQuote.author)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.bottom, 4)

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
    //
    // Visual hierarchy follows flow-research:
    //   • In green zone — the timer fades back, quote takes center.
    //     The work is the point, not the clock.
    //   • In yellow — timer grows, coaching line + quote pivot to
    //     "you're in the insight zone" framing.
    //   • In red — timer is prominent, Polya checklist auto-expands,
    //     escape valves visually pop. Time to pivot.

    private var activeView: some View {
        ScrollView {
            VStack(spacing: 16) {
                problemHeader

                problemBody

                hintReveal

                Divider().opacity(0.4)

                clockBlock

                zoneBar

                // Quote card — serif, soft, the emotional center of the
                // page in green/yellow. Recedes in red where the focus
                // is on pivoting.
                if store.zone != .red {
                    quoteCard
                }

                if store.zone == .red || polyaExpanded {
                    polyaSection
                }

                if store.shouldSuggestBreak {
                    burnoutBanner
                }

                statusRow

                actionButtons

                Button("Discard session") {
                    store.discardActive()
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        }
        .onChange(of: store.zone) { _, newZone in
            if newZone == .red { polyaExpanded = true }
            lastZone = newZone
        }
        .onChange(of: store.activeProblem?.id) { _, _ in
            // Reset hint reveal + Polya expansion when navigating between
            // problems. Quote also implicitly resets (it's keyed off the
            // problem ID via `seed` in quoteCard).
            hintsRevealed = 0
            polyaExpanded = false
        }
    }

    private var problemHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let p = store.activeProblem {
                // Top nav row: prev | source-label | font controls | PDF | next
                HStack(spacing: 6) {
                    Button {
                        store.navigatePrevious()
                        hintsRevealed = 0
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .foregroundStyle(store.canNavigatePrevious ? .primary : .tertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.canNavigatePrevious)
                    .help("Previous problem")

                    Text(p.sourceLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()

                    fontScaleControls

                    if let url = problemURL(p) {
                        Link(destination: url) {
                            Label("PDF", systemImage: "doc.text")
                                .font(.system(size: 10))
                        }
                    }
                    Button {
                        store.navigateNext()
                        hintsRevealed = 0
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .foregroundStyle(store.canNavigateNext ? .primary : .tertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.canNavigateNext)
                    .help("Next problem")
                }

                Text(p.title)
                    .font(.system(size: 17 * fontScale, weight: .semibold, design: .serif))
                    .multilineTextAlignment(.leading)

                if p.quantRelevance > 0 {
                    quantRelevanceRow(p)
                }
            }
        }
    }

    /// A−  /  A+  buttons in the header. Adjusts the practice-mode font
    /// scale, persisted via @AppStorage. Clamps to a sensible range.
    private var fontScaleControls: some View {
        HStack(spacing: 2) {
            Button {
                fontScale = max(0.8, fontScale - 0.1)
            } label: {
                Text("A−")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("-", modifiers: .command)
            .help("Smaller text (⌘−)")

            Button {
                fontScale = min(1.6, fontScale + 0.1)
            } label: {
                Text("A+")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("=", modifiers: .command)
            .help("Larger text (⌘=)")
        }
        .foregroundStyle(.secondary)
    }

    /// Stars row + rationale — shows the user how interview-relevant
    /// THIS problem is for quant prep. Source of truth lives in the catalog.
    @ViewBuilder
    private func quantRelevanceRow(_ p: Stat110Problem) -> some View {
        HStack(alignment: .top, spacing: 6) {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= p.quantRelevance ? "star.fill" : "star")
                        .font(.system(size: 9))
                        .foregroundStyle(quantStarColor(p.quantRelevance))
                }
            }
            Text(p.quantRationale)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(quantStarColor(p.quantRelevance).opacity(0.08)))
    }

    private func quantStarColor(_ rel: Int) -> Color {
        switch rel {
        case 5: return Color(red: 0.40, green: 0.78, blue: 0.45)  // green — core
        case 4: return Color(red: 0.27, green: 0.62, blue: 0.83)  // blue — high
        case 3: return Color(red: 0.95, green: 0.74, blue: 0.30)  // amber — medium
        default: return .secondary
        }
    }

    /// The problem statement itself — serif, scrollable when long. Preserves
    /// the user's flow: read here, hint here, move on, all without leaving.
    @ViewBuilder
    private var problemBody: some View {
        if let p = store.activeProblem, !p.body.isEmpty {
            ScrollView {
                Text(p.body)
                    .font(.system(size: 13 * fontScale, weight: .regular, design: .serif))
                    .foregroundStyle(.primary.opacity(0.92))
                    .lineSpacing(3 * fontScale)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .frame(maxHeight: 280 * fontScale)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.05)))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.10), lineWidth: 0.5)
            )
        } else if let p = store.activeProblem {
            // Catalog problem without transcribed body — fall back to a
            // small notice + PDF link. (HW2/HW3 are populated; later
            // problem sets may not be yet.)
            VStack(spacing: 4) {
                Text("Problem text not yet transcribed in-app.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let url = problemURL(p) {
                    Link("Open PDF", destination: url).font(.system(size: 11))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.05)))
        }
    }

    /// The progressive hint reveal card. Each step adds one more piece
    /// of the solution. Math renders via KaTeX in a WKWebView. Steps go
    /// from "set up the notation" all the way to the full solution.
    @ViewBuilder
    private var hintReveal: some View {
        if hintsRevealed > 0, let p = store.activeProblem {
            VStack(alignment: .leading, spacing: 10) {
                hintHeader(for: p)
                if !p.solutionSteps.isEmpty {
                    // Show the first `hintsRevealed` steps, rendered with math.
                    ForEach(0..<min(hintsRevealed, p.solutionSteps.count), id: \.self) { i in
                        revealedStep(p.solutionSteps[i], index: i)
                    }
                } else if !p.firstLineHint.isEmpty {
                    // Fallback: problem only has the single first-line nudge.
                    AutoSizingMathView(content: p.firstLineHint, fontSize: 14 * fontScale)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.25), lineWidth: 0.5))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func hintHeader(for p: Stat110Problem) -> some View {
        let total = max(p.solutionSteps.count, p.firstLineHint.isEmpty ? 0 : 1)
        let isFullSolution = total > 0 && hintsRevealed >= total
        return HStack(spacing: 6) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 11 * fontScale))
                .foregroundStyle(.yellow)
            Text(isFullSolution ? "Full solution" : "Hint \(hintsRevealed) of \(total)")
                .font(.system(size: 10 * fontScale, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { hintsRevealed = 0 }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9 * fontScale, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Hide all hints")
        }
    }

    private func revealedStep(_ step: SolutionStep, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !step.title.isEmpty {
                Text(step.title.uppercased())
                    .font(.system(size: 9 * fontScale, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            AutoSizingMathView(content: step.body, fontSize: 14 * fontScale)
        }
        .padding(.top, index == 0 ? 0 : 4)
    }

    /// Clock + zone label. Size and prominence scale with zone — in green
    /// it's subtle, in red it's the main element. This is intentional:
    /// timer-as-centerpiece creates time anxiety in flow zones.
    private var clockBlock: some View {
        let size: CGFloat = {
            switch store.zone {
            case .green:  return 36
            case .yellow: return 48
            case .red:    return 60
            }
        }()
        let weight: Font.Weight = (store.zone == .red) ? .regular : .ultraLight
        return VStack(spacing: 6) {
            Text(elapsedString)
                .font(.system(size: size, weight: weight, design: .monospaced))
                .foregroundStyle(store.zone.color.opacity(store.zone == .green ? 0.75 : 1.0))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: elapsedString)
                .animation(.easeInOut(duration: 0.4), value: store.zone)

            Text(store.zone.label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(store.zone.color)

            Text(coachingLine)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(minHeight: 28)
                .animation(.easeInOut(duration: 0.4), value: store.zone)
        }
        .padding(.vertical, store.zone == .green ? 4 : 10)
    }

    /// Coaching line — rewritten from the Zone helper to be more
    /// permission-granting + specific. Pulled here so it can adapt
    /// based on hint count etc. without touching the FocusCore enum.
    private var coachingLine: String {
        switch store.zone {
        case .green:
            return "Settle in. Read the problem twice. Define your variables."
        case .yellow:
            return "You've thought deeply for 15 minutes. Most insights show up in the next 5."
        case .red:
            if store.hintsPeeked == 0 && !store.monteCarloUsed {
                return "Time to pivot. A first-line peek isn't giving up — it's the move."
            } else if store.monteCarloUsed {
                return "You ran the sim. What pattern does the empirical answer suggest?"
            } else {
                return "You took the nudge. Run with it. That's the muscle you're building."
            }
        }
    }

    /// The quote card. Serif, soft cream background. Stable per problem —
    /// the seed is derived from the problem ID so the same problem
    /// always shows the same quote, no churn during a session.
    private var quoteCard: some View {
        let context: PracticeQuotes.Context = {
            switch store.zone {
            case .green:  return .general
            case .yellow: return .yellowZone
            case .red:    return .redZone
            }
        }()
        let seed = (store.activeProblem?.id.hashValue ?? 0) ^ store.zone.hashValue
        let q = PracticeQuotes.pick(context, seed: seed)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Text("\u{201C}")
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundStyle(store.zone.color.opacity(0.45))
                    .padding(.top, 2)
                Text(q.text)
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !q.author.isEmpty {
                Text("— \(q.author)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(store.zone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(store.zone.color.opacity(0.15), lineWidth: 0.5)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Polya checklist — Stat 110-specific "things to try" moves. Auto-
    /// expands at red zone. Each row is a concrete probabilistic tactic
    /// with a one-line hint about when it applies.
    private var polyaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Things to try")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("· Stat 110 toolkit")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { polyaExpanded.toggle() }
                } label: {
                    Image(systemName: polyaExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            if polyaExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(PolyaChecklist.stat110Moves) { move in
                        polyaRow(move)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.05)))
    }

    private func polyaRow(_ move: PolyaChecklist.Move) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle")
                .font(.system(size: 7))
                .foregroundStyle(.tertiary)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(move.title)
                    .font(.system(size: 12, weight: .medium))
                Text(move.hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    /// Counters + status, but rendered as a single line of subtle text
    /// instead of three big chips that dominated the old design. The
    /// signal is here when you want it, but doesn't compete for attention.
    private var statusRow: some View {
        HStack(spacing: 14) {
            statusItem(icon: "lightbulb",
                       label: store.hintsPeeked == 0 ? "no hints yet" :
                              "\(store.hintsPeeked) hint\(store.hintsPeeked == 1 ? "" : "s")")
            statusItem(icon: "function",
                       label: store.monteCarloUsed ? "MC used" : "no sim yet")
            statusItem(icon: store.isPaused ? "pause.circle" : "circle.fill",
                       label: store.isPaused ? "paused" : "running",
                       tint: store.isPaused ? .orange : .green)
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
    }

    private func statusItem(icon: String, label: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
                .foregroundStyle(tint)
            Text(label)
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
                    advanceHint()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: peekButtonIcon)
                        Text(peekButtonLabel)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(nudgeColor.opacity(0.12)))
                    .foregroundStyle(nudgeColor)
                }
                .buttonStyle(.plain)
                .help(peekButtonHelp)
                .disabled(peekButtonDisabled)
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

    // MARK: - Hint progression

    private var totalSteps: Int {
        guard let p = store.activeProblem else { return 0 }
        if !p.solutionSteps.isEmpty { return p.solutionSteps.count }
        return p.firstLineHint.isEmpty ? 0 : 1
    }

    private var peekButtonDisabled: Bool {
        guard let _ = store.activeProblem else { return true }
        return totalSteps == 0 || hintsRevealed >= totalSteps
    }

    private var peekButtonIcon: String {
        if hintsRevealed == 0 { return "lightbulb" }
        if hintsRevealed >= totalSteps { return "lightbulb.fill" }
        return "lightbulb.fill"
    }

    private var peekButtonLabel: String {
        if hintsRevealed == 0 { return totalSteps > 1 ? "Hint 1 of \(totalSteps)" : "Peek hint" }
        if hintsRevealed >= totalSteps { return "All revealed" }
        return "Hint \(hintsRevealed + 1) of \(totalSteps)"
    }

    private var peekButtonHelp: String {
        if hintsRevealed == 0 { return "Reveal the first nudge" }
        if hintsRevealed >= totalSteps { return "All hints revealed" }
        return "Reveal the next step of the solution"
    }

    private func advanceHint() {
        guard hintsRevealed < totalSteps else { return }
        if hintsRevealed == 0 { store.peekHint() }   // count only first peek
        withAnimation(.easeInOut(duration: 0.2)) { hintsRevealed += 1 }
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
        // Celebration moment: big green seal at top, contextual quote
        // beneath, then the calibration form. The point of the sheet is
        // the moment first, the bookkeeping second.
        let q = PracticeQuotes.pick(.afterSolved, seed: Int(store.elapsedSeconds))
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Locked in.")
                        .font(.system(size: 20, weight: .semibold))
                    Text("One more pattern in your library.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Contextual celebration quote
            if !q.text.isEmpty {
                Text(q.text)
                    .font(.system(size: 12, weight: .regular, design: .serif))
                    .foregroundStyle(.primary.opacity(0.85))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.07)))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("How well did you know it?")
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
                    Text("Resurface for review")
                        .font(.system(size: 12, weight: .medium))
                    Text("Auto-on for Shaky / Struggled. We'll bring it back at the right moment.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: confidence) { _, new in
                needsReview = (new != .solid)
            }

            Text("Key insight (one line — your future self will thank you)")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            TextEditor(text: $notes)
                .font(.system(size: 12, design: .serif))
                .frame(height: 70)
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
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Save & continue").fontWeight(.semibold)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(0.22)))
                    .foregroundStyle(Color.green)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(width: 440)
        .onAppear {
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
        // Reframing moment. The point is to make this feel like a real
        // strategic choice, not a defeat. Quote first, options second.
        let stuckQuote = PracticeQuotes.pick(.afterStuck, seed: Int(store.elapsedSeconds))
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Moving on is a skill.")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Coming back with fresh eyes is a technique, not a consolation.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(stuckQuote.text)
                .font(.system(size: 12, weight: .regular, design: .serif))
                .foregroundStyle(.primary.opacity(0.85))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.07)))

            Text("Where did the path stop? (one line is plenty)")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            TextEditor(text: $notes)
                .font(.system(size: 12, design: .serif))
                .frame(height: 60)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.06)))

            VStack(spacing: 6) {
                Button {
                    store.finishStuck(notes: notes)
                    isPresented = false
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                            Text("Stuck — bring back tomorrow")
                                .fontWeight(.semibold)
                        }
                        Text("Used the toolkit. Resurfaces in your review queue with fresh eyes.")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.14)))
                    .foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain)

                Button {
                    store.finishSkipped(notes: notes)
                    isPresented = false
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right.circle")
                            Text("Skip — needs a tool I don't have yet")
                                .fontWeight(.medium)
                        }
                        Text("Topic mismatch. Logged but not put in review.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
            }
        }
        .padding(22)
        .frame(width: 440)
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

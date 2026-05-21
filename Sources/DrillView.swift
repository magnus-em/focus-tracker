import AppKit
import FocusCore
import SwiftUI

// MARK: - Window controller

/// Standalone "Drill Mode" window. Same pattern as DashboardWindowController:
/// open/refocus, don't release on close (so the same instance persists across
/// open cycles and we don't lose the in-flight attempt if the user accidentally
/// hits the red dot).
@MainActor
class DrillWindowController: ObservableObject {
    private var window: NSWindow?

    func open(store: DrillStore, problem: Stat110Problem? = nil) {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if let p = problem, !store.isActive { store.start(problem: p) }
            return
        }
        let view = DrillView(store: store, initialProblem: problem)
        let vc = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: vc)
        w.title = "Drill Mode"
        w.setContentSize(NSSize(width: 560, height: 640))
        w.minSize = NSSize(width: 480, height: 560)
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

// MARK: - Main view

struct DrillView: View {
    @ObservedObject var store: DrillStore
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
            DrillProblemPicker(isPresented: $showPicker) { p in
                store.start(problem: p)
            }
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 18) {
            Text("Drill Mode")
                .font(.system(size: 22, weight: .semibold))

            Text("Pick a Stat 110 problem and drill it under the 20-minute productive-struggle rule. Green zone you struggle. Yellow zone you check in. Red zone you pivot — peek a hint, run a Monte Carlo, or log & move on.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                showPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("Start a Drill").fontWeight(.semibold)
                }
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            Divider().padding(.vertical, 4)

            todayStatsRow

            if !store.attempts.isEmpty {
                recentAttemptsList
            } else {
                Text("No drills logged yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }

            Spacer()
        }
    }

    private var todayStatsRow: some View {
        HStack(spacing: 14) {
            statCard(label: "Today", value: "\(store.drillsToday)", sub: "drills")
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

    private var recentAttemptsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent attempts")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.attempts.prefix(15)) { a in
                        attemptRow(a)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private func attemptRow(_ a: StoredDrillAttempt) -> some View {
        HStack(spacing: 8) {
            Image(systemName: outcomeIcon(a.outcome))
                .foregroundStyle(outcomeColor(a.outcome))
                .font(.system(size: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text(a.title.isEmpty ? a.source : a.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text("\(a.source) · \(fmtMins(a.activeSeconds / 60.0))" +
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

            // Counters
            HStack(spacing: 14) {
                counterChip(label: "Hints peeked", value: "\(store.hintsPeeked)")
                counterChip(label: "Monte Carlo", value: store.monteCarloUsed ? "used" : "—")
                counterChip(label: "Status", value: store.isPaused ? "paused" : "running")
            }

            Spacer(minLength: 8)

            // Action row
            actionButtons

            // Discard exit (small, low-emphasis)
            Button("Discard attempt") {
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
                // Yellow & red zone markers (15 / 20 min)
                HStack(spacing: 0) {
                    Capsule().fill(DrillStore.Zone.green.color.opacity(0.5))
                        .frame(width: geo.size.width * (15.0 / 30.0), height: 6)
                    Capsule().fill(DrillStore.Zone.yellow.color.opacity(0.5))
                        .frame(width: geo.size.width * (5.0 / 30.0), height: 6)
                    Capsule().fill(DrillStore.Zone.red.color.opacity(0.5))
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
            Text("\(store.burstCount) drills in this burst. Consider a 10-min walk after this one.")
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
            // Primary: solved (always visible, big green)
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

            // Pause/resume + nudges
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

    /// Yellow/red zones use the framework's intended call to action — that's
    /// when nudge buttons should pop visually.
    private var nudgeColor: Color {
        switch store.zone {
        case .green:  return .secondary
        case .yellow: return DrillStore.Zone.yellow.color
        case .red:    return DrillStore.Zone.red.color
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

// MARK: - Solved sheet (confidence + notes)

private struct SolvedSheet: View {
    @ObservedObject var store: DrillStore
    @Binding var isPresented: Bool
    @State private var confidence: Int = 3
    @State private var notes: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Locked in.")
                .font(.system(size: 18, weight: .semibold))
            Text("How confident are you that you can re-derive this cold tomorrow?")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { i in
                    Button { confidence = i } label: {
                        Text("\(i)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .frame(width: 36, height: 36)
                            .background(
                                Circle().fill(confidence == i ? Color.green.opacity(0.22) : Color.gray.opacity(0.08))
                            )
                            .overlay(
                                Circle().stroke(confidence == i ? Color.green : Color.clear, lineWidth: 1)
                            )
                            .foregroundStyle(confidence == i ? Color.green : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
                Text("  1 = shaky · 5 = bulletproof")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Text("Key insight (optional)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextEditor(text: $notes)
                .font(.system(size: 12))
                .frame(height: 90)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.06)))

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button {
                    store.finish(outcome: .solved, confidence: confidence, notes: notes)
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
        .frame(width: 380)
    }
}

// MARK: - Stuck sheet (skipped vs stuck)

private struct StuckSheet: View {
    @ObservedObject var store: DrillStore
    @Binding var isPresented: Bool
    @State private var notes: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Moving on is a skill.")
                .font(.system(size: 18, weight: .semibold))
            Text("Knowing when to defer is a real interview signal. We're logging this so you can come back to it in a few days with fresh eyes.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("What blocked you? (optional)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextEditor(text: $notes)
                .font(.system(size: 12))
                .frame(height: 80)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.06)))

            VStack(spacing: 6) {
                Button {
                    store.finish(outcome: .stuck, notes: notes)
                    isPresented = false
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                        Text("Log as Stuck (used the nudges)")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.14)))
                    .foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain)

                Button {
                    store.finish(outcome: .skipped, notes: notes)
                    isPresented = false
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.circle")
                        Text("Skip (didn't fit my current toolkit)")
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
    @ObservedObject var store: DrillStore
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
            Text("Often the act of formalizing the rules in code makes the math obvious. Copy this template, edit `run_one_trial`, run it. We'll mark this attempt as having used MC.")
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

// MARK: - Problem picker (lightweight — Stat 110 catalog)

private struct DrillProblemPicker: View {
    @Binding var isPresented: Bool
    let onPick: (Stat110Problem) -> Void

    @State private var query: String = ""
    @State private var expandedSets: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pick a problem to drill")
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
        .frame(width: 460, height: 520)
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

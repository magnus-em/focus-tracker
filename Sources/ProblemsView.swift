import SwiftUI

// MARK: - Difficulty colour

extension ProblemDifficulty {
    var color: Color {
        switch self {
        case .easy:   return Color(red: 0.22, green: 0.72, blue: 0.45)
        case .medium: return Color(red: 0.98, green: 0.70, blue: 0.18)
        case .hard:   return Color(red: 0.96, green: 0.36, blue: 0.36)
        }
    }
}

// MARK: - Domain accent colours (SwiftUI-side extension)

extension ProblemDomain {
    var color: Color {
        switch self {
        case .quant: return Color(red: 0.27, green: 0.62, blue: 0.83)
        case .swe:   return Color(red: 0.25, green: 0.72, blue: 0.53)
        }
    }

    var icon: String {
        switch self {
        case .quant: return "function"
        case .swe:   return "chevron.left.forwardslash.chevron.right"
        }
    }
}

// MARK: - Main view

struct ProblemsView: View {
    @ObservedObject var store: ProblemStore
    @ObservedObject var settings: AppSettings

    @State private var showLog = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 14) {
                    goalSection
                    Divider().padding(.horizontal, 8)
                    logButton
                    Divider().padding(.horizontal, 8)
                    recentSection
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
            }

            if showLog {
                LogProblemOverlay(store: store, isShowing: $showLog)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
    }

    // MARK: Goal bars

    private var goalSection: some View {
        VStack(spacing: 10) {
            ForEach(ProblemDomain.allCases, id: \.self) { domain in
                GoalBar(
                    domain: domain,
                    count: store.count(for: domain),
                    goal: domain == .quant ? settings.quantGoal : settings.sweGoal
                )
            }
        }
    }

    // MARK: Log button

    private var logButton: some View {
        Button {
            showLog = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Log a Problem")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                LinearGradient(
                    colors: [ProblemDomain.quant.color, ProblemDomain.swe.color],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: Recent list

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.secondary)

            let days = store.byDay().prefix(7)
            if days.isEmpty {
                Text("No problems logged yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(days), id: \.date) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(dayLabel(group.date))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .padding(.bottom, 1)

                        ForEach(group.problems.prefix(8)) { problem in
                            ProblemRow(problem: problem)
                        }
                    }
                }
            }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}

// MARK: - Goal progress bar

private struct GoalBar: View {
    let domain: ProblemDomain
    let count: Int
    let goal: Int

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(1.0, Double(count) / Double(goal))
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: domain.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(domain.color)
                    Text(domain.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                }
                Spacer()
                if goal > 0 {
                    Text("\(count) / \(goal)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(count >= goal ? domain.color : .secondary)
                    Text(String(format: "%.0f%%", progress * 100))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(domain.color.opacity(0.8))
                        .frame(width: 32, alignment: .trailing)
                } else {
                    Text("\(count)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(domain.color)
                    Text("problems")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if goal > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(domain.color.opacity(0.1))
                        Capsule()
                            .fill(domain.color.opacity(0.85))
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 5)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: progress)
            }
        }
        .padding(10)
        .background(domain.color.opacity(0.05))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(domain.color.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Single problem row

private struct ProblemRow: View {
    let problem: ProblemEntry

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(problem.domain.color)
                .frame(width: 6, height: 6)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                if !problem.title.isEmpty {
                    Text(problem.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Text(problem.categories.joined(separator: " · "))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(problem.categories.joined(separator: " · "))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(problem.difficulty.rawValue)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(problem.difficulty.color)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(problem.difficulty.color.opacity(0.12))
                .cornerRadius(4)

            Text(problem.domain.rawValue)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(problem.domain.color.opacity(0.85))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(problem.domain.color.opacity(0.1))
                .cornerRadius(4)
        }
    }
}

// MARK: - Log problem overlay

struct LogProblemOverlay: View {
    @ObservedObject var store: ProblemStore
    @Binding var isShowing: Bool

    @State private var selectedDomain: ProblemDomain = .quant
    @State private var selectedCategories: Set<String> = []
    @State private var selectedDifficulty: ProblemDifficulty = .medium
    @State private var title: String = ""
    @State private var justLogged = false

    private var canLog: Bool { !selectedCategories.isEmpty }

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("LOG A PROBLEM")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        isShowing = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Domain selector
                        HStack(spacing: 8) {
                            ForEach(ProblemDomain.allCases, id: \.self) { domain in
                                let selected = selectedDomain == domain
                                Button {
                                    selectedDomain = domain
                                    selectedCategories = []
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: domain.icon)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(domain.rawValue)
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                    .foregroundStyle(selected ? .white : domain.color)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(selected ? domain.color : domain.color.opacity(0.1))
                                    .cornerRadius(9)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Category picker
                        VStack(alignment: .leading, spacing: 7) {
                            Text("CATEGORY")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(.secondary)

                            let categories = selectedDomain.categories
                            let cols = [GridItem(.adaptive(minimum: 90), spacing: 6)]
                            LazyVGrid(columns: cols, spacing: 6) {
                                ForEach(categories, id: \.self) { cat in
                                    let selected = selectedCategories.contains(cat)
                                    Button(cat) {
                                        if selected { selectedCategories.remove(cat) }
                                        else { selectedCategories.insert(cat) }
                                    }
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity)
                                    .background(selected ? selectedDomain.color.opacity(0.18) : Color.secondary.opacity(0.07))
                                    .foregroundStyle(selected ? selectedDomain.color : Color.secondary)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(selected ? selectedDomain.color.opacity(0.4) : Color.clear, lineWidth: 1)
                                    )
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Difficulty picker
                        VStack(alignment: .leading, spacing: 7) {
                            Text("DIFFICULTY")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 6) {
                                ForEach(ProblemDifficulty.allCases, id: \.self) { diff in
                                    let selected = selectedDifficulty == diff
                                    Button(diff.rawValue) {
                                        selectedDifficulty = diff
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(selected ? diff.color.opacity(0.18) : Color.secondary.opacity(0.07))
                                    .foregroundStyle(selected ? diff.color : Color.secondary)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selected ? diff.color.opacity(0.5) : Color.clear, lineWidth: 1.5)
                                    )
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Optional title
                        VStack(alignment: .leading, spacing: 5) {
                            Text("NOTE (OPTIONAL)")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(.secondary)

                            TextField("e.g. 'Coin flip variance' or #237", text: $title)
                                .font(.system(size: 12))
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.secondary.opacity(0.07))
                                .cornerRadius(7)
                                .onSubmit { if canLog { logAndReset() } }
                        }

                        // Log button
                        Button {
                            if canLog { logAndReset() }
                        } label: {
                            HStack(spacing: 6) {
                                if justLogged {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                    Text("Logged!")
                                        .font(.system(size: 13, weight: .semibold))
                                } else {
                                    Text("Log Problem")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                            }
                            .foregroundStyle(canLog ? .white : Color.secondary.opacity(0.4))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(canLog ? selectedDomain.color : Color.secondary.opacity(0.1))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canLog)
                        .animation(.easeInOut(duration: 0.2), value: justLogged)
                    }
                    .padding(20)
                }
            }
        }
    }

    private func logAndReset() {
        store.add(ProblemEntry(
            title: title,
            domain: selectedDomain,
            categories: Array(selectedCategories),
            difficulty: selectedDifficulty
        ))
        justLogged = true
        title = ""
        selectedCategories = []
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            justLogged = false
        }
    }
}

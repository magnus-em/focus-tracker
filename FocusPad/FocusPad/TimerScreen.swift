import SwiftUI
import SwiftData
import FocusCore

struct TimerScreen: View {
    @EnvironmentObject var engine: FocusTimerEngine
    @EnvironmentObject var settings: PadSettings
    @StateObject private var priorities = TodayPriorities()

    @Query(sort: \StoredWorkSession.startTime, order: .reverse) private var sessions: [StoredWorkSession]
    @Query(sort: \StoredDayRecord.calendarDay, order: .reverse) private var dayRecords: [StoredDayRecord]

    @State private var showBreakSheet = false
    @State private var showCommitment = false
    @State private var showLabelPicker = false
    @State private var showQuickAddProblem = false
    @State private var newPriority = ""

    var body: some View {
        GeometryReader { geo in
            let isWide = geo.size.width > 700
            ScrollView {
                VStack(spacing: 20) {
                    dayHeaderBar
                    if isWide {
                        HStack(alignment: .top, spacing: 20) {
                            ringPanel.frame(maxWidth: .infinity)
                            VStack(spacing: 16) {
                                controlsPanel
                                prioritiesCard
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        ringPanel
                        controlsPanel
                        prioritiesCard
                    }
                    todayFooter
                }
                .padding(PadTheme.pad)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
        .navigationTitle("Focus")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    showQuickAddProblem = true
                } label: {
                    Label("Log Problem", systemImage: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $showBreakSheet) { BreakSheet(engine: engine) }
        .sheet(isPresented: $showCommitment) { CommitmentSheet(settings: settings) }
        .sheet(isPresented: $showLabelPicker) { LabelPickerSheet(engine: engine, settings: settings) }
        .sheet(isPresented: $showQuickAddProblem) { AddProblemSheet() }
        .onAppear {
            if settings.needsCommitmentToday && dayStarted { showCommitment = true }
            priorities.load()
        }
    }

    // MARK: - Priorities card

    private var prioritiesCard: some View {
        PadCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    PadSectionHeader(title: "TODAY'S PRIORITIES")
                    Spacer()
                    Text("\(priorities.items.filter(\.done).count) / \(priorities.items.count) done")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if priorities.items.isEmpty {
                    Text("Pick the 1-3 most important things to ship today.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(priorities.items) { item in
                            HStack(spacing: 10) {
                                Button {
                                    Haptics.tap()
                                    priorities.toggle(item)
                                } label: {
                                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22))
                                        .foregroundStyle(item.done ? FocusColors.goalGreen : .secondary)
                                }
                                Text(item.text)
                                    .strikethrough(item.done)
                                    .foregroundStyle(item.done ? .secondary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button {
                                    priorities.remove(item)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    TextField("Add a priority…", text: $newPriority)
                        .submitLabel(.done)
                        .onSubmit { addPriority() }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill))
                        )
                    if !newPriority.isEmpty {
                        Button("Add") { addPriority() }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func addPriority() {
        priorities.add(newPriority)
        newPriority = ""
        Haptics.tap()
    }

    // MARK: - Day header

    private var todayRecord: StoredDayRecord? {
        let cal = Calendar.current
        return dayRecords.first { cal.isDateInToday($0.calendarDay) }
    }

    private var dayStarted: Bool { todayRecord?.dayStart != nil }
    private var dayEnded: Bool { todayRecord?.dayEnd != nil }

    private var dayHeaderBar: some View {
        HStack(spacing: 10) {
            if dayEnded {
                Label("Day Ended", systemImage: "moon.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Color.purple.opacity(0.15)))
                    .foregroundStyle(Color.purple)
            } else if dayStarted {
                Label("Day Started", systemImage: "sun.max.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                    .foregroundStyle(.orange)
                Spacer()
                Button(role: .destructive) { endDay() } label: {
                    Text("End Day").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            } else {
                Spacer()
                Button { startDay() } label: {
                    Label("Start Day", systemImage: "sun.max.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Ring panel

    private var ringPanel: some View {
        PadCard(padding: 22) {
            VStack(spacing: 16) {
                Text(engine.phase.displayName.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(engine.phase == .work ? FocusColors.focusRed : FocusColors.breakBlue)

                ZStack {
                    let ring = RingsView.Ring(
                        id: "session",
                        progress: engine.progress,
                        color: engine.phase == .work ? FocusColors.focusRed : FocusColors.breakBlue,
                        label: "",
                        value: engine.timeString,
                        goal: ""
                    )
                    RingsView(rings: [ring], lineWidth: 18, spacing: 6)
                        .frame(width: 240, height: 240)

                    VStack(spacing: 6) {
                        Text(engine.timeString)
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        if let label = engine.currentLabel.isEmpty ? nil : engine.currentLabel {
                            Text(label).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }

                if engine.phase == .work && !engine.isActive {
                    presetChips
                }
                if engine.isActive {
                    adjustChips
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var presetChips: some View {
        HStack(spacing: 8) {
            ForEach([15, 25, 45, 60], id: \.self) { mins in
                Button {
                    engine.setSessionDuration(Double(mins))
                } label: {
                    Text("\(mins)m")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(FocusColors.focusRed)
            }
        }
    }

    private var adjustChips: some View {
        HStack(spacing: 8) {
            ForEach([-10, -5, 5, 10], id: \.self) { d in
                Button {
                    engine.adjustDuration(by: Double(d))
                } label: {
                    Text(d > 0 ? "+\(d)" : "\(d)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
        }
    }

    // MARK: - Controls panel

    private var controlsPanel: some View {
        VStack(spacing: 12) {
            primaryControlButtons

            if engine.phase == .work && !engine.isActive {
                tagPickerRow
                Button {
                    showBreakSheet = true
                } label: {
                    Label("Take a Break", systemImage: "cup.and.saucer")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .tint(FocusColors.breakBlue)
            }

            if engine.phase == .breakPhase {
                breakKindsRow
            }
        }
    }

    private var primaryControlButtons: some View {
        HStack(spacing: 10) {
            if !engine.isActive {
                Button { Haptics.medium(); engine.start() } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(engine.phase == .work ? FocusColors.focusRed : FocusColors.breakBlue)
            } else {
                Button { Haptics.tap(); engine.toggleRunPause() } label: {
                    Label(engine.isRunning ? "Pause" : "Resume",
                          systemImage: engine.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(engine.phase == .work ? FocusColors.focusRed : FocusColors.breakBlue)

                Button {
                    Haptics.warning()
                    if engine.phase == .breakPhase { engine.skip() } else { engine.stop() }
                } label: {
                    Label(engine.phase == .breakPhase ? "Skip" : "Stop",
                          systemImage: engine.phase == .breakPhase ? "forward.fill" : "stop.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
        }
    }

    private var tagPickerRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(settings.tags, id: \.self) { tag in
                    let selected = engine.currentLabel == tag
                    Button {
                        engine.currentLabel = selected ? "" : tag
                    } label: {
                        Text(tag)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(
                                Capsule().fill(selected ? FocusColors.focusRed.opacity(0.18) : Color(.tertiarySystemFill))
                            )
                            .foregroundStyle(selected ? FocusColors.focusRed : .primary)
                    }
                }
                Button {
                    showLabelPicker = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(Color(.tertiarySystemFill)))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var breakKindsRow: some View {
        HStack(spacing: 10) {
            ForEach(BreakKind.allCases) { kind in
                let on = engine.currentBreakKinds.contains(kind)
                Button {
                    if on { engine.currentBreakKinds.removeAll { $0 == kind } }
                    else { engine.currentBreakKinds.append(kind) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: kind.icon).font(.system(size: 18))
                        Text(kind.displayName).font(.caption)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(on ? FocusColors.breakBlue.opacity(0.18) : Color(.tertiarySystemFill))
                    )
                    .foregroundStyle(on ? FocusColors.breakBlue : .secondary)
                }
            }
        }
    }

    // MARK: - Today footer

    private var todayFooter: some View {
        let focus = PadStats.workMinutes(sessions, on: Date())
        let count = PadStats.sessionCount(sessions, on: Date())
        let goalMin = Double(settings.dailyGoalHours) * 60
        let pct = goalMin > 0 ? min(focus / goalMin, 1.0) : 0
        return PadCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    PadSectionHeader(title: "TODAY")
                    Spacer()
                    Text("\(PadStats.fmtMinutes(focus)) / \(settings.dailyGoalHours)h")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.15))
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(colors: [FocusColors.focusRed.opacity(0.7), FocusColors.focusRed],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, geo.size.width * pct))
                    }
                }
                .frame(height: 10)

                HStack(spacing: 14) {
                    miniStat(value: "\(count)", label: "Sessions")
                    miniStat(value: "\(Int(pct * 100))%", label: "Of goal")
                    miniStat(value: "\(engine.workSessionsCompletedToday)", label: "This run")
                }
            }
        }
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Day actions

    private func startDay() {
        let ctx = ModelContext(engineContainer)
        let today = Calendar.current.startOfDay(for: Date())
        let existing = (try? ctx.fetch(FetchDescriptor<StoredDayRecord>(
            predicate: #Predicate { $0.calendarDay == today }
        )))?.first
        if let existing {
            existing.dayStart = Date()
        } else {
            let rec = StoredDayRecord()
            rec.calendarDay = today
            rec.dayStart = Date()
            ctx.insert(rec)
        }
        try? ctx.save()
        if settings.commitmentEnabled && settings.needsCommitmentToday {
            showCommitment = true
        }
    }

    private func endDay() {
        let ctx = ModelContext(engineContainer)
        let today = Calendar.current.startOfDay(for: Date())
        if let rec = (try? ctx.fetch(FetchDescriptor<StoredDayRecord>(
            predicate: #Predicate { $0.calendarDay == today }
        )))?.first {
            rec.dayEnd = Date()
            try? ctx.save()
        }
    }

    private var engineContainer: ModelContainer {
        // Pull the same container through the SwiftData environment via modelContext.
        // We use a workaround: re-read via the environment in this view.
        engineContainerFromEnvironment
    }

    @Environment(\.modelContext) private var contextEnv
    private var engineContainerFromEnvironment: ModelContainer { contextEnv.container }
}

// MARK: - Break sheet

private struct BreakSheet: View {
    @ObservedObject var engine: FocusTimerEngine
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Double = 30
    @State private var kinds: Set<BreakKind> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Duration") {
                    HStack(spacing: 8) {
                        ForEach([15, 30, 60, 90, 120], id: \.self) { m in
                            Button {
                                minutes = Double(m)
                            } label: {
                                Text(m >= 60 ? "\(m / 60)h" : "\(m)m")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(minutes == Double(m) ? FocusColors.breakBlue.opacity(0.2) : Color(.tertiarySystemFill))
                                    )
                                    .foregroundStyle(minutes == Double(m) ? FocusColors.breakBlue : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Stepper(value: $minutes, in: 5...480, step: 5) {
                        Text("Custom: \(Int(minutes)) min")
                    }
                }
                Section("Type") {
                    HStack(spacing: 10) {
                        ForEach(BreakKind.allCases) { k in
                            Button {
                                if kinds.contains(k) { kinds.remove(k) } else { kinds.insert(k) }
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: k.icon).font(.system(size: 18))
                                    Text(k.displayName).font(.caption)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(kinds.contains(k) ? FocusColors.breakBlue.opacity(0.2) : Color(.tertiarySystemFill))
                                )
                                .foregroundStyle(kinds.contains(k) ? FocusColors.breakBlue : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Take a Break")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        engine.startManualBreak(minutes: minutes, kinds: Array(kinds))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Custom-label picker

private struct LabelPickerSheet: View {
    @ObservedObject var engine: FocusTimerEngine
    @ObservedObject var settings: PadSettings
    @Environment(\.dismiss) private var dismiss
    @State private var newTag = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Active Tag") {
                    if engine.currentLabel.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Text(engine.currentLabel).bold()
                            Spacer()
                            Button("Clear", role: .destructive) { engine.currentLabel = "" }
                        }
                    }
                }
                Section("Pick a Tag") {
                    ForEach(settings.tags, id: \.self) { t in
                        Button {
                            engine.currentLabel = t
                            dismiss()
                        } label: {
                            HStack {
                                Text(t)
                                Spacer()
                                if engine.currentLabel == t {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
                Section("New Tag") {
                    HStack {
                        TextField("e.g. ML", text: $newTag)
                        Button("Add") {
                            let t = newTag.trimmingCharacters(in: .whitespaces)
                            guard !t.isEmpty, !settings.tags.contains(t) else { return }
                            settings.tags.append(t)
                            engine.currentLabel = t
                            newTag = ""
                            dismiss()
                        }
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Commitment sheet

struct CommitmentSheet: View {
    @ObservedObject var settings: PadSettings
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: PadTheme.pad) {
                Text("What will you accomplish today?")
                    .font(.title3).fontWeight(.semibold)
                Text("Write a clear, specific commitment. You can change it later.")
                    .font(.callout).foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                Spacer()
            }
            .padding(PadTheme.largePad)
            .navigationTitle("Daily Commitment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Skip") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Commit") {
                        settings.markCommitmentDone(text.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { text = settings.todayCommitment }
        }
    }
}

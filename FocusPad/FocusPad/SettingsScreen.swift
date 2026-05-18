import SwiftUI
import SwiftData
import FocusCore

struct SettingsScreen: View {
    @EnvironmentObject var settings: PadSettings
    @EnvironmentObject var engine: FocusTimerEngine
    @Environment(\.modelContext) private var context

    @State private var newTag = ""
    @State private var newSource = ""
    @State private var showInterviewPicker = false

    var body: some View {
        Form {
            Section("Daily Goal") {
                Stepper(value: $settings.dailyGoalHours, in: 1...16) {
                    HStack {
                        Text("Target")
                        Spacer()
                        Text("\(settings.dailyGoalHours)h")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Focus Session") {
                Stepper(value: $settings.workMinutes, in: 5...180, step: 5) {
                    HStack {
                        Text("Default length")
                        Spacer()
                        Text("\(Int(settings.workMinutes))m")
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $settings.breakMinutes, in: 5...60, step: 5) {
                    HStack {
                        Text("Default break")
                        Spacer()
                        Text("\(Int(settings.breakMinutes))m")
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $settings.pauseGraceMinutes, in: 1...60) {
                    HStack {
                        Text("Pause auto-end after")
                        Spacer()
                        Text("\(settings.pauseGraceMinutes)m")
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Auto-start break", isOn: $settings.autoStartBreaks)
                Toggle("Auto-start next focus", isOn: $settings.autoStartWork)
                Toggle("Sound on completion", isOn: $settings.soundEnabled)
            }
            .onChange(of: settings.workMinutes) { _, _ in engine.settings = settings.engineSettings }
            .onChange(of: settings.breakMinutes) { _, _ in engine.settings = settings.engineSettings }
            .onChange(of: settings.autoStartBreaks) { _, _ in engine.settings = settings.engineSettings }
            .onChange(of: settings.autoStartWork) { _, _ in engine.settings = settings.engineSettings }
            .onChange(of: settings.pauseGraceMinutes) { _, _ in engine.settings = settings.engineSettings }

            Section("Focus Tags") {
                ForEach(settings.tags, id: \.self) { tag in
                    HStack {
                        Text(tag)
                        Spacer()
                        Button(role: .destructive) {
                            settings.tags.removeAll { $0 == tag }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onDelete { offsets in
                    for i in offsets { settings.tags.remove(at: i) }
                }
                HStack {
                    TextField("New tag", text: $newTag)
                    Button("Add") {
                        let t = newTag.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty, !settings.tags.contains(t) else { return }
                        settings.tags.append(t)
                        newTag = ""
                    }
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Problem Goals") {
                Stepper(value: $settings.quantGoal, in: 0...100) {
                    HStack { Text("Quant daily"); Spacer(); Text("\(settings.quantGoal)").foregroundStyle(.secondary) }
                }
                Stepper(value: $settings.quantWeeklyGoal, in: 0...500) {
                    HStack { Text("Quant weekly"); Spacer(); Text("\(settings.quantWeeklyGoal)").foregroundStyle(.secondary) }
                }
                Stepper(value: $settings.sweGoal, in: 0...100) {
                    HStack { Text("SWE daily"); Spacer(); Text("\(settings.sweGoal)").foregroundStyle(.secondary) }
                }
                Stepper(value: $settings.sweWeeklyGoal, in: 0...500) {
                    HStack { Text("SWE weekly"); Spacer(); Text("\(settings.sweWeeklyGoal)").foregroundStyle(.secondary) }
                }
            }

            Section("Problem Sources") {
                ForEach(settings.problemSources, id: \.self) { src in
                    Text(src)
                }
                .onDelete { offsets in
                    for i in offsets { settings.problemSources.remove(at: i) }
                }
                HStack {
                    TextField("New source", text: $newSource)
                    Button("Add") {
                        let s = newSource.trimmingCharacters(in: .whitespaces)
                        guard !s.isEmpty, !settings.problemSources.contains(s) else { return }
                        settings.problemSources.append(s)
                        newSource = ""
                    }
                    .disabled(newSource.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Interview Date") {
                Toggle("Track countdown", isOn: Binding(
                    get: { settings.interviewDate != nil },
                    set: { on in
                        if on {
                            settings.interviewDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())
                        } else {
                            settings.interviewDate = nil
                        }
                    }
                ))
                if settings.interviewDate != nil {
                    DatePicker("Date",
                               selection: Binding(
                                get: { settings.interviewDate ?? Date() },
                                set: { settings.interviewDate = $0 }
                               ),
                               displayedComponents: .date)
                }
            }

            Section("Daily Commitment") {
                Toggle("Ask each morning", isOn: $settings.commitmentEnabled)
                if !settings.todayCommitment.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today").font(.caption).foregroundStyle(.secondary)
                        Text(settings.todayCommitment).font(.callout)
                    }
                }
            }

            Section("Sync") {
                Toggle("iCloud Sync (CloudKit)", isOn: $settings.cloudKitSyncEnabled)
                Text("Changes take effect on next launch. Requires iCloud sign-in.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Danger Zone") {
                Button(role: .destructive) { clearAllData() } label: {
                    Label("Clear All Local Data", systemImage: "trash")
                }
            }

            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 2) {
                        Text("Focus for iPad").font(.caption).foregroundStyle(.secondary)
                        Text("v1.0").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }

    private func clearAllData() {
        let ctx = context
        for s in (try? ctx.fetch(FetchDescriptor<StoredWorkSession>())) ?? [] { ctx.delete(s) }
        for p in (try? ctx.fetch(FetchDescriptor<StoredProblem>())) ?? [] { ctx.delete(p) }
        for h in (try? ctx.fetch(FetchDescriptor<StoredHomework>())) ?? [] { ctx.delete(h) }
        for d in (try? ctx.fetch(FetchDescriptor<StoredDayRecord>())) ?? [] { ctx.delete(d) }
        for i in (try? ctx.fetch(FetchDescriptor<StoredScratchItem>())) ?? [] { ctx.delete(i) }
        try? ctx.save()
    }
}

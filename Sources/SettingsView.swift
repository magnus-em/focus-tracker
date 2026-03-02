import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var timer: TimerManager
    @ObservedObject var store: SessionStore
    @State private var showResetConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Intervals
                SectionLabel("INTERVALS")

                IntervalRow(label: "Focus", value: $settings.workMinutes, range: 5...90, step: 5, unit: "min")
                IntervalRow(label: "Short Break", value: $settings.shortBreakMinutes, range: 1...30, step: 1, unit: "min")
                IntervalRow(label: "Long Break", value: $settings.longBreakMinutes, range: 5...60, step: 5, unit: "min")
                IntRow(label: "Long Break After", value: $settings.sessionsBeforeLongBreak, range: 2...10, suffix: "sessions")

                Divider()

                // Goal
                SectionLabel("DAILY GOAL")
                IntRow(label: "Target Sessions", value: $settings.dailyGoal, range: 1...20, suffix: "")

                Divider()

                // Automation
                SectionLabel("BEHAVIOR")

                ToggleRow(label: "Auto-start breaks", isOn: $settings.autoStartBreaks)
                ToggleRow(label: "Auto-start focus", isOn: $settings.autoStartWork)
                ToggleRow(label: "Sound effects", isOn: $settings.soundEnabled)

                Divider()

                // Site Blocking
                SectionLabel("SITE BLOCKING")

                ToggleRow(label: "Block distracting sites", isOn: $settings.siteBlockingEnabled)

                if settings.siteBlockingEnabled {
                    ToggleRow(label: "Block during breaks too", isOn: $settings.blockDuringBreaks)
                    BlockedSitesView(settings: settings)
                        .padding(.top, 2)
                }

                Divider()

                // Reset
                if showResetConfirm {
                    VStack(spacing: 8) {
                        Text("Delete all session history?")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)

                        Text("This cannot be undone.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button {
                                showResetConfirm = false
                            } label: {
                                Text("Cancel")
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(.secondary.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)

                            Button {
                                store.clearAllData()
                                showResetConfirm = false
                            } label: {
                                Text("Reset")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.85))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(.secondary.opacity(0.05))
                    .cornerRadius(8)
                } else {
                    HStack {
                        Spacer()
                        Button {
                            showResetConfirm = true
                        } label: {
                            Text("Reset All Data")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red.opacity(0.8))
                        Spacer()
                    }
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
        }
        .onChange(of: settings.workMinutes) { _, _ in timer.applySettings() }
        .onChange(of: settings.shortBreakMinutes) { _, _ in timer.applySettings() }
        .onChange(of: settings.longBreakMinutes) { _, _ in timer.applySettings() }
        .onChange(of: settings.sessionsBeforeLongBreak) { _, _ in timer.applySettings() }
    }
}

// MARK: - Subviews

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(.secondary)
    }
}

private struct IntervalRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text("\(Int(value)) \(unit)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

private struct IntRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var suffix: String = ""

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text(suffix.isEmpty ? "\(value)" : "\(value) \(suffix)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 56, alignment: .trailing)
            Stepper("", value: $value, in: range)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

private struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

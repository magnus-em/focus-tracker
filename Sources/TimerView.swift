import SwiftUI

struct TimerView: View {
    @ObservedObject var timer: TimerManager
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var dayStore: DayStore
    @Binding var showCommitment: Bool

    @State private var showBreakPicker = false
    @State private var customBreakMinutes: Double = 30

    private var phaseColor: Color {
        switch timer.currentPhase {
        case .work:       return Color(red: 0.96, green: 0.36, blue: 0.36)
        case .shortBreak, .longBreak: return Color(red: 0.27, green: 0.62, blue: 0.83)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            dayStatusRow

            Text(timer.currentPhase.displayName.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(phaseColor)

            if !timer.isOnBreak {
                if settings.tags.isEmpty {
                    Text("Add categories in the Stats tab")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                } else {
                    glassChipGroup {
                        HStack(spacing: 6) {
                            ForEach(settings.tags, id: \.self) { tag in
                                let selected = timer.currentLabel == tag
                                Button(tag) { timer.currentLabel = selected ? "" : tag }
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .foregroundStyle(selected ? phaseColor : Color.secondary)
                                    .glassChip()
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            if timer.isBlockingActive {
                HStack(spacing: 4) {
                    Image(systemName: "shield.fill").font(.system(size: 9))
                    Text("Sites Blocked").font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(phaseColor.opacity(0.7))
            }

            if !timer.isActive && !timer.isOnBreak {
                glassChipGroup {
                    HStack(spacing: 6) {
                        ForEach([15, 25, 45, 60], id: \.self) { mins in
                            let selected = Int(timer.totalTime / 60) == mins
                            Button("\(mins)m") { timer.setSessionDuration(Double(mins)) }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .foregroundStyle(selected ? phaseColor : Color.secondary)
                                .glassChip()
                                .buttonStyle(.plain)
                        }
                    }
                }
            }

            ZStack {
                Circle()
                    .stroke(phaseColor.opacity(0.12), lineWidth: 8)
                    .frame(width: 140, height: 140)
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(phaseColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: timer.progress)

                VStack(spacing: 4) {
                    Text(timer.timeString)
                        .font(.system(size: 34, weight: .medium, design: .monospaced))
                        .contentTransition(.numericText())
                        .animation(.linear(duration: 0.3), value: timer.timeString)

                    if !timer.isOnBreak && store.todaySessionCount > 0 {
                        Text("Session \(store.todaySessionCount + (timer.isActive ? 1 : 0))")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(phaseColor.opacity(0.5))
                    }
                }
            }

            HStack(spacing: 12) {
                controlSecondaryButton(
                    systemImage: timer.isActive ? "stop.fill" : "arrow.counterclockwise",
                    help: timer.isActive ? "End session (saves progress)" : "Reset timer"
                ) { timer.reset() }

                controlPrimaryButton(
                    systemImage: timer.isRunning ? "pause.fill" : "play.fill",
                    tint: phaseColor
                ) { timer.isRunning ? timer.pause() : timer.start() }

                controlSecondaryButton(
                    systemImage: "forward.fill",
                    help: "Skip"
                ) { timer.skip() }
            }

            if timer.isActive && !timer.isOnBreak {
                glassChipGroup {
                    HStack(spacing: 6) {
                        ForEach([-10, -5, 5, 10], id: \.self) { delta in
                            Button(delta > 0 ? "+\(delta)m" : "\(delta)m") {
                                timer.adjustDuration(by: Double(delta))
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .foregroundStyle(delta > 0 ? phaseColor : Color.secondary)
                            .glassChip()
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !timer.isActive && !timer.isOnBreak {
                if showBreakPicker {
                    inlineBreakPicker
                } else {
                    Button {
                        showBreakPicker = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "cup.and.saucer")
                                .font(.system(size: 10))
                            Text("Take a Break")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .glassChip()
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().padding(.horizontal, 8)

            if settings.dailyGoal > 0 {
                let hoursToday = store.todayWorkMinutes / 60.0
                let pct = min(1.0, hoursToday / Double(settings.dailyGoal))
                let goalMet = hoursToday >= Double(settings.dailyGoal)
                let barColor: Color = goalMet ? .green : phaseColor

                VStack(spacing: 4) {
                    HStack {
                        Text("Daily Goal")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1fh / %dh", hoursToday, settings.dailyGoal))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(goalMet ? Color.green : .primary)
                            .contentTransition(.numericText())
                        if goalMet {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.12))
                            Capsule()
                                .fill(barColor)
                                .frame(width: geo.size.width * CGFloat(pct))
                                .animation(.spring(response: 0.5), value: pct)
                        }
                    }
                    .frame(height: 5)
                }
                .padding(.horizontal, 4)
            }

            HStack {
                VStack(spacing: 2) {
                    Text(formatMinutes(store.todayWorkMinutes))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("Focus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text(formatMinutes(store.todayBreakMinutes))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Text("Break")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(store.currentStreak)d")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(store.currentStreak > 0 ? .orange : .secondary)
                    Text("Streak")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var inlineBreakPicker: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Take a Break")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showBreakPicker = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            glassChipGroup {
                HStack(spacing: 6) {
                    ForEach([30.0, 60.0, 120.0], id: \.self) { mins in
                        let label = mins < 60 ? "\(Int(mins))m" : "\(Int(mins / 60))h"
                        Button(label) {
                            showBreakPicker = false
                            timer.startManualBreak(minutes: mins)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(Color(red: 0.27, green: 0.62, blue: 0.83))
                        .glassChip()
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    customBreakMinutes = max(5, customBreakMinutes - 5)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 24)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Text("\(Int(customBreakMinutes)) min")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(minWidth: 54)

                Button {
                    customBreakMinutes = min(480, customBreakMinutes + 5)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 24)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Start") {
                    let mins = customBreakMinutes
                    showBreakPicker = false
                    timer.startManualBreak(minutes: mins)
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .foregroundStyle(Color(red: 0.27, green: 0.62, blue: 0.83))
                .glassChip()
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func controlPrimaryButton(systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        if #available(macOS 26.0, *) {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.glassProminent)
            .tint(tint)
            .clipShape(Circle())
        } else {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(tint)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func controlSecondaryButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        if #available(macOS 26.0, *) {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.glass)
            .clipShape(Circle())
            .help(help)
        } else {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(help)
        }
    }

    @ViewBuilder
    private var dayStatusRow: some View {
        Group {
            if dayStore.isDayEnded {
                HStack(spacing: 4) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text("Day ended")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            } else if dayStore.isDayStarted {
                HStack {
                    if let start = dayStore.todayRecord?.dayStart {
                        HStack(spacing: 3) {
                            Image(systemName: "sunrise.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text("Since \(clockStr(start))")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Button("End Day") { dayStore.endDay() }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                }
            } else {
                HStack {
                    Spacer()
                    Button {
                        dayStore.startDay()
                        if settings.commitmentEnabled && settings.needsCommitmentToday {
                            showCommitment = true
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sunrise.fill")
                                .font(.system(size: 10))
                            Text("Start Day")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(phaseColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(phaseColor.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func formatMinutes(_ minutes: Double) -> String {
        let h = Int(minutes) / 60, m = Int(minutes) % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func clockStr(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mma"; return f.string(from: d)
    }
}


import SwiftUI

struct TimerView: View {
    @ObservedObject var timer: TimerManager
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: AppSettings

    private var phaseColor: Color {
        switch timer.currentPhase {
        case .work:       return Color(red: 0.96, green: 0.36, blue: 0.36)
        case .shortBreak: return Color(red: 0.30, green: 0.78, blue: 0.74)
        case .longBreak:  return Color(red: 0.27, green: 0.62, blue: 0.83)
        }
    }

    private var goalProgress: Double {
        guard settings.dailyGoal > 0 else { return 0 }
        return min(1.0, Double(store.todaySessionCount) / Double(settings.dailyGoal))
    }

    var body: some View {
        VStack(spacing: 12) {
            // Phase label
            Text(timer.currentPhase.rawValue.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(phaseColor)

            // Category selector
            if settings.tags.isEmpty {
                Text("Add categories in the Stats tab")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(settings.tags, id: \.self) { tag in
                            let selected = timer.currentLabel == tag
                            Button(tag) {
                                timer.currentLabel = selected ? "" : tag
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selected ? phaseColor.opacity(0.18) : Color.secondary.opacity(0.08))
                            .foregroundStyle(selected ? phaseColor : Color.secondary)
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }

            // Blocking badge
            if timer.isBlockingActive {
                HStack(spacing: 4) {
                    Image(systemName: "shield.fill").font(.system(size: 9))
                    Text("Sites Blocked").font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(phaseColor.opacity(0.7))
            }

            // Quick presets — only when idle on a work phase
            if !timer.isActive && timer.currentPhase == .work {
                HStack(spacing: 6) {
                    ForEach([15, 25, 45, 60], id: \.self) { mins in
                        let selected = Int(timer.totalTime / 60) == mins
                        Button("\(mins)m") { timer.setSessionDuration(Double(mins)) }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(selected ? phaseColor.opacity(0.18) : Color.secondary.opacity(0.07))
                            .foregroundStyle(selected ? phaseColor : Color.secondary)
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                    }
                }
            }

            // Circular timer ring
            ZStack {
                // Outer ring — daily goal progress (hidden when goal is off)
                if settings.dailyGoal > 0 {
                    Circle()
                        .stroke(Color.secondary.opacity(0.08), lineWidth: 3)
                        .frame(width: 156, height: 156)
                    Circle()
                        .trim(from: 0, to: goalProgress)
                        .stroke(phaseColor.opacity(0.3), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 156, height: 156)
                        .rotationEffect(.degrees(-90))
                }

                // Inner ring — session progress
                Circle()
                    .stroke(phaseColor.opacity(0.12), lineWidth: 8)
                    .frame(width: 136, height: 136)
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(phaseColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 136, height: 136)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: timer.progress)

                // Center display
                VStack(spacing: 4) {
                    Text(timer.timeString)
                        .font(.system(size: 34, weight: .medium, design: .monospaced))
                        .contentTransition(.numericText())
                        .animation(.linear(duration: 0.3), value: timer.timeString)

                    // Cycle position dots
                    if timer.currentPhase == .work {
                        let done = timer.workSessionsCompleted % settings.sessionsBeforeLongBreak
                        HStack(spacing: 5) {
                            ForEach(0..<settings.sessionsBeforeLongBreak, id: \.self) { i in
                                Circle()
                                    .fill(
                                        i < done  ? phaseColor :
                                        i == done ? phaseColor.opacity(0.5) :
                                                    phaseColor.opacity(0.15)
                                    )
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                }
            }

            // Controls
            HStack(spacing: 12) {
                Button {
                    timer.reset()
                } label: {
                    Image(systemName: timer.isActive ? "stop.fill" : "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(timer.isActive ? "End session (saves progress)" : "Reset timer")

                Button {
                    guard !timer.isAwaitingFlowDecision else { return }
                    timer.isRunning ? timer.pause() : timer.start()
                } label: {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(phaseColor)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button(action: timer.skip) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Duration adjustment — active work session only, not during flow decision
            if timer.isActive && timer.currentPhase == .work && !timer.isAwaitingFlowDecision {
                HStack(spacing: 6) {
                    ForEach([-10, -5, 5, 10], id: \.self) { delta in
                        Button(delta > 0 ? "+\(delta)m" : "\(delta)m") {
                            timer.adjustDuration(by: Double(delta))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.07))
                        .foregroundStyle(delta > 0 ? phaseColor : Color.secondary)
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider().padding(.horizontal, 8)

            // Today's stats
            HStack {
                VStack(spacing: 2) {
                    Text("\(store.todaySessionCount)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("Sessions")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text(formatMinutes(store.todayWorkMinutes))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("Focus Time")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                if settings.dailyGoal > 0 {
                    VStack(spacing: 2) {
                        Text("\(store.todaySessionCount)/\(settings.dailyGoal)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(store.todaySessionCount >= settings.dailyGoal ? .green : .primary)
                        Text("Goal")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
    }

    private func formatMinutes(_ minutes: Double) -> String {
        let h = Int(minutes) / 60, m = Int(minutes) % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

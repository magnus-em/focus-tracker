import SwiftUI

struct TimerView: View {
    @ObservedObject var timer: TimerManager
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: AppSettings

    private var phaseColor: Color {
        switch timer.currentPhase {
        case .work: return Color(red: 0.96, green: 0.36, blue: 0.36)
        case .shortBreak: return Color(red: 0.30, green: 0.78, blue: 0.74)
        case .longBreak: return Color(red: 0.27, green: 0.62, blue: 0.83)
        }
    }

    private var goalProgress: Double {
        guard settings.dailyGoal > 0 else { return 0 }
        return min(1.0, Double(store.todaySessionCount) / Double(settings.dailyGoal))
    }

    var body: some View {
        VStack(spacing: 14) {
            // Phase label
            Text(timer.currentPhase.rawValue.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(phaseColor)

            if timer.isBlockingActive {
                HStack(spacing: 4) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 9))
                    Text("Sites Blocked")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(phaseColor.opacity(0.7))
                .padding(.top, -8)
            }

            // Circular timer
            ZStack {
                // Daily goal outer ring (thin)
                Circle()
                    .stroke(Color.secondary.opacity(0.08), lineWidth: 3)
                    .frame(width: 156, height: 156)

                Circle()
                    .trim(from: 0, to: goalProgress)
                    .stroke(
                        phaseColor.opacity(0.3),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 156, height: 156)
                    .rotationEffect(.degrees(-90))

                // Session progress ring
                Circle()
                    .stroke(phaseColor.opacity(0.12), lineWidth: 8)
                    .frame(width: 136, height: 136)

                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(phaseColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 136, height: 136)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: timer.progress)

                // Time display
                VStack(spacing: 3) {
                    Text(timer.timeString)
                        .font(.system(size: 34, weight: .medium, design: .monospaced))
                        .contentTransition(.numericText())
                        .animation(.linear(duration: 0.3), value: timer.timeString)

                    if timer.currentPhase == .work {
                        Text("Round \(timer.currentCyclePosition) of \(settings.sessionsBeforeLongBreak)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Controls
            HStack(spacing: 12) {
                Button(action: timer.reset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(.secondary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button(action: { timer.isRunning ? timer.pause() : timer.start() }) {
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
                        .background(.secondary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Divider().padding(.horizontal, 8)

            // Today's stats
            HStack {
                VStack(spacing: 2) {
                    Text("\(store.todaySessionCount)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Sessions")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text(formatMinutes(store.todayWorkMinutes))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Focus Time")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

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
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
    }

    private func formatMinutes(_ minutes: Double) -> String {
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}

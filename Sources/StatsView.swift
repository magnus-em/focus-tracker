import SwiftUI
import Charts

struct StatsView: View {
    @ObservedObject var store: SessionStore

    private var summaries: [DailySummary] {
        store.dailySummaries(last: 14)
    }

    private var maxMinutes: Double {
        summaries.map(\.totalWorkMinutes).max() ?? 0
    }

    private var weekTotal: Double {
        store.dailySummaries(last: 7).reduce(0) { $0 + $1.totalWorkMinutes }
    }

    var body: some View {
        VStack(spacing: 14) {
            // Summary cards
            HStack(spacing: 0) {
                StatCard(
                    value: formatMinutes(store.todayWorkMinutes),
                    label: "Today"
                )
                StatCard(
                    value: formatMinutes(weekTotal),
                    label: "This Week"
                )
                StatCard(
                    value: "\(store.currentStreak)",
                    label: "Day Streak",
                    icon: store.currentStreak > 0 ? "flame.fill" : nil,
                    iconColor: .orange
                )
            }

            // Chart - always rendered, empty data shows flat bars
            VStack(alignment: .leading, spacing: 6) {
                Text("LAST 14 DAYS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)

                Chart(summaries) { summary in
                    BarMark(
                        x: .value("Date", summary.date, unit: .day),
                        y: .value("Minutes", summary.totalWorkMinutes)
                    )
                    .foregroundStyle(
                        Color(red: 0.96, green: 0.36, blue: 0.36)
                            .opacity(Calendar.current.isDateInToday(summary.date) ? 1.0 : 0.7)
                    )
                    .cornerRadius(3)
                }
                .chartYScale(domain: 0...max(maxMinutes * 1.15, 30))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(shortDateLabel(date))
                                    .font(.system(size: 9))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.secondary.opacity(0.15))
                        AxisValueLabel {
                            if let mins = value.as(Double.self) {
                                Text(formatMinutesShort(mins))
                                    .font(.system(size: 9))
                            }
                        }
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea.background(Color.secondary.opacity(0.02))
                }
                .frame(height: 130)
            }

            // Lifetime stats
            Divider().padding(.horizontal, 8)

            HStack(spacing: 0) {
                MiniStat(value: "\(store.totalWorkSessions)", label: "Total Sessions")
                MiniStat(value: formatHours(store.totalWorkHours), label: "Total Hours")
                MiniStat(value: formatMinutes(store.weeklyAverage()), label: "Daily Avg")
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
    }

    private func shortDateLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private func formatMinutes(_ minutes: Double) -> String {
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    private func formatMinutesShort(_ minutes: Double) -> String {
        if minutes >= 60 {
            return "\(Int(minutes) / 60)h"
        }
        return "\(Int(minutes))m"
    }

    private func formatHours(_ hours: Double) -> String {
        if hours >= 1 {
            return String(format: "%.1fh", hours)
        }
        return "\(Int(hours * 60))m"
    }
}

struct StatCard: View {
    let value: String
    let label: String
    var icon: String? = nil
    var iconColor: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(iconColor)
                }
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MiniStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

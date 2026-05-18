import SwiftUI

/// 18-week (≈4 months) GitHub-style heatmap. Each cell = one day.
struct HeatmapView: View {
    /// (day → minutes). Days outside the range are treated as 0.
    let minutesByDay: [Date: Double]
    var weeks: Int = 18
    var cell: CGFloat = 14
    var gap: CGFloat = 3
    var tint: Color

    private var cal: Calendar { Calendar.current }
    private var endOfToday: Date { cal.startOfDay(for: Date()).addingTimeInterval(86400 - 1) }
    private var startDay: Date {
        let today = cal.startOfDay(for: Date())
        // Week containing today, then go back `weeks - 1` more weeks. Week starts Monday for compactness.
        let weekday = cal.component(.weekday, from: today) // 1=Sun..7=Sat
        let mondayOffset = ((weekday + 5) % 7) // Sun→6, Mon→0, Tue→1...
        let thisWeekMonday = cal.date(byAdding: .day, value: -mondayOffset, to: today)!
        return cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeekMonday)!
    }

    var body: some View {
        let columns = Array(0..<weeks)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: gap) {
                ForEach(columns, id: \.self) { w in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = cal.date(byAdding: .day, value: w * 7 + d, to: startDay)!
                            cellView(for: day)
                        }
                    }
                }
            }
            HStack(spacing: 5) {
                Text("Less").font(.system(size: 9)).foregroundStyle(.tertiary)
                ForEach(0..<5) { lvl in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: Double(lvl) / 4.0 * 240.0))
                        .frame(width: 10, height: 10)
                }
                Text("More").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    private func cellView(for day: Date) -> some View {
        let mins = minutesByDay[cal.startOfDay(for: day)] ?? 0
        let isFuture = day > Date()
        return RoundedRectangle(cornerRadius: 3)
            .fill(isFuture ? Color.gray.opacity(0.05) : color(for: mins))
            .frame(width: cell, height: cell)
    }

    private func color(for minutes: Double) -> Color {
        if minutes <= 0 { return Color.gray.opacity(0.15) }
        // Buckets: 0–30, 30–90, 90–180, 180–300, 300+
        let level: Double
        switch minutes {
        case ..<30:   level = 0.22
        case ..<90:   level = 0.40
        case ..<180:  level = 0.60
        case ..<300:  level = 0.80
        default:      level = 1.00
        }
        return tint.opacity(level)
    }
}

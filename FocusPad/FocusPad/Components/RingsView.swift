import SwiftUI

/// Apple-Fitness-style nested rings. Up to 3 rings.
struct RingsView: View {
    struct Ring: Identifiable {
        let id: String
        let progress: Double         // 0.0–∞; >1 wraps with a darker glow
        let color: Color
        let label: String
        let value: String            // big text in summary
        let goal: String             // goal text
    }

    let rings: [Ring]
    var lineWidth: CGFloat = 22
    var spacing: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(Array(rings.enumerated()), id: \.element.id) { idx, ring in
                    let inset = CGFloat(idx) * (lineWidth + spacing)
                    SingleRing(progress: ring.progress, color: ring.color, lineWidth: lineWidth)
                        .padding(inset)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SingleRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            // First lap.
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [color.opacity(0.7), color]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(360 - 90)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Overflow lap (>100%) — darker color glow.
            if progress > 1 {
                Circle()
                    .trim(from: 0, to: min(progress - 1.0, 1.0))
                    .stroke(
                        color.opacity(0.9),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.6), radius: 4)
            }
        }
        .animation(.easeOut(duration: 0.6), value: progress)
    }
}

/// Compact ring legend (label · value / goal · color dot).
struct RingsLegend: View {
    let rings: [RingsView.Ring]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(rings) { r in
                HStack(spacing: 10) {
                    Circle().fill(r.color).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.label)
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(r.color)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(r.value)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("/ \(r.goal)")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

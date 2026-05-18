import SwiftUI
import FocusCore

/// Centralized iPad design tokens. Inspired by Apple Fitness + iOS productivity
/// apps — rounded large numerals for metrics, generous padding, soft cards.
enum PadTheme {
    // Card shapes
    static let cardRadius: CGFloat = 18
    static let smallCardRadius: CGFloat = 14
    static let chipRadius: CGFloat = 10

    // Spacing scale
    static let pad: CGFloat = 16
    static let largePad: CGFloat = 24

    // Ring colors (Apple Fitness-style trio)
    static let focusRing = FocusColors.focusRed       // Move
    static let problemsRing = Color.cyan              // Exercise (problems solved)
    static let consistencyRing = Color.green          // Stand (days hit goal)

    // Status accents
    static let warning = Color.orange
    static let danger = Color.red
}

/// Card-style background.
struct PadCard<Content: View>: View {
    var padding: CGFloat = PadTheme.pad
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: PadTheme.cardRadius, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
    }
}

/// Small uppercase section header.
struct PadSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

/// Metric tile (big number + label).
struct PadMetric: View {
    let value: String
    let label: String
    let icon: String
    let tint: Color
    var trailing: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .semibold)).tracking(0.6)
                Spacer()
                if let trailing {
                    Text(trailing).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(tint)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: PadTheme.smallCardRadius, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }
}

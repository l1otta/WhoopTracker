import SwiftUI

/// A visual style loosely inspired by WHOOP's own app — near-black background,
/// a circular strain gauge, colour-coded vitals. Not a copy of their assets
/// (no logos, no proprietary UI code), just the same "dark dashboard with a
/// big ring" language that fitness-wearable apps in this space commonly use.
enum WhoopStyle {
    static let background = Color.black
    static let cardBackground = Color(white: 0.09)
    static let strainColor = Color(red: 0.0, green: 0.75, blue: 1.0)   // WHOOP-ish cyan/blue
    static let recoveryGreen = Color(red: 0.15, green: 0.85, blue: 0.45)
    static let recoveryYellow = Color(red: 0.95, green: 0.75, blue: 0.15)
    static let recoveryRed = Color(red: 0.9, green: 0.25, blue: 0.3)
    static let textSecondary = Color(white: 0.6)
}

/// Circular gauge for a 0...maxValue metric — used here for Strain (0-21).
struct RingGauge: View {
    let value: Double
    let maxValue: Double
    let color: Color
    let label: String
    let valueText: String

    private var progress: Double {
        guard maxValue > 0 else { return 0 }
        return min(1, max(0, value / maxValue))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 14)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: progress)

            VStack(spacing: 2) {
                Text(valueText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(WhoopStyle.textSecondary)
                    .textCase(.uppercase)
            }
        }
        .frame(width: 200, height: 200)
    }
}

/// Compact vitals tile — pulse, SpO2, temperature, battery.
struct VitalTile: View {
    let title: String
    let value: String
    let unit: String
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(WhoopStyle.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(WhoopStyle.textSecondary)
            }
            if let footnote {
                Text(footnote)
                    .font(.system(size: 9))
                    .foregroundStyle(WhoopStyle.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(WhoopStyle.cardBackground, in: RoundedRectangle(cornerRadius: 18))
    }
}

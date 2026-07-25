import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Query(sort: \DailyOwnMetric.date) private var history: [DailyOwnMetric]

    private var readiness: ReadinessResult? {
        let points = history.map {
            ReadinessScorer.DailyPoint(
                date: $0.date,
                hrvRMSSD: $0.hrvRMSSD,
                restingHR: $0.minHeartRateBPM,
                strain: $0.strainEstimate
            )
        }
        return ReadinessScorer.score(history: points)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let readiness {
                    ReadinessCard(result: readiness)
                } else {
                    Text("Готовность появится через несколько дней использования — нужна история для сравнения")
                        .font(.caption)
                        .foregroundStyle(WhoopStyle.textSecondary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(WhoopStyle.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                }

                if history.isEmpty {
                    Text("Пока нет сохранённой истории — она копится по дням, пока приложение подключено к браслету")
                        .font(.caption)
                        .foregroundStyle(WhoopStyle.textSecondary)
                } else {
                    ChartSection(title: "Нагрузка (Strain)", color: WhoopStyle.strainColor) {
                        ForEach(history) { point in
                            if let strain = point.strainEstimate {
                                LineMark(x: .value("Дата", point.date, unit: .day), y: .value("Strain", strain))
                            }
                        }
                    }

                    ChartSection(title: "HRV (RMSSD)", color: WhoopStyle.recoveryGreen) {
                        ForEach(history) { point in
                            if let hrv = point.hrvRMSSD {
                                LineMark(x: .value("Дата", point.date, unit: .day), y: .value("HRV", hrv))
                            }
                        }
                    }

                    ChartSection(title: "Мин. пульс за день", color: WhoopStyle.recoveryYellow) {
                        ForEach(history) { point in
                            if let minHR = point.minHeartRateBPM {
                                LineMark(x: .value("Дата", point.date, unit: .day), y: .value("Пульс", minHR))
                            }
                        }
                    }

                    Text("Все графики — из данных, накопленных только с браслета. Никакой выгрузки из официального приложения WHOOP не требуется.")
                        .font(.caption2)
                        .foregroundStyle(WhoopStyle.textSecondary)
                }
            }
            .padding()
        }
        .background(WhoopStyle.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationTitle("История")
    }
}

private struct ChartSection<Content: ChartContent>: View {
    let title: String
    let color: Color
    @ChartContentBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(WhoopStyle.textSecondary)
            Chart {
                content()
            }
            .foregroundStyle(color)
            .frame(height: 160)
        }
        .padding(14)
        .background(WhoopStyle.cardBackground, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct ReadinessCard: View {
    let result: ReadinessResult

    private var color: Color {
        switch result.label {
        case .primed: return WhoopStyle.recoveryGreen
        case .balanced: return WhoopStyle.recoveryGreen.opacity(0.7)
        case .strained: return WhoopStyle.recoveryYellow
        case .runDown: return WhoopStyle.recoveryRed
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ГОТОВНОСТЬ")
                .font(.caption2)
                .foregroundStyle(WhoopStyle.textSecondary)
            Text(result.label.rawValue)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 4) {
                if let hrvZ = result.hrvRMSSDZScoreText { Text(hrvZ) }
                if let drift = result.restingHRDriftText { Text(drift) }
                if let acwr = result.acwrText { Text(acwr) }
                if let monotony = result.monotonyText { Text(monotony) }
            }
            .font(.caption2)
            .foregroundStyle(WhoopStyle.textSecondary)

            Text("Наш синтез по опубликованным спортивно-научным методам (Plews/Buchheit, Lamberts, Gabbett, Foster) — не копия WHOOP Recovery")
                .font(.caption2)
                .foregroundStyle(WhoopStyle.textSecondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(WhoopStyle.cardBackground, in: RoundedRectangle(cornerRadius: 18))
    }
}

private extension ReadinessResult {
    var hrvRMSSDZScoreText: String? {
        guard let z = hrvZScore else { return nil }
        return String(format: "HRV к базовому уровню: %.1fσ", z)
    }
    var restingHRDriftText: String? {
        guard let drift = restingHRDriftBPM else { return nil }
        return String(format: "Дрейф мин. пульса: %+.1f уд/мин", drift)
    }
    var acwrText: String? {
        guard let acwr = acuteChronicRatio else { return nil }
        return String(format: "Острая/хроническая нагрузка: %.2f", acwr)
    }
    var monotonyText: String? {
        guard let m = monotony else { return nil }
        return String(format: "Монотонность нагрузки: %.1f", m)
    }
}

import Foundation
import SwiftData

/// Keeps today's running min/avg heart rate in memory (fed by every live
/// sample) and upserts a single `DailyOwnMetric` row per calendar day.
///
/// The "resting HR" here is just the day's minimum observed heart rate — a
/// rough stand-in for a proper waking/overnight resting HR measurement. It's
/// good enough to feed the Readiness drift signal, but label it honestly in
/// the UI rather than calling it "resting HR" outright.
@MainActor
final class DailyMetricsStore: ObservableObject {
    private var todayHRSum: Double = 0
    private var todayHRCount: Int = 0
    private var todayHRMin: Double?
    private var trackedDay: Date = Calendar.current.startOfDay(for: Date())

    func recordSample(bpm: Double, hrv: Double?, strain: Double?, context: ModelContext) {
        let today = Calendar.current.startOfDay(for: Date())
        if today != trackedDay {
            // Rolled over to a new day — reset in-memory accumulators.
            trackedDay = today
            todayHRSum = 0
            todayHRCount = 0
            todayHRMin = nil
        }

        todayHRSum += bpm
        todayHRCount += 1
        todayHRMin = min(todayHRMin ?? bpm, bpm)

        upsert(
            date: today,
            avgHR: todayHRSum / Double(todayHRCount),
            minHR: todayHRMin,
            hrv: hrv,
            strain: strain,
            context: context
        )
    }

    private func upsert(date: Date, avgHR: Double?, minHR: Double?, hrv: Double?, strain: Double?, context: ModelContext) {
        let descriptor = FetchDescriptor<DailyOwnMetric>(predicate: #Predicate { $0.date == date })
        if let existing = try? context.fetch(descriptor).first {
            existing.avgHeartRateBPM = avgHR
            existing.minHeartRateBPM = minHR
            if let hrv { existing.hrvRMSSD = hrv }
            if let strain { existing.strainEstimate = strain }
        } else {
            let entry = DailyOwnMetric(date: date, avgHeartRateBPM: avgHR, minHeartRateBPM: minHR, hrvRMSSD: hrv, strainEstimate: strain)
            context.insert(entry)
        }
        try? context.save()
    }
}

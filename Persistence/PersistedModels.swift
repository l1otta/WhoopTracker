import Foundation
import SwiftData

/// A daily rollup of our own locally-computed numbers, written from live
/// strap data as you use the app day to day. This — not a CSV import — is
/// the only history source for anyone without a WHOOP subscription: no
/// export required, everything comes straight off the strap.
@Model
final class DailyOwnMetric {
    var date: Date // normalized to the start of the day
    var avgHeartRateBPM: Double?
    var minHeartRateBPM: Double? // rough resting-HR proxy — see caveat in ReadinessScorer usage
    var hrvRMSSD: Double?
    var strainEstimate: Double?

    init(date: Date, avgHeartRateBPM: Double?, minHeartRateBPM: Double?, hrvRMSSD: Double?, strainEstimate: Double?) {
        self.date = date
        self.avgHeartRateBPM = avgHeartRateBPM
        self.minHeartRateBPM = minHeartRateBPM
        self.hrvRMSSD = hrvRMSSD
        self.strainEstimate = strainEstimate
    }
}

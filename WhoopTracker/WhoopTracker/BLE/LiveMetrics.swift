import Foundation

enum WhoopGeneration: String {
    case four = "WHOOP 4.0"
    case five = "WHOOP 5.0"
}

/// Everything the app currently knows how to read, from either generation.
/// Fields are optional and simply stay nil when that generation/firmware
/// doesn't expose the data — the UI is expected to hide a card rather than
/// show a fabricated or guessed value.
struct LiveMetrics {
    var generation: WhoopGeneration?
    var heartRateBPM: Int?
    var batteryPercent: Int?

    // WHOOP 4.0 only — confirmed decoded fields from the custom real-time packet.
    var rrIntervalMS: UInt16?
    var spo2Percent: Int?
    var skinTemperatureC: Double?

    // Computed locally from the above — see HRVCalculator/StrainScorer for method + caveats.
    var hrvRMSSD: Double?
    var strainEstimate: Double?

    static let empty = LiveMetrics()
}

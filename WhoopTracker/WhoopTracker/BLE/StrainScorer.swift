import Foundation

/// Approximates WHOOP's 0-21 Strain score from heart-rate history.
///
/// WHOOP's actual algorithm is proprietary and closed — nobody has reverse
/// engineered the exact model. What follows is a published substitute
/// (Edwards/Banister-style TRIMP weighted by Karvonen %HRR), passed through a
/// logarithmic saturating curve so it *behaves* like the 0-21 scale WHOOP
/// describes publicly (fast to climb early, harder to add each additional
/// point near the top). Treat the output as "our own strain-like number" —
/// it will not match WHOOP's app number-for-number.
enum StrainScorer {

    /// - Parameters:
    ///   - heartRateSamples: (bpm, timestamp) pairs, ideally >=1Hz, covering the period to score.
    ///   - restingHR: user's resting heart rate (bpm).
    ///   - maxHR: user's max heart rate (bpm) — e.g. Tanaka formula: 208 - 0.7 * age.
    static func estimate(
        heartRateSamples: [(bpm: Double, timestamp: Date)],
        restingHR: Double,
        maxHR: Double
    ) -> Double? {
        guard heartRateSamples.count > 1, maxHR > restingHR else { return nil }

        let hrReserve = maxHR - restingHR
        var trimp = 0.0

        for i in 1..<heartRateSamples.count {
            let prev = heartRateSamples[i - 1]
            let curr = heartRateSamples[i]
            let minutes = curr.timestamp.timeIntervalSince(prev.timestamp) / 60.0
            guard minutes > 0, minutes < 5 else { continue } // skip gaps/reconnects

            let avgHR = (prev.bpm + curr.bpm) / 2.0
            let hrr = max(0, min(1, (avgHR - restingHR) / hrReserve))
            // Edwards-style linear weighting kept simple and auditable rather than
            // the exponential Banister term — easier to reason about at a glance.
            trimp += minutes * hrr
        }

        // Logarithmic saturation onto 0-21, so the curve climbs fast early and
        // flattens near the top the way WHOOP describes its own scale behaving.
        let k = 0.11 // calibration constant — tune against your own sessions
        let strain = 21.0 * (1.0 - exp(-k * trimp))
        return min(21.0, strain)
    }

    /// Tanaka et al. (2001) max-HR estimate — a published formula, better
    /// supported by evidence than the older "220 - age" rule of thumb.
    static func estimatedMaxHR(age: Int) -> Double {
        208.0 - 0.7 * Double(age)
    }
}

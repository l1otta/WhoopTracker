import Foundation

/// Computes HRV (RMSSD + SDNN) from a rolling window of R-R intervals, with
/// basic artifact rejection.
///
/// Grounded in the Task Force of the European Society of Cardiology / NASPE
/// 1996 standards for HRV measurement — a public, citable methodology, not
/// anyone's proprietary algorithm. The ectopic-beat filter (reject an R-R
/// interval that jumps >20% from the previous one) is the standard artifact
/// rule cited throughout that literature (often attributed to Malik et al.).
/// WHOOP's own app almost certainly reports something derived from the same
/// underlying R-R data, but whether it's exactly this or a proprietary blend
/// isn't public — treat this as "our own HRV, computed properly", not a
/// reproduction of WHOOP's number.
enum HRVCalculator {

    /// Drops any interval whose jump from the previous one exceeds `maxJumpFraction`
    /// (default 20%) — a simple, standard ectopic/artifact filter.
    static func filterArtifacts(_ rrIntervalsMS: [UInt16], maxJumpFraction: Double = 0.2) -> [Double] {
        var clean: [Double] = []
        var previous: Double?
        for rr in rrIntervalsMS {
            let value = Double(rr)
            if let prev = previous {
                let jump = abs(value - prev) / prev
                if jump > maxJumpFraction {
                    continue // drop the suspected artifact, keep `previous` as-is
                }
            }
            clean.append(value)
            previous = value
        }
        return clean
    }

    /// Root mean square of successive differences, in ms.
    static func rmssd(rrIntervalsMS: [UInt16], windowSize: Int = 60) -> Double? {
        let window = filterArtifacts(Array(rrIntervalsMS.suffix(windowSize)))
        guard window.count > 1 else { return nil }

        var sumSquaredDiffs = 0.0
        for i in 1..<window.count {
            let diff = window[i] - window[i - 1]
            sumSquaredDiffs += diff * diff
        }
        return sqrt(sumSquaredDiffs / Double(window.count - 1))
    }

    /// Standard deviation of NN (normal-to-normal) intervals, in ms.
    static func sdnn(rrIntervalsMS: [UInt16], windowSize: Int = 60) -> Double? {
        let window = filterArtifacts(Array(rrIntervalsMS.suffix(windowSize)))
        guard window.count > 1 else { return nil }

        let mean = window.reduce(0, +) / Double(window.count)
        let variance = window.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(window.count - 1)
        return sqrt(variance)
    }
}

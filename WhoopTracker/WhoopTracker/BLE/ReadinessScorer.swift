import Foundation

enum ReadinessLabel: String {
    case primed = "В форме"
    case balanced = "Сбалансировано"
    case strained = "Нагружен"
    case runDown = "Истощён"
}

struct ReadinessResult {
    let label: ReadinessLabel
    let hrvZScore: Double?
    let restingHRDriftBPM: Double?
    let acuteChronicRatio: Double?
    let monotony: Double?
}

/// Synthesizes a "should you push today?" read from your own recent history —
/// not a reproduction of WHOOP's Recovery %, which is a closed model. Each
/// input here is a named, published method:
///
/// - HRV vs personal baseline: Plews & Buchheit (rolling-average z-score of
///   log-transformed RMSSD against your own recent nights).
/// - Resting-HR drift: Lamberts & Lambert submaximal-HR monitoring — a rise in
///   morning RHR above your own baseline is a fatigue signal.
/// - Acute:chronic workload ratio (ACWR): Gabbett — 7-day load vs 28-day
///   average load; ratios well above 1.0 suggest a spike in training stress.
/// - Monotony: Foster — mean daily load divided by its standard deviation
///   over the week; high monotony (little variation day-to-day) is
///   independently associated with overtraining risk.
///
/// This is pure, deterministic math over numbers you already have (daily
/// strain estimates + resting HR + HRV) — no proprietary model, no ML.
enum ReadinessScorer {

    struct DailyPoint {
        let date: Date
        let hrvRMSSD: Double?
        let restingHR: Double?
        let strain: Double?
    }

    static func score(history: [DailyPoint]) -> ReadinessResult? {
        guard history.count >= 3 else { return nil }
        let sorted = history.sorted { $0.date < $1.date }
        guard let today = sorted.last else { return nil }

        let hrvZ = hrvBaselineZScore(sorted)
        let rhrDrift = restingHRDrift(sorted)
        let acwr = acuteChronicRatio(sorted)
        let monotony = trainingMonotony(sorted)

        // Simple, transparent composite: start neutral, nudge per signal.
        var score = 0.0
        var signals = 0

        if let hrvZ {
            score += hrvZ // positive HRV z-score is good
            signals += 1
        }
        if let rhrDrift {
            score -= rhrDrift / 3.0 // higher-than-baseline RHR is bad
            signals += 1
        }
        if let acwr {
            // Sweet spot ~0.8-1.3 per Gabbett; outside that, penalize.
            let penalty = acwr > 1.3 ? (acwr - 1.3) * 2 : (acwr < 0.8 ? (0.8 - acwr) * 2 : 0)
            score -= penalty
            signals += 1
        }
        if let monotony, monotony > 2.0 {
            score -= (monotony - 2.0) * 0.5 // high monotony is an independent risk flag
            signals += 1
        }

        guard signals > 0 else { return nil }

        let label: ReadinessLabel
        switch score {
        case 1.0...: label = .primed
        case -0.5..<1.0: label = .balanced
        case -1.5..<(-0.5): label = .strained
        default: label = .runDown
        }

        _ = today // kept for clarity that "today" anchors the window; extend as needed
        return ReadinessResult(
            label: label,
            hrvZScore: hrvZ,
            restingHRDriftBPM: rhrDrift,
            acuteChronicRatio: acwr,
            monotony: monotony
        )
    }

    // MARK: - Individual signals

    private static func hrvBaselineZScore(_ history: [DailyPoint]) -> Double? {
        let values = history.compactMap { $0.hrvRMSSD }.map { log($0) } // log-transform per Plews/Buchheit
        guard values.count >= 3, let latest = values.last else { return nil }
        let baseline = Array(values.dropLast())
        let mean = baseline.reduce(0, +) / Double(baseline.count)
        let variance = baseline.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(1, baseline.count - 1))
        let sd = sqrt(variance)
        guard sd > 0 else { return nil }
        return (latest - mean) / sd
    }

    private static func restingHRDrift(_ history: [DailyPoint]) -> Double? {
        let values = history.compactMap { $0.restingHR }
        guard values.count >= 3, let latest = values.last else { return nil }
        let baseline = Array(values.dropLast())
        let mean = baseline.reduce(0, +) / Double(baseline.count)
        return latest - mean
    }

    private static func acuteChronicRatio(_ history: [DailyPoint]) -> Double? {
        let strains = history.compactMap { $0.strain }
        guard strains.count >= 7 else { return nil }
        let acuteWindow = Array(strains.suffix(7))
        let chronicWindow = Array(strains.suffix(min(28, strains.count)))
        let acute = acuteWindow.reduce(0, +) / Double(acuteWindow.count)
        let chronic = chronicWindow.reduce(0, +) / Double(chronicWindow.count)
        guard chronic > 0 else { return nil }
        return acute / chronic
    }

    private static func trainingMonotony(_ history: [DailyPoint]) -> Double? {
        let strains = Array(history.compactMap { $0.strain }.suffix(7))
        guard strains.count >= 4 else { return nil }
        let mean = strains.reduce(0, +) / Double(strains.count)
        let variance = strains.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(strains.count)
        let sd = sqrt(variance)
        guard sd > 0 else { return nil }
        return mean / sd
    }
}

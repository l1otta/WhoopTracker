import Foundation

/// A single decoded sample from the WHOOP 4.0 real-time data stream.
///
/// Only fields the community reports as "Decoded" (not "candidate/unconfirmed")
/// are exposed here: heart rate, R-R interval, SpO2, skin temperature.
/// Accelerometer/motion/PPG bytes were deliberately dropped from this parser —
/// they were only ever "candidate (unconfirmed)", and surfacing unconfirmed
/// data (e.g. as a sleep/motion signal) is exactly what produces nonsense like
/// "asleep" while you're walking. If those bytes get properly confirmed later,
/// add them back with a source.
struct WhoopRealtimeSample {
    let timestamp: Date
    let heartRateBPM: UInt8?
    let rrIntervalMS: UInt16?
    let spo2Percent: UInt8?
    let skinTemperatureC: Double?
    let crcValid: Bool
}

enum WhoopPacketParser {

    static let packetLength = 96

    /// Parses one 96-byte notification payload from the data characteristic.
    /// Returns nil if the length is wrong or the CRC doesn't check out — a
    /// failed CRC means the bytes are noise, so we don't emit a sample rather
    /// than emit possibly-garbage numbers.
    static func parse(_ data: Data) -> WhoopRealtimeSample? {
        guard data.count == packetLength else { return nil }
        let bytes = [UInt8](data)

        let payload = Array(bytes[0..<92])
        let receivedCRC = UInt32(bytes[92])
            | (UInt32(bytes[93]) << 8)
            | (UInt32(bytes[94]) << 16)
            | (UInt32(bytes[95]) << 24)
        let crcValid = CRC32.checksum(payload) == receivedCRC
        guard crcValid else { return nil }

        let heartRate = bytes[1]
        let rr = UInt16(bytes[3]) | (UInt16(bytes[4]) << 8)
        let spo2 = bytes[5]
        let skinTemp = Double(bytes[6]) / 10.0

        return WhoopRealtimeSample(
            timestamp: Date(),
            heartRateBPM: heartRate > 0 ? heartRate : nil,
            rrIntervalMS: rr > 0 ? rr : nil,
            spo2Percent: spo2 > 0 ? spo2 : nil,
            skinTemperatureC: skinTemp,
            crcValid: crcValid
        )
    }
}

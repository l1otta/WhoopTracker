import Foundation
import CoreBluetooth

/// WHOOP 5.0 (Maverick firmware) identifiers.
///
/// Unlike the 4.0, the 5.0 exposes heart rate and battery through **standard**
/// Bluetooth SIG GATT services — no reverse-engineering needed for those two,
/// CoreBluetooth understands the format natively.
///
/// Everything else (skin temperature, motion, gravity vector, historical data)
/// lives behind a proprietary "Maverick frame" protocol on custom characteristics
/// (`fd4b0002`-`fd4b0007`) that community reverse-engineering has documented at
/// the wire-frame level (CRC16 header + CRC32 inner buffer, 4-byte alignment,
/// an ACK'd historical-drain handshake) but WITHOUT publishing the exact byte
/// offsets for skin temp / motion within the decoded chunks — those were found
/// empirically per-installation with probe scripts, not published as a stable
/// spec. Implementing that here would mean guessing byte offsets, which is
/// exactly the kind of inaccurate data this app should avoid. So this app
/// deliberately does NOT read skin temp / motion / historical data on 5.0 yet.
///
/// Also confirmed by that same reverse-engineering effort: current 5.0 firmware
/// does not expose per-second HRV, SpO2, or sleep/strain data over BLE at all —
/// those are computed by WHOOP's cloud from data only visible in each user's
/// "Download My Data" export, not on the strap. So this app doesn't show HRV,
/// SpO2, strain, or sleep for 5.0 — there is nothing to read locally yet.
enum Whoop5Protocol {

    /// Standard Bluetooth SIG Heart Rate service.
    static let heartRateServiceUUID = CBUUID(string: "180D")
    static let heartRateMeasurementCharUUID = CBUUID(string: "2A37")

    /// Standard Bluetooth SIG Battery service.
    static let batteryServiceUUID = CBUUID(string: "180F")
    static let batteryLevelCharUUID = CBUUID(string: "2A19")

    // NOTE: a proprietary "fd4b..." service also exists on the 5.0 for historical
    // data, motion, skin temp, and alarms — but the source that documented it
    // only ever showed the UUID truncated (`fd4b0001-…`), so the full 128-bit
    // UUID isn't confirmed here. Deliberately not declaring a guessed constant
    // for it — wire it up once you've confirmed the full UUID yourself (e.g. by
    // inspecting `peripheral.services` after connecting) rather than trusting
    // a guess.

    /// Command frame format for the 5.0's proprietary channel, corroborated by
    /// two independent reverse-engineering efforts (frame layout is a protocol
    /// fact, not copyrightable code): a CRC16-Modbus-checked 6-byte header
    /// wrapping a CRC32-checked inner command buffer — nicknamed the "puffin"
    /// envelope by one of those write-ups.
    ///
    /// Layout: [0xAA][0x01][declLen u16 LE][field=0x0100][CRC16-Modbus of the 6 header bytes]
    ///         [inner: 0x23 type][seq][cmd][b3][payload...][CRC32 of inner, u32 LE]
    /// `b3` (4th inner byte) matters per the source: GET_HELLO / SET_CONFIG want
    /// 0x01; GET_DATA_RANGE / SEND_HISTORICAL want 0x00.
    ///
    /// Only the frame-building is implemented here — actually writing to the
    /// (unconfirmed) characteristic is left to you once you've verified the UUID.
    enum PuffinCommand: UInt8 {
        case startDeviceConfigKeyExchange = 0x73
        case setFFValue = 0x78
    }

    static func buildPuffinFrame(command: PuffinCommand, sequence: UInt8, b3: UInt8, payload: [UInt8] = []) -> Data {
        var inner: [UInt8] = [0x23, sequence, command.rawValue, b3]
        inner.append(contentsOf: payload)
        let innerCRC = CRC32.checksum(inner)
        inner.append(UInt8(innerCRC & 0xFF))
        inner.append(UInt8((innerCRC >> 8) & 0xFF))
        inner.append(UInt8((innerCRC >> 16) & 0xFF))
        inner.append(UInt8((innerCRC >> 24) & 0xFF))

        var header: [UInt8] = [0xAA, 0x01]
        let declLen = UInt16(inner.count)
        header.append(UInt8(declLen & 0xFF))
        header.append(UInt8((declLen >> 8) & 0xFF))
        header.append(0x00)
        header.append(0x01)

        let headerCRC = CRC16Modbus.checksum(header)
        header.append(UInt8(headerCRC & 0xFF))
        header.append(UInt8((headerCRC >> 8) & 0xFF))

        return Data(header + inner)
    }
}

/// CRC16-Modbus — used to check the WHOOP 5.0 puffin frame header.
enum CRC16Modbus {
    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                if crc & 0x0001 != 0 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc >>= 1
                }
            }
        }
        return crc
    }
}

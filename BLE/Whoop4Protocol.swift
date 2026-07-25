import Foundation
import CoreBluetooth

/// BLE identifiers and low-level framing for the WHOOP 4.0 custom GATT service.
///
/// Protocol knowledge is derived from independent community reverse-engineering
/// (jogolden/whoomp, bWanShiTong/reverse-engineering-whoop, openwhoop,
/// christianmeurer/whoop-reader). This code only implements the communication
/// protocol to achieve interoperability with a device you own — it does not
/// contain, extract, or redistribute any WHOOP firmware or proprietary algorithm.
enum Whoop4Protocol {

    /// Custom GATT service exposed by the WHOOP 4.0 strap.
    static let serviceUUID = CBUUID(string: "61080000-8D6D-82B8-614A-1C8CB0F8DCC6")

    /// Characteristics under the WHOOP service. Suffixes follow the community's
    /// documented naming (offsets 01-05 within the 128-bit base UUID).
    enum Characteristic {
        static let command  = CBUUID(string: "61080001-8D6D-82B8-614A-1C8CB0F8DCC6")
        static let response = CBUUID(string: "61080002-8D6D-82B8-614A-1C8CB0F8DCC6")
        static let event    = CBUUID(string: "61080003-8D6D-82B8-614A-1C8CB0F8DCC6")
        static let data     = CBUUID(string: "61080004-8D6D-82B8-614A-1C8CB0F8DCC6")
        static let debug    = CBUUID(string: "61080005-8D6D-82B8-614A-1C8CB0F8DCC6")
    }

    /// Known command opcodes. Anything not listed here is simply unimplemented,
    /// not necessarily unknown to the community.
    enum Command: UInt8 {
        case getBatteryLevel = 0x0A
        case getDeviceInfo   = 0x0E
        case startRealtimeHR = 0x10
        case stopRealtimeHR  = 0x11
    }

    /// Frame format: [0xAA][CMD][LEN_LO][LEN_HI][PAYLOAD...][CRC32_LE]
    static func buildFrame(command: Command, payload: [UInt8] = []) -> Data {
        var frame: [UInt8] = [0xAA, command.rawValue]
        let length = UInt16(payload.count)
        frame.append(UInt8(length & 0xFF))
        frame.append(UInt8((length >> 8) & 0xFF))
        frame.append(contentsOf: payload)

        let crc = CRC32.checksum(frame)
        frame.append(UInt8(crc & 0xFF))
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8((crc >> 16) & 0xFF))
        frame.append(UInt8((crc >> 24) & 0xFF))

        return Data(frame)
    }
}

/// CRC-32 variant used by the WHOOP command/response framing.
/// Polynomial 0x04C11DB7, init 0xFFFFFFFF, reflected in/out, final XOR 0xF43F44AC.
enum CRC32 {
    private static let table: [UInt32] = {
        (0...255).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1 != 0) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in bytes {
            let index = (crc ^ UInt32(byte)) & 0xFF
            crc = table[Int(index)] ^ (crc >> 8)
        }
        return (crc ^ 0xFFFFFFFF) ^ 0xF43F44AC
    }
}

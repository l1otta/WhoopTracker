import Foundation
import CoreBluetooth
import Combine

/// Owns the CoreBluetooth session for either a WHOOP 4.0 or WHOOP 5.0 strap.
/// Generation is detected from which GATT services the peripheral exposes —
/// the app doesn't ask the user which one they have.
@MainActor
final class WhoopManager: NSObject, ObservableObject {

    enum ConnectionState: Equatable {
        case disconnected
        case scanning
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var discoveredPeripherals: [CBPeripheral] = []
    @Published private(set) var metrics: LiveMetrics = .empty

    /// Rolling buffer of recent WHOOP 4.0 samples, used by HRVCalculator.
    /// (WHOOP 5.0 doesn't expose R-R intervals over BLE, so this stays empty there.)
    @Published private(set) var recentRRIntervals: [UInt16] = []
    private let maxBufferedIntervals = 300

    /// Rolling buffer of (bpm, timestamp) used by StrainScorer — works for both
    /// generations since it's HR-only, no R-R intervals required.
    @Published private(set) var recentHRSamples: [(bpm: Double, timestamp: Date)] = []
    private let maxBufferedHRSamples = 3600 // ~1hr at 1Hz

    /// User profile inputs for StrainScorer. Defaults are placeholders —
    /// wire these to onboarding/settings instead of hardcoding.
    var restingHR: Double = 55
    var maxHR: Double = StrainScorer.estimatedMaxHR(age: 30)

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?

    // WHOOP 4.0
    private var whoop4CommandChar: CBCharacteristic?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else { return }
        discoveredPeripherals.removeAll()
        state = .scanning
        // Scan for either generation's advertised service — CoreBluetooth
        // matches a peripheral if it advertises ANY of these.
        central.scanForPeripherals(
            withServices: [Whoop4Protocol.serviceUUID, Whoop5Protocol.heartRateServiceUUID],
            options: nil
        )
    }

    func stopScan() {
        central.stopScan()
    }

    func connect(to peripheral: CBPeripheral) {
        stopScan()
        self.peripheral = peripheral
        state = .connecting
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    /// Only meaningful for WHOOP 4.0 — starts the custom real-time HR stream.
    /// On WHOOP 5.0 the standard HR characteristic notifies on its own once
    /// subscribed, no explicit start command needed.
    func startStreamingIfNeeded() {
        guard metrics.generation == .four, let whoop4CommandChar, let peripheral else { return }
        let frame = Whoop4Protocol.buildFrame(command: .startRealtimeHR)
        peripheral.writeValue(frame, for: whoop4CommandChar, type: .withResponse)
    }

    private func pushWhoop4Sample(_ sample: WhoopRealtimeSample) {
        metrics.heartRateBPM = sample.heartRateBPM.map(Int.init)
        metrics.spo2Percent = sample.spo2Percent.map(Int.init)
        metrics.skinTemperatureC = sample.skinTemperatureC
        metrics.rrIntervalMS = sample.rrIntervalMS

        if let rr = sample.rrIntervalMS {
            recentRRIntervals.append(rr)
            if recentRRIntervals.count > maxBufferedIntervals {
                recentRRIntervals.removeFirst(recentRRIntervals.count - maxBufferedIntervals)
            }
        }

        if let bpm = sample.heartRateBPM {
            pushHRSample(Double(bpm))
        }

        metrics.hrvRMSSD = HRVCalculator.rmssd(rrIntervalsMS: recentRRIntervals)
        recomputeStrain()
    }

    private func pushHRSample(_ bpm: Double) {
        recentHRSamples.append((bpm: bpm, timestamp: Date()))
        if recentHRSamples.count > maxBufferedHRSamples {
            recentHRSamples.removeFirst(recentHRSamples.count - maxBufferedHRSamples)
        }
    }

    private func recomputeStrain() {
        metrics.strainEstimate = StrainScorer.estimate(
            heartRateSamples: recentHRSamples,
            restingHR: restingHR,
            maxHR: maxHR
        )
    }
}

extension WhoopManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScan()
        } else {
            state = .failed("Bluetooth недоступен: \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager,
                         didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any],
                         rssi RSSI: NSNumber) {
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals.append(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .connected
        peripheral.delegate = self
        peripheral.discoverServices([
            Whoop4Protocol.serviceUUID,
            Whoop5Protocol.heartRateServiceUUID,
            Whoop5Protocol.batteryServiceUUID
        ])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        state = .failed(error?.localizedDescription ?? "Не удалось подключиться")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        state = .disconnected
        whoop4CommandChar = nil
        metrics = .empty
        recentRRIntervals.removeAll()
        recentHRSamples.removeAll()
    }
}

extension WhoopManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            switch service.uuid {
            case Whoop4Protocol.serviceUUID:
                metrics.generation = .four
                peripheral.discoverCharacteristics(nil, for: service)
            case Whoop5Protocol.heartRateServiceUUID:
                metrics.generation = .five
                peripheral.discoverCharacteristics([Whoop5Protocol.heartRateMeasurementCharUUID], for: service)
            case Whoop5Protocol.batteryServiceUUID:
                peripheral.discoverCharacteristics([Whoop5Protocol.batteryLevelCharUUID], for: service)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didDiscoverCharacteristicsFor service: CBService,
                     error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            switch char.uuid {
            // WHOOP 4.0
            case Whoop4Protocol.Characteristic.command:
                whoop4CommandChar = char
            case Whoop4Protocol.Characteristic.data:
                peripheral.setNotifyValue(true, for: char)

            // WHOOP 5.0 — standard GATT, subscribing is enough to start receiving.
            case Whoop5Protocol.heartRateMeasurementCharUUID:
                peripheral.setNotifyValue(true, for: char)
            case Whoop5Protocol.batteryLevelCharUUID:
                peripheral.setNotifyValue(true, for: char)
                peripheral.readValue(for: char)

            default:
                break
            }
        }

        if service.uuid == Whoop4Protocol.serviceUUID {
            startStreamingIfNeeded()
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didUpdateValueFor characteristic: CBCharacteristic,
                     error: Error?) {
        guard let value = characteristic.value else { return }

        switch characteristic.uuid {
        case Whoop4Protocol.Characteristic.data:
            if let sample = WhoopPacketParser.parse(value) {
                pushWhoop4Sample(sample)
            }

        case Whoop5Protocol.heartRateMeasurementCharUUID:
            if let bpm = Self.parseStandardHeartRate(value) {
                metrics.heartRateBPM = bpm
                pushHRSample(Double(bpm))
                recomputeStrain()
            }

        case Whoop5Protocol.batteryLevelCharUUID:
            metrics.batteryPercent = [UInt8](value).first.map(Int.init)

        default:
            break
        }
    }

    /// Standard Bluetooth SIG Heart Rate Measurement (0x2A37) format.
    /// Flags byte bit 0: 0 = HR is UInt8 in byte 1, 1 = HR is UInt16 LE in bytes 1-2.
    /// This is a public Bluetooth spec, not reverse-engineered.
    private static func parseStandardHeartRate(_ data: Data) -> Int? {
        let bytes = [UInt8](data)
        guard let flags = bytes.first, bytes.count > 1 else { return nil }
        let is16Bit = (flags & 0x01) != 0
        if is16Bit {
            guard bytes.count >= 3 else { return nil }
            return Int(bytes[1]) | (Int(bytes[2]) << 8)
        } else {
            return Int(bytes[1])
        }
    }
}

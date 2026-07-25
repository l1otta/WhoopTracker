import SwiftUI
import SwiftData

struct DashboardView: View {
    @EnvironmentObject var whoop: WhoopManager
    @Environment(\.modelContext) private var modelContext
    @StateObject private var dailyStore = DailyMetricsStore()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let generation = whoop.metrics.generation {
                    HStack {
                        Circle()
                            .fill(WhoopStyle.recoveryGreen)
                            .frame(width: 8, height: 8)
                        Text(generation == .four ? "WHOOP 4.0" : "WHOOP 5.0")
                            .font(.caption)
                            .foregroundStyle(WhoopStyle.textSecondary)
                        Spacer()
                        if let battery = whoop.metrics.batteryPercent {
                            Label("\(battery)%", systemImage: "battery.100")
                                .font(.caption)
                                .foregroundStyle(WhoopStyle.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Strain — the headline ring, WHOOP-style.
                if let strain = whoop.metrics.strainEstimate {
                    VStack(spacing: 8) {
                        RingGauge(
                            value: strain,
                            maxValue: 21,
                            color: WhoopStyle.strainColor,
                            label: "Нагрузка",
                            valueText: String(format: "%.1f", strain)
                        )
                        Text("Наша оценка по TRIMP — не копия алгоритма WHOOP")
                            .font(.caption2)
                            .foregroundStyle(WhoopStyle.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Считаем нагрузку — нужно немного данных пульса")
                            .font(.caption)
                            .foregroundStyle(WhoopStyle.textSecondary)
                    }
                    .frame(height: 200)
                }

                // Vitals grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    if let hr = whoop.metrics.heartRateBPM {
                        VitalTile(title: "Пульс", value: "\(hr)", unit: "уд/мин")
                    }

                    if let hrv = whoop.metrics.hrvRMSSD {
                        VitalTile(
                            title: "HRV",
                            value: String(format: "%.0f", hrv),
                            unit: "мс",
                            footnote: "RMSSD, наш расчёт"
                        )
                    }

                    if let spo2 = whoop.metrics.spo2Percent {
                        VitalTile(title: "SpO2", value: "\(spo2)", unit: "%")
                    }

                    if let temp = whoop.metrics.skinTemperatureC {
                        VitalTile(title: "Темп. кожи", value: String(format: "%.1f", temp), unit: "°C")
                    }
                }

                if whoop.metrics.generation == .five {
                    Text("На WHOOP 5.0 сейчас доступны пульс, батарея и нагрузка (считается по пульсу). HRV, SpO2 и температура кожи эта прошивка не передаёт по BLE в реальном времени.")
                        .font(.caption)
                        .foregroundStyle(WhoopStyle.textSecondary)
                        .padding(.top, 4)
                }

                if whoop.metrics.heartRateBPM == nil {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Ждём данные от браслета...")
                            .foregroundStyle(WhoopStyle.textSecondary)
                    }
                    .padding(.top, 30)
                }
            }
            .padding()
        }
        .background(WhoopStyle.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationTitle("WHOOP Tracker")
        .toolbarBackground(WhoopStyle.background, for: .navigationBar)
        .onChange(of: whoop.metrics.heartRateBPM) { _, newValue in
            guard let bpm = newValue else { return }
            dailyStore.recordSample(
                bpm: Double(bpm),
                hrv: whoop.metrics.hrvRMSSD,
                strain: whoop.metrics.strainEstimate,
                context: modelContext
            )
        }
    }
}

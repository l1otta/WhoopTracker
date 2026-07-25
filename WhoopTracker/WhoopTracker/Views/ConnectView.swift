import SwiftUI
import CoreBluetooth

struct ConnectView: View {
    @EnvironmentObject var whoop: WhoopManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 44))
                .foregroundStyle(WhoopStyle.strainColor)
                .padding(.top, 40)

            switch whoop.state {
            case .disconnected, .scanning:
                ProgressView("Поиск браслета...")
                    .tint(.white)
                    .foregroundStyle(.white)

                if whoop.discoveredPeripherals.isEmpty {
                    Text("Держи браслет рядом и открытым для подключения")
                        .font(.caption)
                        .foregroundStyle(WhoopStyle.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                } else {
                    List(whoop.discoveredPeripherals, id: \.identifier) { peripheral in
                        Button {
                            whoop.connect(to: peripheral)
                        } label: {
                            Text(peripheral.name ?? "Неизвестное устройство")
                                .foregroundStyle(.white)
                        }
                        .listRowBackground(WhoopStyle.cardBackground)
                    }
                    .scrollContentBackground(.hidden)
                }

            case .connecting:
                ProgressView("Подключение...")
                    .tint(.white)
                    .foregroundStyle(.white)

            case .connected:
                Label("Подключено", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(WhoopStyle.recoveryGreen)
                Button("Отключить") { whoop.disconnect() }
                    .foregroundStyle(WhoopStyle.strainColor)

            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(WhoopStyle.recoveryRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Button("Повторить") { whoop.startScan() }
                    .foregroundStyle(WhoopStyle.strainColor)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WhoopStyle.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { whoop.startScan() }
    }
}

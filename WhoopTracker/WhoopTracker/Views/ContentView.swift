import SwiftUI

struct ContentView: View {
    @EnvironmentObject var whoop: WhoopManager

    var body: some View {
        if whoop.state == .connected {
            TabView {
                NavigationStack {
                    DashboardView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Отключить") { whoop.disconnect() }
                            }
                        }
                        .onAppear {
                            whoop.startStreamingIfNeeded()
                        }
                }
                .tabItem { Label("Сегодня", systemImage: "waveform.path.ecg") }

                NavigationStack {
                    HistoryView()
                }
                .tabItem { Label("История", systemImage: "chart.line.uptrend.xyaxis") }
            }
            .tint(WhoopStyle.strainColor)
        } else {
            NavigationStack {
                ConnectView()
                    .navigationTitle("Подключение")
            }
            .tint(WhoopStyle.strainColor)
        }
    }
}

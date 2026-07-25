import SwiftUI
import SwiftData

@main
struct WhoopTrackerApp: App {
    @StateObject private var whoopManager = WhoopManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(whoopManager)
        }
        .modelContainer(for: [DailyOwnMetric.self])
    }
}

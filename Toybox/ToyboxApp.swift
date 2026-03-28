import SwiftUI

/// App-wide constants (not actor-isolated so they can be used anywhere)
enum ToyboxConstants {
    static let subsystem = "com.toybox.app"
}

@main
struct ToyboxApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
    }
}

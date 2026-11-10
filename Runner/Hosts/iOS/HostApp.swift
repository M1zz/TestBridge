import SwiftUI

/// Minimal host app. XCUITest requires a host target; the interpreter launches the
/// app under test by bundle identifier, so this app never needs to do anything.
@main
struct RunnerHostApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                Text("TestBridge Runner Host")
                    .font(.headline)
                Text("Nothing to see here.")
                    .font(.caption)
            }
            .padding()
        }
    }
}

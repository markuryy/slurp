import SwiftUI

@main
struct SlurpApp: App {
    @StateObject private var capture = CaptureManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(capture)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 720)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Take Screenshot") {
                    capture.takeScreenshot()
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }
}

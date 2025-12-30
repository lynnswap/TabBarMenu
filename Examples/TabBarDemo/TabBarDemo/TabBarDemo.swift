import SwiftUI
import TabBarMenuDemoSupport

@main
struct TabBarDemo: App {
    var body: some Scene {
        WindowGroup {
            TabBarMenuPreviewScreen(mode: .uiTab)
        }
    }
}

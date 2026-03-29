import SwiftUI

@main
struct TodusMacApp: App {
    var body: some Scene {
        WindowGroup {
            MacRootView()
                .frame(minWidth: 1100, minHeight: 720)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}

import SwiftUI

@main
struct BookuhApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(BookuhTheme.green)
                .font(BookuhTheme.bodyFont())
                .preferredColorScheme(.light)
        }
    }
}

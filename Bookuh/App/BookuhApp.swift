import SwiftUI

@main
@MainActor
struct BookuhApp: App {
    @StateObject private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            BookuhRootView()
                .environmentObject(session)
                .tint(BookuhTheme.green)
                .font(BookuhTheme.bodyFont())
                .preferredColorScheme(.light)
        }
    }
}

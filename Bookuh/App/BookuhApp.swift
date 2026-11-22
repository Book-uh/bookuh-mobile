import SwiftUI

@main
@MainActor
struct BookuhApp: App {
    @StateObject private var session = AppSession()
    @StateObject private var managerChat = ManagerChatStore()

    var body: some Scene {
        WindowGroup {
            BookuhRootView()
                .environmentObject(session)
                .environmentObject(managerChat)
                .tint(BookuhTheme.green)
                .font(BookuhTheme.bodyFont())
                .foregroundStyle(BookuhTheme.ink)
                .preferredColorScheme(.light)
        }
    }
}

import SwiftUI

/// Главная точка входа приложения TranscribeIt
@main
struct TranscribeItApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar приложение с возможностью показа окна
        Settings {
            EmptyView()
        }
    }
}

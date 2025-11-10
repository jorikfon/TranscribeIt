import Cocoa

/// Главная точка входа приложения TranscribeIt
/// Используем чистый AppKit без SwiftUI App (окна управляются через AppDelegate)
@main
class TranscribeItMain {
    // Сохраняем strong reference на AppDelegate (иначе он сразу освободится)
    static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.run()
    }
}

import Cocoa
import TranscribeItCore

/// Главная точка входа приложения TranscribeIt
/// Используем чистый AppKit без SwiftUI App (окна управляются через AppDelegate)
@main
class TranscribeItMain {
    // Создаем все зависимости явно для чистого DI
    static let dependencies: DependencyContainer = {
        let modelManager = ModelManager.shared
        let userSettings = UserSettings.shared
        let vocabularyManager = VocabularyManager.shared
        let audioCache = AudioCache()

        return DependencyContainer(
            modelManager: modelManager,
            userSettings: userSettings,
            vocabularyManager: vocabularyManager,
            audioCache: audioCache
        )
    }()

    // Сохраняем strong reference на AppDelegate (иначе он сразу освободится)
    static let appDelegate = AppDelegate(dependencies: dependencies)

    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.run()
    }
}

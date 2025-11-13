import XCTest
@testable import TranscribeItCore

/// Базовый тест для проверки работоспособности Test Target
final class TranscribeItCoreTests: XCTestCase {

    /// Проверяет, что тестовая инфраструктура настроена корректно
    func testTestTargetIsWorking() {
        XCTAssertTrue(true, "Test target is properly configured")
    }

    /// Проверяет доступность основных классов из TranscribeItCore
    func testCoreClassesAreAccessible() {
        // Проверяем доступность синглтонов
        let userSettings = UserSettings.shared
        XCTAssertNotNil(userSettings)

        let vocabularyManager = VocabularyManager.shared
        XCTAssertNotNil(vocabularyManager)

        // Проверяем, что можем создать сервисы через явный DI
        let whisperService = WhisperService(
            modelSize: "tiny",
            vocabularyManager: vocabularyManager
        )
        XCTAssertNotNil(whisperService)
    }
}

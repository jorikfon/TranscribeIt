import XCTest
@testable import TranscribeItCore

/// Примеры использования Mock-объектов для тестирования
/// Этот файл демонстрирует различные сценарии использования Mock-реализаций
final class MockUsageExamples: XCTestCase {

    // MARK: - MockVocabularyManager Examples

    func testMockVocabularyManager_BasicUsage() {
        // Given: Создаем mock и настраиваем его поведение
        let mockVocab = MockVocabularyManager()
        mockVocab.stubbedCorrection = "corrected text"

        // When: Вызываем метод
        let result = mockVocab.correctTranscription("original text")

        // Then: Проверяем результат и счетчик вызовов
        XCTAssertEqual(result, "corrected text")
        XCTAssertEqual(mockVocab.correctTranscriptionCallCount, 1)
        XCTAssertEqual(mockVocab.correctTranscriptionCalls.first, "original text")
    }

    func testMockVocabularyManager_SpecificCorrections() {
        // Given: Настраиваем специфичные коррекции
        let mockVocab = MockVocabularyManager()
        mockVocab.stubbedCorrections = [
            "hello": "привет",
            "world": "мир"
        ]

        // When & Then: Проверяем специфичные коррекции
        XCTAssertEqual(mockVocab.correctTranscription("hello"), "привет")
        XCTAssertEqual(mockVocab.correctTranscription("world"), "мир")
        XCTAssertEqual(mockVocab.correctTranscription("unknown"), "unknown") // Возвращает исходный
    }

    func testMockVocabularyManager_ErrorHandling() {
        // Given: Настраиваем mock на выброс ошибок
        let mockVocab = MockVocabularyManager()
        mockVocab.shouldThrowOnLoad = true

        // When & Then: Проверяем, что ошибка выбрасывается
        XCTAssertThrowsError(try mockVocab.loadCorrections(from: URL(fileURLWithPath: "/tmp/test.json"))) { error in
            XCTAssertTrue((error as NSError).localizedDescription.contains("Mock load error"))
        }
        XCTAssertEqual(mockVocab.loadCorrectionsCallCount, 1)
    }

    func testMockVocabularyManager_WithRealService() {
        // Given: Создаем WhisperService с mock VocabularyManager
        let mockVocab = MockVocabularyManager()
        mockVocab.stubbedCorrection = "Мокированный результат"

        // Инициализируем сервис с mock зависимостью
        _ = WhisperService(
            modelSize: "tiny",
            vocabularyManager: mockVocab
        )

        // When: Используем сервис (в реальном тесте нужно вызывать методы)
        // Then: Можем проверить, что VocabularyManager использовался корректно
        XCTAssertEqual(mockVocab.correctTranscriptionCallCount, 0) // Пока не вызывали
    }

    // MARK: - MockUserSettings Examples

    func testMockUserSettings_BasicProperties() {
        // Given: Создаем mock настроек
        let mockSettings = MockUserSettings()

        // When: Устанавливаем свойства
        mockSettings.transcriptionLanguage = "ru"
        mockSettings.vadAlgorithmType = .spectralTelephone
        mockSettings.fileTranscriptionMode = .vad

        // Then: Проверяем значения
        XCTAssertEqual(mockSettings.transcriptionLanguage, "ru")
        XCTAssertEqual(mockSettings.vadAlgorithmType, .spectralTelephone)
        XCTAssertEqual(mockSettings.fileTranscriptionMode, .vad)
    }

    func testMockUserSettings_VocabularyManagement() {
        // Given: Создаем mock настроек
        let mockSettings = MockUserSettings()

        // When: Добавляем словарь
        mockSettings.addVocabulary(name: "Tech Terms", words: ["API", "SDK", "HTTP"])

        // Then: Проверяем, что словарь добавлен и включен
        XCTAssertEqual(mockSettings.addVocabularyCallCount, 1)
        XCTAssertEqual(mockSettings.vocabularies.count, 1)
        XCTAssertEqual(mockSettings.vocabularies.first?.name, "Tech Terms")
        XCTAssertTrue(mockSettings.enabledVocabularies.contains(mockSettings.vocabularies.first!.id))
    }

    func testMockUserSettings_StopWords() {
        // Given: Создаем mock настроек
        let mockSettings = MockUserSettings()

        // When: Добавляем стоп-слова
        mockSettings.addStopWord("стоп")
        mockSettings.addStopWord("хватит")

        // Then: Проверяем работу containsStopWord
        XCTAssertTrue(mockSettings.containsStopWord("пожалуйста стоп запись"))
        XCTAssertFalse(mockSettings.containsStopWord("продолжай запись"))
        XCTAssertEqual(mockSettings.addStopWordCallCount, 2)
        XCTAssertEqual(mockSettings.containsStopWordCallCount, 2)
    }

    func testMockUserSettings_WithRealService() {
        // Given: Создаем FileTranscriptionService с mock UserSettings и WhisperService
        let mockSettings = MockUserSettings()
        mockSettings.transcriptionLanguage = "en"
        mockSettings.vadAlgorithmType = .spectralDefault

        let mockVocab = MockVocabularyManager()
        let whisperService = WhisperService(modelSize: "tiny", vocabularyManager: mockVocab)
        let audioCache = AudioCache()

        // Инициализируем сервис с mock зависимостью
        let service = FileTranscriptionService(
            whisperService: whisperService,
            userSettings: mockSettings,
            audioCache: audioCache
        )

        // Then: Сервис будет использовать наши mock настройки
        XCTAssertNotNil(service)
    }

    // MARK: - MockModelManager Examples

    func testMockModelManager_BasicOperations() {
        // Given: Создаем mock manager
        let mockManager = MockModelManager()

        // When: Работаем с моделями
        mockManager.saveCurrentModel("small")
        let isDownloaded = mockManager.isModelDownloaded("small")

        // Then: Проверяем состояние
        XCTAssertEqual(mockManager.currentModel, "small")
        XCTAssertEqual(mockManager.saveCurrentModelCallCount, 1)
        XCTAssertEqual(mockManager.isModelDownloadedCallCount, 1)
        XCTAssertFalse(isDownloaded) // По умолчанию не загружена
    }

    func testMockModelManager_DownloadSimulation() async throws {
        // Given: Создаем mock manager с симуляцией загрузки
        let mockManager = MockModelManager()
        mockManager.simulateDownloadProgress = false // Быстрая загрузка для теста

        // When: Загружаем модель
        try await mockManager.downloadModel("tiny")

        // Then: Проверяем состояние
        XCTAssertEqual(mockManager.downloadModelCallCount, 1)
        XCTAssertTrue(mockManager.isModelDownloaded("tiny"))
        XCTAssertEqual(mockManager.downloadProgress, 1.0)
        XCTAssertFalse(mockManager.isDownloading)
    }

    func testMockModelManager_DownloadError() async {
        // Given: Создаем mock manager с ошибкой загрузки
        let mockManager = MockModelManager()
        mockManager.shouldThrowOnDownload = true

        // When & Then: Проверяем, что ошибка выбрасывается
        do {
            try await mockManager.downloadModel("large")
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue((error as NSError).localizedDescription.contains("Mock download error"))
        }

        XCTAssertEqual(mockManager.downloadModelCallCount, 1)
    }

    func testMockModelManager_ModelAvailability() async {
        // Given: Создаем mock manager с stubbed доступностью
        let mockManager = MockModelManager()
        mockManager.modelAvailability = [
            "tiny": true,
            "large": false
        ]

        // When: Проверяем доступность моделей
        let tinyAvailable = await mockManager.checkModelAvailability("tiny")
        let largeAvailable = await mockManager.checkModelAvailability("large")

        // Then: Проверяем результаты
        XCTAssertTrue(tinyAvailable)
        XCTAssertFalse(largeAvailable)
        XCTAssertEqual(mockManager.checkModelAvailabilityCallCount, 2)
    }

    // MARK: - Integration Example

    func testIntegration_WhisperServiceWithMocks() {
        // Given: Создаем все необходимые mock-зависимости
        let mockVocab = MockVocabularyManager()
        mockVocab.stubbedCorrection = "Corrected transcription"

        // When: Создаем WhisperService с mock зависимостью
        let service = WhisperService(
            modelSize: "tiny",
            vocabularyManager: mockVocab
        )

        // Then: Сервис готов к тестированию с изолированными зависимостями
        XCTAssertNotNil(service)

        // Можем проверить, что при транскрипции используется mockVocab
        // (в реальном тесте нужно вызывать методы транскрипции)
    }

    func testIntegration_FileTranscriptionServiceWithAllMocks() {
        // Given: Создаем все mock-зависимости
        let mockSettings = MockUserSettings()
        mockSettings.transcriptionLanguage = "en"
        mockSettings.vadAlgorithmType = .spectralTelephone
        mockSettings.fileTranscriptionMode = .vad

        let mockVocab = MockVocabularyManager()
        let whisperService = WhisperService(modelSize: "tiny", vocabularyManager: mockVocab)
        let audioCache = AudioCache()

        // When: Создаем FileTranscriptionService
        let service = FileTranscriptionService(
            whisperService: whisperService,
            userSettings: mockSettings,
            audioCache: audioCache
        )

        // Then: Сервис использует наши настройки
        XCTAssertNotNil(service)

        // Можем проверить, что настройки применяются
        let (mode, algorithm) = mockSettings.getVADAlgorithmForService()
        XCTAssertEqual(mode, "vad")
        XCTAssertEqual(algorithm, "spectral_telephone")
    }

    // MARK: - Reset and Cleanup Examples

    func testMockReset_ResetsAllCounters() {
        // Given: Mock с использованными счетчиками
        let mockVocab = MockVocabularyManager()
        _ = mockVocab.correctTranscription("test")
        mockVocab.addCorrection(from: "old", to: "new")
        XCTAssertEqual(mockVocab.correctTranscriptionCallCount, 1)
        XCTAssertEqual(mockVocab.addCorrectionCallCount, 1)

        // When: Сбрасываем mock
        mockVocab.reset()

        // Then: Все счетчики обнулены
        XCTAssertEqual(mockVocab.correctTranscriptionCallCount, 0)
        XCTAssertEqual(mockVocab.addCorrectionCallCount, 0)
        XCTAssertTrue(mockVocab.correctTranscriptionCalls.isEmpty)
        XCTAssertTrue(mockVocab.mockCorrections.isEmpty)
    }
}

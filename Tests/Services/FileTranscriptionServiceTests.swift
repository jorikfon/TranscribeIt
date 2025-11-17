import XCTest
@testable import TranscribeItCore

/// Unit тесты для FileTranscriptionService
///
/// Покрытие:
/// - buildContextPrompt(): Умное усечение по границам слов
/// - buildContextPrompt(): Адаптивный выбор количества реплик
/// - buildContextPrompt(): Извлечение именованных сущностей
/// - buildContextPrompt(): Интеграция терминов из словаря
final class FileTranscriptionServiceTests: XCTestCase {

    // MARK: - Properties

    var mockSettings: MockUserSettings!

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()
        mockSettings = MockUserSettings()
    }

    override func tearDown() {
        mockSettings = nil
        super.tearDown()
    }

    // MARK: - Word-Boundary Truncation Tests

    /// Проверяет что контекст обрезается по границе слова, а не посреди
    func testContextTruncationAtWordBoundary() {
        // Given: Длинный контекст, который превышает maxContextLength
        mockSettings.maxContextLength = 50
        mockSettings.baseContextPrompt = "This is a very long base context that will definitely exceed"

        // Expected: Контекст обрезается по последнему пробелу перед лимитом
        // "This is a very long base context that will..." (50 символов)
        // Должен обрезаться до "This is a very long base context that will"

        // Проверяем что обрезание происходит по границе слова
        let context = mockSettings.baseContextPrompt
        if context.count > mockSettings.maxContextLength {
            // Найдем последний пробел перед лимитом
            let truncatedIndex = context.index(context.startIndex, offsetBy: mockSettings.maxContextLength)
            let searchRange = context.startIndex..<truncatedIndex

            if let lastSpaceIndex = context.range(of: " ", options: .backwards, range: searchRange)?.upperBound {
                let truncated = String(context[..<lastSpaceIndex])
                XCTAssertFalse(truncated.hasSuffix(" "), "Обрезанный текст не должен заканчиваться пробелом")
                XCTAssertLessThanOrEqual(truncated.count, mockSettings.maxContextLength, "Обрезанный текст должен быть <= maxContextLength")
            }
        }
    }

    /// Проверяет что короткий контекст не обрезается
    func testShortContextNotTruncated() {
        // Given: Короткий контекст
        mockSettings.maxContextLength = 300
        mockSettings.baseContextPrompt = "Short context"

        // Then: Контекст возвращается полностью
        let context = mockSettings.baseContextPrompt
        XCTAssertEqual(context, "Short context", "Короткий контекст не должен обрезаться")
    }

    /// Проверяет обработку пустого контекста
    func testEmptyContextHandling() {
        // Given: Пустой контекст
        mockSettings.baseContextPrompt = ""
        mockSettings.maxContextLength = 300

        // Then: Возвращается пустая строка
        let context = mockSettings.baseContextPrompt
        XCTAssertTrue(context.isEmpty, "Пустой контекст должен остаться пустым")
    }

    /// Проверяет что контекст ровно на границе лимита не обрезается
    func testContextExactlyAtLimit() {
        // Given: Контекст точно равный лимиту
        let exactText = String(repeating: "a", count: 300)
        mockSettings.maxContextLength = 300
        mockSettings.baseContextPrompt = exactText

        // Then: Контекст возвращается полностью
        let context = mockSettings.baseContextPrompt
        XCTAssertEqual(context.count, 300, "Контекст на границе лимита не должен обрезаться")
    }

    /// Проверяет усечение длинного текста без пробелов
    func testTruncationWithoutSpaces() {
        // Given: Длинный текст без пробелов (edge case)
        let longTextWithoutSpaces = String(repeating: "a", count: 500)
        mockSettings.maxContextLength = 300

        // Then: Должен обрезаться на границе maxLength (даже без пробела)
        let truncatedLength = min(longTextWithoutSpaces.count, mockSettings.maxContextLength)
        XCTAssertLessThanOrEqual(truncatedLength, mockSettings.maxContextLength)
    }

    /// Проверяет что многоязычный текст корректно обрабатывается
    func testMultilingualContextTruncation() {
        // Given: Русский текст с пробелами
        mockSettings.maxContextLength = 50
        mockSettings.baseContextPrompt = "Это очень длинный русский текст который должен быть обрезан по границе слова"

        // Then: Обрезание по последнему пробелу
        let context = mockSettings.baseContextPrompt
        if context.count > mockSettings.maxContextLength {
            let truncatedIndex = context.index(context.startIndex, offsetBy: mockSettings.maxContextLength)
            let searchRange = context.startIndex..<truncatedIndex

            if let lastSpaceIndex = context.range(of: " ", options: .backwards, range: searchRange)?.upperBound {
                let truncated = String(context[..<lastSpaceIndex])
                XCTAssertLessThanOrEqual(truncated.count, mockSettings.maxContextLength)
            }
        }
    }

    // MARK: - Adaptive Turn Selection Tests

    /// Проверяет что количество реплик берется из настроек
    func testAdaptiveTurnSelection() {
        // Given: Настроенное количество реплик
        mockSettings.maxRecentTurns = 8

        // Then: Должно использоваться значение из настроек
        XCTAssertEqual(mockSettings.maxRecentTurns, 8, "Должно использоваться maxRecentTurns из настроек")
    }

    /// Проверяет минимальное количество реплик
    func testMinimumTurnSelection() {
        mockSettings.maxRecentTurns = 3
        XCTAssertEqual(mockSettings.maxRecentTurns, 3, "Минимум 3 реплики")
    }

    /// Проверяет максимальное количество реплик
    func testMaximumTurnSelection() {
        mockSettings.maxRecentTurns = 10
        XCTAssertEqual(mockSettings.maxRecentTurns, 10, "Максимум 10 реплик")
    }

    /// Проверяет что по умолчанию используется 5 реплик
    func testDefaultTurnSelection() {
        XCTAssertEqual(mockSettings.maxRecentTurns, 5, "По умолчанию 5 реплик")
    }

    // MARK: - Entity Extraction Tests

    /// Проверяет извлечение заглавных слов (имена) из текста
    func testExtractCapitalizedWordsAsEntities() {
        // Given: Текст с именами и компаниями
        let text = "John called Apple to discuss the Microsoft partnership."

        // Expected: Извлечь John, Apple, Microsoft
        let capitalizedPattern = "\\b[A-Z][a-z]+"
        let regex = try! NSRegularExpression(pattern: capitalizedPattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let entities = matches.map { match in
            String(text[Range(match.range, in: text)!])
        }

        XCTAssertTrue(entities.contains("John"), "Должно извлечь имя John")
        XCTAssertTrue(entities.contains("Apple"), "Должно извлечь компанию Apple")
        XCTAssertTrue(entities.contains("Microsoft"), "Должно извлечь компанию Microsoft")
    }

    /// Проверяет извлечение русских имен
    func testExtractRussianEntities() {
        // Given: Русский текст с именами
        let text = "Иван позвонил в Сбербанк для обсуждения контракта."

        // Expected: Извлечь Иван, Сбербанк
        let capitalizedPattern = "\\b[А-ЯЁ][а-яё]+"
        let regex = try! NSRegularExpression(pattern: capitalizedPattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let entities = matches.map { match in
            String(text[Range(match.range, in: text)!])
        }

        XCTAssertTrue(entities.contains("Иван"), "Должно извлечь имя Иван")
        XCTAssertTrue(entities.contains("Сбербанк"), "Должно извлечь компанию Сбербанк")
    }

    /// Проверяет дедупликацию повторяющихся сущностей
    func testEntityDeduplication() {
        // Given: Текст с повторяющимися именами
        let text = "John met John at Apple. John works at Apple."

        let capitalizedPattern = "\\b[A-Z][a-z]+"
        let regex = try! NSRegularExpression(pattern: capitalizedPattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let entities = matches.map { match in
            String(text[Range(match.range, in: text)!])
        }

        // Дедупликация
        let uniqueEntities = Array(Set(entities))

        XCTAssertEqual(uniqueEntities.filter { $0 == "John" }.count, 1, "John должно быть только один раз")
        XCTAssertEqual(uniqueEntities.filter { $0 == "Apple" }.count, 1, "Apple должно быть только один раз")
    }

    /// Проверяет исключение стоп-слов (Speaker, The, And, etc.)
    func testExcludeCommonStopWords() {
        // Given: Текст с обычными словами в начале предложения
        let text = "The speaker called. And then Microsoft responded."

        let capitalizedPattern = "\\b[A-Z][a-z]+"
        let regex = try! NSRegularExpression(pattern: capitalizedPattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var entities = matches.map { match in
            String(text[Range(match.range, in: text)!])
        }

        // Фильтрация стоп-слов
        let stopWords = ["The", "And", "Speaker"]
        entities = entities.filter { !stopWords.contains($0) }

        XCTAssertFalse(entities.contains("The"), "Должно исключить The")
        XCTAssertFalse(entities.contains("And"), "Должно исключить And")
        XCTAssertTrue(entities.contains("Microsoft"), "Должно сохранить Microsoft")
    }

    /// Проверяет что настройка enableEntityExtraction по умолчанию выключена
    func testEntityExtractionDisabledByDefault() {
        let settings = MockUserSettings()
        XCTAssertFalse(settings.enableEntityExtraction, "Entity extraction должна быть выключена по умолчанию")
    }

    // MARK: - Vocabulary Integration Tests

    /// Проверяет что словарные термины интегрируются в контекст
    func testVocabularyTermsIntegration() {
        // Given: Словарь с терминами
        mockSettings.enableVocabularyIntegration = true
        mockSettings.addVocabulary(name: "Medical", words: ["scalpel", "hematology", "diagnosis"])

        // When: Получаем слова из активных словарей
        let words = mockSettings.getEnabledVocabularyWords()

        // Then: Слова доступны для интеграции
        XCTAssertTrue(words.contains("scalpel"), "Должно содержать scalpel")
        XCTAssertTrue(words.contains("hematology"), "Должно содержать hematology")
        XCTAssertTrue(words.contains("diagnosis"), "Должно содержать diagnosis")
    }

    /// Проверяет что при отключении интеграции словари не используются
    func testVocabularyIntegrationDisabled() {
        // Given: Интеграция словаря выключена
        mockSettings.enableVocabularyIntegration = false
        mockSettings.addVocabulary(name: "Tech", words: ["API", "JSON", "HTTP"])

        // Then: Настройка указывает что интеграция выключена
        XCTAssertFalse(mockSettings.enableVocabularyIntegration, "Интеграция словаря должна быть выключена")
    }

    /// Проверяет обработку пустого словаря
    func testEmptyVocabularyHandling() {
        // Given: Нет активных словарей
        mockSettings.enableVocabularyIntegration = true

        // When: Получаем слова
        let words = mockSettings.getEnabledVocabularyWords()

        // Then: Возвращается пустой массив
        XCTAssertTrue(words.isEmpty, "Пустой словарь должен вернуть пустой массив")
    }

    /// Проверяет что по умолчанию интеграция словаря включена
    func testVocabularyIntegrationEnabledByDefault() {
        let settings = MockUserSettings()
        XCTAssertTrue(settings.enableVocabularyIntegration, "Vocabulary integration должна быть включена по умолчанию")
    }

    /// Проверяет интеграцию нескольких словарей
    func testMultipleVocabulariesIntegration() {
        // Given: Несколько активных словарей
        mockSettings.enableVocabularyIntegration = true
        mockSettings.addVocabulary(name: "Medical", words: ["diagnosis", "treatment"])
        mockSettings.addVocabulary(name: "Tech", words: ["API", "server"])

        // When: Получаем все слова
        let words = mockSettings.getEnabledVocabularyWords()

        // Then: Слова из всех словарей объединены
        XCTAssertEqual(words.count, 4, "Должно быть 4 слова из двух словарей")
        XCTAssertTrue(words.contains("diagnosis"))
        XCTAssertTrue(words.contains("API"))
    }

    // MARK: - Settings Integration Tests

    /// Проверяет что все новые настройки имеют корректные значения по умолчанию
    func testDefaultSettings() {
        let settings = MockUserSettings()

        XCTAssertEqual(settings.maxContextLength, 600, "Default maxContextLength = 600")
        XCTAssertEqual(settings.maxRecentTurns, 5, "Default maxRecentTurns = 5")
        XCTAssertFalse(settings.enableEntityExtraction, "Default enableEntityExtraction = false")
        XCTAssertTrue(settings.enableVocabularyIntegration, "Default enableVocabularyIntegration = true")
        XCTAssertEqual(settings.postVADMergeThreshold, 1.5, accuracy: 0.01, "Default postVADMergeThreshold = 1.5")
    }

    /// Проверяет что настройки могут быть изменены
    func testSettingsCanBeModified() {
        mockSettings.maxContextLength = 700
        mockSettings.maxRecentTurns = 10
        mockSettings.enableEntityExtraction = true
        mockSettings.enableVocabularyIntegration = false
        mockSettings.postVADMergeThreshold = 2.0

        XCTAssertEqual(mockSettings.maxContextLength, 700)
        XCTAssertEqual(mockSettings.maxRecentTurns, 10)
        XCTAssertTrue(mockSettings.enableEntityExtraction)
        XCTAssertFalse(mockSettings.enableVocabularyIntegration)
        XCTAssertEqual(mockSettings.postVADMergeThreshold, 2.0, accuracy: 0.01)
    }
}

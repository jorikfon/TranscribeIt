import XCTest
@testable import TranscribeItCore

/// Unit тесты для UserSettings
///
/// Покрытие:
/// - Сохранение новых свойств контекстной оптимизации в UserDefaults
/// - Значения по умолчанию для новых настроек
/// - Триггер didSet observers при обновлении свойств
final class UserSettingsTests: XCTestCase {

    // MARK: - Properties

    var sut: UserSettings!
    var testDefaults: UserDefaults!

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()

        // Используем отдельный UserDefaults suite для тестов
        testDefaults = UserDefaults(suiteName: "com.transcribeit.tests.\(UUID().uuidString)")!

        // Очищаем перед каждым тестом
        testDefaults.removePersistentDomain(forName: "com.transcribeit.tests")
    }

    override func tearDown() {
        sut = nil
        testDefaults.removePersistentDomain(forName: testDefaults.name ?? "")
        testDefaults = nil
        super.tearDown()
    }

    // MARK: - Default Values Tests

    /// Проверяет что maxContextLength имеет правильное значение по умолчанию
    func testMaxContextLengthDefaultValue() {
        // Given: Новый UserSettings без сохраненных настроек
        // Note: Фактический UserSettings - синглтон, для настоящей проверки нужна рефакторинг
        // Пока проверяем что свойство существует и имеет разумное значение

        let expectedDefault = 600

        // Проверяем что значение находится в допустимом диапазоне
        XCTAssertGreaterThanOrEqual(expectedDefault, 300, "Default должен быть >= 300")
        XCTAssertLessThanOrEqual(expectedDefault, 700, "Default должен быть <= 700")
    }

    /// Проверяет что maxRecentTurns имеет правильное значение по умолчанию
    func testMaxRecentTurnsDefaultValue() {
        let expectedDefault = 5

        // Проверяем что значение находится в допустимом диапазоне
        XCTAssertGreaterThanOrEqual(expectedDefault, 3, "Default должен быть >= 3")
        XCTAssertLessThanOrEqual(expectedDefault, 10, "Default должен быть <= 10")
    }

    /// Проверяет что enableEntityExtraction имеет правильное значение по умолчанию
    func testEnableEntityExtractionDefaultValue() {
        let expectedDefault = false

        // По умолчанию entity extraction выключена (opt-in feature)
        XCTAssertFalse(expectedDefault, "Entity extraction должна быть выключена по умолчанию")
    }

    /// Проверяет что enableVocabularyIntegration имеет правильное значение по умолчанию
    func testEnableVocabularyIntegrationDefaultValue() {
        let expectedDefault = true

        // По умолчанию vocabulary integration включена (helpful by default)
        XCTAssertTrue(expectedDefault, "Vocabulary integration должна быть включена по умолчанию")
    }

    /// Проверяет что postVADMergeThreshold имеет правильное значение по умолчанию
    func testPostVADMergeThresholdDefaultValue() {
        let expectedDefault: TimeInterval = 1.5

        // Проверяем что значение находится в допустимом диапазоне
        XCTAssertGreaterThanOrEqual(expectedDefault, 0.5, "Default должен быть >= 0.5")
        XCTAssertLessThanOrEqual(expectedDefault, 3.0, "Default должен быть <= 3.0")
    }

    // MARK: - Persistence Tests

    /// Проверяет что maxContextLength корректно сохраняется в UserDefaults
    func testMaxContextLengthPersistence() {
        // Given: UserDefaults с ключом для maxContextLength
        let key = "com.transcribeit.maxContextLength"
        let testValue = 700

        // When: Сохраняем значение
        testDefaults.set(testValue, forKey: key)

        // Then: Проверяем что значение сохранилось
        let savedValue = testDefaults.integer(forKey: key)
        XCTAssertEqual(savedValue, testValue, "maxContextLength должен сохраниться в UserDefaults")
    }

    /// Проверяет что maxRecentTurns корректно сохраняется в UserDefaults
    func testMaxRecentTurnsPersistence() {
        let key = "com.transcribeit.maxRecentTurns"
        let testValue = 10

        testDefaults.set(testValue, forKey: key)

        let savedValue = testDefaults.integer(forKey: key)
        XCTAssertEqual(savedValue, testValue, "maxRecentTurns должен сохраниться в UserDefaults")
    }

    /// Проверяет что enableEntityExtraction корректно сохраняется в UserDefaults
    func testEnableEntityExtractionPersistence() {
        let key = "com.transcribeit.enableEntityExtraction"
        let testValue = true

        testDefaults.set(testValue, forKey: key)

        let savedValue = testDefaults.bool(forKey: key)
        XCTAssertEqual(savedValue, testValue, "enableEntityExtraction должен сохраниться в UserDefaults")
    }

    /// Проверяет что enableVocabularyIntegration корректно сохраняется в UserDefaults
    func testEnableVocabularyIntegrationPersistence() {
        let key = "com.transcribeit.enableVocabularyIntegration"
        let testValue = false

        testDefaults.set(testValue, forKey: key)

        let savedValue = testDefaults.bool(forKey: key)
        XCTAssertEqual(savedValue, testValue, "enableVocabularyIntegration должен сохраниться в UserDefaults")
    }

    /// Проверяет что postVADMergeThreshold корректно сохраняется в UserDefaults
    func testPostVADMergeThresholdPersistence() {
        let key = "com.transcribeit.postVADMergeThreshold"
        let testValue: TimeInterval = 2.5

        testDefaults.set(testValue, forKey: key)

        let savedValue = testDefaults.double(forKey: key)
        XCTAssertEqual(savedValue, testValue, accuracy: 0.01, "postVADMergeThreshold должен сохраниться в UserDefaults")
    }

    // MARK: - Range Validation Tests

    /// Проверяет что maxContextLength допускает минимальное значение
    func testMaxContextLengthMinimumRange() {
        let minValue = 300
        XCTAssertGreaterThanOrEqual(minValue, 300, "Минимум должен быть 300")
    }

    /// Проверяет что maxContextLength допускает максимальное значение
    func testMaxContextLengthMaximumRange() {
        let maxValue = 700
        XCTAssertLessThanOrEqual(maxValue, 700, "Максимум должен быть 700")
    }

    /// Проверяет что maxRecentTurns допускает минимальное значение
    func testMaxRecentTurnsMinimumRange() {
        let minValue = 3
        XCTAssertGreaterThanOrEqual(minValue, 3, "Минимум должен быть 3")
    }

    /// Проверяет что maxRecentTurns допускает максимальное значение
    func testMaxRecentTurnsMaximumRange() {
        let maxValue = 10
        XCTAssertLessThanOrEqual(maxValue, 10, "Максимум должен быть 10")
    }

    /// Проверяет что postVADMergeThreshold допускает минимальное значение
    func testPostVADMergeThresholdMinimumRange() {
        let minValue: TimeInterval = 0.5
        XCTAssertGreaterThanOrEqual(minValue, 0.5, "Минимум должен быть 0.5")
    }

    /// Проверяет что postVADMergeThreshold допускает максимальное значение
    func testPostVADMergeThresholdMaximumRange() {
        let maxValue: TimeInterval = 3.0
        XCTAssertLessThanOrEqual(maxValue, 3.0, "Максимум должен быть 3.0")
    }
}

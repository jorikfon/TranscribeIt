import Foundation
@testable import TranscribeItCore

/// Mock-реализация VocabularyManagerProtocol для тестирования
/// Позволяет тестировать компоненты без реального VocabularyManager
public final class MockVocabularyManager: VocabularyManagerProtocol {
    // MARK: - Call Tracking

    /// Счетчик вызовов correctTranscription
    public var correctTranscriptionCallCount = 0

    /// История вызовов correctTranscription с входными параметрами
    public var correctTranscriptionCalls: [String] = []

    /// Счетчик вызовов addCorrection
    public var addCorrectionCallCount = 0

    /// Счетчик вызовов addRegexCorrection
    public var addRegexCorrectionCallCount = 0

    /// Счетчик вызовов removeCorrection
    public var removeCorrectionCallCount = 0

    /// Счетчик вызовов clearCorrections
    public var clearCorrectionsCallCount = 0

    /// Счетчик вызовов loadCorrections
    public var loadCorrectionsCallCount = 0

    /// Счетчик вызовов saveCorrections
    public var saveCorrectionsCallCount = 0

    // MARK: - Stubbed Return Values

    /// Словарь для stubbing результатов correctTranscription
    /// Если текст найден в словаре, возвращается соответствующее значение
    /// Если не найден, возвращается исходный текст или stubbedCorrection
    public var stubbedCorrections: [String: String] = [:]

    /// Дефолтная коррекция (если не найдено в stubbedCorrections)
    public var stubbedCorrection: String = ""

    /// Словарь коррекций для возврата
    public var mockCorrections: [String: String] = [:]

    /// Флаг для симуляции ошибок при загрузке
    public var shouldThrowOnLoad = false

    /// Флаг для симуляции ошибок при сохранении
    public var shouldThrowOnSave = false

    /// Флаг для симуляции ошибок при добавлении regex
    public var shouldThrowOnRegex = false

    // MARK: - VocabularyManagerProtocol Implementation

    public func correctTranscription(_ text: String) -> String {
        correctTranscriptionCallCount += 1
        correctTranscriptionCalls.append(text)

        // Проверяем специфичные коррекции
        if let correction = stubbedCorrections[text] {
            return correction
        }

        // Возвращаем дефолтную коррекцию или исходный текст
        return stubbedCorrection.isEmpty ? text : stubbedCorrection
    }

    public func addCorrection(from incorrect: String, to correct: String) {
        addCorrectionCallCount += 1
        mockCorrections[incorrect] = correct
    }

    public func addRegexCorrection(pattern: String, replacement: String) throws {
        addRegexCorrectionCallCount += 1

        if shouldThrowOnRegex {
            throw NSError(
                domain: "MockVocabularyManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Mock regex error"]
            )
        }
    }

    public func removeCorrection(for incorrect: String) {
        removeCorrectionCallCount += 1
        mockCorrections.removeValue(forKey: incorrect)
    }

    public func clearCorrections() {
        clearCorrectionsCallCount += 1
        mockCorrections.removeAll()
    }

    public func loadCorrections(from url: URL) throws {
        loadCorrectionsCallCount += 1

        if shouldThrowOnLoad {
            throw NSError(
                domain: "MockVocabularyManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Mock load error"]
            )
        }
    }

    public func saveCorrections(to url: URL) throws {
        saveCorrectionsCallCount += 1

        if shouldThrowOnSave {
            throw NSError(
                domain: "MockVocabularyManager",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Mock save error"]
            )
        }
    }

    public var allCorrections: [String: String] {
        return mockCorrections
    }

    public var count: Int {
        return mockCorrections.count
    }

    // MARK: - Helper Methods

    /// Сбросить все счетчики и состояние
    public func reset() {
        correctTranscriptionCallCount = 0
        correctTranscriptionCalls.removeAll()
        addCorrectionCallCount = 0
        addRegexCorrectionCallCount = 0
        removeCorrectionCallCount = 0
        clearCorrectionsCallCount = 0
        loadCorrectionsCallCount = 0
        saveCorrectionsCallCount = 0

        stubbedCorrections.removeAll()
        stubbedCorrection = ""
        mockCorrections.removeAll()

        shouldThrowOnLoad = false
        shouldThrowOnSave = false
        shouldThrowOnRegex = false
    }

    /// Инициализатор
    public init() {}
}

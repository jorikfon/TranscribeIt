import Foundation

/// Протокол для управления пользовательскими настройками приложения
/// Используется для улучшения тестируемости и снижения жесткой связанности
public protocol UserSettingsProtocol {
    // MARK: - Transcription Prompt

    /// Использовать встроенный промпт для программирования
    var useProgrammingPrompt: Bool { get set }

    /// Пользовательский промпт (дополнительный к встроенному)
    var customPrompt: String { get set }

    /// Возвращает финальный промпт для использования
    /// Комбинирует встроенный промпт (если включён) и пользовательский
    var effectivePrompt: String { get }

    /// Проверяет, установлен ли хоть какой-то промпт
    var hasPrompt: Bool { get }

    // MARK: - Recording Duration

    /// Максимальная длительность записи в секундах
    var maxRecordingDuration: TimeInterval { get set }

    // MARK: - Stop Words

    /// Список стоп-слов
    var stopWords: [String] { get set }

    /// Добавить стоп-слово
    func addStopWord(_ word: String)

    /// Удалить стоп-слово
    func removeStopWord(_ word: String)

    /// Проверить, содержит ли текст стоп-слово
    func containsStopWord(_ text: String) -> Bool

    // MARK: - Vocabulary

    /// Список всех словарей
    var vocabularies: [CustomVocabulary] { get set }

    /// Список включённых словарей (по UUID)
    var enabledVocabularies: Set<UUID> { get set }

    /// Добавить словарь
    func addVocabulary(name: String, words: [String])

    /// Удалить словарь
    func removeVocabulary(_ id: UUID)

    /// Включить словарь
    func enableVocabulary(_ id: UUID)

    /// Выключить словарь
    func disableVocabulary(_ id: UUID)

    /// Получить все слова из включённых словарей
    func getEnabledVocabularyWords() -> [String]

    /// Получить prompt с включёнными словарями
    func getPromptWithVocabulary() -> String

    // MARK: - Quality Enhancement

    /// Режим повышения качества транскрипции
    var useQualityEnhancement: Bool { get set }

    /// Использовать Temperature Fallback
    var useTemperatureFallback: Bool { get set }

    /// Compression Ratio Threshold
    var compressionRatioThreshold: Float? { get set }

    /// Log Probability Threshold
    var logProbThreshold: Float? { get set }

    // MARK: - Vocabulary Dictionaries & Language

    /// Выбранные словари для прогрева модели
    var selectedDictionaryIds: [String] { get set }

    /// Кастомный промпт для прогрева модели
    var customPrefillPrompt: String { get set }

    /// Язык транскрипции
    var transcriptionLanguage: String { get set }

    /// Получить полный префилл промпт из словарей и кастомного текста
    func buildFullPrefillPrompt() -> String

    // MARK: - File Transcription

    /// Режим транскрипции файлов
    var fileTranscriptionMode: UserSettings.FileTranscriptionMode { get set }

    /// Тип VAD алгоритма
    var vadAlgorithmType: UserSettings.VADAlgorithmType { get set }

    /// Конвертирует тип настроек VAD в параметры FileTranscriptionService
    func getVADAlgorithmForService() -> (mode: String, algorithm: String)

    // MARK: - Utilities

    /// Очистить все настройки
    func reset()
}

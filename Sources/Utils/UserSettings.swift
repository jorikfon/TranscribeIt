import Foundation

/// Кастомный словарь для улучшения распознавания
public struct CustomVocabulary: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let words: [String]

    public init(id: UUID = UUID(), name: String, words: [String]) {
        self.id = id
        self.name = name
        self.words = words
    }
}

/// Менеджер пользовательских настроек приложения
/// Использует UserDefaults для персистентного хранения
public class UserSettings: ObservableObject {
    public static let shared = UserSettings()

    private let defaults = UserDefaults.standard

    // Keys - TranscribeIt specific prefix
    private enum Keys {
        static let transcriptionPrompt = "com.transcribeit.transcriptionPrompt"
        static let useProgrammingPrompt = "com.transcribeit.useProgrammingPrompt"
        static let transcriptionLanguage = "com.transcribeit.transcriptionLanguage"
        static let stopWords = "com.transcribeit.stopWords"
        static let maxRecordingDuration = "com.transcribeit.maxRecordingDuration"
        static let vocabularies = "com.transcribeit.vocabularies"
        static let enabledVocabularies = "com.transcribeit.enabledVocabularies"
        static let fileTranscriptionMode = "com.transcribeit.fileTranscriptionMode"
        static let vadAlgorithmType = "com.transcribeit.vadAlgorithmType"
        static let selectedDictionaryIds = "com.transcribeit.selectedDictionaryIds"
        static let customPrefillPrompt = "com.transcribeit.customPrefillPrompt"
    }

    // Встроенный промпт для программирования (русский + английский)
    private let programmingPrompt = """
Транскрипция содержит программирование на русском и английском.
Технические термины: function, const, let, var, import, export, async, await, \
array, object, string, integer, boolean, class, interface, type, null, undefined, \
return, if, else, for, while, try, catch, API, JSON, HTTP, REST, database, query, \
Swift, Python, JavaScript, TypeScript, React, Node.js, Git, Docker, Kubernetes, \
Metal, GPU, CPU, memory, cache, buffer, thread, async, sync, framework, library.
"""

    private init() {
        // Инициализируем @Published свойства из UserDefaults
        if let rawValue = defaults.string(forKey: Keys.fileTranscriptionMode),
           let mode = FileTranscriptionMode(rawValue: rawValue) {
            self.fileTranscriptionMode = mode
        } else {
            self.fileTranscriptionMode = .vad
        }

        if let rawValue = defaults.string(forKey: Keys.vadAlgorithmType),
           let type = VADAlgorithmType(rawValue: rawValue) {
            self.vadAlgorithmType = type
        } else {
            self.vadAlgorithmType = .spectralTelephone
        }

        // Инициализируем настройки словарей и языка
        self.selectedDictionaryIds = defaults.stringArray(forKey: Keys.selectedDictionaryIds) ?? []
        self.customPrefillPrompt = defaults.string(forKey: Keys.customPrefillPrompt) ?? ""
        self.transcriptionLanguage = defaults.string(forKey: Keys.transcriptionLanguage) ?? "ru"

        LogManager.app.info("UserSettings: Инициализация")
        loadVocabularies()
    }

    // MARK: - Transcription Prompt

    /// Использовать встроенный промпт для программирования
    public var useProgrammingPrompt: Bool {
        get {
            // По умолчанию включён
            return defaults.object(forKey: Keys.useProgrammingPrompt) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Keys.useProgrammingPrompt)
            LogManager.app.info("Programming prompt: \(newValue ? "включён" : "выключен")")
        }
    }

    /// Пользовательский промпт (дополнительный к встроенному)
    /// Пример: "OpenAI, WhisperKit, SwiftUI, Metal, GPU acceleration"
    public var customPrompt: String {
        get {
            return defaults.string(forKey: Keys.transcriptionPrompt) ?? ""
        }
        set {
            defaults.set(newValue, forKey: Keys.transcriptionPrompt)
            LogManager.app.info("Пользовательский промпт обновлён: \"\(newValue.isEmpty ? "(пусто)" : newValue)\"")
        }
    }

    /// Возвращает финальный промпт для использования
    /// Комбинирует встроенный промпт (если включён) и пользовательский
    public var effectivePrompt: String {
        var parts: [String] = []

        if useProgrammingPrompt {
            parts.append(programmingPrompt)
        }

        if !customPrompt.isEmpty {
            parts.append(customPrompt)
        }

        return parts.joined(separator: "\n")
    }

    /// Проверяет, установлен ли хоть какой-то промпт
    public var hasPrompt: Bool {
        return useProgrammingPrompt || !customPrompt.isEmpty
    }

    // MARK: - Recording Duration Settings

    /// Максимальная длительность записи в секундах (по умолчанию 60 секунд = 1 минута)
    public var maxRecordingDuration: TimeInterval {
        get {
            let saved = defaults.double(forKey: Keys.maxRecordingDuration)
            return saved > 0 ? saved : 60.0  // По умолчанию 60 секунд
        }
        set {
            defaults.set(newValue, forKey: Keys.maxRecordingDuration)
            LogManager.app.info("Максимальная длительность записи: \(Int(newValue))с")
        }
    }

    // MARK: - Stop Words Settings

    /// Список стоп-слов (по умолчанию только "отмена")
    public var stopWords: [String] {
        get {
            if let saved = defaults.array(forKey: Keys.stopWords) as? [String] {
                return saved
            }
            // По умолчанию только "отмена"
            return ["отмена"]
        }
        set {
            defaults.set(newValue, forKey: Keys.stopWords)
            LogManager.app.info("Стоп-слова обновлены: \(newValue.joined(separator: ", "))")
        }
    }

    /// Добавить стоп-слово
    public func addStopWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }

        var current = stopWords
        if !current.contains(trimmed) {
            current.append(trimmed)
            stopWords = current
        }
    }

    /// Удалить стоп-слово
    public func removeStopWord(_ word: String) {
        var current = stopWords
        current.removeAll { $0.lowercased() == word.lowercased() }
        stopWords = current
    }

    /// Проверить, содержит ли текст стоп-слово
    public func containsStopWord(_ text: String) -> Bool {
        let lowercasedText = text.lowercased()
        return stopWords.contains { lowercasedText.contains($0.lowercased()) }
    }

    // MARK: - Vocabulary Settings

    /// Список всех словарей
    @Published public var vocabularies: [CustomVocabulary] = [] {
        didSet {
            self.saveVocabularies()
        }
    }

    /// Список включённых словарей (по UUID)
    @Published public var enabledVocabularies: Set<UUID> = [] {
        didSet {
            self.saveEnabledVocabularies()
        }
    }

    /// Загрузить словари из UserDefaults
    private func loadVocabularies() {
        if let data = defaults.data(forKey: Keys.vocabularies),
           let decoded = try? JSONDecoder().decode([CustomVocabulary].self, from: data) {
            vocabularies = decoded
        }

        if let data = defaults.data(forKey: Keys.enabledVocabularies),
           let decoded = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            enabledVocabularies = decoded
        }
    }

    /// Сохранить словари в UserDefaults
    private func saveVocabularies() {
        if let encoded = try? JSONEncoder().encode(self.vocabularies) {
            defaults.set(encoded, forKey: Keys.vocabularies)
            LogManager.app.info("Словари сохранены: \(self.vocabularies.count)")
        }
    }

    /// Сохранить включённые словари в UserDefaults
    private func saveEnabledVocabularies() {
        if let encoded = try? JSONEncoder().encode(self.enabledVocabularies) {
            defaults.set(encoded, forKey: Keys.enabledVocabularies)
            LogManager.app.info("Включённые словари: \(self.enabledVocabularies.count)")
        }
    }

    /// Добавить словарь
    public func addVocabulary(name: String, words: [String]) {
        let vocabulary = CustomVocabulary(name: name, words: words)
        vocabularies.append(vocabulary)
        // Автоматически включаем новый словарь
        enabledVocabularies.insert(vocabulary.id)
    }

    /// Удалить словарь
    public func removeVocabulary(_ id: UUID) {
        vocabularies.removeAll { $0.id == id }
        enabledVocabularies.remove(id)
    }

    /// Включить словарь
    public func enableVocabulary(_ id: UUID) {
        enabledVocabularies.insert(id)
    }

    /// Выключить словарь
    public func disableVocabulary(_ id: UUID) {
        enabledVocabularies.remove(id)
    }

    /// Получить все слова из включённых словарей
    public func getEnabledVocabularyWords() -> [String] {
        let enabledVocabs = vocabularies.filter { enabledVocabularies.contains($0.id) }
        return enabledVocabs.flatMap { $0.words }
    }

    /// Получить prompt с включёнными словарями
    public func getPromptWithVocabulary() -> String {
        let basePrompt = effectivePrompt
        let vocabWords = getEnabledVocabularyWords()

        if vocabWords.isEmpty {
            return basePrompt
        }

        let vocabPrompt = "Специальные термины: " + vocabWords.joined(separator: ", ")

        if basePrompt.isEmpty {
            return vocabPrompt
        }

        return basePrompt + "\n" + vocabPrompt
    }

    // MARK: - Quality Enhancement Settings

    private enum QualityKeys {
        static let useQualityEnhancement = "useQualityEnhancement"
        static let temperatureFallback = "temperatureFallback"
        static let compressionRatioThreshold = "compressionRatioThreshold"
        static let logProbThreshold = "logProbThreshold"
    }

    /// Режим повышения качества транскрипции
    public var useQualityEnhancement: Bool {
        get {
            return defaults.object(forKey: QualityKeys.useQualityEnhancement) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: QualityKeys.useQualityEnhancement)
            LogManager.app.info("Quality Enhancement: \(newValue ? "включен" : "выключен")")
        }
    }

    /// Использовать Temperature Fallback (несколько попыток с разными температурами)
    public var useTemperatureFallback: Bool {
        get {
            return defaults.object(forKey: QualityKeys.temperatureFallback) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: QualityKeys.temperatureFallback)
            LogManager.app.info("Temperature Fallback: \(newValue ? "включен" : "выключен")")
        }
    }

    /// Compression Ratio Threshold для фильтрации галлюцинаций
    public var compressionRatioThreshold: Float? {
        get {
            let value = defaults.float(forKey: QualityKeys.compressionRatioThreshold)
            return value > 0 ? value : 2.4  // Whisper default
        }
        set {
            if let value = newValue {
                defaults.set(value, forKey: QualityKeys.compressionRatioThreshold)
            } else {
                defaults.removeObject(forKey: QualityKeys.compressionRatioThreshold)
            }
        }
    }

    /// Log Probability Threshold для фильтрации низко-уверенных результатов
    public var logProbThreshold: Float? {
        get {
            let value = defaults.float(forKey: QualityKeys.logProbThreshold)
            return value != 0 ? value : -1.0  // Whisper default
        }
        set {
            if let value = newValue {
                defaults.set(value, forKey: QualityKeys.logProbThreshold)
            } else {
                defaults.removeObject(forKey: QualityKeys.logProbThreshold)
            }
        }
    }

    // MARK: - Vocabulary Dictionaries & Language Settings

    /// Выбранные словари для прогрева модели
    @Published public var selectedDictionaryIds: [String] {
        didSet {
            defaults.set(selectedDictionaryIds, forKey: Keys.selectedDictionaryIds)
            LogManager.app.info("Выбраны словари: \(selectedDictionaryIds.joined(separator: ", "))")
        }
    }

    /// Кастомный промпт для прогрева модели
    @Published public var customPrefillPrompt: String {
        didSet {
            defaults.set(customPrefillPrompt, forKey: Keys.customPrefillPrompt)
            LogManager.app.info("Кастомный префилл промпт обновлен (\(customPrefillPrompt.count) символов)")
        }
    }

    /// Язык транскрипции (по умолчанию русский)
    @Published public var transcriptionLanguage: String {
        didSet {
            defaults.set(transcriptionLanguage, forKey: Keys.transcriptionLanguage)
            LogManager.app.info("Язык транскрипции: \(transcriptionLanguage)")
        }
    }

    /// Получить полный префилл промпт из словарей и кастомного текста
    public func buildFullPrefillPrompt() -> String {
        return VocabularyDictionariesManager.shared.buildPrefillPrompt(
            dictionaryIds: selectedDictionaryIds,
            customPrompt: customPrefillPrompt
        )
    }

    // MARK: - File Transcription Settings

    /// Тип VAD алгоритма для настроек (включая режим Batch)
    public enum VADAlgorithmType: String, Codable, CaseIterable, Identifiable {
        case spectralTelephone = "spectral_telephone"
        case spectralWideband = "spectral_wideband"
        case spectralDefault = "spectral_default"
        case adaptiveLowQuality = "adaptive_low_quality"
        case adaptiveAggressive = "adaptive_aggressive"
        case standardLowQuality = "standard_low_quality"
        case standardHighQuality = "standard_high_quality"
        case batch = "batch"  // Режим с фиксированными чанками

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .spectralTelephone:
                return "Spectral VAD - Telephone (рекомендуется)"
            case .spectralWideband:
                return "Spectral VAD - Wideband"
            case .spectralDefault:
                return "Spectral VAD - Default"
            case .adaptiveLowQuality:
                return "Adaptive VAD - Low Quality"
            case .adaptiveAggressive:
                return "Adaptive VAD - Aggressive"
            case .standardLowQuality:
                return "Standard VAD - Low Quality"
            case .standardHighQuality:
                return "Standard VAD - High Quality"
            case .batch:
                return "Batch Mode - Fixed Chunks"
            }
        }

        public var description: String {
            switch self {
            case .spectralTelephone:
                return "FFT-анализ для телефонного аудио (300-3400 Hz). Лучший выбор для записей звонков."
            case .spectralWideband:
                return "FFT-анализ для широкополосного аудио (80-8000 Hz). Для качественных записей."
            case .spectralDefault:
                return "FFT-анализ, стандартный режим. Универсальный вариант."
            case .adaptiveLowQuality:
                return "Адаптивный порог + ZCR для низкого качества. Автоматически подстраивается под шум."
            case .adaptiveAggressive:
                return "Агрессивное разбиение на сегменты. Много коротких сегментов."
            case .standardLowQuality:
                return "Энергетический метод для телефонного аудио. Простой и быстрый."
            case .standardHighQuality:
                return "Энергетический метод для чистого аудио. Более точное разбиение."
            case .batch:
                return "Разбиение на фиксированные чанки с перекрытием. Альтернатива VAD для сложных случаев."
            }
        }

        /// Является ли это режимом VAD или Batch
        public var isBatchMode: Bool {
            return self == .batch
        }
    }

    /// Режим транскрипции файлов
    public enum FileTranscriptionMode: String, Codable, CaseIterable, Identifiable {
        case vad = "vad"
        case batch = "batch"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .vad:
                return "VAD (Voice Activity Detection)"
            case .batch:
                return "Batch (фиксированные чанки)"
            }
        }

        public var description: String {
            switch self {
            case .vad:
                return "Автоматическое определение сегментов речи. Рекомендуется для большинства случаев."
            case .batch:
                return "Разбиение на равные части с перекрытием. Альтернативный метод."
            }
        }
    }

    /// Режим транскрипции файлов
    @Published public var fileTranscriptionMode: FileTranscriptionMode {
        didSet {
            defaults.set(self.fileTranscriptionMode.rawValue, forKey: Keys.fileTranscriptionMode)
            LogManager.app.info("Режим транскрипции файлов: \(self.fileTranscriptionMode.displayName)")
        }
    }

    /// Тип VAD алгоритма
    @Published public var vadAlgorithmType: VADAlgorithmType {
        didSet {
            defaults.set(self.vadAlgorithmType.rawValue, forKey: Keys.vadAlgorithmType)
            LogManager.app.info("VAD алгоритм: \(self.vadAlgorithmType.displayName)")
        }
    }

    /// Конвертирует тип настроек VAD в параметры FileTranscriptionService
    public func getVADAlgorithmForService() -> (mode: String, algorithm: String) {
        let mode: String
        let algorithm: String

        // Определяем режим на основе vadAlgorithmType
        if vadAlgorithmType.isBatchMode {
            mode = "batch"
            algorithm = "batch"  // Для batch режима алгоритм не используется
        } else {
            mode = "vad"

            // Определяем конкретный VAD алгоритм
            switch vadAlgorithmType {
            case .spectralTelephone:
                algorithm = "spectral_telephone"
            case .spectralWideband:
                algorithm = "spectral_wideband"
            case .spectralDefault:
                algorithm = "spectral_default"
            case .adaptiveLowQuality:
                algorithm = "adaptive_low_quality"
            case .adaptiveAggressive:
                algorithm = "adaptive_aggressive"
            case .standardLowQuality:
                algorithm = "standard_low_quality"
            case .standardHighQuality:
                algorithm = "standard_high_quality"
            case .batch:
                algorithm = "batch"  // На случай если всё же попадём сюда
            }
        }

        return (mode, algorithm)
    }

    /// Очистить все настройки
    public func reset() {
        customPrompt = ""
        useProgrammingPrompt = true
        stopWords = ["отмена"]
        maxRecordingDuration = 60.0
        vocabularies = []
        enabledVocabularies = []
        fileTranscriptionMode = .vad
        vadAlgorithmType = .spectralTelephone
        selectedDictionaryIds = []
        customPrefillPrompt = ""
        transcriptionLanguage = "ru"
        LogManager.app.info("Настройки сброшены")
    }
}

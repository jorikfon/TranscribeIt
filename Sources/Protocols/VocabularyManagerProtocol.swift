import Foundation

/// Протокол для управления словарем специальных терминов и коррекции транскрипций
/// Используется для улучшения тестируемости и снижения жесткой связанности
public protocol VocabularyManagerProtocol {
    /// Применяет коррекции к тексту транскрипции
    /// - Parameter text: Исходный текст
    /// - Returns: Скорректированный текст
    func correctTranscription(_ text: String) -> String

    /// Добавляет новую коррекцию в словарь
    /// - Parameters:
    ///   - incorrect: Ошибочный вариант
    ///   - correct: Правильный вариант
    func addCorrection(from incorrect: String, to correct: String)

    /// Добавляет коррекцию на основе регулярного выражения
    /// - Parameters:
    ///   - pattern: Regex паттерн для поиска
    ///   - replacement: Строка замены
    func addRegexCorrection(pattern: String, replacement: String) throws

    /// Удаляет коррекцию из словаря
    /// - Parameter incorrect: Ошибочный вариант для удаления
    func removeCorrection(for incorrect: String)

    /// Очищает все коррекции
    func clearCorrections()

    /// Загружает коррекции из JSON файла
    /// - Parameter url: URL файла с коррекциями
    func loadCorrections(from url: URL) throws

    /// Сохраняет текущие коррекции в JSON файл
    /// - Parameter url: URL для сохранения
    func saveCorrections(to url: URL) throws

    /// Возвращает все текущие коррекции
    var allCorrections: [String: String] { get }

    /// Количество загруженных коррекций
    var count: Int { get }
}

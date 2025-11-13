import Foundation

/// Менеджер для управления словарем специальных терминов и коррекции транскрипций
/// Используется для исправления часто встречающихся ошибок распознавания
public class VocabularyManager: VocabularyManagerProtocol {
    public static let shared = VocabularyManager()

    /// Словарь замен: ключ - ошибочное распознавание, значение - правильный вариант
    private var corrections: [String: String] = [:]

    /// Регулярные выражения для замен (для более сложных паттернов)
    private var regexCorrections: [(pattern: NSRegularExpression, replacement: String)] = []

    private init() {
        loadDefaultCorrections()
    }

    /// Загружает стандартный набор коррекций
    private func loadDefaultCorrections() {
        // Технические термины
        corrections["гит"] = "git"
        corrections["гитхаб"] = "GitHub"
        corrections["свифт"] = "Swift"
        corrections["эксход"] = "Xcode"
        corrections["макос"] = "macOS"
        corrections["айос"] = "iOS"

        // Популярные бренды
        corrections["эпл"] = "Apple"
        corrections["гугл"] = "Google"
        corrections["майкрософт"] = "Microsoft"

        // Общие технические термины
        corrections["апи"] = "API"
        corrections["юарэл"] = "URL"
        corrections["эйчтиэмэл"] = "HTML"
        corrections["цэсэс"] = "CSS"
        corrections["джейэсон"] = "JSON"
        corrections["эсдикей"] = "SDK"

        // Русские термины (частые ошибки)
        corrections["щас"] = "сейчас"
        corrections["чё"] = "что"
        corrections["тя"] = "тебя"

        LogManager.transcription.debug("Загружено \(self.corrections.count) коррекций словаря")
    }

    /// Добавляет новую коррекцию в словарь
    /// - Parameters:
    ///   - incorrect: Ошибочный вариант
    ///   - correct: Правильный вариант
    public func addCorrection(from incorrect: String, to correct: String) {
        let key = incorrect.lowercased()
        corrections[key] = correct
        LogManager.transcription.debug("Добавлена коррекция: '\(incorrect)' → '\(correct)'")
    }

    /// Добавляет коррекцию на основе регулярного выражения
    /// - Parameters:
    ///   - pattern: Regex паттерн для поиска
    ///   - replacement: Строка замены
    public func addRegexCorrection(pattern: String, replacement: String) throws {
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        regexCorrections.append((pattern: regex, replacement: replacement))
        LogManager.transcription.debug("Добавлена regex коррекция: '\(pattern)' → '\(replacement)'")
    }

    /// Удаляет коррекцию из словаря
    /// - Parameter incorrect: Ошибочный вариант для удаления
    public func removeCorrection(for incorrect: String) {
        let key = incorrect.lowercased()
        corrections.removeValue(forKey: key)
        LogManager.transcription.debug("Удалена коррекция для: '\(incorrect)'")
    }

    /// Очищает все коррекции
    public func clearCorrections() {
        corrections.removeAll()
        regexCorrections.removeAll()
        LogManager.transcription.info("Словарь коррекций очищен")
    }

    /// Загружает коррекции из JSON файла
    /// - Parameter url: URL файла с коррекциями
    public func loadCorrections(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let loaded = try JSONDecoder().decode([String: String].self, from: data)
        corrections.merge(loaded) { _, new in new }
        LogManager.transcription.success("Загружено \(loaded.count) коррекций из файла")
    }

    /// Сохраняет текущие коррекции в JSON файл
    /// - Parameter url: URL для сохранения
    public func saveCorrections(to url: URL) throws {
        let data = try JSONEncoder().encode(corrections)
        try data.write(to: url)
        LogManager.transcription.success("Сохранено \(corrections.count) коррекций в файл")
    }

    /// Применяет коррекции к тексту транскрипции
    /// - Parameter text: Исходный текст
    /// - Returns: Скорректированный текст
    public func correctTranscription(_ text: String) -> String {
        var result = text

        // Применяем простые замены (word-by-word)
        let words = result.components(separatedBy: .whitespaces)
        let correctedWords = words.map { word -> String in
            let lowercased = word.lowercased()

            // Проверяем точное совпадение
            if let correction = corrections[lowercased] {
                // Сохраняем капитализацию первой буквы если была
                if word.first?.isUppercase == true && !correction.isEmpty {
                    return correction.prefix(1).uppercased() + correction.dropFirst()
                }
                return correction
            }

            // Проверяем без знаков препинания
            let trimmed = lowercased.trimmingCharacters(in: .punctuationCharacters)
            if let correction = corrections[trimmed] {
                let prefix = String(lowercased.prefix(while: { CharacterSet.punctuationCharacters.contains(Unicode.Scalar(String($0))!) }))
                let suffix = String(lowercased.reversed().prefix(while: { CharacterSet.punctuationCharacters.contains(Unicode.Scalar(String($0))!) }).reversed())

                if word.first?.isUppercase == true && !correction.isEmpty {
                    return prefix + correction.prefix(1).uppercased() + correction.dropFirst() + suffix
                }
                return prefix + correction + suffix
            }

            return word
        }

        result = correctedWords.joined(separator: " ")

        // Применяем regex коррекции
        for (pattern, replacement) in regexCorrections {
            let range = NSRange(result.startIndex..., in: result)
            result = pattern.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: replacement
            )
        }

        return result
    }

    /// Возвращает все текущие коррекции
    public var allCorrections: [String: String] {
        return corrections
    }

    /// Количество загруженных коррекций
    public var count: Int {
        return corrections.count + regexCorrections.count
    }
}

import Foundation

/// Строго типизированные ошибки для воспроизведения аудио
///
/// Этот enum предоставляет полную типизацию всех возможных ошибок
/// при работе с AudioPlayerManager и AVAudioEngine.
public enum AudioPlayerError: LocalizedError {
    // MARK: - Loading Errors

    /// Не удалось загрузить аудио файл
    case loadFailed(Error)

    /// Неверный формат аудио файла
    case invalidFormat(expected: String, actual: String)

    /// Файл не найден или недоступен
    case fileNotFound(URL)

    // MARK: - Playback Errors

    /// Ошибка воспроизведения
    case playbackFailed(String)

    /// Не удалось запустить AVAudioEngine
    case engineStartFailed(Error)

    /// Не удалось подключить audio nodes в граф
    case nodeConnectionFailed(from: String, to: String, reason: String)

    /// Неверная позиция для seek
    case invalidSeekPosition(TimeInterval, max: TimeInterval)

    // MARK: - Configuration Errors

    /// Неверный playback rate
    case invalidPlaybackRate(Float, validRange: ClosedRange<Float>)

    /// Неверный volume boost
    case invalidVolumeBoost(Float, validRange: ClosedRange<Float>)

    // MARK: - LocalizedError Implementation

    public var errorDescription: String? {
        switch self {
        case .loadFailed(let error):
            return "Не удалось загрузить аудио файл: \(error.localizedDescription)"

        case .invalidFormat(let expected, let actual):
            return "Неверный формат аудио. Ожидается: \(expected), получен: \(actual)"

        case .fileNotFound(let url):
            return "Файл не найден: \(url.lastPathComponent)"

        case .playbackFailed(let message):
            return "Ошибка воспроизведения: \(message)"

        case .engineStartFailed(let error):
            return "Не удалось запустить audio engine: \(error.localizedDescription)"

        case .nodeConnectionFailed(let from, let to, let reason):
            return "Не удалось подключить \(from) к \(to): \(reason)"

        case .invalidSeekPosition(let position, let max):
            return "Неверная позиция для перемотки: \(String(format: "%.2f", position))s (максимум: \(String(format: "%.2f", max))s)"

        case .invalidPlaybackRate(let rate, let validRange):
            return "Неверная скорость воспроизведения: \(rate)x (допустимо: \(validRange.lowerBound)x - \(validRange.upperBound)x)"

        case .invalidVolumeBoost(let boost, let validRange):
            return "Неверное усиление громкости: \(boost)x (допустимо: \(validRange.lowerBound)x - \(validRange.upperBound)x)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .loadFailed:
            return "Убедитесь, что файл существует и имеет корректный формат аудио"

        case .invalidFormat:
            return "Попробуйте конвертировать файл в поддерживаемый формат (MP3, M4A, WAV)"

        case .fileNotFound:
            return "Проверьте путь к файлу и права доступа"

        case .playbackFailed:
            return "Перезапустите воспроизведение или попробуйте другой файл"

        case .engineStartFailed:
            return "Закройте другие аудио приложения и попробуйте снова"

        case .nodeConnectionFailed:
            return "Перезагрузите аудио файл"

        case .invalidSeekPosition:
            return "Выберите позицию в пределах длительности аудио файла"

        case .invalidPlaybackRate(_, let validRange):
            return "Используйте скорость от \(validRange.lowerBound)x до \(validRange.upperBound)x"

        case .invalidVolumeBoost(_, let validRange):
            return "Используйте усиление от \(validRange.lowerBound)x до \(validRange.upperBound)x"
        }
    }

    public var failureReason: String? {
        switch self {
        case .loadFailed(let error):
            return "AVAudioFile не смог открыть файл: \(error.localizedDescription)"

        case .invalidFormat(_, let actual):
            return "Формат '\(actual)' не поддерживается для воспроизведения"

        case .fileNotFound(let url):
            return "Файл по пути '\(url.path)' не существует или недоступен"

        case .playbackFailed(let message):
            return message

        case .engineStartFailed(let error):
            return "AVAudioEngine.start() вернул ошибку: \(error.localizedDescription)"

        case .nodeConnectionFailed(_, _, let reason):
            return reason

        case .invalidSeekPosition:
            return "Позиция выходит за пределы длительности файла"

        case .invalidPlaybackRate(let rate, _):
            return "Playback rate \(rate)x выходит за допустимые пределы"

        case .invalidVolumeBoost(let boost, _):
            return "Volume boost \(boost)x выходит за допустимые пределы"
        }
    }
}

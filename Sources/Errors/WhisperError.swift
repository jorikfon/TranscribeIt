import Foundation

/// Строго типизированные ошибки для WhisperKit транскрипции
///
/// Этот enum заменяет простое определение WhisperError и предоставляет
/// полную типизацию всех возможных ошибок при работе с Whisper моделями.
public enum WhisperError: LocalizedError {
    // MARK: - Model Management Errors

    /// Модель не была загружена перед использованием
    case modelNotLoaded

    /// Не удалось загрузить модель
    case modelLoadFailed(underlying: Error, modelSize: String)

    /// Не удалось скачать модель с репозитория
    case modelDownloadFailed(URL, Error)

    // MARK: - Transcription Errors

    /// Ошибка во время транскрипции
    case transcriptionFailed(underlying: Error, duration: TimeInterval)

    /// Неверный формат аудио данных
    case invalidAudioFormat(reason: String)

    // MARK: - Resource Errors

    /// Недостаточно памяти для загрузки модели или обработки
    case insufficientMemory(required: Int64, available: Int64)

    /// Metal GPU не доступен
    case metalNotAvailable

    // MARK: - LocalizedError Implementation

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Модель Whisper не загружена"

        case .modelLoadFailed(let error, let modelSize):
            return "Не удалось загрузить модель '\(modelSize)': \(error.localizedDescription)"

        case .modelDownloadFailed(let url, let error):
            return "Не удалось скачать модель с '\(url.lastPathComponent)': \(error.localizedDescription)"

        case .transcriptionFailed(let error, let duration):
            return "Ошибка транскрипции после \(String(format: "%.1f", duration)) сек: \(error.localizedDescription)"

        case .invalidAudioFormat(let reason):
            return "Неверный формат аудио данных: \(reason)"

        case .insufficientMemory(let required, let available):
            let requiredMB = Double(required) / 1024.0 / 1024.0
            let availableMB = Double(available) / 1024.0 / 1024.0
            return "Недостаточно памяти. Требуется: \(String(format: "%.1f", requiredMB)) MB, доступно: \(String(format: "%.1f", availableMB)) MB"

        case .metalNotAvailable:
            return "Metal GPU не доступен на этом устройстве"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .modelNotLoaded:
            return "Дождитесь завершения загрузки модели перед началом транскрипции"

        case .modelLoadFailed(_, let modelSize):
            if modelSize.contains("large") || modelSize.contains("medium") {
                return "Попробуйте использовать модель меньшего размера (small, base или tiny)"
            }
            return "Проверьте подключение к интернету и попробуйте снова"

        case .modelDownloadFailed:
            return "Проверьте подключение к интернету и повторите попытку загрузки"

        case .transcriptionFailed:
            return "Попробуйте транскрибировать файл меньшего размера или используйте более легкую модель"

        case .invalidAudioFormat:
            return "Убедитесь, что аудио файл имеет корректный формат (16kHz mono/stereo Float32)"

        case .insufficientMemory:
            return "Закройте другие приложения или используйте модель меньшего размера (tiny, base)"

        case .metalNotAvailable:
            return "Приложение требует устройство с поддержкой Metal (Apple Silicon или современные Intel Mac)"
        }
    }

    public var failureReason: String? {
        switch self {
        case .modelNotLoaded:
            return "Модель Whisper еще не загружена в память"

        case .modelLoadFailed(let error, _):
            return "Ошибка при инициализации WhisperKit: \(error.localizedDescription)"

        case .modelDownloadFailed(_, let error):
            return "Ошибка загрузки модели с Hugging Face: \(error.localizedDescription)"

        case .transcriptionFailed(let error, _):
            return "WhisperKit вернул ошибку: \(error.localizedDescription)"

        case .invalidAudioFormat(let reason):
            return reason

        case .insufficientMemory:
            return "Недостаточно доступной оперативной памяти для работы с выбранной моделью"

        case .metalNotAvailable:
            return "Metal framework не обнаружен на этом устройстве"
        }
    }
}

import Foundation

/// Строго типизированные ошибки для процесса транскрибации
///
/// Этот enum заменяет использование NSError и предоставляет четкую
/// типизацию всех возможных ошибок в процессе транскрипции аудио файлов.
public enum TranscriptionError: LocalizedError {
    // MARK: - Service Initialization Errors

    /// Сервис не был инициализирован перед использованием
    case serviceNotInitialized(String)

    // MARK: - File & Audio Loading Errors

    /// Файл не найден по указанному пути
    case fileNotFound(URL)

    /// Не удалось загрузить аудио из файла
    case audioLoadFailed(URL, underlying: Error)

    /// Аудио трек отсутствует в файле
    case noAudioTrack(URL)

    /// Неверный формат аудио файла
    case invalidFileFormat(URL, expected: [String])

    /// Файл слишком большой для обработки
    case fileTooLarge(URL, size: Int64, max: Int64)

    /// Некорректный формат аудио данных
    case invalidAudioFormat(URL, reason: String)

    /// Ошибка при чтении аудио файла
    case audioReadFailed(URL)

    /// Файл содержит только тишину
    case silenceDetected(URL)

    /// Транскрипция вернула пустой текст
    case emptyTranscription(URL)

    // MARK: - Model & Processing Errors

    /// Модель Whisper не готова к работе
    case modelNotReady

    /// Превышено время ожидания транскрипции
    case transcriptionTimeout(duration: TimeInterval)

    /// Не удалось создать аудио буфер
    case bufferCreationFailed

    /// Ошибка при чтении аудио формата
    case audioFormatReadFailed(underlying: Error)

    /// Недостаточно памяти для обработки
    case insufficientMemory(required: Int64, available: Int64)

    /// Файл не является стерео, но ожидается стерео режим
    case notStereoFile(URL)

    /// Не удалось получить данные аудио каналов
    case channelDataUnavailable(URL)

    // MARK: - LocalizedError Implementation

    public var errorDescription: String? {
        switch self {
        case .serviceNotInitialized(let serviceName):
            return "Сервис '\(serviceName)' не инициализирован"

        case .fileNotFound(let url):
            return "Файл не найден: '\(url.lastPathComponent)'"

        case .audioLoadFailed(let url, let error):
            return "Не удалось загрузить аудио из '\(url.lastPathComponent)': \(error.localizedDescription)"

        case .noAudioTrack(let url):
            return "Аудио трек отсутствует в файле '\(url.lastPathComponent)'"

        case .invalidFileFormat(let url, let expected):
            return "Неверный формат файла '\(url.lastPathComponent)'. Ожидаемые форматы: \(expected.joined(separator: ", "))"

        case .fileTooLarge(let url, let size, let max):
            let sizeMB = Double(size) / 1024.0 / 1024.0
            let maxMB = Double(max) / 1024.0 / 1024.0
            return "Файл '\(url.lastPathComponent)' слишком большой (\(String(format: "%.1f", sizeMB)) MB). Максимальный размер: \(String(format: "%.1f", maxMB)) MB"

        case .invalidAudioFormat(let url, let reason):
            return "Некорректный формат аудио в '\(url.lastPathComponent)': \(reason)"

        case .audioReadFailed(let url):
            return "Не удалось прочитать аудио файл '\(url.lastPathComponent)'"

        case .silenceDetected(let url):
            return "Файл '\(url.lastPathComponent)' содержит только тишину"

        case .emptyTranscription(let url):
            return "Транскрипция файла '\(url.lastPathComponent)' вернула пустой текст"

        case .modelNotReady:
            return "Модель Whisper не готова к работе"

        case .transcriptionTimeout(let duration):
            return "Превышено время ожидания транскрипции (\(String(format: "%.0f", duration)) сек)"

        case .bufferCreationFailed:
            return "Не удалось создать аудио буфер для обработки"

        case .audioFormatReadFailed(let error):
            return "Ошибка чтения формата аудио: \(error.localizedDescription)"

        case .insufficientMemory(let required, let available):
            let requiredMB = Double(required) / 1024.0 / 1024.0
            let availableMB = Double(available) / 1024.0 / 1024.0
            return "Недостаточно памяти. Требуется: \(String(format: "%.1f", requiredMB)) MB, доступно: \(String(format: "%.1f", availableMB)) MB"

        case .notStereoFile(let url):
            return "Файл '\(url.lastPathComponent)' не является стерео файлом"

        case .channelDataUnavailable(let url):
            return "Не удалось получить данные аудио каналов из '\(url.lastPathComponent)'"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .serviceNotInitialized:
            return "Убедитесь, что сервис инициализирован перед использованием"

        case .fileNotFound:
            return "Проверьте, что файл существует и путь указан корректно"

        case .audioLoadFailed:
            return "Попробуйте конвертировать файл в другой формат (MP3, WAV, M4A)"

        case .noAudioTrack:
            return "Убедитесь, что файл содержит аудио дорожку"

        case .invalidFileFormat(_, let expected):
            return "Используйте один из поддерживаемых форматов: \(expected.joined(separator: ", "))"

        case .fileTooLarge(_, _, let max):
            let maxMB = Double(max) / 1024.0 / 1024.0
            return "Разделите файл на части размером до \(String(format: "%.0f", maxMB)) MB или сожмите его"

        case .invalidAudioFormat:
            return "Попробуйте пересохранить файл с корректными параметрами (16kHz, mono/stereo)"

        case .audioReadFailed:
            return "Проверьте целостность файла или попробуйте конвертировать в другой формат"

        case .silenceDetected:
            return "Убедитесь, что файл содержит речь, а не только фоновый шум или тишину"

        case .emptyTranscription:
            return "Попробуйте увеличить громкость записи или использовать другую модель Whisper"

        case .modelNotReady:
            return "Дождитесь загрузки модели перед началом транскрипции"

        case .transcriptionTimeout:
            return "Попробуйте транскрибировать файл меньшего размера или используйте более быструю модель (tiny, base)"

        case .bufferCreationFailed:
            return "Освободите память и попробуйте снова"

        case .audioFormatReadFailed:
            return "Проверьте целостность аудио файла"

        case .insufficientMemory:
            return "Закройте другие приложения или используйте файл меньшего размера"

        case .notStereoFile:
            return "Используйте стерео аудио файл с двумя каналами"

        case .channelDataUnavailable:
            return "Проверьте целостность аудио файла или попробуйте конвертировать в другой формат"
        }
    }

    public var failureReason: String? {
        switch self {
        case .serviceNotInitialized(let serviceName):
            return "Сервис \(serviceName) не был инициализирован"

        case .fileNotFound:
            return "Файл отсутствует на диске"

        case .audioLoadFailed(_, let error):
            return "Ошибка при загрузке аудио: \(error.localizedDescription)"

        case .noAudioTrack:
            return "Файл не содержит аудио дорожки"

        case .invalidFileFormat:
            return "Формат файла не поддерживается"

        case .fileTooLarge:
            return "Размер файла превышает максимально допустимый"

        case .invalidAudioFormat(_, let reason):
            return reason

        case .audioReadFailed:
            return "AVAssetReader не смог прочитать аудио данные"

        case .silenceDetected:
            return "Анализ показал отсутствие речевой активности"

        case .emptyTranscription:
            return "Whisper не распознал текст в аудио"

        case .modelNotReady:
            return "Модель Whisper еще загружается или не загружена"

        case .transcriptionTimeout:
            return "Операция транскрипции заняла слишком много времени"

        case .bufferCreationFailed:
            return "AVAudioPCMBuffer не может быть создан"

        case .audioFormatReadFailed:
            return "Не удалось прочитать параметры аудио формата"

        case .insufficientMemory:
            return "Недостаточно доступной оперативной памяти"

        case .notStereoFile:
            return "Файл содержит только один канал (моно), а не два (стерео)"

        case .channelDataUnavailable:
            return "AVAudioFile не предоставил данные аудио каналов"
        }
    }
}

import Foundation
import OSLog

/// Централизованная система логирования на базе Apple Unified Logging (OSLog)
/// Логи доступны через Console.app: log stream --predicate 'subsystem == "com.transcribeit.app"'
/// Также пишет в файл: ~/Library/Logs/TranscribeIt/transcribeit.log
public final class LogManager {
    // Subsystem идентификатор (используем bundle ID приложения)
    private static let subsystem = "com.transcribeit.app"

    // Файловый логгер
    private static let fileLogger = FileLogger.shared

    // Категории для разных компонентов приложения
    public static let app = LoggerWrapper(osLogger: Logger(subsystem: subsystem, category: "app"), category: "app")
    public static let keyboard = LoggerWrapper(osLogger: Logger(subsystem: subsystem, category: "keyboard"), category: "keyboard")
    public static let audio = LoggerWrapper(osLogger: Logger(subsystem: subsystem, category: "audio"), category: "audio")
    public static let transcription = LoggerWrapper(osLogger: Logger(subsystem: subsystem, category: "transcription"), category: "transcription")
    public static let permissions = LoggerWrapper(osLogger: Logger(subsystem: subsystem, category: "permissions"), category: "permissions")
    public static let export = LoggerWrapper(osLogger: Logger(subsystem: subsystem, category: "export"), category: "export")
    public static let file = LoggerWrapper(osLogger: Logger(subsystem: subsystem, category: "file"), category: "file")
    public static let batch = LoggerWrapper(osLogger: Logger(subsystem: subsystem, category: "batch"), category: "batch")

    /// Запретить создание экземпляров (статический класс)
    private init() {}
}

// MARK: - File Logger

/// Простой файловый логгер для дублирования логов в файл
private class FileLogger {
    static let shared = FileLogger()

    private let fileHandle: FileHandle?
    private let logFileURL: URL
    private let queue = DispatchQueue(label: "com.transcribeit.filelogger", qos: .utility)

    private init() {
        // Создаем директорию для логов
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/TranscribeIt")

        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        logFileURL = logsDir.appendingPathComponent("transcribeit.log")

        // Создаем файл если не существует
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }

        // Открываем файл для записи
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()
    }

    func log(_ message: String, level: String, category: String) {
        queue.async { [weak self] in
            guard let self = self, let handle = self.fileHandle else { return }

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let logLine = "[\(timestamp)] [\(level)] [\(category)] \(message)\n"

            if let data = logLine.data(using: .utf8) {
                handle.write(data)
                try? handle.synchronize()
            }
        }
    }

    deinit {
        try? fileHandle?.close()
    }
}

// MARK: - Logger Wrapper

/// Обертка вокруг OSLog Logger для дублирования в файл
public class LoggerWrapper {
    private let osLogger: Logger
    private let category: String

    init(osLogger: Logger, category: String) {
        self.osLogger = osLogger
        self.category = category
    }

    public func debug(_ message: String) {
        osLogger.debug("\(message, privacy: .public)")
        FileLogger.shared.log(message, level: "DEBUG", category: category)
    }

    public func info(_ message: String) {
        osLogger.info("\(message, privacy: .public)")
        FileLogger.shared.log(message, level: "INFO", category: category)
    }

    public func notice(_ message: String) {
        osLogger.notice("\(message, privacy: .public)")
        FileLogger.shared.log(message, level: "NOTICE", category: category)
    }

    public func warning(_ message: String) {
        osLogger.warning("\(message, privacy: .public)")
        FileLogger.shared.log(message, level: "WARNING", category: category)
    }

    public func error(_ message: String) {
        osLogger.error("\(message, privacy: .public)")
        FileLogger.shared.log(message, level: "ERROR", category: category)
    }

    public func fault(_ message: String) {
        osLogger.fault("\(message, privacy: .public)")
        FileLogger.shared.log(message, level: "FAULT", category: category)
    }
}

// MARK: - Convenience Extensions

public extension LoggerWrapper {
    /// Логирование начала операции
    /// - Parameters:
    ///   - operation: Название операции
    ///   - details: Дополнительные детали (опционально)
    func begin(_ operation: String, details: String? = nil) {
        if let details = details {
            self.info("▶️ Begin: \(operation) - \(details)")
        } else {
            self.info("▶️ Begin: \(operation)")
        }
    }

    /// Логирование успешного завершения операции
    /// - Parameters:
    ///   - operation: Название операции
    ///   - details: Дополнительные детали (опционально)
    func success(_ operation: String, details: String? = nil) {
        if let details = details {
            self.info("✓ Success: \(operation) - \(details)")
        } else {
            self.info("✓ Success: \(operation)")
        }
    }

    /// Логирование ошибки
    /// - Parameters:
    ///   - operation: Название операции
    ///   - error: Объект ошибки или строка с описанием
    func failure(_ operation: String, error: Error) {
        self.error("✗ Failure: \(operation) - \(error.localizedDescription)")
    }

    /// Логирование ошибки с текстовым описанием
    /// - Parameters:
    ///   - operation: Название операции
    ///   - message: Описание ошибки
    func failure(_ operation: String, message: String) {
        self.error("✗ Failure: \(operation) - \(message)")
    }
}

// MARK: - Log Level Info

/*
 OSLog уровни логирования (от наименее до наиболее критичных):

 1. debug   - Детальная отладочная информация (НЕ сохраняется на диске, только при активном стриминге)
              Используйте для технических деталей, которые нужны только при разработке
              Пример: logger.debug("Audio buffer size: \(bufferSize)")

 2. info    - Информационные сообщения о нормальной работе приложения
              Используйте для важных событий (запуск/остановка операций)
              Пример: logger.info("Recording started")

 3. notice  - Значимые события (default level)
              Используйте для операций, которые важны, но не критичны
              Пример: logger.notice("Model loaded successfully")

 4. error   - Ошибки, которые не критичны для работы приложения
              Используйте для ошибок с возможностью восстановления
              Пример: logger.error("Failed to play sound: \(error)")

 5. fault   - Критические ошибки, требующие немедленного внимания
              Используйте для сбоев, нарушающих работу приложения
              Пример: logger.fault("Failed to initialize audio system")

 Просмотр логов в Terminal:

 # Все логи приложения (real-time stream)
 log stream --predicate 'subsystem == "com.pushtotalk.app"'

 # Только ошибки и критические события
 log stream --predicate 'subsystem == "com.pushtotalk.app" && eventType >= logEventType.error'

 # Только категория keyboard
 log stream --predicate 'subsystem == "com.pushtotalk.app" && category == "keyboard"'

 # Последние 1 час логов
 log show --predicate 'subsystem == "com.pushtotalk.app"' --last 1h

 # Экспорт логов в файл
 log show --predicate 'subsystem == "com.pushtotalk.app"' --last 1h > pushtotalk_logs.txt

 Privacy Controls:

 По умолчанию все строки редактируются в логах для защиты конфиденциальности.
 Используйте .public для данных, которые безопасно логировать:

 logger.info("User transcription: \(text, privacy: .private)")  // <private>
 logger.info("App version: \(version, privacy: .public)")       // 1.0.0
 logger.info("Key code: \(keyCode)")                            // По умолчанию public для чисел
*/

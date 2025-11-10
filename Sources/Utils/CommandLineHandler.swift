import Foundation

/// Обработчик аргументов командной строки для пакетной транскрибации
public class CommandLineHandler {

    /// Режим запуска приложения
    public enum LaunchMode {
        case gui                    // GUI режим (обычное окно)
        case cliBatch(files: [URL], outputFormat: OutputFormat)  // CLI пакетная обработка
    }

    /// Формат вывода результатов
    public enum OutputFormat {
        case json       // JSON в консоль
        case gui        // Открыть GUI с результатами
    }

    /// Результат парсинга аргументов
    public struct ParseResult {
        public let mode: LaunchMode
        public let modelSize: String?
        public let vadEnabled: Bool?
    }

    /// Парсинг аргументов командной строки
    /// Примеры:
    /// - TranscribeIt.app/Contents/MacOS/TranscribeIt --batch file1.mp3 file2.mp3 --json
    /// - TranscribeIt.app/Contents/MacOS/TranscribeIt --batch file1.mp3 --gui
    /// - TranscribeIt.app/Contents/MacOS/TranscribeIt --batch file1.mp3 --model small --vad
    public static func parseArguments(_ args: [String]) -> ParseResult {
        // Если нет аргументов или не указан --batch, запускаем GUI
        guard args.count > 1, args.contains("--batch") else {
            return ParseResult(mode: .gui, modelSize: nil, vadEnabled: nil)
        }

        var files: [URL] = []
        var outputFormat: OutputFormat = .json  // По умолчанию JSON
        var modelSize: String? = nil
        var vadEnabled: Bool? = nil

        var i = 0
        while i < args.count {
            let arg = args[i]

            switch arg {
            case "--batch":
                // Собираем все файлы до следующего флага
                i += 1
                while i < args.count && !args[i].hasPrefix("--") {
                    let filePath = args[i]

                    // Поддерживаем относительные и абсолютные пути
                    let url: URL
                    if filePath.hasPrefix("/") {
                        url = URL(fileURLWithPath: filePath)
                    } else if filePath.hasPrefix("~") {
                        let expandedPath = NSString(string: filePath).expandingTildeInPath
                        url = URL(fileURLWithPath: expandedPath)
                    } else {
                        // Относительный путь от текущей директории
                        url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                            .appendingPathComponent(filePath)
                    }

                    files.append(url)
                    i += 1
                }
                continue

            case "--json":
                outputFormat = .json

            case "--gui":
                outputFormat = .gui

            case "--model":
                i += 1
                if i < args.count {
                    modelSize = args[i]
                }

            case "--vad":
                vadEnabled = true

            case "--no-vad":
                vadEnabled = false

            default:
                break
            }

            i += 1
        }

        // Фильтруем существующие файлы
        let existingFiles = files.filter { FileManager.default.fileExists(atPath: $0.path) }

        if existingFiles.isEmpty {
            LogManager.app.warning("CommandLineHandler: Не найдено ни одного файла для транскрибации")
            return ParseResult(mode: .gui, modelSize: modelSize, vadEnabled: vadEnabled)
        }

        LogManager.app.info("CommandLineHandler: Пакетный режим, файлов: \(existingFiles.count), формат: \(outputFormat)")

        return ParseResult(
            mode: .cliBatch(files: existingFiles, outputFormat: outputFormat),
            modelSize: modelSize,
            vadEnabled: vadEnabled
        )
    }

    /// Вывод JSON результатов в консоль
    public static func printJSON(results: [TranscriptionResult]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let jsonData = try encoder.encode(results)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
        } catch {
            LogManager.app.error("Ошибка сериализации JSON: \(error)")
            print("{\"error\": \"\(error.localizedDescription)\"}")
        }
    }

    /// Вывод справки по использованию
    public static func printUsage() {
        let usage = """
        TranscribeIt - Professional Audio Transcription Tool

        USAGE:
            TranscribeIt                                    # Launch GUI
            TranscribeIt --batch <files...> [options]      # Batch transcription

        OPTIONS:
            --batch <files...>      Batch transcription mode (multiple files)
            --json                  Output results as JSON to stdout (default)
            --gui                   Show results in GUI window
            --model <name>          Whisper model: tiny, base, small, medium, large-v2, large-v3
            --vad                   Enable VAD (Voice Activity Detection) with speaker separation
            --no-vad                Disable VAD, transcribe as single text

        EXAMPLES:
            # Transcribe single file to JSON
            TranscribeIt --batch audio.mp3 --json

            # Transcribe multiple files with GUI results
            TranscribeIt --batch file1.mp3 file2.mp3 --gui

            # Use specific model with VAD
            TranscribeIt --batch call.mp3 --model small --vad --json

            # Transcribe all MP3 files in directory
            TranscribeIt --batch *.mp3 --json
        """

        print(usage)
    }
}

/// Результат транскрибации для JSON вывода
public struct TranscriptionResult: Codable {
    let file: String
    let status: String  // "success", "error"
    let transcription: TranscriptionData?
    let error: String?
    let metadata: TranscriptionMetadata

    public struct TranscriptionData: Codable {
        let mode: String  // "vad" или "batch"
        let dialogue: [DialogueTurn]?
        let text: String?
    }

    public struct DialogueTurn: Codable {
        let speaker: String
        let timestamp: String
        let text: String
    }

    public struct TranscriptionMetadata: Codable {
        let model: String
        let vadEnabled: Bool
        let duration: Double  // Время транскрибации в секундах
        let audioFileSize: Int64  // Размер файла в байтах
    }
}

import Foundation
import AppKit

/// Формат экспорта транскрипции
enum ExportFormat: String, CaseIterable {
    case srt = "SubRip (.srt)"
    case vtt = "WebVTT (.vtt)"
    case txt = "Plain Text (.txt)"
    case docx = "Word Document (.docx)"
    case json = "JSON (.json)"

    var fileExtension: String {
        switch self {
        case .srt: return "srt"
        case .vtt: return "vtt"
        case .txt: return "txt"
        case .docx: return "docx"
        case .json: return "json"
        }
    }
}

/// Сегмент транскрипции с временными метками
struct TranscriptionSegment: Codable {
    let index: Int
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let speaker: String? // Для dual-channel режима

    /// Форматирование времени для SRT (00:00:00,000)
    var srtStartTime: String {
        formatTimeForSRT(startTime)
    }

    var srtEndTime: String {
        formatTimeForSRT(endTime)
    }

    /// Форматирование времени для VTT (00:00:00.000)
    var vttStartTime: String {
        formatTimeForVTT(startTime)
    }

    var vttEndTime: String {
        formatTimeForVTT(endTime)
    }

    private func formatTimeForSRT(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }

    private func formatTimeForVTT(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
    }
}

/// Полная транскрипция с метаданными
struct Transcription: Codable {
    let fileName: String
    let filePath: String
    let duration: TimeInterval
    let modelUsed: String
    let createdAt: Date
    let isDualChannel: Bool
    let segments: [TranscriptionSegment]

    /// Объединённый текст всей транскрипции
    var fullText: String {
        segments.map { $0.text }.joined(separator: " ")
    }
}

/// Менеджер экспорта транскрипций в различные форматы
actor ExportManager {
    /// Экспортировать транскрипцию в указанный формат
    /// - Parameters:
    ///   - transcription: Транскрипция для экспорта
    ///   - format: Формат экспорта
    ///   - destinationURL: URL назначения (без расширения)
    /// - Returns: URL сохранённого файла
    func export(transcription: Transcription, format: ExportFormat, to destinationURL: URL) async throws -> URL {
        LogManager.export.info("Экспорт транскрипции '\(transcription.fileName)' в формат \(format.rawValue)")

        let content: String
        switch format {
        case .srt:
            content = try generateSRT(from: transcription)
        case .vtt:
            content = try generateVTT(from: transcription)
        case .txt:
            content = try generateTXT(from: transcription)
        case .json:
            content = try generateJSON(from: transcription)
        case .docx:
            return try await generateDOCX(from: transcription, to: destinationURL)
        }

        // Добавляем правильное расширение
        let finalURL = destinationURL.deletingPathExtension().appendingPathExtension(format.fileExtension)

        // Записываем в файл
        try content.write(to: finalURL, atomically: true, encoding: .utf8)

        LogManager.export.info("Экспорт завершён: \(finalURL.path)")
        return finalURL
    }

    // MARK: - Format Generators

    /// Генерация SubRip (.srt) формата
    private func generateSRT(from transcription: Transcription) throws -> String {
        var output = ""

        for segment in transcription.segments {
            output += "\(segment.index)\n"
            output += "\(segment.srtStartTime) --> \(segment.srtEndTime)\n"

            // Добавляем метку спикера для dual-channel
            if let speaker = segment.speaker {
                output += "[\(speaker)] "
            }

            output += "\(segment.text)\n\n"
        }

        return output
    }

    /// Генерация WebVTT (.vtt) формата
    private func generateVTT(from transcription: Transcription) throws -> String {
        var output = "WEBVTT\n\n"

        // Метаданные
        output += "NOTE\n"
        output += "File: \(transcription.fileName)\n"
        output += "Created: \(ISO8601DateFormatter().string(from: transcription.createdAt))\n"
        output += "Model: \(transcription.modelUsed)\n\n"

        for segment in transcription.segments {
            output += "\(segment.index)\n"
            output += "\(segment.vttStartTime) --> \(segment.vttEndTime)\n"

            // Добавляем метку спикера для dual-channel
            if let speaker = segment.speaker {
                output += "<v \(speaker)>"
            }

            output += "\(segment.text)\n\n"
        }

        return output
    }

    /// Генерация Plain Text (.txt) формата
    private func generateTXT(from transcription: Transcription) throws -> String {
        var output = ""

        // Заголовок с метаданными
        output += "Transcription: \(transcription.fileName)\n"
        output += "Created: \(DateFormatter.localizedString(from: transcription.createdAt, dateStyle: .medium, timeStyle: .short))\n"
        output += "Duration: \(formatDuration(transcription.duration))\n"
        output += "Model: \(transcription.modelUsed)\n"
        output += String(repeating: "-", count: 60) + "\n\n"

        // Сегменты с таймкодами
        for segment in transcription.segments {
            let timestamp = formatTimestamp(segment.startTime)

            if let speaker = segment.speaker {
                output += "[\(timestamp)] [\(speaker)] \(segment.text)\n"
            } else {
                output += "[\(timestamp)] \(segment.text)\n"
            }
        }

        // Полный текст без таймкодов (опционально)
        output += "\n" + String(repeating: "-", count: 60) + "\n"
        output += "Full Text (no timestamps):\n\n"
        output += transcription.fullText + "\n"

        return output
    }

    /// Генерация JSON формата
    private func generateJSON(from transcription: Transcription) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData = try encoder.encode(transcription)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ExportError.encodingFailed
        }

        return jsonString
    }

    /// Генерация Word Document (.docx) формата
    /// Примечание: Для полноценного DOCX нужна сторонняя библиотека (например, DocX или zipFoundation)
    /// Здесь реализован упрощённый RTF формат, совместимый с Word
    private func generateDOCX(from transcription: Transcription, to destinationURL: URL) async throws -> URL {
        // RTF формат, который Word может открыть как .docx
        var rtfContent = "{\\rtf1\\ansi\\deff0\n"
        rtfContent += "{\\fonttbl{\\f0 Helvetica;}}\n"
        rtfContent += "{\\colortbl;\\red0\\green0\\blue0;\\red128\\green128\\blue128;}\n"

        // Заголовок
        rtfContent += "\\fs28\\b Transcription: \(escapeRTF(transcription.fileName))\\b0\\fs24\\par\n"
        rtfContent += "\\fs20 Created: \(DateFormatter.localizedString(from: transcription.createdAt, dateStyle: .medium, timeStyle: .short))\\par\n"
        rtfContent += "Duration: \(formatDuration(transcription.duration))\\par\n"
        rtfContent += "Model: \(escapeRTF(transcription.modelUsed))\\par\n"
        rtfContent += "\\par\\par\n"

        // Сегменты
        for segment in transcription.segments {
            // Таймкод серым цветом
            rtfContent += "\\cf2\\fs18 [\(formatTimestamp(segment.startTime))] \\cf1\\fs24 "

            // Метка спикера
            if let speaker = segment.speaker {
                rtfContent += "\\b [\(escapeRTF(speaker))] \\b0 "
            }

            // Текст
            rtfContent += "\(escapeRTF(segment.text))\\par\n"
        }

        rtfContent += "}"

        // Сохраняем как RTF (совместим с Word)
        let finalURL = destinationURL.deletingPathExtension().appendingPathExtension("rtf")
        try rtfContent.write(to: finalURL, atomically: true, encoding: .utf8)

        LogManager.export.info("RTF документ создан (совместим с Word): \(finalURL.path)")
        return finalURL
    }

    // MARK: - Helper Methods

    /// Форматирование длительности в читаемый вид
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// Форматирование таймкода в читаемый вид (MM:SS)
    private func formatTimestamp(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Экранирование специальных символов для RTF
    private func escapeRTF(_ string: String) -> String {
        var escaped = string
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "{", with: "\\{")
        escaped = escaped.replacingOccurrences(of: "}", with: "\\}")
        return escaped
    }
}

// MARK: - Errors

enum ExportError: LocalizedError {
    case encodingFailed
    case invalidFormat
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode transcription data"
        case .invalidFormat:
            return "Invalid export format"
        case .writeFailed(let reason):
            return "Failed to write file: \(reason)"
        }
    }
}

import Foundation
import AVFoundation

/// Утилита для создания нормализованных копий аудио файлов
/// Использует ffmpeg для применения нормализации громкости к файлам
public class AudioFileNormalizer {

    /// Создает нормализованную копию аудио файла
    /// - Parameter sourceURL: URL оригинального файла
    /// - Returns: URL нормализованного файла в /tmp/
    public static func createNormalizedCopy(of sourceURL: URL) throws -> URL {
        let fileName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        let normalizedFileName = "\(fileName)_normalized.\(ext)"
        let normalizedURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(normalizedFileName)

        // Если нормализованная версия уже существует, используем её
        if FileManager.default.fileExists(atPath: normalizedURL.path) {
            LogManager.app.info("Нормализованный файл уже существует: \(normalizedFileName)")
            return normalizedURL
        }

        LogManager.app.begin("Нормализация аудио", details: sourceURL.lastPathComponent)

        // Используем ffmpeg для нормализации
        // loudnorm filter применяет EBU R128 нормализацию
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        process.arguments = [
            "-i", sourceURL.path,
            "-af", "loudnorm=I=-16:TP=-1.5:LRA=11",  // EBU R128 нормализация
            "-y",  // Перезаписать если существует
            normalizedURL.path
        ]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            LogManager.app.success("Файл нормализован: \(normalizedFileName)")
            return normalizedURL
        } else {
            // Если ffmpeg недоступен или ошибка, возвращаем оригинал
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            LogManager.app.error("Ошибка нормализации ffmpeg: \(errorOutput)")

            // Fallback: копируем оригинал без нормализации
            LogManager.app.info("Fallback: используем оригинальный файл")
            return sourceURL
        }
    }

    /// Очищает временные нормализованные файлы
    public static func cleanupTempFiles() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let fileManager = FileManager.default

        do {
            let files = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            let normalizedFiles = files.filter { $0.lastPathComponent.contains("_normalized") }

            for file in normalizedFiles {
                try? fileManager.removeItem(at: file)
            }

            LogManager.app.info("Очищено \(normalizedFiles.count) временных файлов")
        } catch {
            LogManager.app.error("Ошибка очистки временных файлов: \(error)")
        }
    }
}

import XCTest
import AVFoundation
@testable import TranscribeItCore

/// Integration тесты для AudioFileNormalizer
///
/// Эти тесты проверяют работу с реальным ffmpeg для нормализации аудио файлов.
/// Требуют установленный ffmpeg в /opt/homebrew/bin/ffmpeg
final class AudioNormalizerTests: XCTestCase {

    // MARK: - Test Lifecycle

    override func setUp() {
        super.setUp()
        // Очищаем временные файлы перед каждым тестом
        AudioFileNormalizer.cleanupTempFiles()
    }

    override func tearDown() {
        // Очищаем временные файлы после каждого теста
        AudioFileNormalizer.cleanupTempFiles()
        super.tearDown()
    }

    // MARK: - Helper Methods

    /// Создает синтетический WAV файл с заданной амплитудой
    /// - Parameters:
    ///   - amplitude: Амплитуда сигнала (0.0 - 1.0)
    ///   - duration: Длительность в секундах
    ///   - frequency: Частота тона в Гц
    /// - Returns: URL временного аудио файла
    private func createTestAudioFile(amplitude: Float = 0.5, duration: TimeInterval = 1.0, frequency: Float = 440.0) throws -> URL {
        let sampleRate: Double = 16000
        let numSamples = Int(sampleRate * duration)

        // Генерируем синусоидальный сигнал
        var samples: [Float] = []
        for i in 0..<numSamples {
            let time = Float(i) / Float(sampleRate)
            let sample = amplitude * sin(2.0 * Float.pi * frequency * time)
            samples.append(sample)
        }

        // Создаем AVAudioPCMBuffer
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples)) else {
            throw NSError(domain: "TestHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer"])
        }
        buffer.frameLength = AVAudioFrameCount(numSamples)

        // Копируем samples в buffer
        let channelData = buffer.floatChannelData![0]
        for i in 0..<numSamples {
            channelData[i] = samples[i]
        }

        // Записываем во временный файл
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test_audio_\(UUID().uuidString).wav")

        let audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        try audioFile.write(from: buffer)

        return tempURL
    }

    /// Считывает peak амплитуду из аудио файла
    /// - Parameter url: URL аудио файла
    /// - Returns: Максимальная абсолютная амплитуда (0.0 - 1.0)
    private func getPeakAmplitude(from url: URL) throws -> Float {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "TestHelper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer for reading"])
        }

        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData else {
            throw NSError(domain: "TestHelper", code: 3, userInfo: [NSLocalizedDescriptionKey: "No channel data"])
        }

        // Находим максимальную амплитуду
        var maxAmplitude: Float = 0.0
        let samples = channelData[0]
        for i in 0..<Int(buffer.frameLength) {
            let absValue = abs(samples[i])
            if absValue > maxAmplitude {
                maxAmplitude = absValue
            }
        }

        return maxAmplitude
    }

    /// Считывает RMS (Root Mean Square) из аудио файла
    /// - Parameter url: URL аудио файла
    /// - Returns: RMS значение
    private func getRMS(from url: URL) throws -> Float {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "TestHelper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer for reading"])
        }

        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData else {
            throw NSError(domain: "TestHelper", code: 3, userInfo: [NSLocalizedDescriptionKey: "No channel data"])
        }

        // Вычисляем RMS
        let samples = channelData[0]
        var sumSquares: Float = 0.0
        for i in 0..<Int(buffer.frameLength) {
            sumSquares += samples[i] * samples[i]
        }

        return sqrt(sumSquares / Float(buffer.frameLength))
    }

    /// Проверяет, установлен ли ffmpeg
    private func isFFmpegAvailable() -> Bool {
        let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
        return FileManager.default.fileExists(atPath: ffmpegPath)
    }

    // MARK: - Tests

    /// Тест: Нормализация тихого аудио увеличивает громкость
    func testNormalizationIncreasesQuietAudio() throws {
        // Пропускаем тест если ffmpeg не установлен
        guard isFFmpegAvailable() else {
            throw XCTSkip("ffmpeg is not installed at /opt/homebrew/bin/ffmpeg")
        }

        // Given: создаем тихий аудио файл (амплитуда 0.1 = -20 dB)
        let quietFile = try createTestAudioFile(amplitude: 0.1, duration: 0.5)
        defer { try? FileManager.default.removeItem(at: quietFile) }

        let originalRMS = try getRMS(from: quietFile)

        // When: нормализуем файл
        let normalizedFile = try AudioFileNormalizer.createNormalizedCopy(of: quietFile)
        defer { try? FileManager.default.removeItem(at: normalizedFile) }

        // Then: громкость должна увеличиться
        let normalizedRMS = try getRMS(from: normalizedFile)

        XCTAssertGreaterThan(normalizedRMS, originalRMS,
                            "Normalized RMS (\(normalizedRMS)) should be greater than original (\(originalRMS))")

        // Проверяем что нормализованный файл не слишком тихий
        // EBU R128 с I=-16 LUFS дает RMS около 0.15-0.20 для нормализованного аудио
        XCTAssertGreaterThan(normalizedRMS, 0.15,
                            "Normalized audio should have reasonable loudness (RMS > 0.15)")
    }

    /// Тест: Нормализация уже нормального аудио не искажает его сильно
    func testNormalizationPreservesNormalAudio() throws {
        guard isFFmpegAvailable() else {
            throw XCTSkip("ffmpeg is not installed at /opt/homebrew/bin/ffmpeg")
        }

        // Given: создаем аудио файл с нормальной громкостью (амплитуда 0.5)
        let normalFile = try createTestAudioFile(amplitude: 0.5, duration: 0.5)
        defer { try? FileManager.default.removeItem(at: normalFile) }

        let originalRMS = try getRMS(from: normalFile)

        // When: нормализуем файл
        let normalizedFile = try AudioFileNormalizer.createNormalizedCopy(of: normalFile)
        defer { try? FileManager.default.removeItem(at: normalizedFile) }

        // Then: RMS не должен измениться слишком сильно (допуск ±60%)
        // EBU R128 может значительно изменить громкость даже для "нормального" аудио,
        // так как целевая громкость -16 LUFS достаточно консервативна
        let normalizedRMS = try getRMS(from: normalizedFile)
        let difference = abs(normalizedRMS - originalRMS) / originalRMS

        XCTAssertLessThan(difference, 0.6,
                         "Normalized RMS should not differ by more than 60% for normal audio")
    }

    /// Тест: Нормализация предотвращает clipping (peak не превышает 1.0)
    func testNormalizationPreventsPeakClipping() throws {
        guard isFFmpegAvailable() else {
            throw XCTSkip("ffmpeg is not installed at /opt/homebrew/bin/ffmpeg")
        }

        // Given: создаем громкий аудио файл (амплитуда 0.9)
        let loudFile = try createTestAudioFile(amplitude: 0.9, duration: 0.5)
        defer { try? FileManager.default.removeItem(at: loudFile) }

        // When: нормализуем файл
        let normalizedFile = try AudioFileNormalizer.createNormalizedCopy(of: loudFile)
        defer { try? FileManager.default.removeItem(at: normalizedFile) }

        // Then: peak должен быть ниже порога clipping
        let peak = try getPeakAmplitude(from: normalizedFile)

        // EBU R128 с TP=-1.5 dBTP ≈ 0.84 в линейной шкале
        XCTAssertLessThanOrEqual(peak, 0.95,
                                "Normalized peak (\(peak)) should not exceed 0.95 to prevent clipping")
    }

    /// Тест: Повторный вызов возвращает кэшированный файл
    func testNormalizationUsesCache() throws {
        guard isFFmpegAvailable() else {
            throw XCTSkip("ffmpeg is not installed at /opt/homebrew/bin/ffmpeg")
        }

        // Given: создаем аудио файл
        let sourceFile = try createTestAudioFile(amplitude: 0.3, duration: 0.5)
        defer { try? FileManager.default.removeItem(at: sourceFile) }

        // When: нормализуем файл первый раз
        let normalizedFile1 = try AudioFileNormalizer.createNormalizedCopy(of: sourceFile)
        let modificationDate1 = try FileManager.default.attributesOfItem(atPath: normalizedFile1.path)[.modificationDate] as! Date

        // Ждем 0.5 секунды
        Thread.sleep(forTimeInterval: 0.5)

        // When: нормализуем файл второй раз
        let normalizedFile2 = try AudioFileNormalizer.createNormalizedCopy(of: sourceFile)
        let modificationDate2 = try FileManager.default.attributesOfItem(atPath: normalizedFile2.path)[.modificationDate] as! Date

        defer { try? FileManager.default.removeItem(at: normalizedFile1) }

        // Then: должен вернуться тот же файл (по дате модификации)
        XCTAssertEqual(normalizedFile1, normalizedFile2, "Should return the same cached file")
        XCTAssertEqual(modificationDate1, modificationDate2, "Cached file should not be regenerated")
    }

    /// Тест: Fallback при отсутствии ffmpeg возвращает оригинальный файл
    func testFallbackReturnsOriginalFileOnError() throws {
        // Given: создаем аудио файл с невалидным путем к ffmpeg
        // Этот тест проверяет логику fallback, но требует модификации класса для инъекции пути к ffmpeg
        // Для текущей реализации мы можем только задокументировать ожидаемое поведение

        // NOTE: Этот тест требует рефакторинга AudioFileNormalizer для инъекции пути к ffmpeg
        // В текущей реализации путь захардкожен в "/opt/homebrew/bin/ffmpeg"
        // Рекомендуется добавить параметр ffmpegPath в метод createNormalizedCopy

        throw XCTSkip("This test requires refactoring AudioFileNormalizer to support custom ffmpeg path")
    }

    /// Тест: cleanupTempFiles удаляет нормализованные файлы
    func testCleanupRemovesNormalizedFiles() throws {
        guard isFFmpegAvailable() else {
            throw XCTSkip("ffmpeg is not installed at /opt/homebrew/bin/ffmpeg")
        }

        // Given: создаем несколько нормализованных файлов
        let sourceFile1 = try createTestAudioFile(amplitude: 0.3, duration: 0.5)
        let sourceFile2 = try createTestAudioFile(amplitude: 0.4, duration: 0.5)
        defer {
            try? FileManager.default.removeItem(at: sourceFile1)
            try? FileManager.default.removeItem(at: sourceFile2)
        }

        let normalizedFile1 = try AudioFileNormalizer.createNormalizedCopy(of: sourceFile1)
        let normalizedFile2 = try AudioFileNormalizer.createNormalizedCopy(of: sourceFile2)

        // Проверяем что файлы существуют
        XCTAssertTrue(FileManager.default.fileExists(atPath: normalizedFile1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: normalizedFile2.path))

        // When: вызываем cleanup
        AudioFileNormalizer.cleanupTempFiles()

        // Then: нормализованные файлы должны быть удалены
        XCTAssertFalse(FileManager.default.fileExists(atPath: normalizedFile1.path),
                      "Normalized file 1 should be removed after cleanup")
        XCTAssertFalse(FileManager.default.fileExists(atPath: normalizedFile2.path),
                      "Normalized file 2 should be removed after cleanup")
    }

    /// Тест: RMS calculation корректно вычисляется для известного сигнала
    func testRMSCalculation() throws {
        // Given: создаем синусоидальный сигнал с известной амплитудой
        let amplitude: Float = 0.7
        let testFile = try createTestAudioFile(amplitude: amplitude, duration: 1.0)
        defer { try? FileManager.default.removeItem(at: testFile) }

        // When: вычисляем RMS
        let rms = try getRMS(from: testFile)

        // Then: RMS синусоиды = amplitude / sqrt(2) ≈ amplitude * 0.707
        let expectedRMS = amplitude / sqrt(2.0)
        let tolerance: Float = 0.01

        XCTAssertEqual(rms, expectedRMS, accuracy: tolerance,
                      "RMS should be amplitude/sqrt(2) for sine wave")
    }

    /// Тест: Peak detection корректно находит максимальную амплитуду
    func testPeakDetection() throws {
        // Given: создаем сигнал с известной амплитудой
        let amplitude: Float = 0.85
        let testFile = try createTestAudioFile(amplitude: amplitude, duration: 0.5)
        defer { try? FileManager.default.removeItem(at: testFile) }

        // When: вычисляем peak
        let peak = try getPeakAmplitude(from: testFile)

        // Then: peak должен быть близок к amplitude (с небольшим допуском на дискретизацию)
        let tolerance: Float = 0.05

        XCTAssertEqual(peak, amplitude, accuracy: tolerance,
                      "Peak amplitude should match the test signal amplitude")
    }

    /// Тест: Нормализация сохраняет формат файла
    func testNormalizationPreservesFileFormat() throws {
        guard isFFmpegAvailable() else {
            throw XCTSkip("ffmpeg is not installed at /opt/homebrew/bin/ffmpeg")
        }

        // Given: создаем WAV файл
        let sourceFile = try createTestAudioFile(amplitude: 0.3, duration: 0.5)
        defer { try? FileManager.default.removeItem(at: sourceFile) }

        XCTAssertEqual(sourceFile.pathExtension, "wav")

        // When: нормализуем файл
        let normalizedFile = try AudioFileNormalizer.createNormalizedCopy(of: sourceFile)
        defer { try? FileManager.default.removeItem(at: normalizedFile) }

        // Then: расширение должно остаться WAV
        XCTAssertEqual(normalizedFile.pathExtension, "wav",
                      "Normalized file should preserve original format")

        // Проверяем что файл читаемый
        let audioFile = try AVAudioFile(forReading: normalizedFile)
        XCTAssertGreaterThan(audioFile.length, 0, "Normalized file should be readable")
    }
}

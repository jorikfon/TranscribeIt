import XCTest
import Accelerate
@testable import TranscribeItCore

/// Unit тесты для SpectralVAD
///
/// Покрытие:
/// - Обнаружение речевых сегментов в тишине
/// - Фильтрация шума (нерелевантных частот)
/// - Обработка edge cases (начало/конец файла, пустые файлы)
/// - Минимальная длина сегмента
/// - Обработка очень тихого аудио
/// - Различные preset параметры (default, telephone, wideband)
final class SpectralVADTests: XCTestCase {

    // MARK: - Test Helper Methods

    /// Генерирует синусоидальный сигнал заданной частоты
    /// - Parameters:
    ///   - frequency: Частота в Hz
    ///   - duration: Длительность в секундах
    ///   - sampleRate: Частота дискретизации (по умолчанию 16000 Hz)
    ///   - amplitude: Амплитуда сигнала (0.0-1.0)
    /// - Returns: Массив аудио сэмплов
    private func generateSineWave(
        frequency: Float,
        duration: TimeInterval,
        sampleRate: Double = 16000.0,
        amplitude: Float = 0.5
    ) -> [Float] {
        let sampleCount = Int(duration * sampleRate)
        var samples = [Float](repeating: 0, count: sampleCount)

        for i in 0..<sampleCount {
            let t = Float(i) / Float(sampleRate)
            samples[i] = amplitude * sin(2.0 * Float.pi * frequency * t)
        }

        return samples
    }

    /// Генерирует тишину (массив нулей)
    private func generateSilence(duration: TimeInterval, sampleRate: Double = 16000.0) -> [Float] {
        let sampleCount = Int(duration * sampleRate)
        return [Float](repeating: 0, count: sampleCount)
    }

    /// Генерирует белый шум
    private func generateWhiteNoise(
        duration: TimeInterval,
        sampleRate: Double = 16000.0,
        amplitude: Float = 0.1
    ) -> [Float] {
        let sampleCount = Int(duration * sampleRate)
        var samples = [Float](repeating: 0, count: sampleCount)

        for i in 0..<sampleCount {
            samples[i] = Float.random(in: -amplitude...amplitude)
        }

        return samples
    }

    /// Генерирует сложный речевой сигнал (микс нескольких частот в речевом диапазоне)
    private func generateSpeechLikeSignal(
        duration: TimeInterval,
        sampleRate: Double = 16000.0,
        amplitude: Float = 0.5
    ) -> [Float] {
        // Речь обычно содержит гармоники в диапазоне 80-8000 Hz
        // Основной тон обычно 100-300 Hz, формантные частоты выше
        let fundamentalFreq: Float = 150  // Основной тон
        let formant1: Float = 800          // Первая форманта
        let formant2: Float = 1500         // Вторая форманта
        let formant3: Float = 2500         // Третья форманта

        let fundamental = generateSineWave(frequency: fundamentalFreq, duration: duration, sampleRate: sampleRate, amplitude: amplitude * 0.5)
        let f1 = generateSineWave(frequency: formant1, duration: duration, sampleRate: sampleRate, amplitude: amplitude * 0.3)
        let f2 = generateSineWave(frequency: formant2, duration: duration, sampleRate: sampleRate, amplitude: amplitude * 0.2)
        let f3 = generateSineWave(frequency: formant3, duration: duration, sampleRate: sampleRate, amplitude: amplitude * 0.1)

        // Суммируем все компоненты
        var result = [Float](repeating: 0, count: fundamental.count)
        for i in 0..<fundamental.count {
            result[i] = fundamental[i] + f1[i] + f2[i] + f3[i]
        }

        return result
    }

    /// Конкатенирует несколько аудио массивов
    private func concatenate(_ arrays: [[Float]]) -> [Float] {
        return arrays.flatMap { $0 }
    }

    // MARK: - Basic Functionality Tests

    /// Тест: Обнаружение речевого сегмента в тишине
    func testDetectSpeechInSilence() {
        // Given: тишина + речь + тишина
        let silence1 = generateSilence(duration: 0.5)
        let speech = generateSpeechLikeSignal(duration: 1.0)
        let silence2 = generateSilence(duration: 0.5)
        let audio = concatenate([silence1, speech, silence2])

        let vad = SpectralVAD(parameters: .default)

        // When
        let segments = vad.detectSpeechSegments(in: audio)

        // Then
        XCTAssertGreaterThan(segments.count, 0, "Should detect at least one speech segment")

        if let segment = segments.first {
            // Речь должна начинаться примерно в 0.5 секунды
            XCTAssertGreaterThan(segment.startTime, 0.4, "Speech should start after initial silence")
            XCTAssertLessThan(segment.startTime, 0.7, "Speech start detection should be reasonably accurate")

            // Длительность сегмента должна быть близка к 1.0 секунде
            XCTAssertGreaterThan(segment.duration, 0.8, "Speech duration should be close to 1.0 second")
            XCTAssertLessThan(segment.duration, 1.2, "Speech duration should not be over-detected")
        }
    }

    /// Тест: Множественные сегменты речи
    func testDetectMultipleSpeechSegments() {
        // Given: речь + тишина + речь + тишина + речь
        let speech1 = generateSpeechLikeSignal(duration: 0.8)
        let silence1 = generateSilence(duration: 0.4)
        let speech2 = generateSpeechLikeSignal(duration: 0.6)
        let silence2 = generateSilence(duration: 0.4)
        let speech3 = generateSpeechLikeSignal(duration: 0.7)

        let audio = concatenate([speech1, silence1, speech2, silence2, speech3])

        let vad = SpectralVAD(parameters: .default)

        // When
        let segments = vad.detectSpeechSegments(in: audio)

        // Then
        XCTAssertEqual(segments.count, 3, "Should detect three separate speech segments")

        // Проверяем, что сегменты не перекрываются
        for i in 0..<segments.count - 1 {
            XCTAssertLessThan(segments[i].endTime, segments[i + 1].startTime,
                            "Segments should not overlap")
        }
    }

    /// Тест: Отсутствие детекции в чистой тишине
    func testNoDetectionInSilence() {
        // Given: только тишина
        let audio = generateSilence(duration: 2.0)

        let vad = SpectralVAD(parameters: .default)

        // When
        let segments = vad.detectSpeechSegments(in: audio)

        // Then
        XCTAssertEqual(segments.count, 0, "Should not detect speech in pure silence")
    }

    /// Тест: Фильтрация низкочастотного шума
    func testFilterLowFrequencyNoise() {
        // Given: тишина + низкочастотный сигнал (50 Hz, ниже речевого диапазона) + тишина
        let silence1 = generateSilence(duration: 0.3)
        let lowFreqNoise = generateSineWave(frequency: 50, duration: 1.0, amplitude: 0.5)
        let silence2 = generateSilence(duration: 0.3)
        let audio = concatenate([silence1, lowFreqNoise, silence2])

        let vad = SpectralVAD(parameters: .default)

        // When
        let segments = vad.detectSpeechSegments(in: audio)

        // Then
        // Низкочастотный шум (50 Hz) ниже минимальной частоты речи (300 Hz)
        // Поэтому VAD не должен детектировать это как речь
        XCTAssertEqual(segments.count, 0, "Should not detect low-frequency noise as speech")
    }

    /// Тест: Фильтрация высокочастотного шума
    func testFilterHighFrequencyNoise() {
        // Given: высокочастотный сигнал (5000 Hz, выше речевого диапазона)
        let highFreqNoise = generateSineWave(frequency: 5000, duration: 1.0, amplitude: 0.5)

        let vad = SpectralVAD(parameters: .default)

        // When
        let segments = vad.detectSpeechSegments(in: highFreqNoise)

        // Then
        // 5000 Hz выше максимальной частоты речи (3400 Hz) для default параметров
        XCTAssertEqual(segments.count, 0, "Should not detect high-frequency noise as speech")
    }

    /// Тест: Детекция сигнала в речевом диапазоне
    func testDetectSignalInSpeechRange() {
        // Given: сигнал в середине речевого диапазона (1000 Hz)
        let speechFreqSignal = generateSineWave(frequency: 1000, duration: 1.0, amplitude: 0.5)

        let vad = SpectralVAD(parameters: .default)

        // When
        let segments = vad.detectSpeechSegments(in: speechFreqSignal)

        // Then
        XCTAssertGreaterThan(segments.count, 0, "Should detect signal in speech frequency range")
    }

    // MARK: - Parameter Tests

    /// Тест: Минимальная длина сегмента
    func testMinimumSpeechDuration() {
        // Given: очень короткий речевой импульс (0.1 секунды)
        let shortSpeech = generateSpeechLikeSignal(duration: 0.1)
        let silence = generateSilence(duration: 0.5)
        let audio = concatenate([silence, shortSpeech, silence])

        // Параметры с minSpeechDuration = 0.5 секунды
        let params = SpectralVAD.Parameters(
            minSpeechDuration: 0.5,
            minSilenceDuration: 0.3,
            speechEnergyRatio: 0.3
        )
        let vad = SpectralVAD(parameters: params)

        // When
        let segments = vad.detectSpeechSegments(in: audio)

        // Then
        // Сегмент 0.1 секунды должен быть отфильтрован (< 0.5 минимума)
        XCTAssertEqual(segments.count, 0, "Should filter out speech segments shorter than minimum duration")
    }

    /// Тест: Минимальная тишина для разделения сегментов
    func testMinimumSilenceDuration() {
        // Given: речь + короткая пауза (0.1 сек) + речь
        let speech1 = generateSpeechLikeSignal(duration: 0.6)
        let shortSilence = generateSilence(duration: 0.1)
        let speech2 = generateSpeechLikeSignal(duration: 0.6)
        let audio = concatenate([speech1, shortSilence, speech2])

        // Параметры с minSilenceDuration = 0.3 секунды
        let params = SpectralVAD.Parameters(
            minSpeechDuration: 0.3,
            minSilenceDuration: 0.3,
            speechEnergyRatio: 0.3
        )
        let vad = SpectralVAD(parameters: params)

        // When
        let segments = vad.detectSpeechSegments(in: audio)

        // Then
        // Короткая пауза (0.1 сек) недостаточна для разделения (< 0.3 минимума)
        // Должен быть один объединенный сегмент
        XCTAssertEqual(segments.count, 1, "Should merge segments with short silence between them")
    }

    // MARK: - Preset Tests

    /// Тест: Telephone параметры (узкополосное аудио 300-3400 Hz)
    func testTelephonePreset() {
        // Given: сигнал в телефонном диапазоне (800 Hz)
        let telephoneSpeech = generateSineWave(frequency: 800, duration: 1.0, amplitude: 0.5)

        let vad = SpectralVAD(parameters: .telephone)

        // When
        let segments = vad.detectSpeechSegments(in: telephoneSpeech)

        // Then
        XCTAssertGreaterThan(segments.count, 0, "Telephone preset should detect speech in 300-3400 Hz range")
    }

    /// Тест: Wideband параметры (широкополосное аудио 80-8000 Hz)
    func testWidebandPreset() {
        // Given: низкочастотный сигнал (100 Hz), который телефонный VAD не детектирует
        let lowFreqSpeech = generateSineWave(frequency: 100, duration: 1.0, amplitude: 0.5)

        let telephoneVAD = SpectralVAD(parameters: .telephone)
        let widebandVAD = SpectralVAD(parameters: .wideband)

        // When
        let telephoneSegments = telephoneVAD.detectSpeechSegments(in: lowFreqSpeech)
        let widebandSegments = widebandVAD.detectSpeechSegments(in: lowFreqSpeech)

        // Then
        XCTAssertEqual(telephoneSegments.count, 0, "Telephone preset should not detect 100 Hz (< 300 Hz)")
        XCTAssertGreaterThan(widebandSegments.count, 0, "Wideband preset should detect 100 Hz (>= 80 Hz)")
    }

    // MARK: - Edge Cases

    /// Тест: Пустой массив аудио
    func testEmptyAudioArray() {
        // Given
        let emptyAudio: [Float] = []
        let vad = SpectralVAD(parameters: .default)

        // When
        let segments = vad.detectSpeechSegments(in: emptyAudio)

        // Then
        XCTAssertEqual(segments.count, 0, "Should handle empty audio array gracefully")
    }

    /// Тест: Очень короткий аудио файл (меньше FFT окна)
    func testVeryShortAudio() {
        // Given: только 100 сэмплов (меньше чем fftSize = 512)
        let shortAudio = generateSpeechLikeSignal(duration: 0.006)  // ~100 samples at 16kHz

        let vad = SpectralVAD(parameters: .default)

        // When
        let segments = vad.detectSpeechSegments(in: shortAudio)

        // Then
        XCTAssertEqual(segments.count, 0, "Should handle audio shorter than FFT window")
    }

    /// Тест: Речь в начале файла
    func testSpeechAtFileStart() {
        // Given: речь сразу с начала файла
        let speech = generateSpeechLikeSignal(duration: 1.0)
        let silence = generateSilence(duration: 0.5)
        let audio = concatenate([speech, silence])

        let vad = SpectralVAD(parameters: .default)

        // When
        let segments = vad.detectSpeechSegments(in: audio)

        // Then
        XCTAssertGreaterThan(segments.count, 0, "Should detect speech at file start")
        if let segment = segments.first {
            XCTAssertLessThan(segment.startTime, 0.2, "Speech at start should be detected early")
        }
    }

    /// Тест: Речь в конце файла
    func testSpeechAtFileEnd() {
        // Given: тишина + речь в конце
        let silence = generateSilence(duration: 0.5)
        let speech = generateSpeechLikeSignal(duration: 1.0)
        let audio = concatenate([silence, speech])

        let vad = SpectralVAD(parameters: .default)

        // When
        let segments = vad.detectSpeechSegments(in: audio)

        // Then
        XCTAssertGreaterThan(segments.count, 0, "Should detect speech at file end")
        if let segment = segments.first {
            // Речь должна продолжаться до конца файла
            let totalDuration = Double(audio.count) / 16000.0
            XCTAssertGreaterThan(segment.endTime, totalDuration - 0.2, "Speech should extend to near file end")
        }
    }

    /// Тест: Очень тихое аудио
    func testVeryQuietAudio() {
        // Given: очень тихий речевой сигнал (amplitude = 0.01)
        let quietSpeech = generateSpeechLikeSignal(duration: 1.0, amplitude: 0.01)

        let vad = SpectralVAD(parameters: .default)

        // When
        let segments = vad.detectSpeechSegments(in: quietSpeech)

        // Then
        // Адаптивный порог должен справиться с тихим аудио
        // Но возможно детекция будет менее надежной
        // Просто проверяем, что не падает
        XCTAssertGreaterThanOrEqual(segments.count, 0, "Should handle very quiet audio without crashing")
    }

    /// Тест: Очень громкое аудио
    func testVeryLoudAudio() {
        // Given: очень громкий речевой сигнал (amplitude = 1.0)
        let loudSpeech = generateSpeechLikeSignal(duration: 1.0, amplitude: 1.0)

        let vad = SpectralVAD(parameters: .default)

        // When
        let segments = vad.detectSpeechSegments(in: loudSpeech)

        // Then
        XCTAssertGreaterThan(segments.count, 0, "Should detect very loud speech")
    }

    // MARK: - Audio Extraction Tests

    /// Тест: Извлечение аудио для сегмента
    func testExtractAudioForSegment() {
        // Given
        let audio = generateSpeechLikeSignal(duration: 2.0)
        let segment = SpeechSegment(startTime: 0.5, endTime: 1.5)

        let vad = SpectralVAD(parameters: .default)

        // When
        let extracted = vad.extractAudio(for: segment, from: audio)

        // Then
        let expectedSampleCount = Int((1.5 - 0.5) * 16000)  // 1 секунда * 16000 Hz
        XCTAssertEqual(extracted.count, expectedSampleCount, accuracy: 10, "Extracted audio should have correct length")
        XCTAssertFalse(extracted.isEmpty, "Extracted audio should not be empty")
    }

    /// Тест: Извлечение аудио для сегмента за границами
    func testExtractAudioBeyondBounds() {
        // Given
        let audio = generateSpeechLikeSignal(duration: 1.0)
        let segment = SpeechSegment(startTime: 0.5, endTime: 5.0)  // endTime за границами

        let vad = SpectralVAD(parameters: .default)

        // When
        let extracted = vad.extractAudio(for: segment, from: audio)

        // Then
        // Должно извлечь только до конца файла
        XCTAssertGreaterThan(extracted.count, 0, "Should extract available audio")
        XCTAssertLessThanOrEqual(extracted.count, audio.count, "Should not exceed audio length")
    }

    /// Тест: Извлечение аудио для невалидного сегмента
    func testExtractAudioForInvalidSegment() {
        // Given
        let audio = generateSpeechLikeSignal(duration: 1.0)
        let segment = SpeechSegment(startTime: 5.0, endTime: 6.0)  // Полностью за границами

        let vad = SpectralVAD(parameters: .default)

        // When
        let extracted = vad.extractAudio(for: segment, from: audio)

        // Then
        XCTAssertEqual(extracted.count, 0, "Should return empty array for invalid segment")
    }

    // MARK: - Integration Tests

    /// Тест: Реалистичный сценарий - микс речи и шума
    func testRealisticSpeechWithNoise() {
        // Given: речь с фоновым шумом
        let speech1 = generateSpeechLikeSignal(duration: 1.0, amplitude: 0.5)
        let noise1 = generateWhiteNoise(duration: 1.0, amplitude: 0.1)

        // Смешиваем речь и шум
        var mixedAudio = [Float](repeating: 0, count: speech1.count)
        for i in 0..<speech1.count {
            mixedAudio[i] = speech1[i] + noise1[i]
        }

        let vad = SpectralVAD(parameters: .default)

        // When
        let segments = vad.detectSpeechSegments(in: mixedAudio)

        // Then
        XCTAssertGreaterThan(segments.count, 0, "Should detect speech even with background noise")
        if let segment = segments.first {
            XCTAssertGreaterThan(segment.duration, 0.5, "Detected speech should have reasonable duration")
        }
    }
}

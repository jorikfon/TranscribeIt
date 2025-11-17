import XCTest
import AVFoundation
@testable import TranscribeItCore

/// Integration тесты для VAD алгоритмов с реальными аудио файлами
///
/// Использует реальные телефонные записи из Tests/Fixtures/audio/
/// Проверяет работу SpectralVAD и AdaptiveVAD на реальных данных
final class VADIntegrationTests: XCTestCase {

    // MARK: - Helper Methods

    /// Загружает аудио файл и конвертирует в Float32 массив для VAD
    /// - Parameter fileName: Имя файла в Tests/Fixtures/audio/
    /// - Returns: Массив Float32 сэмплов и длительность
    private func loadAudioFile(_ fileName: String) async throws -> (samples: [Float], duration: TimeInterval) {
        // Получаем путь к fixture файлу
        let testBundle = Bundle.module
        guard let fileURL = testBundle.url(forResource: fileName, withExtension: nil, subdirectory: "Fixtures/audio") else {
            // Fallback: пробуем прямой путь
            let directPath = "/Users/nb/Developement/TranscribeIt/Tests/Fixtures/audio/\(fileName)"
            guard FileManager.default.fileExists(atPath: directPath) else {
                XCTFail("Test audio file not found: \(fileName)")
                throw NSError(domain: "VADIntegrationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "File not found: \(fileName)"])
            }
            return try await loadAudioFromPath(directPath)
        }

        return try await loadAudioFromURL(fileURL)
    }

    private func loadAudioFromPath(_ path: String) async throws -> (samples: [Float], duration: TimeInterval) {
        return try await loadAudioFromURL(URL(fileURLWithPath: path))
    }

    private func loadAudioFromURL(_ url: URL) async throws -> (samples: [Float], duration: TimeInterval) {
        let asset = AVAsset(url: url)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(domain: "VADIntegrationTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "No audio track found"])
        }

        let reader = try AVAssetReader(asset: asset)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(readerOutput)

        guard reader.startReading() else {
            throw NSError(domain: "VADIntegrationTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to start reading"])
        }

        var samples: [Float] = []

        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)

            data.withUnsafeMutableBytes { buffer in
                _ = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: buffer.baseAddress!)
            }

            let floatSamples = data.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }

            samples.append(contentsOf: floatSamples)
        }

        let duration = TimeInterval(samples.count) / 16000.0

        return (samples, duration)
    }

    // MARK: - SpectralVAD Integration Tests

    /// Тест: SpectralVAD детектирует речь в коротком звонке
    func testSpectralVAD_ShortCall() async throws {
        // Given
        let (samples, duration) = try await loadAudioFile("short_call.mp3")
        let vad = SpectralVAD(parameters: .telephone)  // Используем telephone preset для телефонных записей

        // When
        let segments = vad.detectSpeechSegments(in: samples)

        // Then
        XCTAssertGreaterThan(segments.count, 0, "Should detect speech segments in short call")
        XCTAssertLessThan(segments.count, 50, "Should not over-segment (< 50 segments)")

        // Проверяем, что сегменты покрывают разумную часть аудио
        let totalSpeechDuration = segments.reduce(0.0) { $0 + $1.duration }
        XCTAssertGreaterThan(totalSpeechDuration, duration * 0.2, "Speech should cover at least 20% of audio")
        XCTAssertLessThan(totalSpeechDuration, duration, "Total speech duration should not exceed audio duration")

        print("SpectralVAD - Short call: \(segments.count) segments, \(String(format: "%.1f", totalSpeechDuration))s speech / \(String(format: "%.1f", duration))s total")
    }

    /// Тест: SpectralVAD детектирует речь в среднем звонке
    func testSpectralVAD_MediumCall() async throws {
        // Given
        let (samples, duration) = try await loadAudioFile("medium_call.mp3")
        let vad = SpectralVAD(parameters: .telephone)

        // When
        let segments = vad.detectSpeechSegments(in: samples)

        // Then
        XCTAssertGreaterThan(segments.count, 0, "Should detect speech segments in medium call")

        let totalSpeechDuration = segments.reduce(0.0) { $0 + $1.duration }
        XCTAssertGreaterThan(totalSpeechDuration, 5.0, "Medium call should have at least 5 seconds of speech")

        print("SpectralVAD - Medium call: \(segments.count) segments, \(String(format: "%.1f", totalSpeechDuration))s speech / \(String(format: "%.1f", duration))s total")
    }

    /// Тест: SpectralVAD детектирует речь в длинном звонке
    func testSpectralVAD_LongCall() async throws {
        // Given
        let (samples, duration) = try await loadAudioFile("long_call.mp3")
        let vad = SpectralVAD(parameters: .telephone)

        // When
        let segments = vad.detectSpeechSegments(in: samples)

        // Then
        XCTAssertGreaterThan(segments.count, 0, "Should detect speech segments in long call")

        let totalSpeechDuration = segments.reduce(0.0) { $0 + $1.duration }
        XCTAssertGreaterThan(totalSpeechDuration, 10.0, "Long call should have at least 10 seconds of speech")

        print("SpectralVAD - Long call: \(segments.count) segments, \(String(format: "%.1f", totalSpeechDuration))s speech / \(String(format: "%.1f", duration))s total")
    }

    // MARK: - AdaptiveVAD Integration Tests

    /// Тест: AdaptiveVAD детектирует речь в коротком звонке
    func testAdaptiveVAD_ShortCall() async throws {
        // Given
        let (samples, duration) = try await loadAudioFile("short_call.mp3")
        let vad = AdaptiveVAD(parameters: .lowQuality)  // lowQuality preset для телефонных записей

        // When
        let segments = vad.detectSpeechSegments(in: samples)

        // Then
        XCTAssertGreaterThan(segments.count, 0, "Should detect speech segments in short call")
        XCTAssertLessThan(segments.count, 50, "Should not over-segment (< 50 segments)")

        let totalSpeechDuration = segments.reduce(0.0) { $0 + $1.duration }
        XCTAssertGreaterThan(totalSpeechDuration, duration * 0.1, "Speech should cover at least 10% of audio")

        print("AdaptiveVAD - Short call: \(segments.count) segments, \(String(format: "%.1f", totalSpeechDuration))s speech / \(String(format: "%.1f", duration))s total")
    }

    /// Тест: AdaptiveVAD детектирует речь в среднем звонке
    func testAdaptiveVAD_MediumCall() async throws {
        // Given
        let (samples, duration) = try await loadAudioFile("medium_call.mp3")
        let vad = AdaptiveVAD(parameters: .lowQuality)

        // When
        let segments = vad.detectSpeechSegments(in: samples)

        // Then
        XCTAssertGreaterThan(segments.count, 0, "Should detect speech segments in medium call")

        let totalSpeechDuration = segments.reduce(0.0) { $0 + $1.duration }
        XCTAssertGreaterThan(totalSpeechDuration, 5.0, "Medium call should have at least 5 seconds of speech")

        print("AdaptiveVAD - Medium call: \(segments.count) segments, \(String(format: "%.1f", totalSpeechDuration))s speech / \(String(format: "%.1f", duration))s total")
    }

    /// Тест: AdaptiveVAD детектирует речь в длинном звонке
    func testAdaptiveVAD_LongCall() async throws {
        // Given
        let (samples, duration) = try await loadAudioFile("long_call.mp3")
        let vad = AdaptiveVAD(parameters: .lowQuality)

        // When
        let segments = vad.detectSpeechSegments(in: samples)

        // Then
        XCTAssertGreaterThan(segments.count, 0, "Should detect speech segments in long call")

        let totalSpeechDuration = segments.reduce(0.0) { $0 + $1.duration }
        XCTAssertGreaterThan(totalSpeechDuration, 10.0, "Long call should have at least 10 seconds of speech")

        print("AdaptiveVAD - Long call: \(segments.count) segments, \(String(format: "%.1f", totalSpeechDuration))s speech / \(String(format: "%.1f", duration))s total")
    }

    // MARK: - Comparison Tests

    /// Тест: Сравнение SpectralVAD и AdaptiveVAD на одном файле
    func testCompareVADAlgorithms() async throws {
        // Given
        let (samples, duration) = try await loadAudioFile("medium_call.mp3")

        let spectralVAD = SpectralVAD(parameters: .telephone)
        let adaptiveVAD = AdaptiveVAD(parameters: .lowQuality)

        // When
        let spectralSegments = spectralVAD.detectSpeechSegments(in: samples)
        let adaptiveSegments = adaptiveVAD.detectSpeechSegments(in: samples)

        // Then
        XCTAssertGreaterThan(spectralSegments.count, 0, "SpectralVAD should detect segments")
        XCTAssertGreaterThan(adaptiveSegments.count, 0, "AdaptiveVAD should detect segments")

        let spectralDuration = spectralSegments.reduce(0.0) { $0 + $1.duration }
        let adaptiveDuration = adaptiveSegments.reduce(0.0) { $0 + $1.duration }

        print("VAD Comparison:")
        print("  SpectralVAD: \(spectralSegments.count) segments, \(String(format: "%.1f", spectralDuration))s speech")
        print("  AdaptiveVAD: \(adaptiveSegments.count) segments, \(String(format: "%.1f", adaptiveDuration))s speech")
        print("  Total duration: \(String(format: "%.1f", duration))s")

        // Оба алгоритма должны детектировать разумное количество речи
        XCTAssertGreaterThan(spectralDuration, duration * 0.1, "SpectralVAD should detect at least 10% of audio")
        XCTAssertGreaterThan(adaptiveDuration, duration * 0.1, "AdaptiveVAD should detect at least 10% of audio")
    }

    // MARK: - Edge Case Tests

    /// Тест: Сегменты не перекрываются
    func testSegmentsDoNotOverlap() async throws {
        // Given
        let (samples, _) = try await loadAudioFile("short_call.mp3")
        let vad = SpectralVAD(parameters: .telephone)

        // When
        let segments = vad.detectSpeechSegments(in: samples)

        // Then
        for i in 0..<segments.count - 1 {
            XCTAssertLessThanOrEqual(segments[i].endTime, segments[i + 1].startTime,
                                    "Segment \(i) should not overlap with segment \(i+1)")
        }
    }

    /// Тест: Все сегменты имеют валидную длительность
    func testSegmentsHaveValidDuration() async throws {
        // Given
        let (samples, duration) = try await loadAudioFile("medium_call.mp3")
        let vad = AdaptiveVAD(parameters: .lowQuality)

        // When
        let segments = vad.detectSpeechSegments(in: samples)

        // Then
        for (index, segment) in segments.enumerated() {
            XCTAssertGreaterThan(segment.duration, 0, "Segment \(index) should have positive duration")
            XCTAssertGreaterThanOrEqual(segment.startTime, 0, "Segment \(index) should start at or after 0")
            XCTAssertLessThanOrEqual(segment.endTime, duration, "Segment \(index) should end before audio ends")
        }
    }

    /// Тест: Извлечение аудио для детектированных сегментов
    func testExtractAudioForDetectedSegments() async throws {
        // Given
        let (samples, _) = try await loadAudioFile("short_call.mp3")
        let vad = SpectralVAD(parameters: .telephone)

        // When
        let segments = vad.detectSpeechSegments(in: samples)

        guard let firstSegment = segments.first else {
            XCTFail("Should detect at least one segment")
            return
        }

        // Then
        let extractedAudio = vad.extractAudio(for: firstSegment, from: samples)

        XCTAssertGreaterThan(extractedAudio.count, 0, "Should extract non-empty audio")

        let expectedSamples = Int(firstSegment.duration * 16000)
        XCTAssertEqual(extractedAudio.count, expectedSamples, accuracy: 100,
                      "Extracted audio should match segment duration")
    }

    // MARK: - Performance Tests

    /// Тест: Производительность SpectralVAD на реальном аудио
    func testSpectralVAD_Performance() async throws {
        // Given
        let (samples, _) = try await loadAudioFile("long_call.mp3")
        let vad = SpectralVAD(parameters: .telephone)

        // When
        measure {
            _ = vad.detectSpeechSegments(in: samples)
        }

        // Then - no assertions, just performance measurement
    }

    /// Тест: Производительность AdaptiveVAD на реальном аудио
    func testAdaptiveVAD_Performance() async throws {
        // Given
        let (samples, _) = try await loadAudioFile("long_call.mp3")
        let vad = AdaptiveVAD(parameters: .lowQuality)

        // When
        measure {
            _ = vad.detectSpeechSegments(in: samples)
        }

        // Then - no assertions, just performance measurement
    }

    // MARK: - Post-VAD Segment Merging Tests

    /// Тест: Слияние соседних сегментов одного спикера с коротким промежутком
    func testMergeAdjacentSegmentsSameSpeaker() {
        // Given: Два сегмента одного спикера с промежутком 1.0с (< threshold 1.5с)
        let segment1 = MockChannelSegment(
            startTime: 0.0, endTime: 2.0, channel: 0, speaker: .left,
            audioSamples: [Float](repeating: 0.5, count: 32000)
        )
        let segment2 = MockChannelSegment(
            startTime: 3.0, endTime: 5.0, channel: 0, speaker: .left,
            audioSamples: [Float](repeating: 0.5, count: 32000)
        )
        let segments = [segment1, segment2]
        let threshold: TimeInterval = 1.5

        // When: Применяем слияние
        let merged = mergeAdjacentSegments(segments, maxGap: threshold)

        // Then: Сегменты должны быть объединены
        XCTAssertEqual(merged.count, 1, "Два соседних сегмента одного спикера с промежутком < 1.5с должны объединиться")
        XCTAssertEqual(merged[0].segment.startTime, 0.0, "Начало должно быть от первого сегмента")
        XCTAssertEqual(merged[0].segment.endTime, 5.0, "Конец должен быть от второго сегмента")
    }

    /// Тест: Не сливать сегменты разных спикеров
    func testDoNotMergeDifferentSpeakers() {
        // Given: Два сегмента разных спикеров с промежутком 1.0с
        let segment1 = MockChannelSegment(
            startTime: 0.0, endTime: 2.0, channel: 0, speaker: .left,
            audioSamples: [Float](repeating: 0.5, count: 32000)
        )
        let segment2 = MockChannelSegment(
            startTime: 3.0, endTime: 5.0, channel: 1, speaker: .right,
            audioSamples: [Float](repeating: 0.5, count: 32000)
        )
        let segments = [segment1, segment2]
        let threshold: TimeInterval = 1.5

        // When: Применяем слияние
        let merged = mergeAdjacentSegments(segments, maxGap: threshold)

        // Then: Сегменты НЕ должны быть объединены (разные спикеры)
        XCTAssertEqual(merged.count, 2, "Сегменты разных спикеров не должны сливаться")
    }

    /// Тест: Не сливать сегменты с большим промежутком
    func testDoNotMergeLargeGap() {
        // Given: Два сегмента одного спикера с промежутком 2.0с (> threshold 1.5с)
        let segment1 = MockChannelSegment(
            startTime: 0.0, endTime: 2.0, channel: 0, speaker: .left,
            audioSamples: [Float](repeating: 0.5, count: 32000)
        )
        let segment2 = MockChannelSegment(
            startTime: 4.0, endTime: 6.0, channel: 0, speaker: .left,
            audioSamples: [Float](repeating: 0.5, count: 32000)
        )
        let segments = [segment1, segment2]
        let threshold: TimeInterval = 1.5

        // When: Применяем слияние
        let merged = mergeAdjacentSegments(segments, maxGap: threshold)

        // Then: Сегменты НЕ должны быть объединены (промежуток > threshold)
        XCTAssertEqual(merged.count, 2, "Сегменты с промежутком > threshold не должны сливаться")
    }

    /// Тест: Edge case - один сегмент
    func testMergeSingleSegment() {
        // Given: Только один сегмент
        let segment = MockChannelSegment(
            startTime: 0.0, endTime: 2.0, channel: 0, speaker: .left,
            audioSamples: [Float](repeating: 0.5, count: 32000)
        )
        let segments = [segment]
        let threshold: TimeInterval = 1.5

        // When: Применяем слияние
        let merged = mergeAdjacentSegments(segments, maxGap: threshold)

        // Then: Возвращается тот же сегмент
        XCTAssertEqual(merged.count, 1, "Один сегмент должен остаться без изменений")
    }

    /// Тест: Edge case - пустой массив
    func testMergeEmptySegments() {
        // Given: Пустой массив сегментов
        let segments: [MockChannelSegment] = []
        let threshold: TimeInterval = 1.5

        // When: Применяем слияние
        let merged = mergeAdjacentSegments(segments, maxGap: threshold)

        // Then: Возвращается пустой массив
        XCTAssertEqual(merged.count, 0, "Пустой массив должен остаться пустым")
    }

    /// Тест: Множественное слияние (3 сегмента подряд)
    func testMergeMultipleConsecutiveSegments() {
        // Given: Три сегмента одного спикера с промежутками < threshold
        let segment1 = MockChannelSegment(
            startTime: 0.0, endTime: 1.0, channel: 0, speaker: .left,
            audioSamples: [Float](repeating: 0.5, count: 16000)
        )
        let segment2 = MockChannelSegment(
            startTime: 2.0, endTime: 3.0, channel: 0, speaker: .left,
            audioSamples: [Float](repeating: 0.5, count: 16000)
        )
        let segment3 = MockChannelSegment(
            startTime: 4.0, endTime: 5.0, channel: 0, speaker: .left,
            audioSamples: [Float](repeating: 0.5, count: 16000)
        )
        let segments = [segment1, segment2, segment3]
        let threshold: TimeInterval = 1.5

        // When: Применяем слияние
        let merged = mergeAdjacentSegments(segments, maxGap: threshold)

        // Then: Все три сегмента должны объединиться в один
        XCTAssertEqual(merged.count, 1, "Три подряд идущих сегмента должны объединиться в один")
        XCTAssertEqual(merged[0].segment.startTime, 0.0)
        XCTAssertEqual(merged[0].segment.endTime, 5.0)
    }

    // MARK: - Helper Mock & Function

    /// Mock структура для тестирования слияния сегментов
    private struct MockChannelSegment {
        let segment: SpeechSegment
        let channel: Int
        let speaker: DialogueTranscription.Turn.Speaker
        let audioSamples: [Float]

        init(startTime: TimeInterval, endTime: TimeInterval, channel: Int, speaker: DialogueTranscription.Turn.Speaker, audioSamples: [Float]) {
            self.segment = SpeechSegment(startTime: startTime, endTime: endTime)
            self.channel = channel
            self.speaker = speaker
            self.audioSamples = audioSamples
        }
    }

    /// Helper функция для слияния сегментов (будет реализована в FileTranscriptionService)
    private func mergeAdjacentSegments(_ segments: [MockChannelSegment], maxGap: TimeInterval) -> [MockChannelSegment] {
        guard segments.count > 1 else { return segments }

        var merged: [MockChannelSegment] = []
        var currentSegment = segments[0]

        for i in 1..<segments.count {
            let nextSegment = segments[i]

            // Проверка: тот же спикер и промежуток < maxGap
            let gap = nextSegment.segment.startTime - currentSegment.segment.endTime
            if currentSegment.speaker == nextSegment.speaker && gap < maxGap {
                // Слияние: объединяем аудио и расширяем временные рамки
                let mergedAudio = currentSegment.audioSamples + nextSegment.audioSamples
                currentSegment = MockChannelSegment(
                    startTime: currentSegment.segment.startTime,
                    endTime: nextSegment.segment.endTime,
                    channel: currentSegment.channel,
                    speaker: currentSegment.speaker,
                    audioSamples: mergedAudio
                )
            } else {
                // Разные спикеры или слишком большой промежуток - сохраняем текущий
                merged.append(currentSegment)
                currentSegment = nextSegment
            }
        }
        merged.append(currentSegment) // Не забыть последний сегмент

        return merged
    }
}

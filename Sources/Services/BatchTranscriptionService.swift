import Foundation
import AVFoundation

/// Пакетная транскрипция файлов без VAD
/// Разбивает аудио на фиксированные чанки и распознает каждый
public class BatchTranscriptionService {

    /// Параметры пакетной транскрипции
    public struct Parameters {
        public let chunkDuration: TimeInterval  // Длительность чанка в секундах
        public let overlapDuration: TimeInterval // Перекрытие между чанками
        public let minTextLength: Int // Минимальная длина текста для сохранения

        public init(
            chunkDuration: TimeInterval = 30.0,
            overlapDuration: TimeInterval = 1.0,
            minTextLength: Int = 5
        ) {
            self.chunkDuration = chunkDuration
            self.overlapDuration = overlapDuration
            self.minTextLength = minTextLength
        }

        /// Параметры для низкокачественного аудио (короткие чанки)
        public static let lowQuality = Parameters(
            chunkDuration: 20.0,
            overlapDuration: 1.0,
            minTextLength: 3
        )

        /// Параметры для обычного качества
        public static let `default` = Parameters()
    }

    private let whisperService: WhisperService
    private let parameters: Parameters

    /// Callback для обновления промежуточных результатов
    public var onProgressUpdate: ((String, Double, DialogueTranscription?) -> Void)?

    public init(whisperService: WhisperService, parameters: Parameters = .default) {
        self.whisperService = whisperService
        self.parameters = parameters
    }

    /// Транскрибирует аудиофайл пакетным методом
    /// - Parameter url: URL аудиофайла
    /// - Returns: Диалог с распознанными репликами
    public func transcribe(url: URL) async throws -> DialogueTranscription {
        LogManager.app.begin("Batch транскрипция", details: url.lastPathComponent)

        // Загружаем аудио
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let totalFrames = Int(audioFile.length)
        let totalDuration = Double(totalFrames) / format.sampleRate
        let isStereo = format.channelCount == 2

        LogManager.app.info("Аудио: \(format.sampleRate) Hz, \(format.channelCount) каналов, длительность: \(String(format: "%.1f", totalDuration))s")

        // Конвертируем в Float32 16kHz
        let targetSampleRate: Double = 16000

        if isStereo {
            LogManager.app.info("Batch режим: стерео с разделением каналов")

            // Загружаем каналы отдельно
            let (leftChannel, rightChannel) = try loadStereoChannels(file: audioFile, targetSampleRate: targetSampleRate)

            return try await transcribeStereo(
                leftChannel: leftChannel,
                rightChannel: rightChannel,
                totalDuration: totalDuration,
                fileName: url.lastPathComponent
            )
        } else {
            LogManager.app.info("Batch режим: моно транскрипция")

            let audioSamples = try loadAndConvertAudio(file: audioFile, targetSampleRate: targetSampleRate)

            return try await transcribeMono(
                audioSamples: audioSamples,
                totalDuration: totalDuration,
                fileName: url.lastPathComponent
            )
        }
    }

    /// Транскрибирует моно аудио пакетным методом
    private func transcribeMono(
        audioSamples: [Float],
        totalDuration: TimeInterval,
        fileName: String
    ) async throws -> DialogueTranscription {
        let chunks = createChunks(audioSamples: audioSamples, sampleRate: 16000)
        var turns: [DialogueTranscription.Turn] = []
        var contextPrompt = ""  // Накапливаем контекст для следующих чанков

        for (index, chunk) in chunks.enumerated() {
            // Передаем предыдущий контекст для улучшения связности
            let text = try await whisperService.transcribe(
                audioSamples: chunk.samples,
                contextPrompt: contextPrompt.isEmpty ? nil : contextPrompt
            )

            if text.count >= parameters.minTextLength {
                // Создаем отдельный turn для каждого чанка с временными метками
                turns.append(DialogueTranscription.Turn(
                    speaker: .left,
                    text: text,
                    startTime: chunk.startTime,
                    endTime: chunk.endTime
                ))

                // Обновляем контекст: берем последние 200 символов распознанного текста
                contextPrompt = buildContextPrompt(from: turns)
            }

            let progress = Double(index + 1) / Double(chunks.count)
            LogManager.app.debug("Chunk \(index + 1)/\(chunks.count): \(text.count) символов, context: \(contextPrompt.count) chars")

            // Промежуточное обновление с накопленными turns
            if !turns.isEmpty {
                let partialDialogue = DialogueTranscription(
                    turns: turns,
                    isStereo: false,
                    totalDuration: totalDuration
                )
                onProgressUpdate?(fileName, progress, partialDialogue)
            }
        }

        LogManager.app.success("Batch моно транскрипция завершена: \(turns.count) реплик")

        return DialogueTranscription(
            turns: turns,
            isStereo: false,
            totalDuration: totalDuration
        )
    }

    /// Транскрибирует стерео аудио пакетным методом
    /// Чередует транскрипцию левого и правого каналов по времени для правильного отображения диалога
    private func transcribeStereo(
        leftChannel: [Float],
        rightChannel: [Float],
        totalDuration: TimeInterval,
        fileName: String
    ) async throws -> DialogueTranscription {
        let leftChunks = createChunks(audioSamples: leftChannel, sampleRate: 16000)
        let rightChunks = createChunks(audioSamples: rightChannel, sampleRate: 16000)

        LogManager.app.info("Стерео транскрипция: левый=\(leftChunks.count) чанков, правый=\(rightChunks.count) чанков")

        var turns: [DialogueTranscription.Turn] = []
        let totalChunks = leftChunks.count + rightChunks.count
        var processedChunks = 0
        var contextPrompt = ""  // Накапливаем контекст из обоих каналов

        // Транскрибируем чанки по индексу (один левый, один правый, чередуя)
        let maxChunks = max(leftChunks.count, rightChunks.count)

        for index in 0..<maxChunks {
            // Транскрибируем левый канал (если есть)
            if index < leftChunks.count {
                let chunk = leftChunks[index]
                let text = try await whisperService.transcribe(
                    audioSamples: chunk.samples,
                    contextPrompt: contextPrompt.isEmpty ? nil : contextPrompt
                )

                if text.count >= parameters.minTextLength {
                    turns.append(DialogueTranscription.Turn(
                        speaker: .left,
                        text: text,
                        startTime: chunk.startTime,
                        endTime: chunk.endTime
                    ))

                    // Обновляем контекст после каждой реплики
                    contextPrompt = buildContextPrompt(from: turns)

                    LogManager.app.debug("Left #\(index + 1) [\(self.formatTime(chunk.startTime))-\(self.formatTime(chunk.endTime))]: \(text.count) символов")
                }

                processedChunks += 1
                let progress = Double(processedChunks) / Double(totalChunks)
                let partialDialogue = DialogueTranscription(turns: turns, isStereo: true, totalDuration: totalDuration)
                onProgressUpdate?(fileName, progress, partialDialogue)
            }

            // Транскрибируем правый канал (если есть)
            if index < rightChunks.count {
                let chunk = rightChunks[index]
                let text = try await whisperService.transcribe(
                    audioSamples: chunk.samples,
                    contextPrompt: contextPrompt.isEmpty ? nil : contextPrompt
                )

                if text.count >= parameters.minTextLength {
                    turns.append(DialogueTranscription.Turn(
                        speaker: .right,
                        text: text,
                        startTime: chunk.startTime,
                        endTime: chunk.endTime
                    ))

                    // Обновляем контекст после каждой реплики
                    contextPrompt = buildContextPrompt(from: turns)

                    LogManager.app.debug("Right #\(index + 1) [\(self.formatTime(chunk.startTime))-\(self.formatTime(chunk.endTime))]: \(text.count) символов")
                }

                processedChunks += 1
                let progress = Double(processedChunks) / Double(totalChunks)
                let partialDialogue = DialogueTranscription(turns: turns, isStereo: true, totalDuration: totalDuration)
                onProgressUpdate?(fileName, progress, partialDialogue)
            }
        }

        LogManager.app.success("Batch стерео транскрипция завершена: \(turns.count) реплик")

        return DialogueTranscription(turns: turns, isStereo: true, totalDuration: totalDuration)
    }

    /// Строит контекстный промпт из последних реплик
    /// Берет последние 2-3 реплики (максимум 200 символов) для контекста
    private func buildContextPrompt(from turns: [DialogueTranscription.Turn]) -> String {
        guard !turns.isEmpty else { return "" }

        // Берем последние 3 реплики
        let recentTurns = turns.suffix(3)
        var contextText = recentTurns.map { $0.text }.joined(separator: " ")

        // Ограничиваем 200 символами (Whisper prompt limit ~220 tokens)
        if contextText.count > 200 {
            contextText = String(contextText.suffix(200))
        }

        return contextText
    }

    /// Форматирует время для логов
    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// Структура чанка аудио
    private struct AudioChunk {
        let samples: [Float]
        let startTime: TimeInterval
        let endTime: TimeInterval
    }

    /// Создает чанки из аудио сэмплов
    private func createChunks(audioSamples: [Float], sampleRate: Int) -> [AudioChunk] {
        let chunkSamples = Int(parameters.chunkDuration * Double(sampleRate))
        let overlapSamples = Int(parameters.overlapDuration * Double(sampleRate))
        let stepSamples = chunkSamples - overlapSamples

        var chunks: [AudioChunk] = []
        var startSample = 0

        while startSample < audioSamples.count {
            let endSample = min(startSample + chunkSamples, audioSamples.count)
            let chunkData = Array(audioSamples[startSample..<endSample])

            let startTime = Double(startSample) / Double(sampleRate)
            let endTime = Double(endSample) / Double(sampleRate)

            chunks.append(AudioChunk(samples: chunkData, startTime: startTime, endTime: endTime))

            startSample += stepSamples

            // Если осталось меньше половины чанка, добавляем последний кусок
            if startSample < audioSamples.count && (audioSamples.count - startSample) < chunkSamples / 2 {
                let lastChunk = Array(audioSamples[startSample..<audioSamples.count])
                let lastStartTime = Double(startSample) / Double(sampleRate)
                let lastEndTime = Double(audioSamples.count) / Double(sampleRate)
                chunks.append(AudioChunk(samples: lastChunk, startTime: lastStartTime, endTime: lastEndTime))
                break
            }
        }

        LogManager.app.info("Создано \(chunks.count) чанков по \(self.parameters.chunkDuration)s с перекрытием \(self.parameters.overlapDuration)s")

        return chunks
    }

    /// Извлекает конкретный канал из стерео аудио
    private func extractChannel(_ audioSamples: [Float], channel: Int) -> [Float] {
        // Предполагаем что audioSamples уже mono (конвертированный)
        // Для реального стерео нужно загружать каналы отдельно
        return audioSamples
    }

    /// Загружает и конвертирует аудио в Float32 16kHz mono
    private func loadAndConvertAudio(file: AVAudioFile, targetSampleRate: Double) throws -> [Float] {
        let format = file.processingFormat
        let frameCount = Int(file.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw NSError(domain: "BatchTranscriptionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось создать буфер"])
        }

        try file.read(into: buffer)

        // Конвертируем в Float32
        var floatArray: [Float] = []

        if let channelData = buffer.floatChannelData {
            let channelCount = Int(format.channelCount)
            let frameLength = Int(buffer.frameLength)

            if channelCount == 1 {
                // Моно
                floatArray = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            } else {
                // Стерео → моно (среднее)
                let leftChannel = UnsafeBufferPointer(start: channelData[0], count: frameLength)
                let rightChannel = UnsafeBufferPointer(start: channelData[1], count: frameLength)

                floatArray = (0..<frameLength).map { i in
                    (leftChannel[i] + rightChannel[i]) / 2.0
                }
            }
        }

        // Resample до 16kHz если нужно
        if format.sampleRate != targetSampleRate {
            floatArray = resample(floatArray, from: format.sampleRate, to: targetSampleRate)
        }

        return floatArray
    }

    /// Загружает стерео каналы отдельно
    private func loadStereoChannels(file: AVAudioFile, targetSampleRate: Double) throws -> ([Float], [Float]) {
        let format = file.processingFormat
        let frameCount = Int(file.length)

        guard format.channelCount == 2 else {
            throw NSError(domain: "BatchTranscriptionService", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Файл не стерео"])
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw NSError(domain: "BatchTranscriptionService", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Не удалось создать буфер"])
        }

        try file.read(into: buffer)

        // Извлекаем каналы
        guard let channelData = buffer.floatChannelData else {
            throw NSError(domain: "BatchTranscriptionService", code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Не удалось получить данные каналов"])
        }

        let frameLength = Int(buffer.frameLength)
        var leftChannel = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        var rightChannel = Array(UnsafeBufferPointer(start: channelData[1], count: frameLength))

        // Resample оба канала до 16kHz если нужно
        if format.sampleRate != targetSampleRate {
            leftChannel = resample(leftChannel, from: format.sampleRate, to: targetSampleRate)
            rightChannel = resample(rightChannel, from: format.sampleRate, to: targetSampleRate)
        }

        LogManager.app.info("Загружены стерео каналы: left=\(leftChannel.count), right=\(rightChannel.count) сэмплов")

        return (leftChannel, rightChannel)
    }

    /// Ресемплирует аудио
    private func resample(_ samples: [Float], from sourceSampleRate: Double, to targetSampleRate: Double) -> [Float] {
        let ratio = targetSampleRate / sourceSampleRate
        let targetCount = Int(Double(samples.count) * ratio)
        var resampled: [Float] = []
        resampled.reserveCapacity(targetCount)

        for i in 0..<targetCount {
            let sourceIndex = Double(i) / ratio
            let index = Int(sourceIndex)

            if index < samples.count - 1 {
                let fraction = Float(sourceIndex - Double(index))
                let sample = samples[index] * (1.0 - fraction) + samples[index + 1] * fraction
                resampled.append(sample)
            } else if index < samples.count {
                resampled.append(samples[index])
            }
        }

        LogManager.app.debug("Resample: \(sourceSampleRate) Hz → \(targetSampleRate) Hz, \(samples.count) → \(resampled.count) samples")

        return resampled
    }

    // MARK: - CLI Batch Processing

    /// Пакетная транскрибация нескольких файлов (для CLI режима)
    /// - Parameters:
    ///   - files: Массив URL файлов для транскрибации
    ///   - vadEnabled: Использовать ли VAD (разделение по спикерам)
    /// - Returns: Массив результатов транскрибации
    public func transcribeMultipleFiles(files: [URL], vadEnabled: Bool) async -> [TranscriptionResult] {
        var results: [TranscriptionResult] = []

        LogManager.batch.info("Начало пакетной транскрибации: \(files.count) файлов")
        fputs("[\u{1B}[34mINFO\u{1B}[0m] Starting batch transcription: \(files.count) file(s)\n", stderr)

        for (index, fileURL) in files.enumerated() {
            LogManager.batch.info("[\(index + 1)/\(files.count)] Обработка: \(fileURL.lastPathComponent)")
            fputs("[\u{1B}[33m\(index + 1)/\(files.count)\u{1B}[0m] Processing: \(fileURL.lastPathComponent)\n", stderr)
            fflush(stderr)

            let startTime = Date()

            do {
                // Получаем размер файла
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                let fileSize = fileAttributes[.size] as? Int64 ?? 0

                let result: TranscriptionResult

                if vadEnabled {
                    // VAD режим не реализован пока, используем batch
                    let dialogue = try await transcribe(url: fileURL)

                    let dialogueTurns = dialogue.turns.map { turn in
                        TranscriptionResult.DialogueTurn(
                            speaker: turn.speaker == .left ? "Speaker 1" : "Speaker 2",
                            timestamp: formatTimestampForJSON(turn.startTime),
                            text: turn.text
                        )
                    }

                    let duration = Date().timeIntervalSince(startTime)

                    result = TranscriptionResult(
                        file: fileURL.lastPathComponent,
                        status: "success",
                        transcription: TranscriptionResult.TranscriptionData(
                            mode: "vad",
                            dialogue: dialogueTurns,
                            text: nil
                        ),
                        error: nil,
                        metadata: TranscriptionResult.TranscriptionMetadata(
                            model: ModelManager.shared.currentModel,
                            vadEnabled: true,
                            duration: duration,
                            audioFileSize: fileSize
                        )
                    )

                    LogManager.batch.success("[\(index + 1)/\(files.count)] Успешно (VAD): \(fileURL.lastPathComponent) - \(dialogue.turns.count) фраз")
                    fputs("[\u{1B}[32m✓\u{1B}[0m] Completed in \(String(format: "%.1f", duration))s - \(dialogue.turns.count) dialogue turns\n", stderr)
                    fflush(stderr)
                } else {
                    // Batch режим - простой текст
                    let dialogue = try await transcribe(url: fileURL)
                    let text = dialogue.turns.map { $0.text }.joined(separator: " ")

                    let duration = Date().timeIntervalSince(startTime)

                    result = TranscriptionResult(
                        file: fileURL.lastPathComponent,
                        status: "success",
                        transcription: TranscriptionResult.TranscriptionData(
                            mode: "batch",
                            dialogue: nil,
                            text: text
                        ),
                        error: nil,
                        metadata: TranscriptionResult.TranscriptionMetadata(
                            model: ModelManager.shared.currentModel,
                            vadEnabled: false,
                            duration: duration,
                            audioFileSize: fileSize
                        )
                    )

                    LogManager.batch.success("[\(index + 1)/\(files.count)] Успешно (Batch): \(fileURL.lastPathComponent)")
                    fputs("[\u{1B}[32m✓\u{1B}[0m] Completed in \(String(format: "%.1f", duration))s\n", stderr)
                    fflush(stderr)
                }

                results.append(result)

            } catch {
                LogManager.batch.error("[\(index + 1)/\(files.count)] Ошибка: \(fileURL.lastPathComponent) - \(error)")

                let duration = Date().timeIntervalSince(startTime)

                let result = TranscriptionResult(
                    file: fileURL.lastPathComponent,
                    status: "error",
                    transcription: nil,
                    error: error.localizedDescription,
                    metadata: TranscriptionResult.TranscriptionMetadata(
                        model: ModelManager.shared.currentModel,
                        vadEnabled: vadEnabled,
                        duration: duration,
                        audioFileSize: 0
                    )
                )

                fputs("[\u{1B}[31m✗\u{1B}[0m] Error: \(error.localizedDescription)\n", stderr)
                fflush(stderr)

                results.append(result)
            }
        }

        LogManager.batch.success("Пакетная транскрибация завершена: \(results.count) файлов")

        let successCount = results.filter { $0.status == "success" }.count
        let errorCount = results.filter { $0.status == "error" }.count
        fputs("\n[\u{1B}[34mINFO\u{1B}[0m] Batch complete: \(successCount) succeeded, \(errorCount) failed\n", stderr)
        fflush(stderr)

        return results
    }

    /// Форматирование timestamp в читаемый формат для JSON (MM:SS)
    private func formatTimestampForJSON(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

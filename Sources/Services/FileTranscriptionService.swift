import Foundation
import AVFoundation
import TranscribeItCore

/// Структура для хранения диалога с разделением по дикторам и временными метками
public struct DialogueTranscription {
    public struct Turn: Identifiable {
        public let id = UUID()  // Уникальный идентификатор для SwiftUI
        public let speaker: Speaker
        public let text: String
        public let startTime: TimeInterval  // Время начала реплики в секундах
        public let endTime: TimeInterval    // Время окончания реплики в секундах

        public enum Speaker {
            case left   // Левый канал (Speaker 1)
            case right  // Правый канал (Speaker 2)

            public var displayName: String {
                switch self {
                case .left: return "Speaker 1"
                case .right: return "Speaker 2"
                }
            }

            public var color: String {
                switch self {
                case .left: return "blue"
                case .right: return "orange"
                }
            }
        }

        public var duration: TimeInterval {
            return endTime - startTime
        }

        public init(speaker: Speaker, text: String, startTime: TimeInterval, endTime: TimeInterval) {
            self.speaker = speaker
            self.text = text
            self.startTime = startTime
            self.endTime = endTime
        }
    }

    public let turns: [Turn]
    public let isStereo: Bool
    public let totalDuration: TimeInterval  // Общая длительность диалога

    public init(turns: [Turn], isStereo: Bool, totalDuration: TimeInterval = 0) {
        self.turns = turns
        self.isStereo = isStereo
        self.totalDuration = totalDuration
    }

    /// Возвращает реплики, отсортированные по времени (для timeline)
    public var sortedByTime: [Turn] {
        return turns.sorted { $0.startTime < $1.startTime }
    }

    /// Форматирует диалог как текст с временными метками
    public func formatted() -> String {
        if !isStereo || turns.isEmpty {
            return turns.first?.text ?? ""
        }

        return sortedByTime.map { turn in
            let timestamp = formatTimestamp(turn.startTime)
            return "[\(timestamp)] \(turn.speaker.displayName): \(turn.text)"
        }.joined(separator: "\n\n")
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, secs, millis)
    }

    /// Убирает периоды тишины (где оба спикера молчат) и пересчитывает временные метки
    /// Минимальный промежуток тишины для удаления: 2 секунды
    public func removesilencePeriods(minGap: TimeInterval = 2.0) -> DialogueTranscription {
        guard !turns.isEmpty else { return self }

        // Сортируем реплики по времени
        let sorted = sortedByTime

        var compressedTurns: [Turn] = []
        var currentTime: TimeInterval = 0

        for (index, turn) in sorted.enumerated() {
            let turnDuration = turn.endTime - turn.startTime

            if index == 0 {
                // Первая реплика начинается с 0
                compressedTurns.append(Turn(
                    speaker: turn.speaker,
                    text: turn.text,
                    startTime: currentTime,
                    endTime: currentTime + turnDuration
                ))
                currentTime += turnDuration
            } else {
                // Проверяем промежуток с предыдущей репликой
                let previousTurn = sorted[index - 1]
                let gap = turn.startTime - previousTurn.endTime

                // Добавляем паузу только если она меньше минимального порога
                // Иначе это тишина, которую нужно убрать
                if gap < minGap {
                    currentTime += gap
                } else {
                    // Добавляем небольшую паузу (0.5 сек) вместо длинной тишины
                    currentTime += 0.5
                }

                compressedTurns.append(Turn(
                    speaker: turn.speaker,
                    text: turn.text,
                    startTime: currentTime,
                    endTime: currentTime + turnDuration
                ))
                currentTime += turnDuration
            }
        }

        // Новая общая длительность - это время окончания последней реплики
        let newTotalDuration = compressedTurns.last?.endTime ?? 0

        LogManager.app.info("Сжатие диалога: \(String(format: "%.1f", totalDuration))s -> \(String(format: "%.1f", newTotalDuration))s (\(turns.count) реплик)")

        return DialogueTranscription(
            turns: compressedTurns,
            isStereo: isStereo,
            totalDuration: newTotalDuration
        )
    }
}

/// Сервис для транскрипции audio/video файлов
/// Загружает файл, конвертирует в формат WhisperKit и транскрибирует
public class FileTranscriptionService {

    /// Режим транскрипции
    public enum TranscriptionMode {
        case vad        // Использовать Voice Activity Detection (рекомендуется с SpectralVAD для телефонного аудио)
        case batch      // Пакетная транскрипция фиксированными чанками (альтернативный метод)
    }

    /// Тип VAD алгоритма для режима .vad
    public enum VADAlgorithm {
        case standard(VADParameters)       // Стандартный энергетический VAD
        case adaptive(AdaptiveVAD.Parameters)  // Адаптивный VAD с ZCR
        case spectral(SpectralVAD.Parameters)  // Спектральный VAD (FFT)

        /// Рекомендуемый для телефонного аудио
        public static let telephone = VADAlgorithm.spectral(.telephone)

        /// Рекомендуемый для широкополосного аудио
        public static let wideband = VADAlgorithm.spectral(.wideband)

        /// Стандартный
        public static let `default` = VADAlgorithm.spectral(.default)
    }

    private let whisperService: WhisperService
    private var batchService: BatchTranscriptionService?

    /// Текущий режим транскрипции
    public var mode: TranscriptionMode = .vad  // VAD режим с SpectralVAD для телефонного аудио

    /// Алгоритм VAD (используется только в режиме .vad)
    public var vadAlgorithm: VADAlgorithm = .telephone  // SpectralVAD - Telephone по умолчанию

    /// Callback для обновления промежуточных результатов (прогресс и реплики)
    public var onProgressUpdate: ((String, Double, DialogueTranscription?) -> Void)?

    public init(whisperService: WhisperService) {
        self.whisperService = whisperService
        self.batchService = BatchTranscriptionService(
            whisperService: whisperService,
            parameters: .lowQuality
        )
        // Применяем настройки из UserSettings
        applyUserSettings()
    }

    /// Применяет настройки VAD из UserSettings
    public func applyUserSettings() {
        let settings = UserSettings.shared

        // Режим транскрипции
        switch settings.fileTranscriptionMode {
        case .vad:
            mode = .vad
        case .batch:
            mode = .batch
        }

        // VAD алгоритм
        switch settings.vadAlgorithmType {
        case .spectralTelephone:
            vadAlgorithm = .telephone
        case .spectralWideband:
            vadAlgorithm = .wideband
        case .spectralDefault:
            vadAlgorithm = .default
        case .adaptiveLowQuality:
            vadAlgorithm = .adaptive(AdaptiveVAD.Parameters.lowQuality)
        case .adaptiveAggressive:
            vadAlgorithm = .adaptive(AdaptiveVAD.Parameters.aggressive)
        case .standardLowQuality:
            vadAlgorithm = .standard(VADParameters.lowQuality)
        case .standardHighQuality:
            vadAlgorithm = .standard(VADParameters.highQuality)
        case .batch:
            // Для batch режима VAD алгоритм не используется, но устанавливаем дефолтный
            vadAlgorithm = .default
        }

        LogManager.app.info("FileTranscriptionService: применены настройки - режим: \(self.mode == .vad ? "VAD" : "Batch"), алгоритм: \(self.vadAlgorithmName)")
    }

    /// Транскрибирует аудио/видео файл с поддержкой стерео разделения
    /// - Parameter url: URL файла для транскрипции
    /// - Returns: Диалог с разделением по дикторам (если стерео)
    /// - Throws: Ошибки загрузки или транскрипции
    public func transcribeFileWithDialogue(at url: URL) async throws -> DialogueTranscription {
        LogManager.app.begin("Транскрипция файла с определением дикторов: \(url.lastPathComponent)")

        // Проверяем готовность модели Whisper
        if !whisperService.isReady {
            LogManager.app.error("Модель Whisper не загружена, ожидание...")
            // Ждём до 60 секунд пока модель загрузится
            for attempt in 1...60 {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 секунда
                if whisperService.isReady {
                    LogManager.app.success("Модель Whisper готова (попытка \(attempt))")
                    break
                }
                if attempt == 60 {
                    LogManager.app.failure("Таймаут загрузки модели", message: "Модель не загрузилась за 60 секунд")
                    throw WhisperError.modelNotLoaded
                }
            }
        }

        LogManager.app.info("Режим транскрипции: \(self.mode == .batch ? "BATCH" : "VAD (\(self.vadAlgorithmName))")")

        // Используем batch режим, если выбран
        if mode == .batch {
            guard let batchService = batchService else {
                throw NSError(domain: "FileTranscriptionService", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "BatchTranscriptionService не инициализирован"])
            }

            // Пробрасываем callback в batchService
            batchService.onProgressUpdate = onProgressUpdate

            return try await batchService.transcribe(url: url)
        }

        // VAD режим (оригинальный код)
        // 1. Проверяем, стерео ли файл
        let channelCount = try await getChannelCount(from: url)
        LogManager.app.info("Обнаружено каналов: \(channelCount)")

        if channelCount == 2 {
            // Стерео: разделяем каналы и транскрибируем отдельно
            return try await transcribeStereoAsDialogue(url: url)
        } else {
            // Моно: обычная транскрипция
            let audioSamples = try await loadAudio(from: url)
            let totalDuration = TimeInterval(audioSamples.count) / 16000.0
            let text = try await whisperService.transcribe(audioSamples: audioSamples)

            LogManager.app.info("Моно транскрипция завершена: \(text.count) символов")

            let dialogue = DialogueTranscription(
                turns: [DialogueTranscription.Turn(
                    speaker: .left,
                    text: text,
                    startTime: 0,
                    endTime: totalDuration
                )],
                isStereo: false,
                totalDuration: totalDuration
            )

            // Вызываем callback для моно файлов тоже
            onProgressUpdate?(url.lastPathComponent, 1.0, dialogue)

            return dialogue
        }
    }

    /// Транскрибирует аудио/видео файл (обычный режим)
    /// - Parameter url: URL файла для транскрипции
    /// - Returns: Текст транскрипции
    /// - Throws: Ошибки загрузки или транскрипции
    public func transcribeFile(at url: URL) async throws -> String {
        LogManager.app.begin("Транскрипция файла: \(url.lastPathComponent)")

        // Проверяем готовность модели Whisper
        if !whisperService.isReady {
            LogManager.app.error("Модель Whisper не загружена, ожидание...")
            // Ждём до 60 секунд пока модель загрузится
            for attempt in 1...60 {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 секунда
                if whisperService.isReady {
                    LogManager.app.success("Модель Whisper готова (попытка \(attempt))")
                    break
                }
                if attempt == 60 {
                    LogManager.app.failure("Таймаут загрузки модели", message: "Модель не загрузилась за 60 секунд")
                    throw WhisperError.modelNotLoaded
                }
            }
        }

        // 1. Загружаем аудио из файла
        let audioSamples = try await loadAudio(from: url)

        // 2. Проверяем на тишину
        if SilenceDetector.shared.isSilence(audioSamples) {
            LogManager.app.info("🔇 Файл содержит только тишину")
            throw FileTranscriptionError.silenceDetected
        }

        // 3. Транскрибируем
        let transcription = try await whisperService.transcribe(audioSamples: audioSamples)

        if transcription.isEmpty {
            throw FileTranscriptionError.emptyTranscription
        }

        LogManager.app.success("Транскрипция файла завершена: \(transcription.count) символов")
        return transcription
    }

    /// Загружает аудио из файла и конвертирует в формат WhisperKit (16kHz mono Float32)
    /// - Parameter url: URL файла
    /// - Returns: Массив audio samples
    /// - Throws: Ошибки загрузки или конвертации
    private func loadAudio(from url: URL) async throws -> [Float] {
        let asset = AVAsset(url: url)

        // Проверяем, что файл содержит audio track
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            LogManager.app.failure("Файл не содержит audio track", error: FileTranscriptionError.noAudioTrack)
            throw FileTranscriptionError.noAudioTrack
        }

        // Создаем reader для чтения аудио
        let reader = try AVAssetReader(asset: asset)

        // Настройки вывода: 16kHz, mono, Linear PCM Float32
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)

        guard reader.startReading() else {
            LogManager.app.failure("Не удалось начать чтение файла", error: FileTranscriptionError.readError)
            throw FileTranscriptionError.readError
        }

        var audioSamples: [Float] = []

        // Читаем все sample buffers
        while let sampleBuffer = output.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var data = Data(count: length)

                _ = data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
                }

                // Конвертируем Data в [Float]
                let floatArray = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> [Float] in
                    let floatPtr = ptr.bindMemory(to: Float.self)
                    return Array(floatPtr)
                }

                audioSamples.append(contentsOf: floatArray)
            }
        }

        reader.cancelReading()

        let durationSeconds = Float(audioSamples.count) / 16000.0
        LogManager.app.success("Файл загружен: \(audioSamples.count) samples, \(String(format: "%.1f", durationSeconds))s")

        // Ограничение убрано - поддерживаем файлы любой длительности
        // Транскрипция будет происходить по сегментам через VAD

        return audioSamples
    }

    /// Получает количество аудио каналов в файле
    private func getChannelCount(from url: URL) async throws -> Int {
        let asset = AVAsset(url: url)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw FileTranscriptionError.noAudioTrack
        }

        let formatDescriptions = try await audioTrack.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first else {
            return 1 // По умолчанию моно
        }

        if let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
            return Int(audioStreamBasicDescription.pointee.mChannelsPerFrame)
        }

        return 1
    }

    /// Структура для хранения сегмента с привязкой к каналу
    private struct ChannelSegment {
        let segment: SpeechSegment
        let channel: Int  // 0 = left, 1 = right
        let speaker: DialogueTranscription.Turn.Speaker
        let audioSamples: [Float]
    }

    /// Транскрибирует стерео файл как диалог (левый и правый каналы отдельно)
    /// УЛУЧШЕННЫЙ АЛГОРИТМ: обрабатывает сегменты в шахматном порядке по времени,
    /// используя предыдущий диалог как контекст для улучшения качества распознавания
    private func transcribeStereoAsDialogue(url: URL) async throws -> DialogueTranscription {
        LogManager.app.info("🎧 Стерео режим: разделяем каналы для определения дикторов")

        // 1. Загружаем стерео аудио
        let stereoSamples = try await loadAudioStereo(from: url)

        // 2. Разделяем на левый и правый каналы
        let leftChannel = extractChannel(from: stereoSamples, channel: 0)
        let rightChannel = extractChannel(from: stereoSamples, channel: 1)

        // 3. Определяем общую длительность
        let totalDuration = TimeInterval(leftChannel.count) / 16000.0

        // 4. Используем выбранный VAD алгоритм для определения сегментов речи в каждом канале
        LogManager.app.info("🎤 VAD: анализ левого канала (алгоритм: \(self.vadAlgorithmName))...")
        let leftSegments = detectSegments(in: leftChannel)
        LogManager.app.info("Найдено \(leftSegments.count) сегментов речи в левом канале")

        LogManager.app.info("🎤 VAD: анализ правого канала (алгоритм: \(self.vadAlgorithmName))...")
        let rightSegments = detectSegments(in: rightChannel)
        LogManager.app.info("Найдено \(rightSegments.count) сегментов речи в правом канале")

        // 5. НОВОЕ: Объединяем сегменты из обоих каналов с привязкой к каналу
        var allSegments: [ChannelSegment] = []

        // Добавляем левые сегменты
        for segment in leftSegments {
            let audio = extractSegmentAudio(segment, from: leftChannel)
            allSegments.append(ChannelSegment(
                segment: segment,
                channel: 0,
                speaker: DialogueTranscription.Turn.Speaker.left,
                audioSamples: audio
            ))
        }

        // Добавляем правые сегменты
        for segment in rightSegments {
            let audio = extractSegmentAudio(segment, from: rightChannel)
            allSegments.append(ChannelSegment(
                segment: segment,
                channel: 1,
                speaker: DialogueTranscription.Turn.Speaker.right,
                audioSamples: audio
            ))
        }

        // 6. НОВОЕ: Сортируем по времени (шахматный порядок)
        allSegments.sort(by: { $0.segment.startTime < $1.segment.startTime })
        LogManager.app.info("🔄 Сегменты отсортированы по времени для последовательной обработки (\(allSegments.count) всего)")

        // 7. НОВОЕ: Транскрибируем в шахматном порядке с контекстом
        var turns: [DialogueTranscription.Turn] = []
        let totalSegments = allSegments.count
        var processedSegments = 0

        for channelSegment in allSegments {
            let segment = channelSegment.segment
            let speaker = channelSegment.speaker
            let segmentAudio = channelSegment.audioSamples

            if !SilenceDetector.shared.isSilence(segmentAudio) {
                // НОВОЕ: Формируем контекст из последних N реплик (например, 5)
                let contextPrompt = buildContextPrompt(from: turns, maxTurns: 5)

                let speakerName = speaker == .left ? "Speaker 1" : "Speaker 2"
                LogManager.app.info("Транскрибируем \(speakerName): \(String(format: "%.1f", segment.startTime))s - \(String(format: "%.1f", segment.endTime))s (контекст: \(contextPrompt.isEmpty ? "нет" : "\(contextPrompt.count) символов"))")

                // НОВОЕ: Передаем контекст в Whisper
                let text = try await whisperService.transcribe(
                    audioSamples: segmentAudio,
                    contextPrompt: contextPrompt.isEmpty ? nil : contextPrompt
                )

                if !text.isEmpty {
                    turns.append(DialogueTranscription.Turn(
                        speaker: speaker,
                        text: text,
                        startTime: segment.startTime,
                        endTime: segment.endTime
                    ))

                    // Обновляем прогресс после каждой реплики
                    processedSegments += 1
                    let progress = Double(processedSegments) / Double(totalSegments)
                    let partialDialogue = DialogueTranscription(turns: turns, isStereo: true, totalDuration: totalDuration)
                    LogManager.app.debug("Обновление прогресса: \(processedSegments)/\(totalSegments), turns: \(turns.count)")
                    onProgressUpdate?(url.lastPathComponent, progress, partialDialogue)
                } else {
                    LogManager.app.warning("\(speakerName): пустой текст для сегмента \(String(format: "%.1f", segment.startTime))s")
                }
            }
        }

        LogManager.app.success("Стерео транскрипция завершена: \(turns.count) реплик (обработаны в хронологическом порядке)")

        return DialogueTranscription(turns: turns, isStereo: true, totalDuration: totalDuration)
    }

    /// НОВОЕ: Формирует контекстный промпт из предыдущих реплик диалога
    /// Помогает Whisper лучше распознавать имена, термины и контекст разговора
    private func buildContextPrompt(from turns: [DialogueTranscription.Turn], maxTurns: Int = 5) -> String {
        // Берем последние N реплик
        let recentTurns = Array(turns.suffix(maxTurns))

        if recentTurns.isEmpty {
            return ""
        }

        // Формируем контекст в виде диалога
        let context = recentTurns.map { turn in
            let speakerName = turn.speaker == .left ? "Speaker 1" : "Speaker 2"
            return "\(speakerName): \(turn.text)"
        }.joined(separator: " ")

        // Ограничиваем длину контекста (примерно 200-300 символов оптимально)
        let maxLength = 300
        if context.count > maxLength {
            let endIndex = context.index(context.startIndex, offsetBy: maxLength)
            return String(context[..<endIndex]) + "..."
        }

        return context
    }

    /// Загружает стерео аудио (сохраняя оба канала)
    private func loadAudioStereo(from url: URL) async throws -> [[Float]] {
        let asset = AVAsset(url: url)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw FileTranscriptionError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)

        // Настройки вывода: 16kHz, STEREO (2 channels), Linear PCM Float32
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 2,  // Стерео!
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false  // Interleaved: L, R, L, R, ...
        ]

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)

        guard reader.startReading() else {
            throw FileTranscriptionError.readError
        }

        var interleavedSamples: [Float] = []

        while let sampleBuffer = output.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var data = Data(count: length)

                _ = data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
                }

                let floatArray = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> [Float] in
                    let floatPtr = ptr.bindMemory(to: Float.self)
                    return Array(floatPtr)
                }

                interleavedSamples.append(contentsOf: floatArray)
            }
        }

        reader.cancelReading()

        // Возвращаем как массив из двух каналов (пока interleaved)
        return [interleavedSamples]
    }

    /// Извлекает один канал из interleaved стерео
    private func extractChannel(from stereoData: [[Float]], channel: Int) -> [Float] {
        guard let interleavedSamples = stereoData.first else { return [] }

        var channelSamples: [Float] = []
        channelSamples.reserveCapacity(interleavedSamples.count / 2)

        // Interleaved format: L, R, L, R, L, R, ...
        // channel 0 = left (indices 0, 2, 4, ...)
        // channel 1 = right (indices 1, 3, 5, ...)
        stride(from: channel, to: interleavedSamples.count, by: 2).forEach { index in
            channelSamples.append(interleavedSamples[index])
        }

        let durationSeconds = Float(channelSamples.count) / 16000.0
        LogManager.app.info("Канал \(channel): \(channelSamples.count) samples, \(String(format: "%.1f", durationSeconds))s")

        return channelSamples
    }

    // MARK: - VAD Helpers

    /// Определяет сегменты речи с использованием выбранного алгоритма
    private func detectSegments(in samples: [Float]) -> [SpeechSegment] {
        switch vadAlgorithm {
        case .standard(let params):
            let vad = VoiceActivityDetector(parameters: params)
            return vad.detectSpeechSegments(in: samples)

        case .adaptive(let params):
            let vad = AdaptiveVAD(parameters: params)
            return vad.detectSpeechSegments(in: samples)

        case .spectral(let params):
            let vad = SpectralVAD(parameters: params)
            return vad.detectSpeechSegments(in: samples)
        }
    }

    /// Извлекает аудио для сегмента
    private func extractSegmentAudio(_ segment: SpeechSegment, from samples: [Float]) -> [Float] {
        let startIndex = max(0, segment.startSample)
        let endIndex = min(samples.count, segment.endSample)

        guard startIndex < endIndex && startIndex < samples.count else {
            return []
        }

        return Array(samples[startIndex..<endIndex])
    }

    /// Возвращает название текущего VAD алгоритма для логирования
    private var vadAlgorithmName: String {
        switch vadAlgorithm {
        case .standard:
            return "Standard VAD"
        case .adaptive:
            return "Adaptive VAD"
        case .spectral(let params):
            if params.speechFreqMin == 300 && params.speechFreqMax == 3400 {
                return "Spectral VAD (Telephone)"
            } else if params.speechFreqMin == 80 && params.speechFreqMax == 8000 {
                return "Spectral VAD (Wideband)"
            } else {
                return "Spectral VAD"
            }
        }
    }

}

/// Ошибки транскрипции файлов
enum FileTranscriptionError: LocalizedError {
    case noAudioTrack
    case readError
    case silenceDetected
    case emptyTranscription
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "File does not contain an audio track"
        case .readError:
            return "Failed to read audio file"
        case .silenceDetected:
            return "File contains only silence"
        case .emptyTranscription:
            return "Transcription resulted in empty text"
        case .fileTooLarge:
            return "File is too large (max 60 minutes)"
        }
    }
}

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

/// Snapshot настроек контекстной оптимизации для изоляции транскрипций
/// Захватывается в начале transcribeFile() чтобы изменения в других экземплярах приложения
/// не влияли на текущую транскрипцию
private struct ContextOptimizationSettings {
    let maxContextLength: Int
    let maxRecentTurns: Int
    let enableEntityExtraction: Bool
    let enableVocabularyIntegration: Bool
    let postVADMergeThreshold: TimeInterval
    let baseContextPrompt: String

    /// Создает snapshot из текущих настроек пользователя
    static func capture(from userSettings: UserSettingsProtocol) -> ContextOptimizationSettings {
        return ContextOptimizationSettings(
            maxContextLength: userSettings.maxContextLength,
            maxRecentTurns: userSettings.maxRecentTurns,
            enableEntityExtraction: userSettings.enableEntityExtraction,
            enableVocabularyIntegration: userSettings.enableVocabularyIntegration,
            postVADMergeThreshold: userSettings.postVADMergeThreshold,
            baseContextPrompt: userSettings.baseContextPrompt
        )
    }
}

/// Профессиональный сервис для транскрипции audio/video файлов с поддержкой стерео разделения
///
/// `FileTranscriptionService` обеспечивает высококачественную транскрипцию аудио файлов с автоматическим
/// разделением дикторов для стерео записей (например, телефонных звонков). Использует WhisperKit для
/// on-device транскрипции с Metal GPU acceleration.
///
/// ## Основные возможности
///
/// - **Стерео разделение**: Автоматическое определение двух дикторов по каналам (Left/Right)
/// - **Voice Activity Detection (VAD)**: Умное обнаружение речевых сегментов с фильтрацией тишины
/// - **Контекстная транскрипция**: Использует предыдущие реплики для улучшения точности
/// - **Кэширование аудио**: Предотвращает повторную загрузку одних и тех же файлов
/// - **Real-time прогресс**: Callback для отслеживания промежуточных результатов
///
/// ## Поддерживаемые форматы
///
/// MP3, M4A, WAV, AIFF, AAC, FLAC, MP4, MOV - любые форматы, поддерживаемые AVFoundation
///
/// ## Режимы транскрипции
///
/// - **VAD режим** (рекомендуется): Использует Voice Activity Detection для умного сегментирования
/// - **Batch режим**: Пакетная обработка фиксированными чанками (для специфических случаев)
///
/// ## Пример использования
///
/// ```swift
/// // Создание сервиса
/// let whisperService = WhisperService(modelSize: "medium")
/// let audioCache = AudioCache()
/// let service = FileTranscriptionService(
///     whisperService: whisperService,
///     userSettings: UserSettings.shared,
///     audioCache: audioCache
/// )
///
/// // Настройка прогресса
/// service.onProgressUpdate = { fileName, progress, partialDialogue in
///     print("Progress: \(Int(progress * 100))% - \(partialDialogue?.turns.count ?? 0) turns")
/// }
///
/// // Транскрипция стерео файла
/// let dialogue = try await service.transcribeFileWithDialogue(at: audioURL)
/// print("Transcribed \(dialogue.turns.count) turns from \(dialogue.isStereo ? "stereo" : "mono") file")
///
/// // Доступ к репликам
/// for turn in dialogue.sortedByTime {
///     print("[\(turn.startTime)s] \(turn.speaker.displayName): \(turn.text)")
/// }
/// ```
///
/// ## Производительность
///
/// - Стерео файл 60 минут: ~10-15 минут на M1/M2 (model: medium, RTF ~0.2x)
/// - VAD сегментация: ~0.5-2 секунды на 60 минут аудио
/// - Кэширование снижает повторную загрузку с ~5s до <0.1s
///
/// ## Thread Safety
///
/// Все методы безопасны для вызова из разных потоков. Внутренний AudioCache использует actor для изоляции.
///
/// - Note: Для оптимальной производительности используйте SpectralVAD с preset `.telephone` для телефонных записей
/// - Warning: Файлы размером >500MB могут вызвать ошибку `TranscriptionError.fileTooLarge`
///
public class FileTranscriptionService {

    /// Режим транскрипции файла
    ///
    /// Определяет стратегию сегментации аудио перед транскрипцией.
    public enum TranscriptionMode {
        /// Voice Activity Detection - умное обнаружение речевых сегментов
        ///
        /// Рекомендуется для большинства случаев. Использует SpectralVAD для фильтрации
        /// тишины и шума, обрабатывая только участки с речью.
        case vad

        /// Пакетная транскрипция фиксированными чанками
        ///
        /// Альтернативный метод для специфических случаев. Делит аудио на равные части
        /// без анализа содержимого.
        case batch
    }

    /// Алгоритм Voice Activity Detection для обнаружения речевых сегментов
    ///
    /// Доступны три типа VAD алгоритмов с разными стратегиями обнаружения речи:
    ///
    /// - **Standard**: Энергетический VAD на основе амплитуды сигнала
    /// - **Adaptive**: Адаптивный VAD с Zero-Crossing Rate (ZCR) анализом
    /// - **Spectral**: Спектральный VAD с FFT анализом частот (рекомендуется)
    ///
    /// ## Рекомендации
    ///
    /// - `.telephone` - для телефонных записей (300-3400 Hz)
    /// - `.wideband` - для широкополосного аудио (80-8000 Hz)
    /// - `.default` - универсальный preset
    ///
    /// ## Пример
    ///
    /// ```swift
    /// service.vadAlgorithm = .telephone  // Оптимально для телефонных звонков
    /// ```
    public enum VADAlgorithm {
        /// Стандартный энергетический VAD на основе амплитуды
        case standard(VADParameters)

        /// Адаптивный VAD с Zero-Crossing Rate анализом
        case adaptive(AdaptiveVAD.Parameters)

        /// Спектральный VAD с FFT анализом частот (рекомендуется)
        case spectral(SpectralVAD.Parameters)

        /// Preset для телефонного аудио (300-3400 Hz)
        ///
        /// Оптимизирован для узкополосных телефонных записей со стандартным
        /// частотным диапазоном 300-3400 Hz.
        public static let telephone = VADAlgorithm.spectral(.telephone)

        /// Preset для широкополосного аудио (80-8000 Hz)
        ///
        /// Подходит для профессиональных записей и аудио высокого качества.
        public static let wideband = VADAlgorithm.spectral(.wideband)

        /// Универсальный preset для большинства случаев
        public static let `default` = VADAlgorithm.spectral(.default)
    }

    /// Константы для оптимизации контекста в длинных звонках
    private enum ContextOptimizationConstants {
        /// Максимальное количество терминов словаря в контексте
        static let maxVocabularyTermsInContext = 15

        /// Максимальное количество последних реплик для извлечения сущностей
        static let maxRecentTurnsForEntityExtraction = 20
    }

    /// Кэшированное регулярное выражение для извлечения именованных сущностей
    /// (оптимизация производительности - компилируется один раз)
    private static let entityExtractionRegex: NSRegularExpression? = {
        let englishPattern = "\\b[A-Z][a-z]+"
        let russianPattern = "\\b[А-ЯЁ][а-яё]+"
        let combinedPattern = "(\(englishPattern))|(\(russianPattern))"
        return try? NSRegularExpression(pattern: combinedPattern)
    }()

    private let whisperService: WhisperService
    private let userSettings: UserSettingsProtocol
    private var batchService: BatchTranscriptionService?
    private let audioCache: AudioCache

    /// Текущий режим транскрипции
    ///
    /// По умолчанию используется `.vad` режим с SpectralVAD для оптимальной сегментации.
    /// Изменение режима влияет на стратегию обработки аудио.
    ///
    /// - Note: Для применения настроек из UserSettings используйте `applyUserSettings()`
    public var mode: TranscriptionMode = .vad

    /// Алгоритм Voice Activity Detection (используется только в режиме .vad)
    ///
    /// По умолчанию используется `.telephone` preset (SpectralVAD с частотным диапазоном 300-3400 Hz),
    /// оптимизированный для телефонных записей.
    ///
    /// ## Доступные preset'ы:
    /// - `.telephone` - для телефонных звонков (300-3400 Hz)
    /// - `.wideband` - для широкополосного аудио (80-8000 Hz)
    /// - `.default` - универсальный
    ///
    /// - Note: Игнорируется в `.batch` режиме
    public var vadAlgorithm: VADAlgorithm = .telephone

    /// Callback для получения real-time обновлений прогресса транскрипции
    ///
    /// Вызывается после обработки каждого сегмента с актуальным прогрессом и частичным результатом.
    ///
    /// ## Параметры callback:
    /// - `fileName: String` - имя обрабатываемого файла
    /// - `progress: Double` - прогресс от 0.0 до 1.0
    /// - `partialDialogue: DialogueTranscription?` - частичный результат с уже обработанными репликами
    ///
    /// ## Пример:
    /// ```swift
    /// service.onProgressUpdate = { fileName, progress, dialogue in
    ///     DispatchQueue.main.async {
    ///         self.progressValue = progress
    ///         self.currentDialogue = dialogue
    ///     }
    /// }
    /// ```
    ///
    /// - Warning: Callback может вызываться из фонового потока. Используйте `@MainActor` или `DispatchQueue.main` для UI обновлений.
    public var onProgressUpdate: ((String, Double, DialogueTranscription?) -> Void)?

    /// Инициализирует сервис транскрипции с необходимыми зависимостями
    ///
    /// После инициализации автоматически применяет настройки из `userSettings` (режим и VAD алгоритм).
    ///
    /// - Parameters:
    ///   - whisperService: Сервис WhisperKit для выполнения транскрипции
    ///   - userSettings: Протокол настроек приложения для получения конфигурации
    ///   - audioCache: Actor для кэширования загруженных аудио данных
    ///
    /// ## Пример:
    /// ```swift
    /// let service = FileTranscriptionService(
    ///     whisperService: WhisperService(modelSize: "medium"),
    ///     userSettings: UserSettings.shared,
    ///     audioCache: AudioCache()
    /// )
    /// ```
    public init(
        whisperService: WhisperService,
        userSettings: UserSettingsProtocol,
        audioCache: AudioCache
    ) {
        self.whisperService = whisperService
        self.userSettings = userSettings
        self.audioCache = audioCache
        self.batchService = BatchTranscriptionService(
            whisperService: whisperService,
            parameters: .lowQuality
        )
        // Применяем настройки из UserSettings
        applyUserSettings()
    }

    /// Применяет настройки режима транскрипции и VAD алгоритма из UserSettings
    ///
    /// Синхронизирует текущие параметры сервиса с пользовательскими настройками:
    /// - Режим транскрипции (VAD или Batch)
    /// - VAD алгоритм и его параметры
    ///
    /// Вызывается автоматически при инициализации. Повторный вызов необходим только
    /// если пользовательские настройки были изменены после создания сервиса.
    ///
    /// ## Пример:
    /// ```swift
    /// // Пользователь изменил настройки в UI
    /// UserSettings.shared.vadAlgorithmType = .spectralWideband
    ///
    /// // Применяем новые настройки к сервису
    /// service.applyUserSettings()
    /// ```
    ///
    /// - Note: Изменения вступают в силу для следующих вызовов `transcribeFileWithDialogue()`
    public func applyUserSettings() {
        // Режим транскрипции
        switch userSettings.fileTranscriptionMode {
        case .vad:
            mode = .vad
        case .batch:
            mode = .batch
        }

        // VAD алгоритм
        switch userSettings.vadAlgorithmType {
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

    // MARK: - Audio Cache Management

    /// Очищает кэш аудио данных
    ///
    /// Полезно вызывать после завершения транскрипции для освобождения памяти.
    public func clearAudioCache() async {
        await audioCache.clearCache()
        LogManager.app.info("Audio cache cleared")
    }

    /// Удаляет конкретный файл из кэша
    /// - Parameter url: URL файла для удаления
    public func evictFromCache(_ url: URL) async {
        await audioCache.evict(url)
        LogManager.app.debug("Evicted from cache: \(url.lastPathComponent)")
    }

    /// Возвращает статистику использования кэша
    /// - Returns: Структура со статистикой (hits, misses, hit rate)
    public func getCacheStatistics() async -> AudioCache.CacheStatistics {
        return await audioCache.getStatistics()
    }

    // MARK: - File Transcription

    /// Транскрибирует аудио/видео файл с автоматическим разделением дикторов (основной метод)
    ///
    /// Универсальный метод для транскрипции файлов с поддержкой:
    /// - **Стерео разделения**: Автоматически определяет два диктора по каналам (Left/Right)
    /// - **Моно обработки**: Обычная транскрипция для одноканальных файлов
    /// - **Real-time прогресс**: Обновления через `onProgressUpdate` callback
    /// - **Контекстная транскрипция**: Использует предыдущие реплики для улучшения точности
    ///
    /// ## Процесс обработки:
    /// 1. Проверка готовности Whisper модели (ожидание до 60 секунд)
    /// 2. Определение количества каналов (моно/стерео)
    /// 3. VAD сегментация или batch обработка (зависит от `mode`)
    /// 4. Транскрипция сегментов с контекстом
    /// 5. Возврат структурированного диалога
    ///
    /// ## Для стерео файлов:
    /// - Left channel → Speaker 1 (blue)
    /// - Right channel → Speaker 2 (orange)
    /// - Реплики обрабатываются в хронологическом порядке
    /// - Каждая реплика использует контекст предыдущих для лучшего распознавания
    ///
    /// ## Для моно файлов:
    /// - Возвращается один Turn с полным текстом
    /// - Speaker = .left (по умолчанию)
    ///
    /// - Parameter url: URL аудио/видео файла для транскрипции
    /// - Returns: `DialogueTranscription` со списком реплик, флагом стерео и общей длительностью
    /// - Throws:
    ///   - `WhisperError.modelNotLoaded` - модель не загрузилась за 60 секунд
    ///   - `TranscriptionError.serviceNotInitialized` - BatchTranscriptionService не инициализирован
    ///   - `TranscriptionError.noAudioTrack` - файл не содержит аудио дорожки
    ///   - `TranscriptionError.audioLoadFailed` - ошибка загрузки аудио
    ///
    /// ## Пример:
    /// ```swift
    /// // Настройка прогресса
    /// service.onProgressUpdate = { fileName, progress, dialogue in
    ///     print("\(fileName): \(Int(progress * 100))%")
    ///     print("Processed turns: \(dialogue?.turns.count ?? 0)")
    /// }
    ///
    /// // Транскрипция
    /// let dialogue = try await service.transcribeFileWithDialogue(at: fileURL)
    ///
    /// // Обработка результата
    /// if dialogue.isStereo {
    ///     print("Stereo dialogue with \(dialogue.turns.count) turns")
    ///     for turn in dialogue.sortedByTime {
    ///         print("[\(turn.startTime)s] \(turn.speaker.displayName): \(turn.text)")
    ///     }
    /// } else {
    ///     print("Mono transcription: \(dialogue.turns.first?.text ?? "")")
    /// }
    /// ```
    ///
    /// - Note: Используйте SpectralVAD с preset `.telephone` для телефонных записей
    /// - Important: Метод автоматически использует AudioCache для предотвращения повторной загрузки
    public func transcribeFileWithDialogue(at url: URL) async throws -> DialogueTranscription {
        LogManager.app.begin("Транскрипция файла с определением дикторов: \(url.lastPathComponent)")

        // Проверяем отмену в самом начале
        try Task.checkCancellation()

        // Проверяем готовность модели Whisper
        if !whisperService.isReady {
            LogManager.app.error("Модель Whisper не загружена, ожидание...")
            // Ждём до 60 секунд пока модель загрузится
            for attempt in 1...60 {
                try await Task.sleep(nanoseconds: ServiceConstants.WaitIntervals.oneSecond)
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
                throw TranscriptionError.serviceNotInitialized("BatchTranscriptionService")
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

            // Используем базовый контекстный промпт если указан
            let baseContextPrompt = self.userSettings.baseContextPrompt
            let contextPrompt = baseContextPrompt.isEmpty ? nil : baseContextPrompt
            let text = try await whisperService.transcribe(audioSamples: audioSamples, contextPrompt: contextPrompt)

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

    /// Транскрибирует аудио/видео файл без разделения дикторов (простой режим)
    ///
    /// Упрощенный метод для транскрипции без структурированного диалога.
    /// Подходит для моно файлов или когда не требуется разделение дикторов.
    ///
    /// ## Процесс:
    /// 1. Ожидание готовности Whisper модели (до 60 секунд)
    /// 2. Загрузка аудио в формат WhisperKit (16kHz mono Float32)
    /// 3. Проверка на тишину с помощью SilenceDetector
    /// 4. Транскрипция всего файла одним блоком
    ///
    /// ## Отличия от `transcribeFileWithDialogue()`:
    /// - ❌ Нет разделения на дикторов
    /// - ❌ Нет временных меток для сегментов
    /// - ❌ Нет real-time прогресса
    /// - ✅ Быстрее для коротких файлов
    /// - ✅ Проще результат (plain text)
    ///
    /// - Parameter url: URL аудио/видео файла для транскрипции
    /// - Returns: Полный текст транскрипции
    /// - Throws:
    ///   - `WhisperError.modelNotLoaded` - модель не загрузилась за 60 секунд
    ///   - `TranscriptionError.silenceDetected` - файл содержит только тишину
    ///   - `TranscriptionError.emptyTranscription` - Whisper вернул пустой результат
    ///   - `TranscriptionError.audioLoadFailed` - ошибка загрузки файла
    ///
    /// ## Пример:
    /// ```swift
    /// // Простая транскрипция
    /// let text = try await service.transcribeFile(at: audioURL)
    /// print("Transcription: \(text)")
    /// ```
    ///
    /// - Warning: Для стерео файлов все каналы будут смешаны в моно. Используйте `transcribeFileWithDialogue()` для разделения дикторов.
    /// - Note: Рекомендуется использовать `transcribeFileWithDialogue()` для телефонных записей
    public func transcribeFile(at url: URL) async throws -> String {
        LogManager.app.begin("Транскрипция файла: \(url.lastPathComponent)")

        // Проверяем готовность модели Whisper
        if !whisperService.isReady {
            LogManager.app.error("Модель Whisper не загружена, ожидание...")
            // Ждём до 60 секунд пока модель загрузится
            for attempt in 1...60 {
                try await Task.sleep(nanoseconds: ServiceConstants.WaitIntervals.oneSecond)
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
            throw TranscriptionError.silenceDetected(url)
        }

        // 3. Транскрибируем
        let transcription = try await whisperService.transcribe(audioSamples: audioSamples)

        if transcription.isEmpty {
            throw TranscriptionError.emptyTranscription(url)
        }

        LogManager.app.success("Транскрипция файла завершена: \(transcription.count) символов")
        return transcription
    }

    /// Загружает аудио из файла и конвертирует в формат WhisperKit (16kHz mono Float32)
    /// - Parameter url: URL файла
    /// - Returns: Массив audio samples
    /// - Throws: Ошибки загрузки или конвертации
    private func loadAudio(from url: URL) async throws -> [Float] {
        // Используем AudioCache для предотвращения повторной загрузки
        let cachedAudio = try await audioCache.loadAudio(from: url)

        let isCached = await audioCache.isCached(url)
        if isCached {
            LogManager.app.debug("Аудио загружено из кэша: \(url.lastPathComponent)")
        } else {
            let durationSeconds = Float(cachedAudio.monoSamples.count) / 16000.0
            LogManager.app.success("Файл загружен: \(cachedAudio.monoSamples.count) samples, \(String(format: "%.1f", durationSeconds))s")
        }

        return cachedAudio.monoSamples
    }

    /// Получает количество аудио каналов в файле
    private func getChannelCount(from url: URL) async throws -> Int {
        let asset = AVAsset(url: url)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw TranscriptionError.noAudioTrack(url)
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

    /// Сливает соседние сегменты одного спикера с коротким промежутком
    /// - Parameters:
    ///   - segments: Массив сегментов для слияния (должен быть отсортирован по времени)
    ///   - maxGap: Максимальный промежуток между сегментами для слияния (в секундах)
    /// - Returns: Массив слитых сегментов
    private func mergeAdjacentSegments(_ segments: [ChannelSegment], maxGap: TimeInterval) -> [ChannelSegment] {
        guard segments.count > 1 else { return segments }

        var merged: [ChannelSegment] = []
        var currentSegment = segments[0]

        for i in 1..<segments.count {
            let nextSegment = segments[i]

            // Проверка: тот же спикер и промежуток < maxGap
            let gap = nextSegment.segment.startTime - currentSegment.segment.endTime
            if currentSegment.speaker == nextSegment.speaker && gap < maxGap {
                // Слияние: объединяем аудио и расширяем временные рамки
                let mergedAudio = currentSegment.audioSamples + nextSegment.audioSamples
                currentSegment = ChannelSegment(
                    segment: SpeechSegment(
                        startTime: currentSegment.segment.startTime,
                        endTime: nextSegment.segment.endTime
                    ),
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

    /// Транскрибирует стерео файл как диалог (левый и правый каналы отдельно)
    /// УЛУЧШЕННЫЙ АЛГОРИТМ: обрабатывает сегменты в шахматном порядке по времени,
    /// используя предыдущий диалог как контекст для улучшения качества распознавания
    private func transcribeStereoAsDialogue(url: URL) async throws -> DialogueTranscription {
        LogManager.app.info("🎧 Стерео режим: разделяем каналы для определения дикторов")

        // Проверяем отмену перед началом обработки
        try Task.checkCancellation()

        // 1. Подготовка: загрузка и разделение стерео каналов
        let (leftChannel, rightChannel, totalDuration) = try await prepareStereoChanels(from: url)

        // Проверяем отмену перед VAD анализом
        try Task.checkCancellation()

        // 2. VAD анализ: обнаружение и объединение сегментов речи
        let allSegments = try await detectAndMergeStereoSegments(
            left: leftChannel,
            right: rightChannel
        )

        // 3. Транскрипция: обработка сегментов в хронологическом порядке
        let turns = try await transcribeSegmentsInOrder(
            allSegments,
            fileName: url.lastPathComponent,
            totalDuration: totalDuration
        )

        LogManager.app.success("Стерео транскрипция завершена: \(turns.count) реплик (обработаны в хронологическом порядке)")

        return DialogueTranscription(turns: turns, isStereo: true, totalDuration: totalDuration)
    }

    /// Подготовка стерео каналов: загрузка и разделение аудио
    /// - Parameter url: URL аудио файла
    /// - Returns: Кортеж из левого канала, правого канала и общей длительности
    private func prepareStereoChanels(from url: URL) async throws -> (left: [Float], right: [Float], duration: TimeInterval) {
        // Загружаем стерео аудио
        let stereoSamples = try await loadAudioStereo(from: url)

        // Разделяем на левый и правый каналы
        let leftChannel = extractChannel(from: stereoSamples, channel: 0)
        let rightChannel = extractChannel(from: stereoSamples, channel: 1)

        // Определяем общую длительность (16kHz sample rate)
        let totalDuration = TimeInterval(leftChannel.count) / 16000.0

        return (leftChannel, rightChannel, totalDuration)
    }

    /// Обнаружение и объединение речевых сегментов из обоих стерео каналов
    /// - Parameters:
    ///   - left: Левый аудио канал
    ///   - right: Правый аудио канал
    /// - Returns: Массив сегментов, отсортированных по времени
    private func detectAndMergeStereoSegments(
        left: [Float],
        right: [Float]
    ) async throws -> [ChannelSegment] {
        // VAD анализ левого канала
        LogManager.app.info("🎤 VAD: анализ левого канала (алгоритм: \(self.vadAlgorithmName))...")
        let leftSegments = detectSegments(in: left)
        LogManager.app.info("Найдено \(leftSegments.count) сегментов речи в левом канале")

        // VAD анализ правого канала
        LogManager.app.info("🎤 VAD: анализ правого канала (алгоритм: \(self.vadAlgorithmName))...")
        let rightSegments = detectSegments(in: right)
        LogManager.app.info("Найдено \(rightSegments.count) сегментов речи в правом канале")

        // Объединяем сегменты из обоих каналов
        var allSegments: [ChannelSegment] = []

        // Добавляем левые сегменты
        for segment in leftSegments {
            let audio = extractSegmentAudio(segment, from: left)
            allSegments.append(ChannelSegment(
                segment: segment,
                channel: 0,
                speaker: DialogueTranscription.Turn.Speaker.left,
                audioSamples: audio
            ))
        }

        // Добавляем правые сегменты
        for segment in rightSegments {
            let audio = extractSegmentAudio(segment, from: right)
            allSegments.append(ChannelSegment(
                segment: segment,
                channel: 1,
                speaker: DialogueTranscription.Turn.Speaker.right,
                audioSamples: audio
            ))
        }

        // Сортируем по времени для хронологической обработки
        allSegments.sort(by: { $0.segment.startTime < $1.segment.startTime })
        LogManager.app.info("🔄 Сегменты отсортированы по времени для последовательной обработки (\(allSegments.count) всего)")

        // Post-VAD merge: сливаем соседние сегменты одного спикера с коротким промежутком
        let segmentCountBefore = allSegments.count
        allSegments = mergeAdjacentSegments(allSegments, maxGap: self.userSettings.postVADMergeThreshold)
        let segmentCountAfter = allSegments.count
        if segmentCountBefore != segmentCountAfter {
            LogManager.app.info("🔗 Post-VAD merge: \(segmentCountBefore) → \(segmentCountAfter) сегментов (порог: \(String(format: "%.1f", self.userSettings.postVADMergeThreshold))с)")
        }

        return allSegments
    }

    /// Транскрибирует сегменты в хронологическом порядке с контекстом
    /// - Parameters:
    ///   - segments: Отсортированный массив сегментов для обработки
    ///   - fileName: Имя файла для логирования
    ///   - totalDuration: Общая длительность для обновления прогресса
    /// - Returns: Массив обработанных реплик диалога
    private func transcribeSegmentsInOrder(
        _ segments: [ChannelSegment],
        fileName: String,
        totalDuration: TimeInterval
    ) async throws -> [DialogueTranscription.Turn] {
        var turns: [DialogueTranscription.Turn] = []
        let totalSegments = segments.count
        var processedSegments = 0

        for channelSegment in segments {
            // Проверяем отмену перед обработкой каждого сегмента
            try Task.checkCancellation()

            let segment = channelSegment.segment
            let speaker = channelSegment.speaker
            let segmentAudio = channelSegment.audioSamples

            // Пропускаем сегменты с тишиной
            if SilenceDetector.shared.isSilence(segmentAudio) {
                continue
            }

            // Формируем контекст из последних N реплик (используем настройку)
            let contextPrompt = buildContextPrompt(from: turns)

            let speakerName = speaker == .left ? "Speaker 1" : "Speaker 2"
            LogManager.app.info("Транскрибируем \(speakerName): \(String(format: "%.1f", segment.startTime))s - \(String(format: "%.1f", segment.endTime))s (контекст: \(contextPrompt.isEmpty ? "нет" : "\(contextPrompt.count) символов"))")

            // Транскрибируем с контекстом
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
                onProgressUpdate?(fileName, progress, partialDialogue)
            } else {
                LogManager.app.warning("\(speakerName): пустой текст для сегмента \(String(format: "%.1f", segment.startTime))s")
            }
        }

        return turns
    }

    /// Извлекает именованные сущности (имена, компании) из реплик диалога
    /// - Parameter turns: Массив реплик для анализа
    /// - Returns: Массив уникальных сущностей
    private func extractNamedEntities(from turns: [DialogueTranscription.Turn]) -> [String] {
        // Используем кэшированное регулярное выражение для производительности
        guard let regex = Self.entityExtractionRegex else {
            LogManager.app.warning("Entity extraction regex не инициализирован")
            return []
        }

        // Стоп-слова для фильтрации (общие слова в начале предложений)
        let stopWords: Set<String> = [
            "The", "And", "Or", "But", "If", "When", "Where", "Who", "What", "Why", "How",
            "Speaker", "Yes", "No", "Ok", "Okay", "Well", "So", "Then", "Now", "Here", "There",
            "This", "That", "These", "Those", "He", "She", "It", "They", "We", "You", "I"
        ]

        var entities = Set<String>()

        // Извлекаем сущности только из последних N реплик (оптимизация памяти и релевантности)
        let recentTurnsForEntities = Array(turns.suffix(ContextOptimizationConstants.maxRecentTurnsForEntityExtraction))

        for turn in recentTurnsForEntities {
            let text = turn.text
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)

            for match in matches {
                if let matchRange = Range(match.range, in: text) {
                    let entity = String(text[matchRange])
                    // Фильтруем стоп-слова
                    if !stopWords.contains(entity) {
                        entities.insert(entity)
                    }
                }
            }
        }

        return Array(entities).sorted() // Возвращаем отсортированный массив
    }

    /// НОВОЕ: Формирует контекстный промпт из предыдущих реплик диалога
    /// Помогает Whisper лучше распознавать имена, термины и контекст разговора
    private func buildContextPrompt(from turns: [DialogueTranscription.Turn], maxTurns: Int? = nil) -> String {
        var contextParts: [String] = []
        var debugStats = (base: 0, entities: 0, vocab: 0, turns: 0)

        // Добавляем базовый контекстный промпт если указан
        let baseContextPrompt = self.userSettings.baseContextPrompt
        if !baseContextPrompt.isEmpty {
            contextParts.append(baseContextPrompt)
            debugStats.base = baseContextPrompt.count
        }

        // Извлекаем именованные сущности если включено
        if self.userSettings.enableEntityExtraction && !turns.isEmpty {
            let entities = extractNamedEntities(from: turns)
            if !entities.isEmpty {
                let entitiesContext = "Named entities: " + entities.joined(separator: ", ")
                contextParts.append(entitiesContext)
                debugStats.entities = entities.count
            }
        }

        // Интегрируем термины из словаря если включено
        var vocabularyTermsCount = 0
        if self.userSettings.enableVocabularyIntegration {
            let vocabularyWords = self.userSettings.getEnabledVocabularyWords()
            if !vocabularyWords.isEmpty {
                // Ограничиваем количество терминов для сохранения места в контексте
                let limitedWords = Array(vocabularyWords.prefix(ContextOptimizationConstants.maxVocabularyTermsInContext))
                let vocabularyContext = "Vocabulary: " + limitedWords.joined(separator: ", ")
                contextParts.append(vocabularyContext)
                vocabularyTermsCount = limitedWords.count
                debugStats.vocab = vocabularyTermsCount
            }
        }

        // Берем последние N реплик (используем настройку или переданное значение)
        let turnsToTake = maxTurns ?? self.userSettings.maxRecentTurns
        let recentTurns = Array(turns.suffix(turnsToTake))

        if !recentTurns.isEmpty {
            // Формируем контекст в виде диалога
            let dialogueContext = recentTurns.map { turn in
                let speakerName = turn.speaker == .left ? "Speaker 1" : "Speaker 2"
                return "\(speakerName): \(turn.text)"
            }.joined(separator: " ")
            contextParts.append(dialogueContext)
            debugStats.turns = recentTurns.count
        }

        // Объединяем все части контекста
        let fullContext = contextParts.joined(separator: ". ")

        // Ограничиваем длину контекста используя настройку maxContextLength
        let maxLength = self.userSettings.maxContextLength
        if fullContext.count > maxLength {
            // Умное усечение по границе слова с Unicode-безопасностью
            guard let targetIndex = fullContext.index(fullContext.startIndex, offsetBy: maxLength, limitedBy: fullContext.endIndex) else {
                // Edge case: maxLength больше длины строки (не должно происходить, но безопасность)
                return fullContext
            }

            let searchRange = fullContext.startIndex..<targetIndex

            // Ищем последний пробел перед лимитом
            if let lastSpaceRange = fullContext.range(of: " ", options: .backwards, range: searchRange) {
                // Обрезаем по последнему пробелу
                let truncated = String(fullContext[..<lastSpaceRange.lowerBound])
                let finalLength = truncated.count
                LogManager.transcription.debug("Context truncated: base=\(debugStats.base)ch, entities=\(debugStats.entities), vocab=\(debugStats.vocab), turns=\(debugStats.turns), \(fullContext.count)ch → \(finalLength)ch")
                return truncated + "..."
            } else {
                // Edge case: нет пробелов - обрезаем по лимиту с Unicode-безопасностью
                // limitedBy гарантирует, что не обрежем посреди grapheme cluster (emoji, диакритики)
                let safeIndex = fullContext.index(fullContext.startIndex, offsetBy: maxLength, limitedBy: fullContext.endIndex) ?? fullContext.endIndex
                let truncated = String(fullContext[..<safeIndex])
                LogManager.transcription.debug("Context truncated (no spaces): base=\(debugStats.base)ch, entities=\(debugStats.entities), vocab=\(debugStats.vocab), turns=\(debugStats.turns), \(fullContext.count)ch → \(truncated.count)ch")
                return truncated + "..."
            }
        }

        // Логируем статистику построения контекста для отладки качества
        LogManager.transcription.debug("Context built: base=\(debugStats.base)ch, entities=\(debugStats.entities), vocab=\(debugStats.vocab), turns=\(debugStats.turns), final=\(fullContext.count)ch")

        return fullContext
    }

    /// Загружает стерео аудио (сохраняя оба канала)
    private func loadAudioStereo(from url: URL) async throws -> [[Float]] {
        // Используем AudioCache для предотвращения повторной загрузки
        let cachedAudio = try await audioCache.loadAudio(from: url)

        let isCached = await audioCache.isCached(url)
        if isCached {
            LogManager.app.debug("Стерео аудио загружено из кэша: \(url.lastPathComponent)")
        }

        // Проверяем, что файл действительно stereo
        guard cachedAudio.isStereo, let stereoChannels = cachedAudio.stereoChannels else {
            throw TranscriptionError.notStereoFile(url)
        }

        // Возвращаем interleaved формат для совместимости с существующим кодом
        // Преобразуем (left, right) обратно в interleaved [L, R, L, R, ...]
        var interleavedSamples: [Float] = []
        interleavedSamples.reserveCapacity(stereoChannels.left.count * 2)

        for i in 0..<stereoChannels.left.count {
            interleavedSamples.append(stereoChannels.left[i])
            if i < stereoChannels.right.count {
                interleavedSamples.append(stereoChannels.right[i])
            }
        }

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

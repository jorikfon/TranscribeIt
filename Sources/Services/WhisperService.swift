import Foundation
import WhisperKit
import Metal

/// Сервис для транскрипции аудио через WhisperKit с поддержкой Metal GPU и Neural Engine
///
/// Предоставляет on-device транскрипцию аудио с использованием оптимизированных моделей Whisper
/// для Apple Silicon. Поддерживает автоматическую нормализацию аудио, контекстные промпты
/// и vocabulary corrections для улучшения качества распознавания.
///
/// ## Поддерживаемые модели
/// - `tiny` - Самая быстрая, базовая точность (~39M параметров)
/// - `base` - Баланс скорости и точности (~74M параметров)
/// - `small` - Хорошая точность (~244M параметров) - рекомендуется
/// - `medium` - Высокая точность (~769M параметров)
/// - `large` - Максимальная точность (~1550M параметров)
///
/// ## Оптимизация производительности
/// - **Metal GPU**: Используется для mel-спектрограмм
/// - **Neural Engine**: Используется для encoder/decoder/prefill
/// - **Unified Memory**: Эффективное использование памяти Apple Silicon
/// - **Prewarm**: Предварительный прогрев модели для быстрого первого запуска
///
/// ## Возможности
/// - Автоматическая нормализация тихого аудио
/// - Контекстные промпты для улучшения связности текста
/// - Vocabulary corrections через VocabularyManager
/// - Performance metrics (RTF - Real-Time Factor)
/// - Поддержка различных языков
/// - Кэширование моделей для быстрой загрузки
///
/// ## Example
/// ```swift
/// let whisperService = WhisperService(
///     modelSize: "small",
///     vocabularyManager: VocabularyManager.shared
/// )
///
/// // Загрузка модели
/// try await whisperService.loadModel()
///
/// // Транскрипция аудио
/// let audioSamples: [Float] = // ... 16kHz mono audio
/// let text = try await whisperService.transcribe(
///     audioSamples: audioSamples,
///     contextPrompt: "Previous dialogue context"
/// )
/// print("Transcribed: \(text)")
/// print("RTF: \(whisperService.averageRTF)")
/// ```
///
/// ## Performance
/// Типичный Real-Time Factor (RTF) на Apple Silicon:
/// - M1/M2/M3 + tiny: 0.05-0.1x (20x быстрее реального времени)
/// - M1/M2/M3 + small: 0.15-0.3x (3-7x быстрее реального времени)
/// - M1/M2/M3 + medium: 0.4-0.8x (1.2-2.5x быстрее реального времени)
///
/// ## Thread Safety
/// WhisperService не является thread-safe. Используйте один экземпляр на последовательную очередь
/// или защищайте доступ через actor/locks.
public class WhisperService {
    private var whisperKit: WhisperKit?
    private var modelSize: String  // Изменено с let на var для возможности смены модели
    private let vocabularyManager: VocabularyManagerProtocol
    private let audioNormalizer = AudioNormalizer(parameters: .default)

    // Prompt для специальных терминов и контекста
    public var promptText: String? = nil

    // Включить нормализацию аудио (по умолчанию включено)
    public var enableNormalization: Bool = true

    // Performance metrics
    public private(set) var lastTranscriptionTime: TimeInterval = 0
    public private(set) var averageRTF: Double = 0  // Real-Time Factor
    private var transcriptionCount: Int = 0
    private var totalRTF: Double = 0

    // GPU/Neural Engine status
    public private(set) var isMetalAvailable: Bool = false
    public private(set) var isNeuralEngineAvailable: Bool = false
    public private(set) var gpuName: String = "Unknown"

    /// Размер текущей модели
    public var currentModelSize: String {
        return modelSize
    }

    public init(
        modelSize: String,
        vocabularyManager: VocabularyManagerProtocol
    ) {
        self.modelSize = modelSize
        self.vocabularyManager = vocabularyManager
        LogManager.transcription.info("Инициализация WhisperService с моделью \(modelSize)")
    }

    /// Перезагружает WhisperKit с новой моделью
    ///
    /// Освобождает текущую модель из памяти и загружает новую. Полезно для переключения
    /// между моделями во время работы приложения (например, с small на medium для лучшей точности).
    ///
    /// - Parameter newModelSize: Размер новой модели (tiny, base, small, medium, large)
    /// - Throws: `WhisperError.modelLoadFailed` если загрузка новой модели не удалась
    ///
    /// ## Example
    /// ```swift
    /// // Переключение на более точную модель
    /// try await whisperService.reloadModel(newModelSize: "medium")
    /// ```
    ///
    /// - Note: Если модель уже загружена, метод ничего не делает
    /// - Note: После смены модели сбрасывается статистика производительности
    public func reloadModel(newModelSize: String) async throws {
        guard newModelSize != modelSize else {
            LogManager.transcription.info("Модель \(newModelSize) уже загружена, перезагрузка не требуется")
            return
        }

        LogManager.transcription.begin("Смена модели", details: "\(modelSize) → \(newModelSize)")

        // Освобождаем старую модель
        whisperKit = nil

        // Обновляем размер
        modelSize = newModelSize

        // Загружаем новую модель
        try await loadModel()

        // Сбрасываем статистику
        resetPerformanceStats()

        LogManager.transcription.success("Модель успешно сменена на \(newModelSize)")
    }

    /// Загружает модель Whisper с максимальной оптимизацией для Apple Silicon
    ///
    /// Инициализирует WhisperKit с указанной моделью, используя Neural Engine и Metal GPU
    /// для максимальной производительности. Модели загружаются из Hugging Face и кэшируются
    /// локально в `~/Library/Application Support/TranscribeIt/Models/`.
    ///
    /// - Throws: `WhisperError.modelLoadFailed` если загрузка модели не удалась
    ///
    /// ## Compute Options
    /// - Mel спектрограмма: CPU + GPU
    /// - Audio encoder: CPU + Neural Engine
    /// - Text decoder: CPU + Neural Engine
    /// - Prefill: CPU + Neural Engine
    ///
    /// ## Example
    /// ```swift
    /// let service = WhisperService(modelSize: "small", vocabularyManager: VocabularyManager.shared)
    /// try await service.loadModel()
    /// // Модель готова к использованию
    /// ```
    ///
    /// - Note: Первая загрузка модели занимает время (скачивание с Hugging Face)
    /// - Note: Повторные запуски используют кэшированную модель и загружаются быстрее
    public func loadModel() async throws {
        LogManager.transcription.begin("Загрузка модели", details: modelSize)

        // Используем постоянный путь для кэша моделей
        // Это позволяет переиспользовать модели между запусками
        let modelsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TranscribeIt/Models")

        // Создаём директорию если её нет
        try? FileManager.default.createDirectory(at: modelsPath, withIntermediateDirectories: true)

        LogManager.transcription.info("Путь к моделям: \(modelsPath.path)")

        // Настройка вычислительных юнитов для максимальной производительности на M1 MAX
        // Используем Neural Engine для всех компонентов где возможно
        let computeOptions = ModelComputeOptions(
            melCompute: .cpuAndGPU,              // Mel спектрограмма - GPU
            audioEncoderCompute: .cpuAndNeuralEngine,  // Audio encoder - Neural Engine
            textDecoderCompute: .cpuAndNeuralEngine,   // Text decoder - Neural Engine
            prefillCompute: .cpuAndNeuralEngine        // Prefill - Neural Engine
        )

        do {
            // Инициализация WhisperKit с указанной моделью и путём к кэшу
            // Модель будет загружена автоматически с Hugging Face если её нет локально
            whisperKit = try await WhisperKit(
                model: modelSize,
                downloadBase: modelsPath,  // Используем постоянный путь
                modelRepo: "argmaxinc/whisperkit-coreml",
                computeOptions: computeOptions,
                verbose: true,
                logLevel: .debug,
                prewarm: true  // Предварительный прогрев модели для быстрого первого запуска
            )

            LogManager.transcription.success("Модель загружена", details: modelSize)

            // Проверка Metal acceleration и Neural Engine
            verifyMetalAcceleration()
        } catch {
            LogManager.transcription.failure("Загрузка модели", error: error)
            throw WhisperError.modelLoadFailed(underlying: error, modelSize: modelSize)
        }
    }

    /// Проверка использования Metal GPU acceleration и Neural Engine
    private func verifyMetalAcceleration() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            LogManager.transcription.error("Metal GPU не доступен")
            isMetalAvailable = false
            isNeuralEngineAvailable = false
            gpuName = "None"
            return
        }

        // Сохраняем статус GPU
        isMetalAvailable = true
        gpuName = device.name
        isNeuralEngineAvailable = device.supportsFamily(.apple7) // M1 и новее

        let memoryGB = device.recommendedMaxWorkingSetSize / 1024 / 1024 / 1024
        let isAppleSilicon = device.supportsFamily(.apple7)
        let maxThreads = device.maxThreadsPerThreadgroup

        LogManager.transcription.info("🚀 Apple Silicon Acceleration")
        LogManager.transcription.info("  GPU: \(device.name)")
        LogManager.transcription.info("  Unified Memory: \(memoryGB)GB")
        LogManager.transcription.info("  Metal: \(isAppleSilicon ? "✅" : "❌") Apple Silicon")
        LogManager.transcription.info("  Neural Engine: \(isNeuralEngineAvailable ? "✅ Enabled (All components)" : "❌")")
        LogManager.transcription.info("  Compute Units: Mel=GPU, Encoder/Decoder/Prefill=ANE")
        LogManager.transcription.debug("  Max threads: \(maxThreads.width)×\(maxThreads.height)×\(maxThreads.depth)")

        if device.name.contains("M1") {
            LogManager.transcription.info("  🔥 M1 detected - using all performance cores + Neural Engine")
        } else if device.name.contains("M2") || device.name.contains("M3") {
            LogManager.transcription.info("  🔥 \(device.name) detected - maximum performance mode")
        }
    }

    /// Быстрая транскрипция аудио чанка для real-time отображения
    ///
    /// Использует упрощенные настройки для максимальной скорости: greedy decoding (topK=1),
    /// без beam search, детерминированный вывод. Предназначен для быстрой предварительной
    /// транскрипции во время записи или потоковой обработки.
    ///
    /// - Parameter audioSamples: Массив Float32 аудио сэмплов в формате 16kHz mono
    /// - Returns: Распознанный текст с применением vocabulary corrections
    /// - Throws: `WhisperError.modelNotLoaded` если модель не загружена
    ///
    /// ## Example
    /// ```swift
    /// // Транскрипция короткого чанка аудио
    /// let chunk: [Float] = // ... 3 секунды аудио (48000 samples @ 16kHz)
    /// let quickResult = try await whisperService.transcribeChunk(audioSamples: chunk)
    /// print("Quick transcription: \(quickResult)")
    /// ```
    ///
    /// - Note: Для финальной высококачественной транскрипции используйте `transcribe(audioSamples:contextPrompt:)`
    /// - Note: Автоматически применяется нормализация для тихого аудио
    public func transcribeChunk(audioSamples: [Float]) async throws -> String {
        guard let whisperKit = whisperKit else {
            throw WhisperError.modelNotLoaded
        }

        // Нормализация аудио перед транскрипцией
        var processedSamples = audioSamples
        if enableNormalization {
            let stats = audioNormalizer.analyze(audioSamples)
            if stats.isQuiet {
                LogManager.transcription.info("Тихое аудио обнаружено (RMS=\(stats.rms)), применяем нормализацию")
                processedSamples = audioNormalizer.normalize(audioSamples)
            }
        }

        // Для real-time НЕ используем Quality Enhancement (слишком медленно)
        // Оставляем только базовые настройки для скорости
        let settings = UserSettings.shared
        let prefillPrompt = settings.buildFullPrefillPrompt()
        let usePrefill = !prefillPrompt.isEmpty

        let options = DecodingOptions(
            task: .transcribe,        // TRANSCRIBE, не translate!
            language: settings.transcriptionLanguage,  // Язык из настроек
            temperature: 0.0,         // Детерминированный вывод
            topK: 1,                  // Greedy decoding для скорости (НЕ beam search в real-time)
            usePrefillPrompt: usePrefill,   // Контекст из словарей если есть
            usePrefillCache: usePrefill,    // Кэширование контекста
            detectLanguage: false     // Отключаем автодетект, используем язык из настроек
        )

        let results = try await whisperKit.transcribe(
            audioArray: processedSamples,
            decodeOptions: options
        )

        guard let firstResult = results.first else {
            return ""
        }

        let transcription = firstResult.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        // Apply vocabulary corrections
        let correctedText = vocabularyManager.correctTranscription(transcription)

        return correctedText
    }

    /// Транскрибирует аудио данные с опциональным контекстным промптом
    ///
    /// Выполняет высококачественную транскрипцию с использованием beam search и quality enhancement.
    /// Контекстный промпт используется для улучшения связности текста между соседними сегментами
    /// диалога (например, передавая текст предыдущих реплик для лучшего распознавания имен и терминов).
    ///
    /// - Parameters:
    ///   - audioSamples: Массив Float32 аудио сэмплов в формате 16kHz mono
    ///   - contextPrompt: Опциональный промпт с предыдущим контекстом (макс 224 токена)
    /// - Returns: Распознанный текст с применением vocabulary corrections
    /// - Throws: `WhisperError.modelNotLoaded` если модель не загружена
    ///
    /// ## Example
    /// ```swift
    /// // Транскрипция с контекстом предыдущего диалога
    /// let previousContext = "Иван: Здравствуйте. Мария: Добрый день, Иван."
    /// let audioSamples: [Float] = // ... аудио следующей реплики
    /// let text = try await whisperService.transcribe(
    ///     audioSamples: audioSamples,
    ///     contextPrompt: previousContext
    /// )
    /// ```
    ///
    /// ## Performance
    /// - Включает quality enhancement для лучшей точности
    /// - Использует beam search (топ-5 кандидатов)
    /// - Применяет префильный кэш для ускорения повторных вызовов
    /// - Автоматическая нормализация тихого аудио
    ///
    /// - Note: Контекстный промпт временно заменяет `promptText` на время транскрипции
    /// - Note: После транскрипции обновляются метрики производительности (RTF)
    public func transcribe(audioSamples: [Float], contextPrompt: String? = nil) async throws -> String {
        // Токенизируем контекстный промпт если передан
        var promptTokens: [Int]? = nil
        if let context = contextPrompt, !context.isEmpty {
            if let tokenizer = whisperKit?.tokenizer {
                promptTokens = tokenizer.encode(text: context)
                LogManager.transcription.debug("Токенизирован контекстный промпт: \(promptTokens?.count ?? 0) токенов из \(context.count) символов: \"\(context.prefix(100))...\"")
            } else {
                LogManager.transcription.warning("Tokenizer недоступен, контекстный промпт будет проигнорирован")
            }
        }

        // Вызываем основную транскрипцию с токенизированным промптом
        let result = try await transcribeInternal(audioSamples: audioSamples, promptTokens: promptTokens)

        return result
    }

    /// Транскрипция аудио данных с измерением производительности (внутренний метод)
    /// - Parameters:
    ///   - audioSamples: Массив Float32 аудио сэмплов (16kHz mono)
    ///   - promptTokens: Опциональный массив токенов для контекстного промпта
    /// - Returns: Распознанный текст
    private func transcribeInternal(audioSamples: [Float], promptTokens: [Int]? = nil) async throws -> String {
        // Проверяем отмену перед началом транскрипции
        try Task.checkCancellation()

        guard let whisperKit = whisperKit else {
            LogManager.transcription.failure("Транскрипция", message: "Модель не загружена")
            throw WhisperError.modelNotLoaded
        }

        let sampleCount = audioSamples.count
        let audioDuration = Double(sampleCount) / 16000.0  // 16kHz sample rate

        LogManager.transcription.begin("Транскрипция", details: "\(sampleCount) samples, \(String(format: "%.2f", audioDuration))s")

        // Нормализация аудио перед транскрипцией
        var processedSamples = audioSamples
        if enableNormalization {
            let stats = audioNormalizer.analyze(audioSamples)
            LogManager.transcription.debug("Аудио статистика: peak=\(String(format: "%.3f", stats.peak)), rms=\(String(format: "%.3f", stats.rms))")

            if stats.isQuiet {
                LogManager.transcription.info("Тихое аудио обнаружено (RMS=\(String(format: "%.3f", stats.rms))), применяем нормализацию")
                processedSamples = audioNormalizer.normalize(audioSamples)

                let normalizedStats = audioNormalizer.analyze(processedSamples)
                LogManager.transcription.success("Нормализация завершена: RMS \(String(format: "%.3f", stats.rms)) → \(String(format: "%.3f", normalizedStats.rms))")
            } else {
                LogManager.transcription.debug("Громкость аудио достаточная, нормализация не требуется")
            }
        }

        let startTime = Date()

        do {
            // ОПТИМАЛЬНЫЕ настройки для СМЕШАННОЙ речи (RU+EN)
            // Применяем режим повышения качества если включен
            let settings = UserSettings.shared
            let useQualityMode = settings.useQualityEnhancement

            // Получаем префилл промпт из словарей и кастомного текста
            let prefillPrompt = settings.buildFullPrefillPrompt()
            let usePrefill = !prefillPrompt.isEmpty

            let options = DecodingOptions(
                task: .transcribe,      // transcribe (не translate!)
                language: settings.transcriptionLanguage,  // Язык из настроек (по умолчанию "ru")
                temperature: 0.0,       // Детерминированный вывод
                temperatureIncrementOnFallback: useQualityMode && settings.useTemperatureFallback ? 0.2 : 0.0,
                temperatureFallbackCount: useQualityMode && settings.useTemperatureFallback ? 5 : 0,
                topK: useQualityMode ? 5 : 1,  // Beam search: 5 beams vs greedy (1)
                usePrefillPrompt: usePrefill,   // Используем prefill если есть словари/промпт
                usePrefillCache: usePrefill,    // Кэширование prefill
                detectLanguage: false,          // Отключаем автодетект, используем язык из настроек
                promptTokens: promptTokens,     // Контекстный промпт в виде токенов
                compressionRatioThreshold: useQualityMode ? settings.compressionRatioThreshold : nil,
                logProbThreshold: useQualityMode ? settings.logProbThreshold : nil,
                noSpeechThreshold: useQualityMode ? 0.6 : nil  // Фильтр тишины
            )

            // Логирование настроек
            LogManager.transcription.info("🌐 Language: \(settings.transcriptionLanguage)")
            if let tokens = promptTokens, !tokens.isEmpty {
                LogManager.transcription.info("💬 Context prompt tokens: \(tokens.count)")
            }
            if !settings.selectedDictionaryIds.isEmpty {
                LogManager.transcription.info("📚 Active dictionaries: \(settings.selectedDictionaryIds.joined(separator: ", "))")
            }
            if !settings.customPrefillPrompt.isEmpty {
                LogManager.transcription.info("✏️  Custom prefill: \(settings.customPrefillPrompt.prefix(50))...")
            }

            if useQualityMode {
                LogManager.transcription.info("✨ Quality Enhancement Mode:")
                LogManager.transcription.info("  - Beam search: \(options.topK) beams")
                if settings.useTemperatureFallback {
                    LogManager.transcription.info("  - Temperature fallback: 0.0 → 1.0 (5 steps)")
                }
                LogManager.transcription.info("  - Compression ratio filter: \(settings.compressionRatioThreshold ?? 0.0)")
                LogManager.transcription.info("  - Log prob filter: \(settings.logProbThreshold ?? 0.0)")
            }

            // TODO: Добавить токенизацию промпта когда получим доступ к tokenizer
            if usePrefill {
                LogManager.transcription.debug("Prefill prompt (\(prefillPrompt.count) chars): \"\(prefillPrompt.prefix(100))...\"")
            }
            if let prompt = promptText, !prompt.isEmpty {
                LogManager.transcription.debug("Дополнительный промпт: \"\(prompt.prefix(50))...\"")
            }

            let results = try await whisperKit.transcribe(
                audioArray: processedSamples,
                decodeOptions: options
            )

            // Измеряем время транскрипции
            let transcriptionTime = Date().timeIntervalSince(startTime)
            lastTranscriptionTime = transcriptionTime

            // Вычисляем Real-Time Factor (RTF)
            // RTF = transcription_time / audio_duration
            // RTF < 1.0 = faster than real-time
            // RTF > 1.0 = slower than real-time
            let rtf = transcriptionTime / audioDuration
            transcriptionCount += 1
            totalRTF += rtf
            averageRTF = totalRTF / Double(transcriptionCount)

            // Получаем финальный текст из массива результатов
            guard let firstResult = results.first else {
                LogManager.transcription.failure("Транскрипция", message: "Пустой результат")
                return ""
            }

            let transcription = firstResult.text
            let cleanedText = transcription.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            // Apply vocabulary corrections
            let correctedText = vocabularyManager.correctTranscription(cleanedText)

            // Логирование производительности
            let speedMultiplier = audioDuration / transcriptionTime
            LogManager.transcription.success(
                "Транскрипция завершена",
                details: "\"\(correctedText)\" (\(String(format: "%.2f", transcriptionTime))s, RTF: \(String(format: "%.2f", rtf))x, \(String(format: "%.1f", speedMultiplier))x realtime)"
            )
            LogManager.transcription.debug("Avg RTF: \(String(format: "%.2f", self.averageRTF))x over \(self.transcriptionCount) transcriptions")

            if cleanedText != correctedText {
                LogManager.transcription.debug("Vocabulary correction applied: '\(cleanedText)' -> '\(correctedText)'")
            }

            return correctedText
        } catch {
            let elapsedTime = Date().timeIntervalSince(startTime)
            LogManager.transcription.failure("Транскрипция", error: error)
            throw WhisperError.transcriptionFailed(underlying: error, duration: elapsedTime)
        }
    }

    /// Получить статистику производительности
    public func getPerformanceStats() -> PerformanceStats {
        return PerformanceStats(
            lastTranscriptionTime: lastTranscriptionTime,
            averageRTF: averageRTF,
            transcriptionCount: transcriptionCount,
            modelSize: modelSize
        )
    }

    /// Сбросить статистику производительности
    public func resetPerformanceStats() {
        lastTranscriptionTime = 0
        averageRTF = 0
        transcriptionCount = 0
        totalRTF = 0
        LogManager.transcription.info("Статистика производительности сброшена")
    }

    /// Проверка готовности модели
    public var isReady: Bool {
        return whisperKit != nil
    }

    deinit {
        LogManager.transcription.info("WhisperService деинициализирован")
    }
}

// WhisperError определен в Sources/Errors/WhisperError.swift

/// Статистика производительности транскрипции
public struct PerformanceStats {
    public let lastTranscriptionTime: TimeInterval
    public let averageRTF: Double
    public let transcriptionCount: Int
    public let modelSize: String

    public var description: String {
        """
        Performance Statistics:
        - Model: \(modelSize)
        - Transcriptions: \(transcriptionCount)
        - Last Time: \(String(format: "%.2f", lastTranscriptionTime))s
        - Average RTF: \(String(format: "%.2f", averageRTF))x
        - Status: \(averageRTF < 1.0 ? "✓ Faster than realtime" : "⚠️ Slower than realtime")
        """
    }
}

import Foundation
import AVFoundation
import Combine

/// Менеджер для воспроизведения аудио файлов в FileTranscriptionWindow
/// Поддерживает навигацию по временным меткам (реплики диалога)
///
/// ## Управление состоянием
///
/// AudioPlayerManager использует единую структуру `AudioPlayerState` для управления всеми состояниями:
///
/// ```swift
/// let player = AudioPlayerManager(audioCache: cache)
///
/// // Управление воспроизведением
/// player.state.playback.isPlaying  // true/false
/// player.state.playback.currentTime  // 10.5
///
/// // Настройки аудио
/// player.state.audio.volume  // 0.0 - 1.0
/// player.state.audio.volumeBoost  // 1.0 - 5.0
///
/// // Настройки воспроизведения
/// player.state.settings.playbackRate  // 0.5 - 2.0
/// player.state.settings.monoMode  // true/false
/// ```
public class AudioPlayerManager: ObservableObject {
    /// Централизованное состояние аудио плеера
    ///
    /// Объединяет все @Published свойства в логические группы:
    /// - `playback`: состояние воспроизведения (isPlaying, currentTime, duration)
    /// - `audio`: настройки аудио (volume, volumeBoost)
    /// - `settings`: настройки воспроизведения (playbackRate, monoMode, pauseOtherPlayersEnabled)
    @Published public var state = AudioPlayerState()

    // AVAudioEngine для поддержки усиления громкости выше 100%
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let mixer = AVAudioMixerNode()
    private let stereoToMonoMixer = AVAudioMixerNode()  // Для конвертации стерео в моно

    private var audioFile: AVAudioFile?
    private var displayLink: Timer?
    private var audioFileURL: URL?
    private var audioFormat: AVAudioFormat?

    // Для отслеживания позиции воспроизведения
    private var startTime: TimeInterval = 0
    private var pauseTime: TimeInterval = 0

    // Audio cache для оптимизации загрузки
    private let audioCache: AudioCache

    public init(audioCache: AudioCache) {
        self.audioCache = audioCache
        LogManager.app.info("AudioPlayerManager: Инициализация")
        loadSettings()
        setupAudioEngine()
    }

    // MARK: - Audio Engine Setup

    /// Настройка AVAudioEngine с базовыми узлами обработки
    ///
    /// Создает граф обработки аудио:
    /// - playerNode: воспроизведение аудио файла
    /// - timePitch: изменение скорости воспроизведения
    /// - stereoToMonoMixer: конвертация стерео в моно (опционально)
    /// - mixer: управление громкостью с усилением
    ///
    /// - Note: Соединения между узлами устанавливаются в `loadAudio(from:)`
    ///         в зависимости от формата файла и настроек моно/стерео режима
    private func setupAudioEngine() {
        attachAudioNodes()
        configureMixerDefaults()
        LogManager.app.info("AudioPlayerManager: AVAudioEngine настроен")
    }

    /// Добавляет все необходимые узлы в аудио граф
    private func attachAudioNodes() {
        audioEngine.attach(playerNode)
        audioEngine.attach(timePitch)
        audioEngine.attach(stereoToMonoMixer)
        audioEngine.attach(mixer)
    }

    /// Устанавливает дефолтные значения для mixer узла
    private func configureMixerDefaults() {
        mixer.outputVolume = 1.0
    }

    /// Отключает все соединения между узлами перед переконфигурацией
    ///
    /// Вызывается перед настройкой нового аудио файла для очистки предыдущих соединений
    private func disconnectAllNodes() {
        audioEngine.disconnectNodeInput(timePitch)
        audioEngine.disconnectNodeInput(stereoToMonoMixer)
        audioEngine.disconnectNodeInput(mixer)
    }

    /// Настраивает граф обработки аудио в зависимости от формата файла
    ///
    /// Создает одну из двух конфигураций:
    /// - **Моно режим (стерео файл)**: playerNode → timePitch → stereoToMonoMixer → mixer → output
    /// - **Стерео/моно файл**: playerNode → timePitch → mixer → output
    ///
    /// - Parameters:
    ///   - format: Формат аудио файла (sample rate, количество каналов)
    ///   - isStereo: Является ли файл стерео (2+ канала)
    private func configureAudioGraph(format: AVAudioFormat, isStereo: Bool) {
        if state.settings.monoMode && isStereo {
            configureMonoModeGraph(format: format)
        } else {
            configureStereoModeGraph(format: format)
        }
    }

    /// Настраивает граф для моно режима (стерео → моно конвертация)
    ///
    /// Граф: playerNode → timePitch → stereoToMonoMixer → mixer → output
    ///
    /// - Parameter format: Формат стерео аудио файла
    private func configureMonoModeGraph(format: AVAudioFormat) {
        // playerNode → timePitch (стерео)
        audioEngine.connect(playerNode, to: timePitch, format: format)

        // Создаем моно формат для финального вывода
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!

        // timePitch → stereoToMonoMixer (стерео → моно)
        audioEngine.connect(timePitch, to: stereoToMonoMixer, format: format)

        // stereoToMonoMixer → mixer → output (моно)
        audioEngine.connect(stereoToMonoMixer, to: mixer, format: monoFormat)
        audioEngine.connect(mixer, to: audioEngine.mainMixerNode, format: monoFormat)

        LogManager.app.info("Моно режим включен: стерео -> моно")
    }

    /// Настраивает граф для стерео режима или моно файла (без конвертации)
    ///
    /// Граф: playerNode → timePitch → mixer → output
    ///
    /// - Parameter format: Формат аудио файла (стерео или моно)
    private func configureStereoModeGraph(format: AVAudioFormat) {
        // playerNode → timePitch → mixer → output
        audioEngine.connect(playerNode, to: timePitch, format: format)
        audioEngine.connect(timePitch, to: mixer, format: format)
        audioEngine.connect(mixer, to: audioEngine.mainMixerNode, format: format)

        LogManager.app.info("Стерео режим или моно файл")
    }

    /// Применяет текущие настройки к узлам аудио графа
    ///
    /// Синхронизирует состояние UI (playbackRate, volume, volumeBoost) с узлами AVAudioEngine
    private func applyCurrentSettings() {
        timePitch.rate = state.settings.playbackRate
        mixer.outputVolume = state.audio.effectiveVolume
    }

    /// Загрузка настроек из UserDefaults
    private func loadSettings() {
        state.settings.pauseOtherPlayersEnabled = UserDefaults.standard.object(forKey: "pauseOtherPlayersInTranscription") as? Bool ?? true

        if UserDefaults.standard.object(forKey: "pauseOtherPlayersInTranscription") == nil {
            UserDefaults.standard.set(true, forKey: "pauseOtherPlayersInTranscription")
        }
    }

    /// Сохранение настройки паузы других плееров
    public func savePauseOtherPlayersEnabled(_ enabled: Bool) {
        state.settings.pauseOtherPlayersEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "pauseOtherPlayersInTranscription")
        LogManager.app.info("AudioPlayerManager: Пауза других плееров \(enabled ? "включена" : "выключена")")
    }

    /// Загружает аудио файл для воспроизведения
    /// Файл должен быть уже нормализован через AudioFileNormalizer
    public func loadAudio(from url: URL) throws {
        // Если файл уже загружен, не загружаем заново
        if audioFileURL == url, audioFile != nil {
            LogManager.app.debug("AudioPlayerManager: Файл уже загружен, пропускаем")
            return
        }

        LogManager.app.info("AudioPlayerManager: Загрузка файла \(url.lastPathComponent)")

        // Останавливаем старый плеер
        if playerNode.isPlaying {
            playerNode.stop()
            stopProgressTimer()
        }

        // Останавливаем engine если запущен
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        // Проверяем кэш для оптимизации (предзагрузка данных для FileTranscriptionService)
        // Это гарантирует, что если файл используется для транскрипции,
        // AudioCache уже будет содержать его данные
        Task {
            do {
                _ = try await audioCache.loadAudio(from: url)
                let stats = await audioCache.getStatistics()
                LogManager.app.debug("AudioCache stats: \(stats.currentSize) files, hit rate: \(String(format: "%.1f%%", stats.hitRate * 100))")
            } catch {
                // Ошибка кэша не критична для воспроизведения
                LogManager.app.debug("AudioCache preload failed (non-critical): \(error.localizedDescription)")
            }
        }

        // Создаем новый audio file
        do {
            audioFile = try AVAudioFile(forReading: url)
            guard let file = audioFile else {
                throw AudioPlayerError.playbackFailed("Failed to create audio file")
            }

            audioFormat = file.processingFormat
            audioFileURL = url

            // Подключаем узлы в граф
            guard let format = audioFormat else {
                throw AudioPlayerError.playbackFailed("Invalid audio format")
            }

            let isStereo = format.channelCount > 1

            // Переконфигурируем аудио граф для нового файла
            disconnectAllNodes()
            configureAudioGraph(format: format, isStereo: isStereo)
            applyCurrentSettings()

            // Обновляем длительность
            state.playback.duration = Double(file.length) / file.fileFormat.sampleRate
            state.playback.isPlaying = false
            state.playback.currentTime = 0
            startTime = 0
            pauseTime = 0

            LogManager.app.success("Файл загружен: \(state.playback.duration)s, format: \(format.sampleRate)Hz")
        } catch {
            LogManager.app.failure("Ошибка загрузки файла", error: error)
            throw AudioPlayerError.loadFailed(error)
        }
    }

    /// Начинает воспроизведение с текущей позиции
    /// - Parameter shouldPauseOtherPlayers: Останавливать ли другие медиа-плееры (только при явном нажатии Play)
    public func play(shouldPauseOtherPlayers: Bool = false) {
        guard let file = audioFile else {
            LogManager.app.error("AudioPlayerManager: Файл не загружен")
            return
        }

        // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Всегда останавливаем и сбрасываем playerNode
        // перед началом нового воспроизведения, чтобы избежать наложения аудио потоков
        if playerNode.isPlaying {
            playerNode.stop()
            stopProgressTimer()
            LogManager.app.debug("AudioPlayerManager: Остановлен предыдущий поток воспроизведения")
        }

        // Полная очистка внутренних буферов AVAudioPlayerNode
        // Это гарантирует, что не осталось запланированных сегментов из предыдущих вызовов
        playerNode.reset()

        // TranscribeIt не управляет другими медиа-плеерами
        // (эта функция была в PushToTalk для YouTube Music/Spotify)

        // Запускаем engine если не запущен
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                LogManager.app.failure("Ошибка запуска audio engine", error: error)
                return
            }
        }

        // Вычисляем фрейм с которого начать воспроизведение
        let sampleRate = file.fileFormat.sampleRate
        let startFrame = AVAudioFramePosition(state.playback.currentTime * sampleRate)

        // Проверяем что не вышли за границы
        if startFrame >= file.length {
            LogManager.app.warning("Попытка воспроизведения за пределами файла")
            return
        }

        // Воспроизводим с текущей позиции до конца
        playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: AVAudioFrameCount(file.length - startFrame), at: nil) { [weak self] in
            DispatchQueue.main.async {
                self?.handlePlaybackFinished()
            }
        }

        playerNode.play()

        // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Принудительно обновляем состояние на главном потоке
        // для гарантии синхронизации с UI при быстрых кликах
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.state.playback.isPlaying = true
            self.startTime = CACurrentMediaTime() - self.state.playback.currentTime
            self.startProgressTimer()
            LogManager.app.info("Воспроизведение начато с \(self.state.playback.currentTime)s")
        }
    }

    /// Приостанавливает воспроизведение
    public func pause() {
        if !playerNode.isPlaying { return }

        playerNode.pause()

        // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Принудительно обновляем состояние на главном потоке
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pauseTime = CACurrentMediaTime()
            self.state.playback.currentTime = self.pauseTime - self.startTime
            self.state.playback.isPlaying = false
            self.stopProgressTimer()
            LogManager.app.info("Воспроизведение приостановлено на \(self.state.playback.currentTime)s")
        }
    }

    /// Останавливает воспроизведение и сбрасывает позицию
    public func stop() {
        playerNode.stop()
        state.playback.isPlaying = false
        state.playback.currentTime = 0
        startTime = 0
        pauseTime = 0
        stopProgressTimer()

        LogManager.app.info("Воспроизведение остановлено")
    }

    /// Обработка завершения воспроизведения
    private func handlePlaybackFinished() {
        state.playback.isPlaying = false
        stopProgressTimer()

        LogManager.app.info("Воспроизведение завершено")
    }

    /// Переход к указанному времени
    public func seek(to time: TimeInterval) {
        let clampedTime = max(0, min(time, state.playback.duration))

        // Если воспроизведение активно, перезапускаем с новой позиции
        let wasPlaying = state.playback.isPlaying

        if wasPlaying {
            playerNode.stop()
            stopProgressTimer()
        }

        state.playback.currentTime = clampedTime

        if wasPlaying {
            play()
        }

        LogManager.app.info("Переход к \(clampedTime)s")
    }

    /// Переход к указанному времени и начало воспроизведения
    /// Используется при клике на фразу - явное действие пользователя "перейти и слушать"
    public func seekAndPlay(to time: TimeInterval) {
        // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Атомарное обновление времени и состояния на главном потоке
        // для корректной синхронизации UI (подсветка реплики + кнопка play/pause)
        let clampedTime = max(0, min(time, state.playback.duration))
        state.playback.currentTime = clampedTime
        // Клик на фразу - явное действие пользователя, останавливаем внешний плеер
        play(shouldPauseOtherPlayers: true)
    }

    /// Изменение громкости (0.0 - 1.0)
    public func setVolume(_ newVolume: Float) {
        let clampedVolume = max(0.0, min(1.0, newVolume))
        state.audio.volume = clampedVolume
        mixer.outputVolume = state.audio.effectiveVolume

        LogManager.app.info("Громкость: \(String(format: "%.0f%%", clampedVolume * 100))")
    }

    /// Изменение усиления громкости (1.0 - 5.0)
    public func setVolumeBoost(_ newBoost: Float) {
        let clampedBoost = max(1.0, min(5.0, newBoost))
        state.audio.volumeBoost = clampedBoost
        mixer.outputVolume = state.audio.effectiveVolume

        LogManager.app.info("Усиление громкости: \(String(format: "%.0f%%", clampedBoost * 100))")
    }

    /// Изменение скорости воспроизведения (0.5x - 2.0x)
    public func setPlaybackRate(_ newRate: Float) {
        let clampedRate = max(0.5, min(2.0, newRate))
        state.settings.playbackRate = clampedRate
        timePitch.rate = clampedRate

        LogManager.app.info("Скорость воспроизведения: \(String(format: "%.1fx", clampedRate))")
    }

    /// Переключение моно/стерео режима
    public func setMonoMode(_ enabled: Bool) {
        state.settings.monoMode = enabled

        // Если файл загружен, перезагружаем граф
        if let url = audioFileURL {
            let wasPlaying = state.playback.isPlaying
            let savedTime = state.playback.currentTime

            if wasPlaying {
                playerNode.stop()
                stopProgressTimer()
            }

            // Сбрасываем audioFileURL чтобы loadAudio() не пропустил перезагрузку
            audioFileURL = nil
            audioFile = nil

            // Перезагружаем файл для переконфигурации графа
            try? loadAudio(from: url)

            if wasPlaying {
                state.playback.currentTime = savedTime
                play()
            }

            LogManager.app.info("Моно режим: \(enabled ? "включен" : "выключен")")
        }
    }

    /// Переключение воспроизведения (play/pause)
    public func togglePlayback() {
        if state.playback.isPlaying {
            pause()
        } else {
            // Только при явном нажатии Play останавливаем другие плееры
            play(shouldPauseOtherPlayers: true)
        }
    }

    // MARK: - Private Methods

    /// Запускает таймер для обновления прогресса
    private func startProgressTimer() {
        stopProgressTimer()

        displayLink = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            DispatchQueue.main.async {
                // Вычисляем текущее время на основе CACurrentMediaTime
                if self.state.playback.isPlaying {
                    self.state.playback.currentTime = CACurrentMediaTime() - self.startTime

                    // Проверяем что не вышли за границы
                    if self.state.playback.currentTime >= self.state.playback.duration {
                        self.state.playback.currentTime = self.state.playback.duration
                    }
                }
            }
        }
    }

    /// Останавливает таймер обновления прогресса
    private func stopProgressTimer() {
        displayLink?.invalidate()
        displayLink = nil
    }

    deinit {
        // Останавливаем воспроизведение
        playerNode.stop()
        audioEngine.stop()
        stopProgressTimer()

        LogManager.app.info("AudioPlayerManager: deinit")
    }
}

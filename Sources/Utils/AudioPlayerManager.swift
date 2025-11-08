import Foundation
import AVFoundation
import Combine

/// Менеджер для воспроизведения аудио файлов в FileTranscriptionWindow
/// Поддерживает навигацию по временным меткам (реплики диалога)
public class AudioPlayerManager: ObservableObject {
    @Published public var isPlaying: Bool = false
    @Published public var currentTime: TimeInterval = 0
    @Published public var duration: TimeInterval = 0
    @Published public var volume: Float = 1.0
    @Published public var volumeBoost: Float = 1.0  // Усиление громкости (1.0 - 5.0)
    @Published public var playbackRate: Float = 1.0  // Скорость воспроизведения (0.5x - 2.0x)
    @Published public var monoMode: Bool = true  // Моно режим (оба канала в обоих ушах)
    @Published public var pauseOtherPlayersEnabled: Bool = true // Останавливать другие плееры при воспроизведении

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

    public init() {
        LogManager.app.info("AudioPlayerManager: Инициализация")
        loadSettings()
        setupAudioEngine()
    }

    /// Настройка AVAudioEngine
    private func setupAudioEngine() {
        // Добавляем узлы в граф
        audioEngine.attach(playerNode)
        audioEngine.attach(timePitch)
        audioEngine.attach(stereoToMonoMixer)
        audioEngine.attach(mixer)

        // Настраиваем mixer для усиления громкости
        mixer.outputVolume = 1.0

        LogManager.app.info("AudioPlayerManager: AVAudioEngine настроен")
    }

    /// Загрузка настроек из UserDefaults
    private func loadSettings() {
        pauseOtherPlayersEnabled = UserDefaults.standard.object(forKey: "pauseOtherPlayersInTranscription") as? Bool ?? true

        if UserDefaults.standard.object(forKey: "pauseOtherPlayersInTranscription") == nil {
            UserDefaults.standard.set(true, forKey: "pauseOtherPlayersInTranscription")
        }
    }

    /// Сохранение настройки паузы других плееров
    public func savePauseOtherPlayersEnabled(_ enabled: Bool) {
        pauseOtherPlayersEnabled = enabled
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

            // Отключаем все соединения перед переподключением
            audioEngine.disconnectNodeInput(timePitch)
            audioEngine.disconnectNodeInput(stereoToMonoMixer)
            audioEngine.disconnectNodeInput(mixer)

            if monoMode && isStereo {
                // Моно режим для стерео файла: playerNode -> timePitch -> stereoToMonoMixer -> mixer -> output
                audioEngine.connect(playerNode, to: timePitch, format: format)

                // Конвертируем в моно формат
                let monoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!
                audioEngine.connect(timePitch, to: stereoToMonoMixer, format: format)
                audioEngine.connect(stereoToMonoMixer, to: mixer, format: monoFormat)
                audioEngine.connect(mixer, to: audioEngine.mainMixerNode, format: monoFormat)

                LogManager.app.info("Моно режим включен: стерео -> моно")
            } else {
                // Стерео режим или моно файл: playerNode -> timePitch -> mixer -> output
                audioEngine.connect(playerNode, to: timePitch, format: format)
                audioEngine.connect(timePitch, to: mixer, format: format)
                audioEngine.connect(mixer, to: audioEngine.mainMixerNode, format: format)

                LogManager.app.info("Стерео режим или моно файл")
            }

            // Настраиваем timePitch для изменения скорости
            timePitch.rate = playbackRate

            // Настраиваем mixer для усиления громкости
            mixer.outputVolume = volume * volumeBoost

            // Обновляем длительность
            duration = Double(file.length) / file.fileFormat.sampleRate
            isPlaying = false
            currentTime = 0
            startTime = 0
            pauseTime = 0

            LogManager.app.success("Файл загружен: \(duration)s, format: \(format.sampleRate)Hz")
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

        // Если уже играет, не создаем новое воспроизведение
        if playerNode.isPlaying {
            LogManager.app.debug("AudioPlayerManager: Уже воспроизводится")
            return
        }

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
        let startFrame = AVAudioFramePosition(currentTime * sampleRate)

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
        isPlaying = true
        startTime = CACurrentMediaTime() - currentTime
        startProgressTimer()

        LogManager.app.info("Воспроизведение начато с \(self.currentTime)s")
    }

    /// Приостанавливает воспроизведение
    public func pause() {
        if !playerNode.isPlaying { return }

        playerNode.pause()
        pauseTime = CACurrentMediaTime()
        currentTime = pauseTime - startTime
        isPlaying = false
        stopProgressTimer()

        LogManager.app.info("Воспроизведение приостановлено на \(self.currentTime)s")
    }

    /// Останавливает воспроизведение и сбрасывает позицию
    public func stop() {
        playerNode.stop()
        isPlaying = false
        currentTime = 0
        startTime = 0
        pauseTime = 0
        stopProgressTimer()

        LogManager.app.info("Воспроизведение остановлено")
    }

    /// Обработка завершения воспроизведения
    private func handlePlaybackFinished() {
        isPlaying = false
        stopProgressTimer()

        LogManager.app.info("Воспроизведение завершено")
    }

    /// Переход к указанному времени
    public func seek(to time: TimeInterval) {
        let clampedTime = max(0, min(time, duration))

        // Если воспроизведение активно, перезапускаем с новой позиции
        let wasPlaying = isPlaying

        if wasPlaying {
            playerNode.stop()
            stopProgressTimer()
        }

        currentTime = clampedTime

        if wasPlaying {
            play()
        }

        LogManager.app.info("Переход к \(clampedTime)s")
    }

    /// Переход к указанному времени и начало воспроизведения
    /// Используется при клике на фразу - явное действие пользователя "перейти и слушать"
    public func seekAndPlay(to time: TimeInterval) {
        // Если уже играет, сначала останавливаем
        if isPlaying {
            playerNode.stop()
            stopProgressTimer()
            isPlaying = false
        }
        currentTime = time
        // Клик на фразу - явное действие пользователя, останавливаем внешний плеер
        play(shouldPauseOtherPlayers: true)
    }

    /// Изменение громкости (0.0 - 1.0)
    public func setVolume(_ newVolume: Float) {
        let clampedVolume = max(0.0, min(1.0, newVolume))
        volume = clampedVolume
        mixer.outputVolume = clampedVolume * volumeBoost

        LogManager.app.info("Громкость: \(String(format: "%.0f%%", clampedVolume * 100))")
    }

    /// Изменение усиления громкости (1.0 - 5.0)
    public func setVolumeBoost(_ newBoost: Float) {
        let clampedBoost = max(1.0, min(5.0, newBoost))
        volumeBoost = clampedBoost
        mixer.outputVolume = volume * clampedBoost

        LogManager.app.info("Усиление громкости: \(String(format: "%.0f%%", clampedBoost * 100))")
    }

    /// Изменение скорости воспроизведения (0.5x - 2.0x)
    public func setPlaybackRate(_ newRate: Float) {
        let clampedRate = max(0.5, min(2.0, newRate))
        playbackRate = clampedRate
        timePitch.rate = clampedRate

        LogManager.app.info("Скорость воспроизведения: \(String(format: "%.1fx", clampedRate))")
    }

    /// Переключение моно/стерео режима
    public func setMonoMode(_ enabled: Bool) {
        monoMode = enabled

        // Если файл загружен, перезагружаем граф
        if let url = audioFileURL {
            let wasPlaying = isPlaying
            let savedTime = currentTime

            if wasPlaying {
                playerNode.stop()
                stopProgressTimer()
            }

            // Перезагружаем файл для переконфигурации графа
            try? loadAudio(from: url)

            if wasPlaying {
                currentTime = savedTime
                play()
            }

            LogManager.app.info("Моно режим: \(enabled ? "включен" : "выключен")")
        }
    }

    /// Переключение воспроизведения (play/pause)
    public func togglePlayback() {
        if isPlaying {
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
                if self.isPlaying {
                    self.currentTime = CACurrentMediaTime() - self.startTime

                    // Проверяем что не вышли за границы
                    if self.currentTime >= self.duration {
                        self.currentTime = self.duration
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

/// Ошибки AudioPlayerManager
enum AudioPlayerError: LocalizedError {
    case loadFailed(Error)
    case playbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let error):
            return "Failed to load audio file: \(error.localizedDescription)"
        case .playbackFailed(let message):
            return "Playback failed: \(message)"
        }
    }
}

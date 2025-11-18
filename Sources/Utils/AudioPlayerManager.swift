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
/// ```
///
/// ## Смешивание стерео каналов
///
/// Для комфортного прослушивания телефонных разговоров стерео файлы автоматически воспроизводятся
/// с 65/35 смешиванием каналов:
/// - Левое ухо: 65% левого канала + 35% правого канала
/// - Правое ухо: 35% левого канала + 65% правого канала
///
/// Это создаёт почти моно звучание с лёгким ощущением направления (собеседник "чуть сбоку").
public class AudioPlayerManager: ObservableObject {
    /// Централизованное состояние аудио плеера
    ///
    /// Объединяет все @Published свойства в логические группы:
    /// - `playback`: состояние воспроизведения (isPlaying, currentTime, duration)
    /// - `audio`: настройки аудио (volume, volumeBoost)
    /// - `settings`: настройки воспроизведения (playbackRate, pauseOtherPlayersEnabled)
    @Published public var state = AudioPlayerState()

    // AVAudioEngine для поддержки усиления громкости выше 100%
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let mixer = AVAudioMixerNode()

    private var audioFile: AVAudioFile?
    private var displayLink: Timer?
    private var audioFileURL: URL?
    private var audioFormat: AVAudioFormat?

    // Для отслеживания позиции воспроизведения
    private var startTime: TimeInterval = 0
    private var pauseTime: TimeInterval = 0

    // Audio cache для оптимизации загрузки
    private let audioCache: AudioCache

    // Наблюдатель за изменениями конфигурации аудио устройств
    private var configurationChangeObserver: NSObjectProtocol?

    // Флаг для предотвращения обработки изменений устройств во время загрузки файла
    private var isReconfiguring = false

    // Флаг для отслеживания явной остановки пользователем
    private var wasExplicitlyStopped = false

    // Отложенная задача для debouncing изменений конфигурации
    private var configurationChangeWorkItem: DispatchWorkItem?

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
    /// - mixer: управление громкостью с усилением
    ///
    /// - Note: Соединения между узлами устанавливаются в `loadAudio(from:)`
    private func setupAudioEngine() {
        attachAudioNodes()
        configureMixerDefaults()
        setupConfigurationChangeObserver()
        LogManager.app.info("AudioPlayerManager: AVAudioEngine настроен")
    }

    /// Добавляет все необходимые узлы в аудио граф
    private func attachAudioNodes() {
        audioEngine.attach(playerNode)
        audioEngine.attach(timePitch)
        audioEngine.attach(mixer)
    }

    /// Устанавливает дефолтные значения для mixer узла
    private func configureMixerDefaults() {
        mixer.outputVolume = 1.0
    }

    /// Настраивает наблюдатель за изменениями конфигурации аудио устройств
    ///
    /// Подписывается на уведомления AVAudioEngineConfigurationChange для обработки:
    /// - Отключения/подключения аудио устройств
    /// - Изменения маршрута аудио (headphones → speakers)
    /// - Изменения частоты дискретизации или количества каналов
    private func setupConfigurationChangeObserver() {
        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: nil
        ) { [weak self] notification in
            self?.handleAudioConfigurationChange(notification)
        }
        LogManager.app.info("AudioPlayerManager: Наблюдатель за изменениями аудио устройств настроен")
    }

    /// Отключает все соединения между узлами перед переконфигурацией
    ///
    /// Вызывается перед настройкой нового аудио файла для очистки предыдущих соединений
    private func disconnectAllNodes() {
        audioEngine.disconnectNodeInput(timePitch)
        audioEngine.disconnectNodeInput(mixer)
    }

    /// Настраивает граф обработки аудио
    ///
    /// Создает граф: playerNode → timePitch → mixer → output
    ///
    /// - Parameter format: Формат аудио файла
    private func configureAudioGraph(format: AVAudioFormat) {
        // playerNode → timePitch → mixer → output
        audioEngine.connect(playerNode, to: timePitch, format: format)
        audioEngine.connect(timePitch, to: mixer, format: format)
        audioEngine.connect(mixer, to: audioEngine.mainMixerNode, format: format)

        LogManager.app.info("Аудио граф настроен для \(format.channelCount) канал(ов)")
    }

    /// Применяет текущие настройки к узлам аудио графа
    ///
    /// Синхронизирует состояние UI (playbackRate, volume, volumeBoost) с узлами AVAudioEngine
    private func applyCurrentSettings() {
        timePitch.rate = state.settings.playbackRate
        mixer.outputVolume = state.audio.effectiveVolume
    }

    /// Применяет смешивание каналов 65/35 к стерео аудио файлу
    ///
    /// Для комфортного прослушивания телефонных разговоров каналы смешиваются:
    /// - Левое ухо: 65% левого канала + 35% правого канала
    /// - Правое ухо: 35% левого канала + 65% правого канала
    ///
    /// Это создаёт почти моно звучание с лёгким ощущением направления (собеседник "чуть сбоку").
    ///
    /// - Parameter file: Стерео аудио файл для обработки
    /// - Returns: Новый файл с примененным смешиванием каналов
    /// - Throws: AudioPlayerError если не удалось создать или обработать файл
    private func applyChannelMixing(to file: AVAudioFile) throws -> AVAudioFile {
        guard file.fileFormat.channelCount == 2 else {
            // Моно файл не нуждается в смешивании
            return file
        }

        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioPlayerError.playbackFailed("Failed to create audio buffer")
        }

        // Читаем весь файл в буфер
        try file.read(into: buffer)
        buffer.frameLength = frameCount

        guard let leftChannel = buffer.floatChannelData?[0],
              let rightChannel = buffer.floatChannelData?[1] else {
            throw AudioPlayerError.playbackFailed("Failed to access channel data")
        }

        // Применяем смешивание 65/35
        for i in 0..<Int(frameCount) {
            let originalLeft = leftChannel[i]
            let originalRight = rightChannel[i]

            // Левое ухо: 65% L + 35% R
            leftChannel[i] = 0.65 * originalLeft + 0.35 * originalRight

            // Правое ухо: 35% L + 65% R
            rightChannel[i] = 0.35 * originalLeft + 0.65 * originalRight
        }

        // Создаем временный файл для обработанного аудио
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")

        guard let outputFile = try? AVAudioFile(forWriting: tempURL, settings: format.settings) else {
            throw AudioPlayerError.playbackFailed("Failed to create output file")
        }

        // Записываем обработанный буфер
        try outputFile.write(from: buffer)

        LogManager.app.info("Применено смешивание каналов 65/35")
        return outputFile
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

        // Устанавливаем флаг переконфигурации для предотвращения race condition
        // с обработчиком изменений устройств
        isReconfiguring = true
        defer { isReconfiguring = false }

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
            var file = try AVAudioFile(forReading: url)

            // Применяем смешивание каналов для стерео файлов
            if file.fileFormat.channelCount == 2 {
                file = try applyChannelMixing(to: file)
            }

            audioFile = file
            audioFormat = file.processingFormat
            audioFileURL = url

            // Подключаем узлы в граф
            guard let format = audioFormat else {
                throw AudioPlayerError.playbackFailed("Invalid audio format")
            }

            // Переконфигурируем аудио граф для нового файла
            disconnectAllNodes()
            configureAudioGraph(format: format)
            applyCurrentSettings()

            // Обновляем длительность
            state.playback.duration = Double(file.length) / file.fileFormat.sampleRate
            state.playback.isPlaying = false
            state.playback.currentTime = 0
            startTime = 0
            pauseTime = 0

            LogManager.app.success("Файл загружен: \(state.playback.duration)s, format: \(format.sampleRate)Hz, \(format.channelCount) канал(ов)")
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

        // Сбрасываем флаг явной остановки при начале воспроизведения
        wasExplicitlyStopped = false

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

        // Отмечаем что остановка была явной (пользователем)
        wasExplicitlyStopped = true

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

    /// Обрабатывает изменения конфигурации аудио устройств
    ///
    /// Вызывается когда:
    /// - Аудио устройство отключено/подключено
    /// - Изменился маршрут аудио (headphones → speakers)
    /// - Изменилась частота дискретизации или количество каналов
    ///
    /// Выполняет автоматическое восстановление воспроизведения:
    /// 1. Сохраняет текущую позицию если воспроизведение активно
    /// 2. Останавливает engine
    /// 3. Пытается перезапустить engine (автоматически подключится к новому устройству)
    /// 4. Восстанавливает воспроизведение с сохраненной позиции
    ///
    /// - Parameter notification: Уведомление об изменении конфигурации
    private func handleAudioConfigurationChange(_ notification: Notification) {
        // Отменяем предыдущую отложенную задачу (debouncing)
        configurationChangeWorkItem?.cancel()

        // Создаем новую задачу с задержкой 0.3s для предотвращения множественных перезапусков
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Пропускаем обработку если идет загрузка файла (race condition prevention)
            guard !self.isReconfiguring else {
                LogManager.app.debug("AudioPlayerManager: Пропускаем изменение конфигурации во время загрузки файла")
                return
            }

            // Проверяем, нужно ли восстанавливать воспроизведение
            guard self.audioFile != nil else {
                LogManager.app.debug("AudioPlayerManager: Нет загруженного файла, восстановление не требуется")
                return
            }

            // Пропускаем если пользователь явно остановил воспроизведение
            guard !self.wasExplicitlyStopped else {
                LogManager.app.debug("AudioPlayerManager: Пропускаем восстановление - воспроизведение остановлено пользователем")
                return
            }

            LogManager.app.info("AudioPlayerManager: Обнаружено изменение конфигурации аудио устройств")

            // Устанавливаем статус переподключения
            self.state.deviceStatus = .reconnecting

            // Сохраняем состояние воспроизведения
            let wasPlaying = self.state.playback.isPlaying
            let savedPosition = self.state.playback.currentTime

            // Останавливаем воспроизведение и engine
            if self.playerNode.isPlaying {
                self.playerNode.stop()
                self.stopProgressTimer()
            }

            if self.audioEngine.isRunning {
                self.audioEngine.stop()
                LogManager.app.debug("AudioPlayerManager: Engine остановлен для переконфигурации")
            }

            // Пытаемся перезапустить engine
            // AVAudioEngine автоматически подключится к текущему устройству по умолчанию
            do {
                try self.audioEngine.start()
                LogManager.app.success("AudioPlayerManager: Engine успешно переподключен к новому аудио устройству")

                // Устанавливаем статус подключено
                self.state.deviceStatus = .connected

                // Восстанавливаем воспроизведение если оно было активно
                if wasPlaying {
                    self.state.playback.currentTime = savedPosition
                    self.play()
                    LogManager.app.info("AudioPlayerManager: Воспроизведение восстановлено с позиции \(savedPosition)s")
                }
            } catch {
                // Не удалось перезапустить engine - вероятно нет доступных устройств
                LogManager.app.failure("AudioPlayerManager: Не удалось переподключиться к аудио устройству", error: error)

                // Устанавливаем статус недоступно
                self.state.deviceStatus = .unavailable

                // Обновляем состояние UI
                self.state.playback.isPlaying = false
            }
        }

        configurationChangeWorkItem = workItem

        // Уведомление приходит на фоновом потоке (CoreAudio thread)
        // Выполняем с задержкой на главном потоке для debouncing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    deinit {
        // Отменяем отложенную задачу переконфигурации
        configurationChangeWorkItem?.cancel()
        configurationChangeWorkItem = nil

        // Удаляем наблюдатель за изменениями аудио устройств
        if let observer = configurationChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationChangeObserver = nil
        }

        // Останавливаем воспроизведение
        playerNode.stop()
        audioEngine.stop()
        stopProgressTimer()

        LogManager.app.info("AudioPlayerManager: deinit")
    }
}

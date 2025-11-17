import Foundation

/// Состояние аудио плеера
///
/// Объединяет все состояния AudioPlayerManager в логические группы
/// для упрощения отслеживания и управления состоянием.
///
/// ## Использование
///
/// ```swift
/// let state = AudioPlayerState()
///
/// // Управление воспроизведением
/// state.playback.isPlaying = true
/// state.playback.currentTime = 10.5
///
/// // Настройки аудио
/// state.audio.volume = 0.8
/// state.audio.volumeBoost = 2.0  // 200% усиление
///
/// // Настройки воспроизведения
/// state.settings.playbackRate = 1.5  // 1.5x скорость
/// ```
public struct AudioPlayerState: Equatable {
    /// Состояние воспроизведения (play/pause, позиция)
    public var playback: PlaybackState

    /// Настройки аудио (громкость, усиление)
    public var audio: AudioState

    /// Настройки воспроизведения (скорость, режим)
    public var settings: AudioSettings

    /// Инициализирует состояние с дефолтными значениями
    public init(
        playback: PlaybackState = PlaybackState(),
        audio: AudioState = AudioState(),
        settings: AudioSettings = AudioSettings()
    ) {
        self.playback = playback
        self.audio = audio
        self.settings = settings
    }
}

/// Состояние воспроизведения аудио
///
/// Содержит информацию о текущем состоянии воспроизведения,
/// позиции и длительности трека.
public struct PlaybackState: Equatable {
    /// Воспроизводится ли аудио в данный момент
    public var isPlaying: Bool = false

    /// Текущая позиция воспроизведения (в секундах)
    public var currentTime: TimeInterval = 0

    /// Общая длительность аудио файла (в секундах)
    public var duration: TimeInterval = 0

    /// Инициализирует состояние воспроизведения
    ///
    /// - Parameters:
    ///   - isPlaying: Воспроизводится ли аудио (по умолчанию: false)
    ///   - currentTime: Текущая позиция (по умолчанию: 0)
    ///   - duration: Длительность трека (по умолчанию: 0)
    public init(
        isPlaying: Bool = false,
        currentTime: TimeInterval = 0,
        duration: TimeInterval = 0
    ) {
        self.isPlaying = isPlaying
        self.currentTime = currentTime
        self.duration = duration
    }

    /// Прогресс воспроизведения (0.0 - 1.0)
    ///
    /// Вычисляется как `currentTime / duration`.
    /// Возвращает 0 если duration равен 0.
    public var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    /// Оставшееся время воспроизведения (в секундах)
    public var remainingTime: TimeInterval {
        return max(0, duration - currentTime)
    }
}

/// Состояние аудио настроек (громкость, усиление)
///
/// Содержит настройки громкости и вычисляемое эффективное значение
/// с учетом усиления.
public struct AudioState: Equatable {
    /// Базовая громкость (0.0 - 1.0)
    public var volume: Float = 1.0

    /// Усиление громкости (1.0 - 5.0)
    ///
    /// Позволяет усиливать громкость выше 100% для тихих записей.
    /// - 1.0 = 100% (без усиления)
    /// - 2.0 = 200% (удвоение громкости)
    /// - 5.0 = 500% (максимальное усиление)
    public var volumeBoost: Float = 1.0

    /// Инициализирует состояние аудио
    ///
    /// - Parameters:
    ///   - volume: Базовая громкость (по умолчанию: 1.0)
    ///   - volumeBoost: Усиление громкости (по умолчанию: 1.0)
    public init(
        volume: Float = 1.0,
        volumeBoost: Float = 1.0
    ) {
        self.volume = volume
        self.volumeBoost = volumeBoost
    }

    /// Эффективная громкость с учетом усиления
    ///
    /// Вычисляется как `volume * volumeBoost`.
    /// Максимальное значение: 5.0 (при volume=1.0, volumeBoost=5.0)
    ///
    /// ## Example
    ///
    /// ```swift
    /// var audio = AudioState(volume: 0.8, volumeBoost: 2.5)
    /// print(audio.effectiveVolume)  // 2.0 (0.8 * 2.5)
    /// ```
    public var effectiveVolume: Float {
        return volume * volumeBoost
    }

    /// Процентное отображение громкости (0-100%)
    public var volumePercentage: Int {
        return Int(volume * 100)
    }

    /// Процентное отображение усиления (100-500%)
    public var boostPercentage: Int {
        return Int(volumeBoost * 100)
    }
}

/// Настройки воспроизведения
///
/// Содержит настройки скорости воспроизведения и поведения при конкурентном воспроизведении.
/// Стерео файлы автоматически воспроизводятся с 90/10 смешиванием каналов для комфортного прослушивания.
public struct AudioSettings: Equatable {
    /// Скорость воспроизведения (0.5x - 2.0x)
    ///
    /// - 0.5 = половинная скорость (медленнее)
    /// - 1.0 = нормальная скорость
    /// - 2.0 = двойная скорость (быстрее)
    public var playbackRate: Float = 1.0

    /// Останавливать другие плееры при воспроизведении
    ///
    /// Если true, запуск воспроизведения автоматически останавливает
    /// другие активные AudioPlayerManager экземпляры.
    public var pauseOtherPlayersEnabled: Bool = true

    /// Инициализирует настройки воспроизведения
    ///
    /// - Parameters:
    ///   - playbackRate: Скорость воспроизведения (по умолчанию: 1.0)
    ///   - pauseOtherPlayersEnabled: Останавливать другие плееры (по умолчанию: true)
    public init(
        playbackRate: Float = 1.0,
        pauseOtherPlayersEnabled: Bool = true
    ) {
        self.playbackRate = playbackRate
        self.pauseOtherPlayersEnabled = pauseOtherPlayersEnabled
    }

    /// Допустимые значения скорости воспроизведения
    public static let availablePlaybackRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    /// Минимально допустимая скорость воспроизведения
    public static let minPlaybackRate: Float = 0.5

    /// Максимально допустимая скорость воспроизведения
    public static let maxPlaybackRate: Float = 2.0

    /// Проверяет, является ли текущая скорость допустимой
    public var isValidPlaybackRate: Bool {
        return playbackRate >= Self.minPlaybackRate && playbackRate <= Self.maxPlaybackRate
    }
}

// MARK: - Convenience Extensions

extension AudioPlayerState {
    /// Сбрасывает все состояние в начальные значения
    public mutating func reset() {
        playback = PlaybackState()
        audio = AudioState()
        settings = AudioSettings()
    }

    /// Создает копию состояния с остановленным воспроизведением
    public func stopped() -> AudioPlayerState {
        var state = self
        state.playback.isPlaying = false
        state.playback.currentTime = 0
        return state
    }
}

extension PlaybackState {
    /// Форматирует текущее время в MM:SS формат
    public var formattedCurrentTime: String {
        return formatTime(currentTime)
    }

    /// Форматирует длительность в MM:SS формат
    public var formattedDuration: String {
        return formatTime(duration)
    }

    /// Форматирует оставшееся время в MM:SS формат
    public var formattedRemainingTime: String {
        return formatTime(remainingTime)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension AudioState {
    /// Константы для усиления громкости
    public enum VolumeBoostConstants {
        /// Минимальное усиление (без усиления)
        public static let min: Float = 1.0

        /// Максимальное усиление (500%)
        public static let max: Float = 5.0

        /// Стандартный шаг изменения усиления
        public static let step: Float = 0.5
    }

    /// Увеличивает усиление на стандартный шаг
    public mutating func increaseBoost() {
        volumeBoost = min(volumeBoost + VolumeBoostConstants.step, VolumeBoostConstants.max)
    }

    /// Уменьшает усиление на стандартный шаг
    public mutating func decreaseBoost() {
        volumeBoost = max(volumeBoost - VolumeBoostConstants.step, VolumeBoostConstants.min)
    }
}

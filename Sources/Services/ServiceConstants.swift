import Foundation

/// Константы для сервисов транскрипции
enum ServiceConstants {

    // MARK: - Timing Constants

    /// Интервалы ожидания для различных операций
    enum WaitIntervals {
        /// 1 секунда в наносекундах (для Task.sleep)
        static let oneSecond: UInt64 = 1_000_000_000

        /// 0.5 секунды в наносекундах (для Task.sleep)
        static let halfSecond: UInt64 = 500_000_000
    }

    // MARK: - Audio Constants

    /// Константы для обработки аудио
    enum Audio {
        /// Стандартная частота дискретизации для Whisper (16 kHz)
        static let whisperSampleRate: Double = 16000.0

        /// Частота дискретизации CD качества (44.1 kHz)
        static let cdSampleRate: Double = 44100.0

        /// Профессиональная частота дискретизации (48 kHz)
        static let professionalSampleRate: Double = 48000.0

        /// Частота дискретизации телефонии (8 kHz)
        static let telephonySampleRate: Double = 8000.0
    }

    // MARK: - Time Conversion Constants

    /// Константы для преобразования времени
    enum Time {
        /// Секунд в минуте
        static let secondsPerMinute: Int = 60

        /// Секунд в часе
        static let secondsPerHour: Int = 3600

        /// Минут в часе
        static let minutesPerHour: Int = 60
    }
}

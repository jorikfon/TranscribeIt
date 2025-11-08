import Foundation
import Accelerate

/// Параметры для нормализации аудио
public struct NormalizationParameters {
    /// Целевой уровень RMS (Root Mean Square) после нормализации
    public let targetRMS: Float

    /// Максимальный gain (усиление) в dB
    public let maxGainDB: Float

    /// Порог для определения "тихого" аудио (RMS)
    public let quietThreshold: Float

    /// Применять ли peak limiting для предотвращения клиппинга
    public let enablePeakLimiting: Bool

    /// Максимальное значение пика (для предотвращения клиппинга)
    public let peakLimit: Float

    public static let `default` = NormalizationParameters(
        targetRMS: 0.1,          // Целевой RMS уровень
        maxGainDB: 20.0,         // Максимум +20dB усиления
        quietThreshold: 0.02,    // Считать тихим если RMS < 0.02
        enablePeakLimiting: true,
        peakLimit: 0.95          // Не допускать пики выше 0.95
    )

    public init(
        targetRMS: Float = 0.1,
        maxGainDB: Float = 20.0,
        quietThreshold: Float = 0.02,
        enablePeakLimiting: Bool = true,
        peakLimit: Float = 0.95
    ) {
        self.targetRMS = targetRMS
        self.maxGainDB = maxGainDB
        self.quietThreshold = quietThreshold
        self.enablePeakLimiting = enablePeakLimiting
        self.peakLimit = peakLimit
    }
}

/// Статистика аудио сигнала для нормализации
public struct NormalizationStats {
    /// Peak (максимальное значение)
    public let peak: Float

    /// RMS (Root Mean Square) - средняя энергия сигнала
    public let rms: Float

    /// Является ли аудио тихим (ниже порога)
    public let isQuiet: Bool

    /// Рекомендуемый gain для нормализации (в разах, не dB)
    public let recommendedGain: Float
}

/// Нормализатор аудио сигнала с использованием Accelerate framework
/// Используется для повышения громкости тихих записей перед транскрипцией
public class AudioNormalizer {
    private let parameters: NormalizationParameters

    public init(parameters: NormalizationParameters = .default) {
        self.parameters = parameters
    }

    /// Анализирует аудио и возвращает статистику
    /// - Parameter samples: Массив аудио сэмплов (Float32)
    /// - Returns: Статистика аудио
    public func analyze(_ samples: [Float]) -> NormalizationStats {
        guard !samples.isEmpty else {
            return NormalizationStats(peak: 0, rms: 0, isQuiet: true, recommendedGain: 1.0)
        }

        let count = vDSP_Length(samples.count)

        // Вычисление peak (максимальное абсолютное значение)
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, count)

        // Вычисление RMS (Root Mean Square)
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, count)

        // Определяем тихое ли аудио
        let isQuiet = rms < parameters.quietThreshold

        // Рассчитываем рекомендуемый gain
        var recommendedGain: Float = 1.0
        if rms > 0.0001 { // Избегаем деления на очень маленькие значения
            recommendedGain = parameters.targetRMS / rms

            // Ограничиваем максимальный gain
            let maxGainLinear = pow(10.0, parameters.maxGainDB / 20.0)
            recommendedGain = min(recommendedGain, maxGainLinear)

            // Если peak limiting включен, учитываем peak
            if parameters.enablePeakLimiting && peak > 0 {
                let peakLimitGain = parameters.peakLimit / peak
                recommendedGain = min(recommendedGain, peakLimitGain)
            }
        }

        return NormalizationStats(
            peak: peak,
            rms: rms,
            isQuiet: isQuiet,
            recommendedGain: recommendedGain
        )
    }

    /// Нормализует аудио сэмплы к целевому RMS уровню
    /// - Parameter samples: Исходные аудио сэмплы
    /// - Returns: Нормализованные сэмплы
    public func normalize(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else {
            return samples
        }

        // Анализируем аудио
        let stats = analyze(samples)

        // Если gain близок к 1.0, нормализация не нужна
        if abs(stats.recommendedGain - 1.0) < 0.01 {
            return samples
        }

        // Применяем gain
        var normalized = samples
        var gain = stats.recommendedGain
        let count = vDSP_Length(samples.count)

        vDSP_vsmul(samples, 1, &gain, &normalized, 1, count)

        // Применяем soft clipping если включен peak limiting
        if parameters.enablePeakLimiting {
            normalized = applySoftClipping(normalized)
        }

        return normalized
    }

    /// Применяет "мягкое" ограничение пиков (soft clipping)
    /// Использует tanh для плавного ограничения вместо жесткого обрезания
    /// - Parameter samples: Аудио сэмплы
    /// - Returns: Сэмплы с примененным soft clipping
    private func applySoftClipping(_ samples: [Float]) -> [Float] {
        var clipped = samples
        var count = Int32(samples.count)

        // Применяем tanh для мягкого ограничения
        // tanh дает плавное насыщение вместо жесткого клиппинга
        vvtanhf(&clipped, samples, &count)

        // Масштабируем к peakLimit
        var scale = parameters.peakLimit
        let vCount = vDSP_Length(samples.count)
        vDSP_vsmul(clipped, 1, &scale, &clipped, 1, vCount)

        return clipped
    }

    /// Нормализует аудио с кастомным gain
    /// - Parameters:
    ///   - samples: Исходные сэмплы
    ///   - gain: Коэффициент усиления (1.0 = без изменений)
    /// - Returns: Нормализованные сэмплы
    public func normalize(_ samples: [Float], gain: Float) -> [Float] {
        guard !samples.isEmpty else {
            return samples
        }

        var normalized = samples
        var appliedGain = gain
        let count = vDSP_Length(samples.count)

        vDSP_vsmul(samples, 1, &appliedGain, &normalized, 1, count)

        if parameters.enablePeakLimiting {
            normalized = applySoftClipping(normalized)
        }

        return normalized
    }

    /// Вычисляет gain в dB для указанного linear gain
    /// - Parameter linearGain: Linear gain (1.0 = 0dB)
    /// - Returns: Gain в decibels
    public static func linearToDecibels(_ linearGain: Float) -> Float {
        return 20.0 * log10(max(linearGain, 0.000001))
    }

    /// Конвертирует gain из dB в linear
    /// - Parameter decibels: Gain в dB
    /// - Returns: Linear gain
    public static func decibelsToLinear(_ decibels: Float) -> Float {
        return pow(10.0, decibels / 20.0)
    }
}

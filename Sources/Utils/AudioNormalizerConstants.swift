import Foundation

/// Константы для аудио нормализации
/// Используются в AudioNormalizer для предотвращения magic numbers
public enum AudioNormalizerConstants {
    // MARK: - Thresholds

    /// Минимальное значение RMS для безопасного деления
    /// Значения ниже этого порога считаются практически нулевыми
    static let minSafeRMS: Float = 0.0001

    /// Порог близости gain к 1.0, при котором нормализация не применяется
    /// Если abs(gain - 1.0) < этого значения, нормализация пропускается
    static let gainToleranceThreshold: Float = 0.01

    /// Минимальное значение для log10 операции (для предотвращения -inf)
    static let minLogValue: Float = 0.000001

    // MARK: - Decibel Conversion

    /// Коэффициент для конвертации между dB и linear gain
    /// Формула: dB = 20 * log10(linear)
    static let decibelConversionFactor: Float = 20.0

    /// База для экспоненты в конвертации dB
    /// Формула: linear = 10^(dB/20)
    static let decibelBase: Float = 10.0
}

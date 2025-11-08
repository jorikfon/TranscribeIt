import Foundation
import Accelerate

/// Улучшенный Voice Activity Detector с адаптивным порогом
/// Автоматически определяет уровень шума и адаптирует порог
/// Использует комбинацию энергии (RMS) и Zero Crossing Rate (ZCR)
public class AdaptiveVAD {

    /// Параметры адаптивного VAD
    public struct Parameters {
        /// Размер окна анализа в секундах
        public let windowSize: TimeInterval

        /// Минимальная длительность речи в секундах
        public let minSpeechDuration: TimeInterval

        /// Минимальная длительность тишины для разделения сегментов
        public let minSilenceDuration: TimeInterval

        /// Множитель для адаптивного порога (относительно среднего шума)
        /// Например, 2.0 означает порог = средний_шум + 2 * std_deviation
        public let thresholdMultiplier: Float

        /// Вес ZCR в комбинированной метрике (0.0 - только энергия, 1.0 - только ZCR)
        public let zcrWeight: Float

        /// Параметры по умолчанию
        public static let `default` = Parameters(
            windowSize: 0.03,
            minSpeechDuration: 0.5,
            minSilenceDuration: 0.3,
            thresholdMultiplier: 2.0,
            zcrWeight: 0.3
        )

        /// Параметры для низкого качества / телефонного аудио
        public static let lowQuality = Parameters(
            windowSize: 0.05,
            minSpeechDuration: 0.3,
            minSilenceDuration: 0.5,
            thresholdMultiplier: 1.5,  // Более чувствительный
            zcrWeight: 0.4
        )

        /// Параметры для агрессивного разбиения (много сегментов)
        public static let aggressive = Parameters(
            windowSize: 0.02,
            minSpeechDuration: 0.2,
            minSilenceDuration: 0.2,
            thresholdMultiplier: 1.2,  // Очень чувствительный
            zcrWeight: 0.5
        )

        public init(
            windowSize: TimeInterval = 0.03,
            minSpeechDuration: TimeInterval = 0.5,
            minSilenceDuration: TimeInterval = 0.3,
            thresholdMultiplier: Float = 2.0,
            zcrWeight: Float = 0.3
        ) {
            self.windowSize = windowSize
            self.minSpeechDuration = minSpeechDuration
            self.minSilenceDuration = minSilenceDuration
            self.thresholdMultiplier = thresholdMultiplier
            self.zcrWeight = zcrWeight
        }
    }

    private let parameters: Parameters
    private let sampleRate: Double = 16000.0

    public init(parameters: Parameters = .default) {
        self.parameters = parameters
    }

    /// Определяет сегменты речи с адаптивным порогом
    public func detectSpeechSegments(in samples: [Float]) -> [SpeechSegment] {
        guard !samples.isEmpty else {
            return []
        }

        let windowSamples = Int(parameters.windowSize * sampleRate)
        let hopSamples = windowSamples / 2

        // 1. Вычисляем метрики для каждого окна
        var metrics: [(time: TimeInterval, energy: Float, zcr: Float)] = []

        var position = 0
        while position + windowSamples <= samples.count {
            let window = Array(samples[position..<(position + windowSamples)])
            let time = Double(position) / sampleRate

            let energy = calculateRMS(window)
            let zcr = calculateZCR(window)

            metrics.append((time: time, energy: energy, zcr: zcr))
            position += hopSamples
        }

        // 2. Адаптивный порог на основе статистики
        let (energyThreshold, zcrThreshold) = calculateAdaptiveThresholds(metrics: metrics)

        LogManager.app.debug("AdaptiveVAD: энергия порог=\(String(format: "%.4f", energyThreshold)), ZCR порог=\(String(format: "%.4f", zcrThreshold))")

        // 3. Определяем сегменты речи
        var segments: [SpeechSegment] = []
        var currentSegmentStart: TimeInterval? = nil
        var lastSpeechTime: TimeInterval = 0

        for metric in metrics {
            // Комбинированная метрика: взвешенная сумма энергии и ZCR
            let energyScore = metric.energy >= energyThreshold ? 1.0 : 0.0
            let zcrScore = metric.zcr >= zcrThreshold ? 1.0 : 0.0
            let combinedScore = Float(energyScore) * (1.0 - parameters.zcrWeight) + Float(zcrScore) * parameters.zcrWeight

            let isSpeech = combinedScore > 0.5

            if isSpeech {
                if currentSegmentStart == nil {
                    currentSegmentStart = metric.time
                }
                lastSpeechTime = metric.time + parameters.windowSize
            } else {
                if let start = currentSegmentStart {
                    let silenceDuration = metric.time - lastSpeechTime

                    if silenceDuration >= parameters.minSilenceDuration {
                        let segment = SpeechSegment(
                            startTime: start,
                            endTime: lastSpeechTime
                        )

                        if segment.duration >= parameters.minSpeechDuration {
                            segments.append(segment)
                        }

                        currentSegmentStart = nil
                    }
                }
            }
        }

        // Завершаем последний сегмент
        if let start = currentSegmentStart {
            let segment = SpeechSegment(
                startTime: start,
                endTime: lastSpeechTime
            )

            if segment.duration >= parameters.minSpeechDuration {
                segments.append(segment)
            }
        }

        return segments
    }

    /// Вычисляет адаптивные пороги на основе статистики
    private func calculateAdaptiveThresholds(
        metrics: [(time: TimeInterval, energy: Float, zcr: Float)]
    ) -> (energyThreshold: Float, zcrThreshold: Float) {
        guard !metrics.isEmpty else {
            return (0.01, 0.05)
        }

        let energyValues = metrics.map(\.energy)
        let zcrValues = metrics.map(\.zcr)

        // Энергия: используем процентиль + стандартное отклонение
        let energyMean = energyValues.reduce(0, +) / Float(energyValues.count)
        let energyStd = standardDeviation(energyValues, mean: energyMean)

        // Порог = среднее + множитель * std
        let energyThreshold = energyMean + parameters.thresholdMultiplier * energyStd

        // ZCR: используем медиану для более робастного определения
        let sortedZCR = zcrValues.sorted()
        let zcrMedian = sortedZCR[sortedZCR.count / 2]
        let zcrThreshold = zcrMedian * 1.2  // 20% выше медианы

        return (energyThreshold, zcrThreshold)
    }

    /// Вычисляет стандартное отклонение
    private func standardDeviation(_ values: [Float], mean: Float) -> Float {
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Float(values.count)
        return sqrt(variance)
    }

    /// Вычисляет RMS (Root Mean Square) для окна
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else {
            return 0
        }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

        return rms
    }

    /// Вычисляет Zero Crossing Rate (ZCR) - количество пересечений нуля
    /// Речь имеет характерный паттерн ZCR (обычно 0.05-0.15)
    private func calculateZCR(_ samples: [Float]) -> Float {
        guard samples.count > 1 else {
            return 0
        }

        var crossings = 0

        for i in 1..<samples.count {
            if (samples[i] >= 0 && samples[i - 1] < 0) || (samples[i] < 0 && samples[i - 1] >= 0) {
                crossings += 1
            }
        }

        return Float(crossings) / Float(samples.count)
    }

    /// Извлекает аудио для конкретного сегмента
    public func extractAudio(for segment: SpeechSegment, from samples: [Float]) -> [Float] {
        let startIndex = max(0, segment.startSample)
        let endIndex = min(samples.count, segment.endSample)

        guard startIndex < endIndex && startIndex < samples.count else {
            return []
        }

        return Array(samples[startIndex..<endIndex])
    }
}

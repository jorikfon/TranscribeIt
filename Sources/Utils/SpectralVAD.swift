import Foundation
import Accelerate

/// Voice Activity Detector со спектральным анализом
/// Использует FFT для анализа частотного содержимого
/// Речь обычно имеет энергию в диапазоне 300-3400 Hz
public class SpectralVAD {

    /// Параметры спектрального VAD
    public struct Parameters {
        /// Размер окна FFT (должен быть степенью 2)
        public let fftSize: Int

        /// Минимальная длительность речи в секундах
        public let minSpeechDuration: TimeInterval

        /// Минимальная длительность тишины для разделения сегментов
        public let minSilenceDuration: TimeInterval

        /// Минимальная частота для речи (Hz)
        public let speechFreqMin: Float

        /// Максимальная частота для речи (Hz)
        public let speechFreqMax: Float

        /// Порог энергии в речевом диапазоне (относительно общей энергии)
        public let speechEnergyRatio: Float

        /// Параметры по умолчанию
        public static let `default` = Parameters(
            fftSize: 512,
            minSpeechDuration: 0.5,
            minSilenceDuration: 0.3,
            speechFreqMin: 300,
            speechFreqMax: 3400,
            speechEnergyRatio: 0.3
        )

        /// Параметры для телефонного аудио (узкополосное 300-3400 Hz)
        public static let telephone = Parameters(
            fftSize: 512,
            minSpeechDuration: 0.3,
            minSilenceDuration: 0.5,
            speechFreqMin: 300,
            speechFreqMax: 3400,
            speechEnergyRatio: 0.25
        )

        /// Параметры для широкополосного аудио
        public static let wideband = Parameters(
            fftSize: 1024,
            minSpeechDuration: 0.3,
            minSilenceDuration: 0.3,
            speechFreqMin: 80,
            speechFreqMax: 8000,
            speechEnergyRatio: 0.4
        )

        public init(
            fftSize: Int = 512,
            minSpeechDuration: TimeInterval = 0.5,
            minSilenceDuration: TimeInterval = 0.3,
            speechFreqMin: Float = 300,
            speechFreqMax: Float = 3400,
            speechEnergyRatio: Float = 0.3
        ) {
            self.fftSize = fftSize
            self.minSpeechDuration = minSpeechDuration
            self.minSilenceDuration = minSilenceDuration
            self.speechFreqMin = speechFreqMin
            self.speechFreqMax = speechFreqMax
            self.speechEnergyRatio = speechEnergyRatio
        }
    }

    private let parameters: Parameters
    private let sampleRate: Double = 16000.0
    private var fftSetup: FFTSetup?

    public init(parameters: Parameters = .default) {
        self.parameters = parameters

        // Создаем FFT setup
        let log2n = vDSP_Length(log2(Float(parameters.fftSize)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }

    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    /// Определяет сегменты речи с использованием спектрального анализа
    public func detectSpeechSegments(in samples: [Float]) -> [SpeechSegment] {
        guard !samples.isEmpty, let fftSetup = fftSetup else {
            return []
        }

        let hopSize = parameters.fftSize / 2

        // Вычисляем спектральные метрики для каждого окна
        var metrics: [(time: TimeInterval, speechEnergy: Float, totalEnergy: Float)] = []

        var position = 0
        while position + parameters.fftSize <= samples.count {
            let window = Array(samples[position..<(position + parameters.fftSize)])
            let time = Double(position) / sampleRate

            // Применяем окно Ханна
            let windowedSamples = applyHannWindow(window)

            // Вычисляем FFT
            let (speechEnergy, totalEnergy) = calculateSpeechEnergy(windowedSamples, fftSetup: fftSetup)

            metrics.append((time: time, speechEnergy: speechEnergy, totalEnergy: totalEnergy))
            position += hopSize
        }

        // Определяем адаптивный порог
        let threshold = calculateAdaptiveThreshold(metrics: metrics)

        LogManager.app.debug("SpectralVAD: адаптивный порог = \(String(format: "%.4f", threshold))")

        // Определяем сегменты речи
        var segments: [SpeechSegment] = []
        var currentSegmentStart: TimeInterval? = nil
        var lastSpeechTime: TimeInterval = 0

        for metric in metrics {
            let energyRatio = metric.totalEnergy > 0.0001 ? metric.speechEnergy / metric.totalEnergy : 0
            let isSpeech = energyRatio >= threshold

            if isSpeech {
                if currentSegmentStart == nil {
                    currentSegmentStart = metric.time
                }
                lastSpeechTime = metric.time + Double(parameters.fftSize) / sampleRate
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

    /// Вычисляет адаптивный порог на основе статистики
    private func calculateAdaptiveThreshold(
        metrics: [(time: TimeInterval, speechEnergy: Float, totalEnergy: Float)]
    ) -> Float {
        guard !metrics.isEmpty else {
            return parameters.speechEnergyRatio
        }

        let ratios = metrics.compactMap { metric -> Float? in
            guard metric.totalEnergy > 0.0001 else { return nil }
            return metric.speechEnergy / metric.totalEnergy
        }

        guard !ratios.isEmpty else {
            return parameters.speechEnergyRatio
        }

        // Используем медиану для робастности
        let sortedRatios = ratios.sorted()
        let median = sortedRatios[sortedRatios.count / 2]

        // Порог = медиана * 0.8 (немного ниже медианы для чувствительности)
        return max(median * 0.8, parameters.speechEnergyRatio)
    }

    /// Вычисляет энергию в речевом диапазоне частот
    private func calculateSpeechEnergy(_ samples: [Float], fftSetup: FFTSetup) -> (speechEnergy: Float, totalEnergy: Float) {
        let n = vDSP_Length(parameters.fftSize)
        let log2n = vDSP_Length(log2(Float(parameters.fftSize)))

        // Подготавливаем буферы
        var realp = [Float](repeating: 0, count: parameters.fftSize / 2)
        var imagp = [Float](repeating: 0, count: parameters.fftSize / 2)

        var splitComplex = DSPSplitComplex(realp: &realp, imagp: &imagp)

        // Конвертируем в split complex format
        var input = samples
        input.withUnsafeMutableBufferPointer { inputPtr in
            inputPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: parameters.fftSize / 2) { complexPtr in
                vDSP_ctoz(complexPtr, 2, &splitComplex, 1, n / 2)
            }
        }

        // Выполняем FFT
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

        // Вычисляем магнитуды (энергию каждой частоты)
        var magnitudes = [Float](repeating: 0, count: parameters.fftSize / 2)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, n / 2)

        // Определяем индексы частотных бинов для речевого диапазона
        let freqResolution = Float(sampleRate) / Float(parameters.fftSize)
        let minBin = Int(parameters.speechFreqMin / freqResolution)
        let maxBin = min(Int(parameters.speechFreqMax / freqResolution), magnitudes.count - 1)

        // Защита от невалидного диапазона
        guard minBin <= maxBin && minBin >= 0 && maxBin < magnitudes.count else {
            LogManager.app.warning("SpectralVAD: невалидный диапазон частот - minBin=\(minBin), maxBin=\(maxBin), magnitudes.count=\(magnitudes.count)")
            return (0, 0)
        }

        // Суммируем энергию в речевом диапазоне
        var speechEnergy: Float = 0
        vDSP_sve(Array(magnitudes[minBin...maxBin]), 1, &speechEnergy, vDSP_Length(maxBin - minBin + 1))

        // Суммируем общую энергию
        var totalEnergy: Float = 0
        vDSP_sve(magnitudes, 1, &totalEnergy, n / 2)

        return (speechEnergy, totalEnergy)
    }

    /// Применяет окно Ханна для уменьшения спектральных утечек
    private func applyHannWindow(_ samples: [Float]) -> [Float] {
        var windowed = samples
        var window = [Float](repeating: 0, count: samples.count)

        // Создаем окно Ханна
        vDSP_hann_window(&window, vDSP_Length(samples.count), Int32(vDSP_HANN_NORM))

        // Применяем окно
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(samples.count))

        return windowed
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

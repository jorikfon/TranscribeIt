import Foundation
import Accelerate

/// Параметры для Voice Activity Detection
public struct VADParameters {
    /// Размер окна анализа в секундах
    public let windowSize: TimeInterval

    /// Минимальная длительность речи в секундах
    public let minSpeechDuration: TimeInterval

    /// Минимальная длительность тишины для разделения сегментов
    public let minSilenceDuration: TimeInterval

    /// Порог RMS для определения речи
    public let rmsThreshold: Float

    /// Параметры по умолчанию - стандартное качество
    public static let `default` = VADParameters(
        windowSize: 0.03,           // 30ms окно
        minSpeechDuration: 0.5,     // Минимум 0.5s речи
        minSilenceDuration: 0.3,    // 300ms тишины для разделения
        rmsThreshold: 0.02          // RMS порог
    )

    /// Параметры для низкого качества / телефонного аудио
    public static let lowQuality = VADParameters(
        windowSize: 0.05,           // Увеличенное окно для более плавного анализа
        minSpeechDuration: 0.3,     // Меньший минимум для коротких реплик
        minSilenceDuration: 0.5,    // Больше тишины для уверенного разделения
        rmsThreshold: 0.01          // Более чувствительный порог
    )

    /// Параметры для высокого качества
    public static let highQuality = VADParameters(
        windowSize: 0.02,           // 20ms окно для точности
        minSpeechDuration: 0.3,
        minSilenceDuration: 0.2,    // Меньше тишины - более частое разделение
        rmsThreshold: 0.03          // Менее чувствительный порог
    )

    public init(
        windowSize: TimeInterval = 0.03,
        minSpeechDuration: TimeInterval = 0.5,
        minSilenceDuration: TimeInterval = 0.3,
        rmsThreshold: Float = 0.02
    ) {
        self.windowSize = windowSize
        self.minSpeechDuration = minSpeechDuration
        self.minSilenceDuration = minSilenceDuration
        self.rmsThreshold = rmsThreshold
    }
}

/// Сегмент речи с временными метками
public struct SpeechSegment {
    /// Время начала в секундах
    public let startTime: TimeInterval

    /// Время окончания в секундах
    public let endTime: TimeInterval

    /// Длительность сегмента
    public var duration: TimeInterval {
        return endTime - startTime
    }

    /// Начальный индекс сэмпла (при 16kHz)
    public var startSample: Int {
        return Int(startTime * 16000)
    }

    /// Конечный индекс сэмпла (при 16kHz)
    public var endSample: Int {
        return Int(endTime * 16000)
    }

    public init(startTime: TimeInterval, endTime: TimeInterval) {
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// Voice Activity Detector - определяет сегменты речи в аудио
/// Использует энергетический метод (RMS) с скользящим окном
public class VoiceActivityDetector {
    private let parameters: VADParameters
    private let sampleRate: Double = 16000.0  // 16kHz

    public init(parameters: VADParameters = .default) {
        self.parameters = parameters
    }

    /// Определяет сегменты речи в аудио
    /// - Parameter samples: Массив аудио сэмплов (16kHz mono)
    /// - Returns: Массив сегментов речи с временными метками
    public func detectSpeechSegments(in samples: [Float]) -> [SpeechSegment] {
        guard !samples.isEmpty else {
            return []
        }

        let windowSamples = Int(parameters.windowSize * sampleRate)
        let hopSamples = windowSamples / 2  // 50% перекрытие

        // Вычисляем RMS для каждого окна
        var rmsValues: [(time: TimeInterval, rms: Float)] = []

        var position = 0
        while position + windowSamples <= samples.count {
            let window = Array(samples[position..<(position + windowSamples)])
            let rms = calculateRMS(window)
            let time = Double(position) / sampleRate

            rmsValues.append((time: time, rms: rms))
            position += hopSamples
        }

        // Определяем сегменты на основе порога
        var segments: [SpeechSegment] = []
        var currentSegmentStart: TimeInterval? = nil
        var lastSpeechTime: TimeInterval = 0

        for (time, rms) in rmsValues {
            let isSpeech = rms >= parameters.rmsThreshold

            if isSpeech {
                if currentSegmentStart == nil {
                    // Начало нового сегмента
                    currentSegmentStart = time
                }
                lastSpeechTime = time + parameters.windowSize
            } else {
                // Тишина
                if let start = currentSegmentStart {
                    let silenceDuration = time - lastSpeechTime

                    if silenceDuration >= parameters.minSilenceDuration {
                        // Достаточно длинная тишина - завершаем сегмент
                        let segment = SpeechSegment(
                            startTime: start,
                            endTime: lastSpeechTime
                        )

                        // Проверяем минимальную длительность
                        if segment.duration >= parameters.minSpeechDuration {
                            segments.append(segment)
                        }

                        currentSegmentStart = nil
                    }
                }
            }
        }

        // Завершаем последний сегмент если есть
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

    /// Извлекает аудио для конкретного сегмента
    /// - Parameters:
    ///   - segment: Сегмент речи
    ///   - samples: Полный массив аудио сэмплов
    /// - Returns: Сэмплы для данного сегмента
    public func extractSegment(_ segment: SpeechSegment, from samples: [Float]) -> [Float] {
        let startIndex = max(0, segment.startSample)
        let endIndex = min(samples.count, segment.endSample)

        guard startIndex < endIndex && startIndex < samples.count else {
            return []
        }

        return Array(samples[startIndex..<endIndex])
    }

    /// Алиас для extractSegment (для обратной совместимости)
    public func extractAudio(for segment: SpeechSegment, from samples: [Float]) -> [Float] {
        return extractSegment(segment, from: samples)
    }

    /// Вычисляет RMS (Root Mean Square) для массива сэмплов
    /// - Parameter samples: Аудио сэмплы
    /// - Returns: RMS значение
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else {
            return 0
        }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

        return rms
    }

    /// Проверяет, содержит ли аудио речь
    /// - Parameter samples: Аудио сэмплы
    /// - Returns: true если обнаружена речь
    public func hasSpeech(in samples: [Float]) -> Bool {
        let segments = detectSpeechSegments(in: samples)
        return !segments.isEmpty
    }

    /// Вычисляет общую длительность речи в аудио
    /// - Parameter samples: Аудио сэмплы
    /// - Returns: Суммарная длительность речи в секундах
    public func totalSpeechDuration(in samples: [Float]) -> TimeInterval {
        let segments = detectSpeechSegments(in: samples)
        return segments.reduce(0) { $0 + $1.duration }
    }
}

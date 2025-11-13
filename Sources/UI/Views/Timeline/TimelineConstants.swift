//
//  TimelineConstants.swift
//  TranscribeIt
//
//  Created on 2025-11-13.
//  Centralized constants for Timeline components (Task 7.1)
//

import CoreGraphics
import Foundation

/// Centralized constants for timeline visualization and compression
///
/// This enum provides all magic numbers used throughout timeline components:
/// - Silence gap compression parameters
/// - Visual scaling and layout dimensions
/// - Synchronization tolerances
/// - Duration bar scaling factors
///
/// ## Usage
/// ```swift
/// let minGap = TimelineConstants.Compression.minSilenceGapToCompress
/// let scale = TimelineConstants.Scaling.defaultPixelsPerSecond
/// let tolerance = TimelineConstants.Synchronization.turnTimeTolerance
/// ```
public enum TimelineConstants {

    // MARK: - Compression Constants

    /// Параметры сжатия промежутков тишины в timeline
    public enum Compression {
        /// Минимальная длительность промежутка тишины для сжатия (в секундах)
        ///
        /// Промежутки короче этого значения не сжимаются для естественного отображения.
        /// **Значение:** 0.5 секунды (агрессивное сжатие для компактного отображения)
        public static let minSilenceGapToCompress: TimeInterval = 0.5

        /// Длительность отображения сжатого промежутка тишины (в секундах)
        ///
        /// Все сжатые промежутки визуально отображаются с этой длительностью.
        /// **Значение:** 0.15 секунды (минимальный заметный визуальный зазор)
        public static let compressedGapDisplayDuration: TimeInterval = 0.15
    }

    // MARK: - Scaling Constants

    /// Параметры визуального масштабирования timeline
    public enum Scaling {
        /// Минимальное количество пикселей на секунду для компактного отображения
        ///
        /// Используется для длинных диалогов, чтобы уместить их на экран.
        /// **Значение:** 15 пикселей/секунда
        public static let minPixelsPerSecond: CGFloat = 15

        /// Максимальное количество пикселей на секунду для детального отображения
        ///
        /// Используется для очень коротких диалогов, чтобы сделать их более читабельными.
        /// **Значение:** 80 пикселей/секунда
        public static let maxPixelsPerSecond: CGFloat = 80

        /// Максимальная высота timeline в пикселях
        ///
        /// Ограничивает общую высоту timeline view для предотвращения переполнения экрана.
        /// **Значение:** 600 пикселей
        public static let maxTimelineHeight: CGFloat = 600

        /// Масштабный коэффициент по умолчанию для диалогов средней длительности
        ///
        /// Используется когда невозможно вычислить адаптивный масштаб (нет реплик или нулевая длительность).
        /// **Значение:** 40 пикселей/секунда
        public static let defaultPixelsPerSecond: CGFloat = 40
    }

    // MARK: - Synchronization Constants

    /// Параметры синхронизации реплик между колонками
    public enum Synchronization {
        /// Порог времени для объединения реплик в одну строку (в секундах)
        ///
        /// Реплики с разницей во времени меньше этого значения отображаются на одном уровне.
        /// Это позволяет визуализировать одновременную речь обоих спикеров.
        /// **Значение:** 0.5 секунды
        public static let turnTimeTolerance: TimeInterval = 0.5

        /// Минимальная длительность промежутка тишины для отображения индикатора (в секундах)
        ///
        /// Индикатор промежутка тишины показывается только если тишина длится больше этого значения.
        /// Короткие паузы игнорируются для визуальной чистоты.
        /// **Значение:** 1.0 секунда
        public static let significantSilenceThreshold: TimeInterval = 1.0

        /// Минимальная длительность промежутка в рамках одного канала для отображения (в секундах)
        ///
        /// Используется при вычислении промежутков тишины внутри одного канала (один спикер).
        /// **Значение:** 2.0 секунды
        public static let singleChannelSilenceThreshold: TimeInterval = 2.0
    }

    // MARK: - Duration Bar Constants

    /// Параметры визуализации полоски длительности реплики
    public enum DurationBar {
        /// Масштабный коэффициент для визуализации длительности (пиксели/секунда)
        ///
        /// Используется для отображения цветной полоски длительности слева от реплики.
        /// **Значение:** 3 пикселя = 1 секунда
        public static let scale: CGFloat = 3.0
    }
}

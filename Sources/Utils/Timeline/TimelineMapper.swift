//
//  TimelineMapper.swift
//  TranscribeIt
//
//  Created on 2025-11-10.
//  Выделено из MainWindow.swift в рамках рефакторинга (задача 3.2)
//

import Foundation

/// Mapper для сжатия временной шкалы диалога, исключая длительные периоды тишины
///
/// Основная задача: визуально сжимать промежутки тишины (когда ОБА спикера молчат),
/// чтобы диалог отображался более компактно без потери информации о реальных временных метках.
///
/// ## Алгоритм работы
///
/// 1. **Анализ реплик**: Находит все временные интервалы, когда говорит хотя бы один спикер
/// 2. **Объединение интервалов**: Объединяет перекрывающиеся интервалы активности
/// 3. **Поиск тишины**: Находит промежутки между интервалами активности (когда ОБА спикера молчат)
/// 4. **Сжатие**: Длинные промежутки тишины (> 0.5 сек) визуально сжимаются до 0.15 сек
/// 5. **Маппинг**: Преобразует реальное время в визуальное с учетом сжатия
///
/// ## Использование
///
/// ```swift
/// let mapper = CompressedTimelineMapper(turns: dialogue.turns)
///
/// // Получить визуальную позицию для реального времени
/// let visualTime = mapper.visualPosition(for: 10.5)  // 10.5 секунд реального времени
///
/// // Получить общую визуальную длительность
/// let visualDuration = mapper.totalVisualDuration(realDuration: dialogue.totalDuration)
///
/// // Проверить найденные промежутки тишины
/// print("Найдено \(mapper.silenceGaps.count) промежутков тишины")
/// ```
///
/// ## Пример сжатия
///
/// **До сжатия:**
/// ```
/// [Спикер 1: 0-2сек] ----тишина (3 сек)---- [Спикер 2: 5-7сек]
/// ```
///
/// **После сжатия:**
/// ```
/// [Спикер 1: 0-2сек] -0.15сек- [Спикер 2: 2.15-4.15сек]
/// ```
public struct CompressedTimelineMapper {

    // MARK: - Public Types

    /// Представляет промежуток тишины, когда оба спикера молчат
    public struct SilenceGap {
        /// Реальное время начала промежутка тишины
        public let realStartTime: TimeInterval

        /// Реальное время окончания промежутка тишины
        public let realEndTime: TimeInterval

        /// Длительность промежутка тишины в секундах
        public let duration: TimeInterval
    }

    // MARK: - Public Properties

    /// Массив найденных промежутков тишины, отсортированных по времени
    public let silenceGaps: [SilenceGap]

    /// Минимальная длительность промежутка тишины для сжатия (в секундах)
    ///
    /// Промежутки короче этого значения не сжимаются.
    /// По умолчанию: 0.5 секунды (агрессивное сжатие для компактного отображения)
    public let minGapToCompress: TimeInterval = TimelineConstants.Compression.minSilenceGapToCompress

    /// Длительность отображения сжатого промежутка тишины (в секундах)
    ///
    /// Все сжатые промежутки визуально отображаются с этой длительностью.
    /// По умолчанию: 0.15 секунды (минимальный заметный визуальный зазор)
    public let compressedGapDisplay: TimeInterval = TimelineConstants.Compression.compressedGapDisplayDuration

    // MARK: - Initialization

    /// Инициализирует mapper, анализируя реплики и находя периоды тишины
    ///
    /// - Parameter turns: Массив всех реплик диалога (обоих спикеров)
    ///
    /// - Note: Алгоритм ищет только промежутки, где ОБА спикера молчат одновременно.
    ///         Если один спикер говорит, а второй молчит - это НЕ считается тишиной.
    ///
    /// ## Пример
    ///
    /// ```swift
    /// let turns = [
    ///     DialogueTranscription.Turn(speaker: .left, text: "Hello", startTime: 0, endTime: 2),
    ///     DialogueTranscription.Turn(speaker: .right, text: "Hi", startTime: 5, endTime: 7)
    /// ]
    /// let mapper = CompressedTimelineMapper(turns: turns)
    /// // mapper.silenceGaps.count == 1 (тишина между 2 и 5 секундами)
    /// ```
    public init(turns: [DialogueTranscription.Turn]) {
        let sortedTurns = turns.sorted { $0.startTime < $1.startTime }
        var gaps: [SilenceGap] = []

        // Логирование для отладки
        LogManager.app.debug("CompressedTimelineMapper: Анализ \(sortedTurns.count) реплик для поиска gaps")

        guard !sortedTurns.isEmpty else {
            self.silenceGaps = []
            return
        }

        // 1. Создаем массив всех занятых временных интервалов
        var occupiedIntervals: [(start: TimeInterval, end: TimeInterval)] = []
        for turn in sortedTurns {
            occupiedIntervals.append((start: turn.startTime, end: turn.endTime))
        }

        // 2. Сортируем интервалы по началу
        occupiedIntervals.sort { $0.start < $1.start }

        // 3. Объединяем перекрывающиеся интервалы
        var mergedIntervals: [(start: TimeInterval, end: TimeInterval)] = []
        var currentInterval = occupiedIntervals[0]

        for i in 1..<occupiedIntervals.count {
            let nextInterval = occupiedIntervals[i]

            if nextInterval.start <= currentInterval.end {
                // Интервалы перекрываются или соприкасаются - объединяем
                currentInterval.end = max(currentInterval.end, nextInterval.end)
            } else {
                // Интервалы не перекрываются - сохраняем текущий и начинаем новый
                mergedIntervals.append(currentInterval)
                currentInterval = nextInterval
            }
        }
        mergedIntervals.append(currentInterval)

        LogManager.app.debug("  Объединено в \(mergedIntervals.count) непрерывных интервалов активности")

        // 4. Находим промежутки тишины между объединенными интервалами
        for i in 0..<(mergedIntervals.count - 1) {
            let currentEnd = mergedIntervals[i].end
            let nextStart = mergedIntervals[i + 1].start
            let gapDuration = nextStart - currentEnd

            // Сжимаем только длинные промежутки тишины (оба спикера молчат)
            if gapDuration > minGapToCompress {
                gaps.append(SilenceGap(
                    realStartTime: currentEnd,
                    realEndTime: nextStart,
                    duration: gapDuration
                ))
                LogManager.app.debug("  Тишина (оба молчат): \(String(format: "%.1f", currentEnd))s - \(String(format: "%.1f", nextStart))s (длительность: \(String(format: "%.1f", gapDuration))s)")
            }
        }

        self.silenceGaps = gaps
        LogManager.app.info("CompressedTimelineMapper: Найдено \(gaps.count) периодов тишины (оба спикера) для сжатия")
    }

    // MARK: - Public Methods

    /// Преобразует реальное время в визуальную позицию (с учетом сжатия)
    ///
    /// - Parameter realTime: Реальное время в секундах
    /// - Returns: Визуальное время в секундах (после сжатия промежутков тишины)
    ///
    /// ## Логика преобразования
    ///
    /// Для каждого промежутка тишины, который находится до `realTime`:
    /// - Если `realTime` после промежутка: вычитаем полную компрессию
    /// - Если `realTime` внутри промежутка: вычитаем частичную компрессию пропорционально позиции
    ///
    /// ## Пример
    ///
    /// ```swift
    /// // Допустим, есть промежуток тишины 2-5сек (длительность 3сек), сжатый до 0.15сек
    /// let mapper = CompressedTimelineMapper(turns: turns)
    /// let visual = mapper.visualPosition(for: 7.0)  // 7 секунд реального времени
    /// // visual ≈ 4.15 (7.0 - (3.0 - 0.15) = 4.15 секунд визуального времени)
    /// ```
    public func visualPosition(for realTime: TimeInterval) -> TimeInterval {
        var visualTime = realTime

        // Вычитаем сжатые интервалы для всех gaps, которые до этого времени
        for gap in silenceGaps {
            if realTime > gap.realStartTime {
                let compressionAmount = min(gap.duration - compressedGapDisplay, gap.duration)
                if realTime >= gap.realEndTime {
                    // Полностью прошли gap - вычитаем всю компрессию
                    visualTime -= compressionAmount
                } else {
                    // Внутри gap - частичная компрессия
                    let withinGap = realTime - gap.realStartTime
                    let ratio = withinGap / gap.duration
                    visualTime -= compressionAmount * ratio
                }
            }
        }

        return max(0, visualTime)
    }

    /// Возвращает общую визуальную длительность (сжатую)
    ///
    /// - Parameter realDuration: Реальная общая длительность диалога в секундах
    /// - Returns: Визуальная длительность в секундах (после сжатия всех промежутков тишины)
    ///
    /// ## Формула
    ///
    /// ```
    /// visualDuration = realDuration - Σ(gap.duration - compressedGapDisplay)
    /// ```
    ///
    /// ## Пример
    ///
    /// ```swift
    /// // Диалог 60 секунд с двумя промежутками тишины по 5 секунд каждый
    /// let mapper = CompressedTimelineMapper(turns: turns)
    /// let visual = mapper.totalVisualDuration(realDuration: 60.0)
    /// // visual ≈ 50.3 (60 - 2*(5 - 0.15) = 60 - 9.7 = 50.3 секунд)
    /// ```
    public func totalVisualDuration(realDuration: TimeInterval) -> TimeInterval {
        let totalCompression = silenceGaps.reduce(0.0) { sum, gap in
            sum + (gap.duration - compressedGapDisplay)
        }
        return max(0, realDuration - totalCompression)
    }
}

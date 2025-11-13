//
//  TimelineMapperTests.swift
//  TranscribeItCoreTests
//
//  Created on 2025-11-12.
//  Тесты для CompressedTimelineMapper (задача 4.2)
//

import XCTest
@testable import TranscribeItCore

/// Тесты для CompressedTimelineMapper - алгоритма сжатия временной шкалы диалога
///
/// Проверяет:
/// - Обнаружение промежутков тишины между репликами
/// - Сжатие длинных промежутков (>0.5 сек) до 0.15 сек
/// - Преобразование реального времени в визуальное
/// - Вычисление общей визуальной длительности
/// - Обработку overlapping реплик (когда спикеры говорят одновременно)
/// - Обработку edge cases (пустой диалог, одна реплика, нет тишины)
final class TimelineMapperTests: XCTestCase {

    // MARK: - Helper Methods

    /// Создает тестовую реплику
    private func makeTurn(
        speaker: DialogueTranscription.Turn.Speaker,
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> DialogueTranscription.Turn {
        return DialogueTranscription.Turn(
            speaker: speaker,
            text: text,
            startTime: startTime,
            endTime: endTime
        )
    }

    // MARK: - Silence Gap Detection Tests

    /// Тест: Обнаружение простого промежутка тишины между двумя репликами
    func testSimpleSilenceGapDetection() {
        // Given: Две реплики с промежутком тишины 3 секунды
        let turns = [
            makeTurn(speaker: .left, text: "Hello", startTime: 0, endTime: 2),
            makeTurn(speaker: .right, text: "World", startTime: 5, endTime: 7)
        ]

        // When: Создаем mapper
        let mapper = CompressedTimelineMapper(turns: turns)

        // Then: Должен найти один промежуток тишины
        XCTAssertEqual(mapper.silenceGaps.count, 1, "Должен найти ровно один промежуток тишины")

        let gap = mapper.silenceGaps[0]
        XCTAssertEqual(gap.realStartTime, 2.0, accuracy: 0.01, "Тишина начинается в 2 секунды")
        XCTAssertEqual(gap.realEndTime, 5.0, accuracy: 0.01, "Тишина заканчивается в 5 секунд")
        XCTAssertEqual(gap.duration, 3.0, accuracy: 0.01, "Длительность тишины 3 секунды")
    }

    /// Тест: Множественные промежутки тишины
    func testMultipleSilenceGaps() {
        // Given: Три реплики с двумя промежутками тишины
        let turns = [
            makeTurn(speaker: .left, text: "First", startTime: 0, endTime: 2),
            makeTurn(speaker: .right, text: "Second", startTime: 5, endTime: 7),
            makeTurn(speaker: .left, text: "Third", startTime: 10, endTime: 12)
        ]

        // When
        let mapper = CompressedTimelineMapper(turns: turns)

        // Then: Должно быть два промежутка тишины
        XCTAssertEqual(mapper.silenceGaps.count, 2, "Должно быть два промежутка тишины")

        // Проверяем первый промежуток
        let firstGap = mapper.silenceGaps[0]
        XCTAssertEqual(firstGap.realStartTime, 2.0, accuracy: 0.01)
        XCTAssertEqual(firstGap.realEndTime, 5.0, accuracy: 0.01)
        XCTAssertEqual(firstGap.duration, 3.0, accuracy: 0.01)

        // Проверяем второй промежуток
        let secondGap = mapper.silenceGaps[1]
        XCTAssertEqual(secondGap.realStartTime, 7.0, accuracy: 0.01)
        XCTAssertEqual(secondGap.realEndTime, 10.0, accuracy: 0.01)
        XCTAssertEqual(secondGap.duration, 3.0, accuracy: 0.01)
    }

    /// Тест: Короткий промежуток НЕ должен считаться тишиной для сжатия
    func testShortGapNotCompressed() {
        // Given: Две реплики с коротким промежутком (0.3 сек < 0.5 порог)
        let turns = [
            makeTurn(speaker: .left, text: "Quick", startTime: 0, endTime: 2),
            makeTurn(speaker: .right, text: "Response", startTime: 2.3, endTime: 4)
        ]

        // When
        let mapper = CompressedTimelineMapper(turns: turns)

        // Then: Не должно быть промежутков для сжатия
        XCTAssertEqual(mapper.silenceGaps.count, 0, "Короткий промежуток (<0.5s) не должен сжиматься")
    }

    /// Тест: Граничный случай - промежуток ровно на пороге сжатия
    func testGapExactlyAtThreshold() {
        // Given: Промежуток ровно 0.5 секунды (на границе порога minGapToCompress)
        let turns = [
            makeTurn(speaker: .left, text: "Test", startTime: 0, endTime: 2),
            makeTurn(speaker: .right, text: "Test2", startTime: 2.5, endTime: 4)
        ]

        // When
        let mapper = CompressedTimelineMapper(turns: turns)

        // Then: Промежуток 0.5 секунды не сжимается (нужно строго больше)
        XCTAssertEqual(mapper.silenceGaps.count, 0, "Промежуток ровно 0.5s не должен сжиматься (нужно > 0.5)")
    }

    /// Тест: Промежуток чуть больше порога должен сжиматься
    func testGapJustAboveThreshold() {
        // Given: Промежуток 0.51 секунды (чуть больше порога 0.5)
        let turns = [
            makeTurn(speaker: .left, text: "Test", startTime: 0, endTime: 2),
            makeTurn(speaker: .right, text: "Test2", startTime: 2.51, endTime: 4)
        ]

        // When
        let mapper = CompressedTimelineMapper(turns: turns)

        // Then: Должен найти один промежуток для сжатия
        XCTAssertEqual(mapper.silenceGaps.count, 1, "Промежуток 0.51s должен сжиматься")
        XCTAssertEqual(mapper.silenceGaps[0].duration, 0.51, accuracy: 0.01)
    }

    // MARK: - Overlapping Turns Tests

    /// Тест: Overlapping реплики (спикеры говорят одновременно) НЕ создают промежуток тишины
    func testOverlappingTurnsNoGap() {
        // Given: Две реплики, которые перекрываются по времени
        let turns = [
            makeTurn(speaker: .left, text: "First", startTime: 0, endTime: 5),
            makeTurn(speaker: .right, text: "Second", startTime: 3, endTime: 7)  // Начинается до окончания первой
        ]

        // When
        let mapper = CompressedTimelineMapper(turns: turns)

        // Then: Не должно быть промежутков тишины
        XCTAssertEqual(mapper.silenceGaps.count, 0, "Overlapping реплики не создают промежуток тишины")
    }

    /// Тест: Частичное перекрытие с последующей тишиной
    func testPartialOverlapWithSilenceAfter() {
        // Given: Три реплики - две overlapping, затем тишина и третья
        let turns = [
            makeTurn(speaker: .left, text: "First", startTime: 0, endTime: 5),
            makeTurn(speaker: .right, text: "Second", startTime: 3, endTime: 7),  // Overlapping
            makeTurn(speaker: .left, text: "Third", startTime: 10, endTime: 12)  // После тишины
        ]

        // When
        let mapper = CompressedTimelineMapper(turns: turns)

        // Then: Должен найти один промежуток между 7 и 10 секундами
        XCTAssertEqual(mapper.silenceGaps.count, 1, "Должен найти тишину после overlapping реплик")
        XCTAssertEqual(mapper.silenceGaps[0].realStartTime, 7.0, accuracy: 0.01)
        XCTAssertEqual(mapper.silenceGaps[0].realEndTime, 10.0, accuracy: 0.01)
    }

    /// Тест: Полное перекрытие (одна реплика внутри другой)
    func testFullyNestedTurns() {
        // Given: Одна реплика полностью внутри другой
        let turns = [
            makeTurn(speaker: .left, text: "Long speech", startTime: 0, endTime: 10),
            makeTurn(speaker: .right, text: "Short", startTime: 3, endTime: 5),  // Полностью внутри
            makeTurn(speaker: .left, text: "After", startTime: 15, endTime: 17)
        ]

        // When
        let mapper = CompressedTimelineMapper(turns: turns)

        // Then: Должен найти тишину только между 10 и 15 секундами
        XCTAssertEqual(mapper.silenceGaps.count, 1)
        XCTAssertEqual(mapper.silenceGaps[0].realStartTime, 10.0, accuracy: 0.01)
        XCTAssertEqual(mapper.silenceGaps[0].realEndTime, 15.0, accuracy: 0.01)
    }

    // MARK: - Visual Position Mapping Tests

    /// Тест: Визуальная позиция ДО промежутка тишины остается без изменений
    func testVisualPositionBeforeGap() {
        // Given: Реплики с промежутком тишины 2-5 секунд
        let turns = [
            makeTurn(speaker: .left, text: "Hello", startTime: 0, endTime: 2),
            makeTurn(speaker: .right, text: "World", startTime: 5, endTime: 7)
        ]
        let mapper = CompressedTimelineMapper(turns: turns)

        // When: Запрашиваем визуальную позицию до промежутка
        let visualTime = mapper.visualPosition(for: 1.5)

        // Then: Визуальное время равно реальному (нет сжатия)
        XCTAssertEqual(visualTime, 1.5, accuracy: 0.01, "До промежутка тишины время не меняется")
    }

    /// Тест: Визуальная позиция ПОСЛЕ промежутка тишины сдвигается
    func testVisualPositionAfterGap() {
        // Given: Промежуток тишины 2-5 секунд (длительность 3 сек)
        let turns = [
            makeTurn(speaker: .left, text: "Hello", startTime: 0, endTime: 2),
            makeTurn(speaker: .right, text: "World", startTime: 5, endTime: 7)
        ]
        let mapper = CompressedTimelineMapper(turns: turns)

        // When: Запрашиваем визуальную позицию после промежутка
        let realTime = 7.0
        let visualTime = mapper.visualPosition(for: realTime)

        // Then: Компрессия = 3.0 - 0.15 = 2.85 секунд
        // Визуальное время = 7.0 - 2.85 = 4.15
        let expectedCompression = 3.0 - 0.15
        let expectedVisual = realTime - expectedCompression
        XCTAssertEqual(visualTime, expectedVisual, accuracy: 0.01,
                      "После промежутка время сжимается на \(expectedCompression) секунд")
    }

    /// Тест: Визуальная позиция ВНУТРИ промежутка тишины
    func testVisualPositionInsideGap() {
        // Given: Промежуток тишины 2-5 секунд (длительность 3 сек)
        let turns = [
            makeTurn(speaker: .left, text: "Hello", startTime: 0, endTime: 2),
            makeTurn(speaker: .right, text: "World", startTime: 5, endTime: 7)
        ]
        let mapper = CompressedTimelineMapper(turns: turns)

        // When: Запрашиваем визуальную позицию в середине промежутка
        let realTime = 3.5  // В середине промежутка 2-5
        let visualTime = mapper.visualPosition(for: realTime)

        // Then: Частичная компрессия
        // Прошли 1.5 сек из 3.0 сек промежутка (ratio = 0.5)
        // Компрессия = (3.0 - 0.15) * 0.5 = 1.425
        // Визуальное время = 3.5 - 1.425 = 2.075
        let compression = (3.0 - 0.15)
        let ratio = (realTime - 2.0) / 3.0  // (3.5 - 2.0) / 3.0 = 0.5
        let expectedVisual = realTime - (compression * ratio)
        XCTAssertEqual(visualTime, expectedVisual, accuracy: 0.01,
                      "Внутри промежутка применяется частичная компрессия")
    }

    /// Тест: Множественные промежутки - суммарная компрессия
    func testVisualPositionWithMultipleGaps() {
        // Given: Три реплики с двумя промежутками по 3 секунды каждый
        let turns = [
            makeTurn(speaker: .left, text: "First", startTime: 0, endTime: 2),
            makeTurn(speaker: .right, text: "Second", startTime: 5, endTime: 7),
            makeTurn(speaker: .left, text: "Third", startTime: 10, endTime: 12)
        ]
        let mapper = CompressedTimelineMapper(turns: turns)

        // When: Запрашиваем позицию после обоих промежутков
        let realTime = 12.0
        let visualTime = mapper.visualPosition(for: realTime)

        // Then: Суммарная компрессия от двух промежутков
        // Gap 1: 2-5 (3 сек) → компрессия 2.85
        // Gap 2: 7-10 (3 сек) → компрессия 2.85
        // Общая компрессия: 5.7 секунд
        let compressionPerGap = 3.0 - 0.15
        let totalCompression = compressionPerGap * 2
        let expectedVisual = realTime - totalCompression
        XCTAssertEqual(visualTime, expectedVisual, accuracy: 0.01,
                      "Компрессия от нескольких промежутков суммируется")
    }

    // MARK: - Total Visual Duration Tests

    /// Тест: Общая визуальная длительность без промежутков тишины
    func testTotalDurationWithoutGaps() {
        // Given: Непрерывный диалог без промежутков
        let turns = [
            makeTurn(speaker: .left, text: "First", startTime: 0, endTime: 5),
            makeTurn(speaker: .right, text: "Second", startTime: 5, endTime: 10)
        ]
        let mapper = CompressedTimelineMapper(turns: turns)

        // When
        let visualDuration = mapper.totalVisualDuration(realDuration: 10.0)

        // Then: Визуальная длительность равна реальной
        XCTAssertEqual(visualDuration, 10.0, accuracy: 0.01,
                      "Без промежутков тишины длительность не меняется")
    }

    /// Тест: Общая визуальная длительность с одним промежутком
    func testTotalDurationWithSingleGap() {
        // Given: Диалог с одним промежутком тишины 3 секунды
        let turns = [
            makeTurn(speaker: .left, text: "Hello", startTime: 0, endTime: 2),
            makeTurn(speaker: .right, text: "World", startTime: 5, endTime: 7)
        ]
        let mapper = CompressedTimelineMapper(turns: turns)

        // When
        let realDuration = 7.0
        let visualDuration = mapper.totalVisualDuration(realDuration: realDuration)

        // Then: Вычитаем компрессию одного промежутка
        // Компрессия = 3.0 - 0.15 = 2.85
        // Визуальная длительность = 7.0 - 2.85 = 4.15
        let compression = 3.0 - 0.15
        let expectedDuration = realDuration - compression
        XCTAssertEqual(visualDuration, expectedDuration, accuracy: 0.01,
                      "Визуальная длительность уменьшается на величину компрессии")
    }

    /// Тест: Общая визуальная длительность с несколькими промежутками
    func testTotalDurationWithMultipleGaps() {
        // Given: Диалог с двумя промежутками тишины
        let turns = [
            makeTurn(speaker: .left, text: "First", startTime: 0, endTime: 2),
            makeTurn(speaker: .right, text: "Second", startTime: 6, endTime: 8),  // Gap 1: 2-6 (4 сек)
            makeTurn(speaker: .left, text: "Third", startTime: 13, endTime: 15)   // Gap 2: 8-13 (5 сек)
        ]
        let mapper = CompressedTimelineMapper(turns: turns)

        // When
        let realDuration = 15.0
        let visualDuration = mapper.totalVisualDuration(realDuration: realDuration)

        // Then: Вычитаем компрессию обоих промежутков
        // Gap 1 compression: 4.0 - 0.15 = 3.85
        // Gap 2 compression: 5.0 - 0.15 = 4.85
        // Total compression: 8.7
        // Visual duration: 15.0 - 8.7 = 6.3
        let compression1 = 4.0 - 0.15
        let compression2 = 5.0 - 0.15
        let totalCompression = compression1 + compression2
        let expectedDuration = realDuration - totalCompression
        XCTAssertEqual(visualDuration, expectedDuration, accuracy: 0.01,
                      "Компрессия всех промежутков суммируется")
    }

    // MARK: - Edge Cases Tests

    /// Тест: Пустой массив реплик
    func testEmptyTurnsArray() {
        // Given: Пустой массив
        let turns: [DialogueTranscription.Turn] = []

        // When
        let mapper = CompressedTimelineMapper(turns: turns)

        // Then: Нет промежутков тишины
        XCTAssertEqual(mapper.silenceGaps.count, 0, "Пустой массив не содержит промежутков")
        XCTAssertEqual(mapper.visualPosition(for: 0), 0, accuracy: 0.01)
        XCTAssertEqual(mapper.totalVisualDuration(realDuration: 0), 0, accuracy: 0.01)
    }

    /// Тест: Одна реплика
    func testSingleTurn() {
        // Given: Только одна реплика
        let turns = [
            makeTurn(speaker: .left, text: "Solo", startTime: 0, endTime: 5)
        ]

        // When
        let mapper = CompressedTimelineMapper(turns: turns)

        // Then: Нет промежутков тишины
        XCTAssertEqual(mapper.silenceGaps.count, 0, "Одна реплика не создает промежутков")
        XCTAssertEqual(mapper.visualPosition(for: 3.0), 3.0, accuracy: 0.01)
        XCTAssertEqual(mapper.totalVisualDuration(realDuration: 5.0), 5.0, accuracy: 0.01)
    }

    /// Тест: Реплики в неотсортированном порядке
    func testUnsortedTurns() {
        // Given: Реплики в обратном порядке
        let turns = [
            makeTurn(speaker: .right, text: "Second", startTime: 5, endTime: 7),
            makeTurn(speaker: .left, text: "First", startTime: 0, endTime: 2)
        ]

        // When
        let mapper = CompressedTimelineMapper(turns: turns)

        // Then: Mapper должен автоматически отсортировать и найти промежуток
        XCTAssertEqual(mapper.silenceGaps.count, 1, "Mapper должен обработать неотсортированные реплики")
        XCTAssertEqual(mapper.silenceGaps[0].realStartTime, 2.0, accuracy: 0.01)
        XCTAssertEqual(mapper.silenceGaps[0].realEndTime, 5.0, accuracy: 0.01)
    }

    /// Тест: Отрицательное время (некорректные данные)
    func testNegativeTime() {
        // Given: Корректные реплики
        let turns = [
            makeTurn(speaker: .left, text: "Test", startTime: 0, endTime: 2),
            makeTurn(speaker: .right, text: "Test2", startTime: 5, endTime: 7)
        ]
        let mapper = CompressedTimelineMapper(turns: turns)

        // When: Запрашиваем визуальную позицию для отрицательного времени
        let visualTime = mapper.visualPosition(for: -1.0)

        // Then: Должен вернуть 0 (защита от отрицательных значений)
        XCTAssertEqual(visualTime, 0.0, accuracy: 0.01,
                      "Отрицательное время должно возвращать 0")
    }

    /// Тест: Очень большие временные интервалы
    func testLargeTimeIntervals() {
        // Given: Реплики с большими временными интервалами
        let turns = [
            makeTurn(speaker: .left, text: "Start", startTime: 0, endTime: 10),
            makeTurn(speaker: .right, text: "End", startTime: 1000, endTime: 1010)  // 990 секунд тишины
        ]

        // When
        let mapper = CompressedTimelineMapper(turns: turns)

        // Then: Должен корректно обработать большой промежуток
        XCTAssertEqual(mapper.silenceGaps.count, 1)
        XCTAssertEqual(mapper.silenceGaps[0].duration, 990.0, accuracy: 0.01,
                      "Должен корректно обрабатывать большие промежутки")

        let compression = 990.0 - 0.15
        let expectedVisual = 1010.0 - compression
        XCTAssertEqual(mapper.visualPosition(for: 1010.0), expectedVisual, accuracy: 0.01)
    }

    /// Тест: Соприкасающиеся реплики (endTime = startTime)
    func testAdjacentTurns() {
        // Given: Реплики без промежутка (одна заканчивается, другая начинается)
        let turns = [
            makeTurn(speaker: .left, text: "First", startTime: 0, endTime: 5),
            makeTurn(speaker: .right, text: "Second", startTime: 5, endTime: 10),
            makeTurn(speaker: .left, text: "Third", startTime: 10, endTime: 15)
        ]

        // When
        let mapper = CompressedTimelineMapper(turns: turns)

        // Then: Не должно быть промежутков тишины
        XCTAssertEqual(mapper.silenceGaps.count, 0,
                      "Соприкасающиеся реплики не создают промежутки тишины")
    }
}

import SwiftUI

/// Новый вид: компактные блоки с индикаторами длительности
/// Высота блока = высота текста, слева цветная полоска = длительность
///
/// Отображает две колонки с синхронизированными по времени репликами:
/// - Левая колонка: Speaker 1 (левый канал)
/// - Правая колонка: Speaker 2 (правый канал)
/// - Реплики с близкими временными метками размещаются на одном уровне
/// - Между репликами отображаются индикаторы промежутков тишины
///
/// ## Использование
/// ```swift
/// TimelineDialogueView(
///     dialogue: dialogueTranscription,
///     audioPlayer: audioPlayerManager
/// )
/// ```
public struct TimelineDialogueView: View {
    let dialogue: DialogueTranscription
    @ObservedObject var audioPlayer: AudioPlayerManager

    // Mapper для определения промежутков тишины
    private var timelineMapper: CompressedTimelineMapper {
        CompressedTimelineMapper(turns: dialogue.turns)
    }

    // Масштаб для индикатора длительности (px/sec)
    private let durationBarScale: CGFloat = TimelineConstants.DurationBar.scale

    // Структура для синхронизированной строки (левая и правая реплика на одном уровне)
    struct SyncedRow {
        let leftTurn: DialogueTranscription.Turn?
        let rightTurn: DialogueTranscription.Turn?
        let timestamp: TimeInterval  // Опорная временная метка для строки
    }

    // Синхронизированные строки - реплики с близкими временными метками на одном уровне
    private var syncedRows: [SyncedRow] {
        let leftTurns = dialogue.turns.filter { $0.speaker == .left }.sorted { $0.startTime < $1.startTime }
        let rightTurns = dialogue.turns.filter { $0.speaker == .right }.sorted { $0.startTime < $1.startTime }

        var rows: [SyncedRow] = []
        var leftIndex = 0
        var rightIndex = 0

        // Порог времени для объединения реплик в одну строку
        let timeTolerance: TimeInterval = TimelineConstants.Synchronization.turnTimeTolerance

        while leftIndex < leftTurns.count || rightIndex < rightTurns.count {
            let leftTurn = leftIndex < leftTurns.count ? leftTurns[leftIndex] : nil
            let rightTurn = rightIndex < rightTurns.count ? rightTurns[rightIndex] : nil

            if let left = leftTurn, let right = rightTurn {
                // Обе реплики есть - сравниваем время
                let timeDiff = abs(left.startTime - right.startTime)

                if timeDiff <= timeTolerance {
                    // Реплики близко по времени - объединяем в одну строку
                    let avgTime = (left.startTime + right.startTime) / 2
                    rows.append(SyncedRow(leftTurn: left, rightTurn: right, timestamp: avgTime))
                    leftIndex += 1
                    rightIndex += 1
                } else if left.startTime < right.startTime {
                    // Левая реплика раньше
                    rows.append(SyncedRow(leftTurn: left, rightTurn: nil, timestamp: left.startTime))
                    leftIndex += 1
                } else {
                    // Правая реплика раньше
                    rows.append(SyncedRow(leftTurn: nil, rightTurn: right, timestamp: right.startTime))
                    rightIndex += 1
                }
            } else if let left = leftTurn {
                // Только левая реплика осталась
                rows.append(SyncedRow(leftTurn: left, rightTurn: nil, timestamp: left.startTime))
                leftIndex += 1
            } else if let right = rightTurn {
                // Только правая реплика осталась
                rows.append(SyncedRow(leftTurn: nil, rightTurn: right, timestamp: right.startTime))
                rightIndex += 1
            }
        }

        return rows
    }

    // Вычисляет промежуток тишины между строками
    private func calculateGap(from currentRow: SyncedRow, to nextRow: SyncedRow) -> TimeInterval? {
        // Находим максимальное endTime в текущей строке
        var maxEndTime: TimeInterval = 0
        if let left = currentRow.leftTurn {
            maxEndTime = max(maxEndTime, left.endTime)
        }
        if let right = currentRow.rightTurn {
            maxEndTime = max(maxEndTime, right.endTime)
        }

        // Находим минимальное startTime в следующей строке
        var minStartTime: TimeInterval = .greatestFiniteMagnitude
        if let left = nextRow.leftTurn {
            minStartTime = min(minStartTime, left.startTime)
        }
        if let right = nextRow.rightTurn {
            minStartTime = min(minStartTime, right.startTime)
        }

        let gap = minStartTime - maxEndTime

        // Показываем индикатор только для значительных промежутков
        return gap > TimelineConstants.Synchronization.significantSilenceThreshold ? gap : nil
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Заголовки колонок
                HStack(spacing: 8) {
                    Text("Speaker 1")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.speaker1Accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.speaker1Background)
                        .cornerRadius(6)

                    Text("Speaker 2")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.speaker2Accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.speaker2Background)
                        .cornerRadius(6)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                // DEBUG: Показываем текущее время воспроизведения
                if audioPlayer.state.playback.isPlaying {
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 10))
                        Text("Playing: \(String(format: "%.2f", audioPlayer.state.playback.currentTime))s")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
                    .padding(.horizontal, 12)
                }

                // Синхронизированные реплики - реплики на одном уровне по времени
                VStack(spacing: 0) {
                    ForEach(Array(syncedRows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .top, spacing: 8) {
                            // Левая колонка
                            if let leftTurn = row.leftTurn {
                                CompactTurnCard(
                                    turn: leftTurn,
                                    speaker: .left,
                                    audioPlayer: audioPlayer,
                                    durationBarScale: durationBarScale
                                )
                                .frame(maxWidth: .infinity)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                            }

                            // Правая колонка
                            if let rightTurn = row.rightTurn {
                                CompactTurnCard(
                                    turn: rightTurn,
                                    speaker: .right,
                                    audioPlayer: audioPlayer,
                                    durationBarScale: durationBarScale
                                )
                                .frame(maxWidth: .infinity)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 12)

                        // Индикатор промежутка до следующей строки
                        if index < syncedRows.count - 1 {
                            let nextRow = syncedRows[index + 1]
                            if let gap = calculateGap(from: row, to: nextRow) {
                                SilenceIndicator(duration: gap, scale: durationBarScale)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    // Вычисляет промежуток тишины перед репликой (в рамках одного канала)
    private func getSilenceGapBefore(turn: DialogueTranscription.Turn, in turns: [DialogueTranscription.Turn]) -> TimeInterval? {
        // Находим предыдущую реплику того же спикера
        let sameChannelTurns = turns.filter { $0.speaker == turn.speaker }
        guard let currentIndex = sameChannelTurns.firstIndex(where: { $0.id == turn.id }), currentIndex > 0 else {
            return nil
        }

        let previousTurn = sameChannelTurns[currentIndex - 1]
        let gap = turn.startTime - previousTurn.endTime

        // Показываем индикатор только для значительных промежутков в рамках одного канала
        return gap > TimelineConstants.Synchronization.singleChannelSilenceThreshold ? gap : nil
    }
}

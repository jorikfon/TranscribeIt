import SwiftUI

/// Отображение диалога в виде двух синхронизированных по времени колонок
///
/// Главный контейнер для timeline view, который:
/// - Отображает заголовок с информацией о длительности
/// - Использует CompressedTimelineMapper для визуального сжатия промежутков тишины
/// - Адаптивно масштабирует timeline на основе длительности диалога
/// - Вычисляет оптимальный масштаб (pixelsPerSecond) для наилучшего отображения
///
/// ## Использование
/// ```swift
/// TimelineSyncedDialogueView(
///     dialogue: dialogueTranscription,
///     audioPlayer: audioPlayerManager
/// )
/// ```
public struct TimelineSyncedDialogueView: View {
    let dialogue: DialogueTranscription
    @ObservedObject var audioPlayer: AudioPlayerManager

    // Mapper для визуального сжатия тишины
    private var timelineMapper: CompressedTimelineMapper {
        CompressedTimelineMapper(turns: dialogue.turns)
    }

    // Визуальная длительность (с учетом сжатия)
    private var visualDuration: TimeInterval {
        timelineMapper.totalVisualDuration(realDuration: dialogue.totalDuration)
    }

    // Адаптивная высота: вычисляем оптимальный масштаб
    private var pixelsPerSecond: CGFloat {
        calculateAdaptiveScale()
    }

    // Максимальная и минимальная высота timeline
    private let maxTimelineHeight: CGFloat = TimelineConstants.Scaling.maxTimelineHeight
    private let minPixelsPerSecond: CGFloat = TimelineConstants.Scaling.minPixelsPerSecond
    private let maxPixelsPerSecond: CGFloat = TimelineConstants.Scaling.maxPixelsPerSecond

    /// Вычисляет адаптивный масштаб timeline на основе ВИЗУАЛЬНОЙ длительности (сжатой)
    private func calculateAdaptiveScale() -> CGFloat {
        // Если нет реплик, используем средний масштаб
        guard !dialogue.turns.isEmpty else { return TimelineConstants.Scaling.defaultPixelsPerSecond }

        // Используем ВИЗУАЛЬНУЮ длительность (с учетом сжатия тишины)
        let duration = visualDuration
        guard duration > 0 else { return TimelineConstants.Scaling.defaultPixelsPerSecond }

        // Вычисляем идеальный масштаб, чтобы вместить диалог в maxTimelineHeight
        let idealScale = maxTimelineHeight / CGFloat(duration)

        // Ограничиваем масштаб для читабельности
        return max(minPixelsPerSecond, min(maxPixelsPerSecond, idealScale))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Заголовок с информацией
            HStack {
                Image(systemName: "waveform.path")
                    .foregroundColor(.blue)
                Text("Timeline View")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                // Общая длительность
                Text(formatDuration(dialogue.totalDuration))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Divider()

            if dialogue.turns.isEmpty {
                Text("Нет распознанных реплик")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                // Две колонки с единой временной шкалой (показывает одновременную речь)
                ScrollView {
                    TimelineDialogueView(dialogue: dialogue, audioPlayer: audioPlayer)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
                .frame(maxHeight: TimelineConstants.Scaling.maxTimelineHeight)
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

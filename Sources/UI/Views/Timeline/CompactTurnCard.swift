import SwiftUI
import AppKit

/// Компактная карточка реплики с индикатором длительности слева
///
/// Отображает отдельную реплику диалога с визуальными элементами:
/// - Цветная вертикальная полоска слева (высота = длительность реплики)
/// - Метка времени начала реплики
/// - Длительность реплики
/// - Полный текст реплики с автоматическим переносом
/// - Подсветка при активном воспроизведении
/// - Кнопка копирования текста (появляется при наведении)
///
/// ## Взаимодействие
/// - **Клик по карточке**: переход к времени реплики и начало воспроизведения
/// - **Наведение**: появляется кнопка копирования
/// - **Клик по кнопке копирования**: копирование текста в буфер обмена
///
/// ## Использование
/// ```swift
/// CompactTurnCard(
///     turn: dialogueTurn,
///     speaker: .left,
///     audioPlayer: audioPlayerManager,
///     durationBarScale: 3.0
/// )
/// ```
///
/// - Parameters:
///   - turn: Реплика для отображения
///   - speaker: Спикер (левый или правый канал)
///   - audioPlayer: Менеджер аудио плеера для синхронизации воспроизведения
///   - durationBarScale: Масштаб индикатора длительности (пикселей на секунду)
public struct CompactTurnCard: View {
    let turn: DialogueTranscription.Turn
    let speaker: DialogueTranscription.Turn.Speaker
    @ObservedObject var audioPlayer: AudioPlayerManager
    let durationBarScale: CGFloat

    @State private var isHovered: Bool = false
    @State private var showCopiedFeedback: Bool = false

    // Проверка активности
    private var isPlaying: Bool {
        audioPlayer.state.playback.isPlaying &&
        audioPlayer.state.playback.currentTime >= turn.startTime &&
        audioPlayer.state.playback.currentTime <= turn.endTime
    }

    // Высота индикатора длительности (ограничена 60px максимум)
    private var durationBarHeight: CGFloat {
        min(max(CGFloat(turn.duration) * durationBarScale, TurnCardConstants.minDurationBarHeight), TurnCardConstants.maxDurationBarHeight)
    }

    public var body: some View {
        HStack(alignment: .top, spacing: TurnCardConstants.mainHorizontalSpacing) {
            // Цветная полоска длительности слева
            VStack(spacing: TurnCardConstants.durationBarVerticalSpacing) {
                Rectangle()
                    .fill(speaker == .left ? Color.speaker1Accent : Color.speaker2Accent)
                    .frame(width: TurnCardConstants.durationBarWidth, height: durationBarHeight)
                    .cornerRadius(TurnCardConstants.durationBarCornerRadius)

                // Время начала
                Text(formatTime(turn.startTime))
                    .font(.system(size: TurnCardConstants.startTimeFontSize, weight: .medium))
                    .foregroundColor(.secondary.opacity(TurnCardConstants.secondaryTextOpacity))
            }
            .frame(height: durationBarHeight + TurnCardConstants.durationBarVStackExtraHeight)  // Фиксированная высота для VStack

            // Контент реплики
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: TurnCardConstants.contentVerticalSpacing) {
                    // Заголовок: длительность
                    Text(formatDuration(turn.duration))
                        .font(.system(size: TurnCardConstants.durationFontSize))
                        .foregroundColor(.secondary)

                    // Текст реплики - полное развертывание без ограничений
                    Text(turn.text)
                        .font(.system(size: TurnCardConstants.textFontSize))
                        .foregroundColor(.primary)
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(TurnCardConstants.contentPadding)
                .frame(maxWidth: .infinity)

                // Кнопка копирования (появляется при наведении)
                if isHovered {
                    Button(action: {
                        copyToClipboard()
                    }) {
                        ZStack {
                            // Фон кнопки
                            Circle()
                                .fill(Color(NSColor.controlBackgroundColor).opacity(TurnCardConstants.copyButtonBackgroundOpacity))
                                .frame(width: TurnCardConstants.copyButtonSize, height: TurnCardConstants.copyButtonSize)

                            // Иконка
                            Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                                .font(.system(size: TurnCardConstants.copyButtonIconSize, weight: .medium))
                                .foregroundColor(showCopiedFeedback ? .green : .secondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(TurnCardConstants.copyButtonPadding)
                    .transition(.opacity)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: TurnCardConstants.cardCornerRadius)
                    .fill(speaker == .left ? Color.speaker1Background : Color.speaker2Background)
                    .overlay(
                        RoundedRectangle(cornerRadius: TurnCardConstants.cardCornerRadius)
                            .stroke(
                                isPlaying ? (speaker == .left ? Color.speaker1Accent : Color.speaker2Accent) : Color.clear,
                                lineWidth: TurnCardConstants.activeStrokeWidth
                            )
                    )
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: TurnCardConstants.hoverAnimationDuration)) {
                    isHovered = hovering
                }
            }
        }
        .padding(.vertical, TurnCardConstants.verticalPadding)
        .onTapGesture {
            // Клик → переход к времени реплики и воспроизведение
            audioPlayer.seekAndPlay(to: turn.startTime)
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(turn.text, forType: .string)

        // Показываем обратную связь
        withAnimation {
            showCopiedFeedback = true
        }

        // Скрываем галочку через заданное время
        DispatchQueue.main.asyncAfter(deadline: .now() + TurnCardConstants.copiedFeedbackDuration) {
            withAnimation {
                showCopiedFeedback = false
            }
        }

        LogManager.app.info("Скопирован текст реплики: \(turn.text.prefix(50))...")
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        return String(format: "%.1fs", seconds)
    }
}

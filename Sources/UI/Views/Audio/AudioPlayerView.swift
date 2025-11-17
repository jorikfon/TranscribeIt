import SwiftUI

/// Constants for AudioPlayer UI layout
enum AudioPlayerConstants {
    // Icon sizes
    static let playButtonIconSize: CGFloat = 24
    static let speedIconSize: CGFloat = 10
    static let volumeIconSize: CGFloat = 12

    // Font sizes
    static let speedButtonFontSize: CGFloat = 9
    static let timeFontSize: CGFloat = 11
    static let volumePercentFontSize: CGFloat = 9

    // Spacing
    static let mainSpacing: CGFloat = 8
    static let controlsSpacing: CGFloat = 12
    static let speedControlSpacing: CGFloat = 4
    static let volumeControlSpacing: CGFloat = 6

    // Layout dimensions
    static let progressBarHeight: CGFloat = 4
    static let cornerRadius: CGFloat = 8
    static let progressBarCornerRadius: CGFloat = 2
    static let speedButtonCornerRadius: CGFloat = 3
    static let volumeSliderWidth: CGFloat = 60
    static let volumeTextWidth: CGFloat = 35
    static let containerPadding: CGFloat = 8

    // Playback settings
    static let availablePlaybackRates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    static let minVolumeBoost: Double = 1.0
    static let maxVolumeBoost: Double = 5.0

    // Speed button padding
    static let speedButtonHorizontalPadding: CGFloat = 4
    static let speedButtonVerticalPadding: CGFloat = 2

    // Comparison tolerance for floating point
    static let floatComparisonTolerance: Float = 0.01
}

/// Аудио плеер для воспроизведения файла
///
/// Предоставляет интерактивные контролы для управления воспроизведением аудио файла:
/// - Прогресс бар с возможностью перемотки (drag to seek)
/// - Play/Pause кнопка
/// - Переключатель моно/стерео режима
/// - Регулировка скорости воспроизведения (0.5x - 2.0x)
/// - Отображение текущего времени и общей длительности
/// - Усиление громкости (100% - 500%) для тихих записей
///
/// ## Example
/// ```swift
/// AudioPlayerView(
///     audioPlayer: audioPlayerManager,
///     fileURL: audioFileURL
/// )
/// ```
public struct AudioPlayerView: View {
    @ObservedObject var audioPlayer: AudioPlayerManager
    let fileURL: URL

    public var body: some View {
        VStack(spacing: AudioPlayerConstants.mainSpacing) {
            // Прогресс бар
            progressBar

            // Контролы плеера
            playerControls
        }
        .padding(AudioPlayerConstants.containerPadding)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(AudioPlayerConstants.cornerRadius)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Фоновая дорожка
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: AudioPlayerConstants.progressBarHeight)
                    .cornerRadius(AudioPlayerConstants.progressBarCornerRadius)

                // Прогресс
                Rectangle()
                    .fill(Color.blue)
                    .frame(
                        width: geometry.size.width * CGFloat(audioPlayer.state.playback.currentTime / max(audioPlayer.state.playback.duration, 1)),
                        height: AudioPlayerConstants.progressBarHeight
                    )
                    .cornerRadius(AudioPlayerConstants.progressBarCornerRadius)
            }
            .frame(height: AudioPlayerConstants.progressBarHeight)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newTime = Double(value.location.x / geometry.size.width) * audioPlayer.state.playback.duration
                        audioPlayer.seek(to: newTime)
                    }
            )
        }
        .frame(height: AudioPlayerConstants.progressBarHeight)
    }

    // MARK: - Player Controls

    private var playerControls: some View {
        HStack(spacing: AudioPlayerConstants.controlsSpacing) {
            // Кнопка Play/Pause
            playPauseButton

            // Контрол скорости воспроизведения
            speedControl

            // Текущее время
            Text(formatTime(audioPlayer.state.playback.currentTime))
                .font(.system(size: AudioPlayerConstants.timeFontSize, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            // Общая длительность
            Text(formatTime(audioPlayer.state.playback.duration))
                .font(.system(size: AudioPlayerConstants.timeFontSize, design: .monospaced))
                .foregroundColor(.secondary)

            // Усиление громкости (100% - 500%)
            volumeBoostControl
        }
    }

    // MARK: - Control Components

    private var playPauseButton: some View {
        Button(action: {
            audioPlayer.togglePlayback()
        }) {
            Image(systemName: audioPlayer.state.playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: AudioPlayerConstants.playButtonIconSize))
                .foregroundColor(.blue)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var speedControl: some View {
        HStack(spacing: AudioPlayerConstants.speedControlSpacing) {
            Image(systemName: "gauge.medium")
                .font(.system(size: AudioPlayerConstants.speedIconSize))
                .foregroundColor(.secondary)

            ForEach(AudioPlayerConstants.availablePlaybackRates, id: \.self) { rate in
                speedButton(for: rate)
            }
        }
    }

    private func speedButton(for rate: Double) -> some View {
        let isSelected = abs(audioPlayer.state.settings.playbackRate - Float(rate)) < AudioPlayerConstants.floatComparisonTolerance

        return Button(action: {
            audioPlayer.setPlaybackRate(Float(rate))
        }) {
            Text(formatRate(rate))
                .font(.system(
                    size: AudioPlayerConstants.speedButtonFontSize,
                    weight: isSelected ? .bold : .regular
                ))
                .foregroundColor(isSelected ? .blue : .secondary)
                .padding(.horizontal, AudioPlayerConstants.speedButtonHorizontalPadding)
                .padding(.vertical, AudioPlayerConstants.speedButtonVerticalPadding)
                .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
                .cornerRadius(AudioPlayerConstants.speedButtonCornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var volumeBoostControl: some View {
        HStack(spacing: AudioPlayerConstants.volumeControlSpacing) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: AudioPlayerConstants.volumeIconSize))
                .foregroundColor(audioPlayer.state.audio.volumeBoost > 1.0 ? .orange : .secondary)

            Slider(value: Binding(
                get: { Double(audioPlayer.state.audio.volumeBoost) },
                set: { audioPlayer.setVolumeBoost(Float($0)) }
            ), in: AudioPlayerConstants.minVolumeBoost...AudioPlayerConstants.maxVolumeBoost)
            .frame(width: AudioPlayerConstants.volumeSliderWidth)

            Text("\(Int(audioPlayer.state.audio.volumeBoost * 100))%")
                .font(.system(size: AudioPlayerConstants.volumePercentFontSize, design: .monospaced))
                .foregroundColor(audioPlayer.state.audio.volumeBoost > 1.0 ? .orange : .secondary)
                .frame(width: AudioPlayerConstants.volumeTextWidth, alignment: .trailing)
        }
    }

    // MARK: - Formatting Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatRate(_ rate: Double) -> String {
        if rate == 1.0 {
            return "1×"
        } else {
            return String(format: "%.2g×", rate)
        }
    }
}

import SwiftUI

/// Константы для StatusIndicator компонентов
enum StatusIndicatorConstants {
    static let iconSize: CGFloat = 10
    static let textSize: CGFloat = 10
    static let spacing: CGFloat = 4
    static let progressScale: CGFloat = 0.4
    static let progressFrameSize: CGFloat = 10
}

/// Индикатор статуса с иконкой и текстом
///
/// Используется для отображения статической информации о состоянии приложения
/// (модель, язык, VAD алгоритм и т.д.)
///
/// ## Example
/// ```swift
/// StatusIndicator(
///     icon: "cpu",
///     text: "small",
///     color: .blue
/// )
/// ```
struct StatusIndicator: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: StatusIndicatorConstants.spacing) {
            Image(systemName: icon)
                .font(.system(size: StatusIndicatorConstants.iconSize))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: StatusIndicatorConstants.textSize))
                .foregroundColor(.secondary)
        }
    }
}

/// Индикатор статуса с ProgressView для загрузки
///
/// Используется для отображения процессов загрузки с текстовым описанием
/// и анимированным индикатором прогресса
///
/// ## Example
/// ```swift
/// LoadingStatusIndicator(
///     text: "Загрузка модели...",
///     color: .orange
/// )
/// ```
struct LoadingStatusIndicator: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: StatusIndicatorConstants.spacing) {
            ProgressView()
                .scaleEffect(StatusIndicatorConstants.progressScale)
                .frame(
                    width: StatusIndicatorConstants.progressFrameSize,
                    height: StatusIndicatorConstants.progressFrameSize
                )
            Text(text)
                .font(.system(size: StatusIndicatorConstants.textSize))
                .foregroundColor(color)
        }
    }
}

// MARK: - Previews

#Preview("StatusIndicator - CPU") {
    StatusIndicator(icon: "cpu", text: "small", color: .blue)
        .padding()
}

#Preview("StatusIndicator - Language") {
    StatusIndicator(icon: "globe", text: "RU", color: .purple)
        .padding()
}

#Preview("StatusIndicator - VAD") {
    StatusIndicator(icon: "waveform", text: "Spectral", color: .green)
        .padding()
}

#Preview("LoadingStatusIndicator") {
    LoadingStatusIndicator(text: "Загрузка модели...", color: .orange)
        .padding()
}

#Preview("Multiple Indicators") {
    HStack(spacing: 8) {
        LoadingStatusIndicator(text: "Загрузка...", color: .orange)
        StatusIndicator(icon: "cpu", text: "small", color: .blue)
        StatusIndicator(icon: "globe", text: "AUTO", color: .purple)
        StatusIndicator(icon: "waveform", text: "Spectral", color: .green)
    }
    .padding()
}

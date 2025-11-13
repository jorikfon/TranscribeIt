import SwiftUI

/// Индикатор промежутка тишины между репликами
///
/// Отображает визуальный маркер паузы между репликами в timeline view:
/// - Пунктирная вертикальная линия
/// - Длительность паузы в читаемом формате
/// - Высота линии пропорциональна длительности (с учетом масштаба)
///
/// ## Использование
/// ```swift
/// SilenceIndicator(duration: 3.5, scale: 3.0)
/// ```
///
/// - Parameters:
///   - duration: Длительность промежутка тишины в секундах
///   - scale: Масштаб визуализации (пикселей на секунду)
public struct SilenceIndicator: View {
    typealias Constants = SilenceIndicatorConstants

    let duration: TimeInterval
    let scale: CGFloat

    public var body: some View {
        HStack(spacing: Constants.iconTextSpacing) {
            // Пунктирная линия
            Rectangle()
                .fill(Color.gray.opacity(Constants.lineOpacity))
                .frame(width: Constants.lineWidth, height: min(CGFloat(duration) * scale, Constants.maxLineHeight))
                .overlay(
                    Rectangle()
                        .strokeBorder(style: StrokeStyle(lineWidth: Constants.strokeWidth, dash: Constants.dashPattern))
                        .foregroundColor(.gray.opacity(Constants.strokeOpacity))
                )

            // Время промежутка
            Text("⋯ \(formatDuration(duration))")
                .font(.system(size: Constants.durationFontSize))
                .foregroundColor(.secondary.opacity(Constants.textOpacity))
        }
        .padding(.vertical, Constants.verticalPadding)
        .padding(.leading, Constants.leadingPadding)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < TimeInterval(Constants.secondsInMinute) {
            return String(format: "%.1fs", seconds)
        } else {
            let mins = Int(seconds) / Constants.secondsInMinute
            let secs = Int(seconds) % Constants.secondsInMinute
            return String(format: "%dm %ds", mins, secs)
        }
    }
}

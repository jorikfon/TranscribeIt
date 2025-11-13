import Foundation
import CoreGraphics

/// Константы для SilenceIndicator компонента
enum SilenceIndicatorConstants {
    // Line
    static let lineWidth: CGFloat = 2
    static let maxLineHeight: CGFloat = 20
    static let strokeWidth: CGFloat = 1
    static let dashPattern: [CGFloat] = [2, 2]

    // Font
    static let durationFontSize: CGFloat = 8

    // Padding
    static let verticalPadding: CGFloat = 2
    static let leadingPadding: CGFloat = 4

    // Spacing
    static let iconTextSpacing: CGFloat = 4

    // Opacity
    static let lineOpacity: Double = 0.3
    static let strokeOpacity: Double = 0.5
    static let textOpacity: Double = 0.6

    // Time Formatting
    static let secondsInMinute: Int = 60
}

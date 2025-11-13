import SwiftUI

/// Константы для компонента CompactTurnCard
///
/// Содержит все магические числа, используемые в карточке реплики для
/// обеспечения единообразного внешнего вида и упрощения настройки.
public enum TurnCardConstants {
    // MARK: - Duration Bar (индикатор длительности)

    /// Минимальная высота полоски длительности (в пикселях)
    public static let minDurationBarHeight: CGFloat = 10

    /// Максимальная высота полоски длительности (в пикселях)
    public static let maxDurationBarHeight: CGFloat = 60

    /// Ширина полоски длительности (в пикселях)
    public static let durationBarWidth: CGFloat = 3

    /// Радиус закругления полоски длительности
    public static let durationBarCornerRadius: CGFloat = 1.5

    /// Дополнительная высота VStack для размещения времени начала
    public static let durationBarVStackExtraHeight: CGFloat = 12

    // MARK: - Spacing (отступы и расстояния)

    /// Горизонтальный отступ между полоской длительности и контентом
    public static let mainHorizontalSpacing: CGFloat = 6

    /// Вертикальный отступ внутри VStack полоски длительности
    public static let durationBarVerticalSpacing: CGFloat = 2

    /// Вертикальный отступ внутри контента реплики
    public static let contentVerticalSpacing: CGFloat = 4

    /// Внутренний padding контента реплики
    public static let contentPadding: CGFloat = 8

    /// Вертикальный padding между карточками
    public static let verticalPadding: CGFloat = 2

    /// Padding кнопки копирования
    public static let copyButtonPadding: CGFloat = 6

    // MARK: - Font Sizes (размеры шрифтов)

    /// Размер шрифта для времени начала реплики
    public static let startTimeFontSize: CGFloat = 7

    /// Размер шрифта для длительности реплики
    public static let durationFontSize: CGFloat = 8

    /// Размер шрифта для текста реплики
    public static let textFontSize: CGFloat = 11

    /// Размер иконки кнопки копирования
    public static let copyButtonIconSize: CGFloat = 10

    // MARK: - Copy Button (кнопка копирования)

    /// Размер кнопки копирования (диаметр круга)
    public static let copyButtonSize: CGFloat = 20

    /// Opacity фона кнопки копирования
    public static let copyButtonBackgroundOpacity: Double = 0.9

    /// Задержка перед скрытием feedback (в секундах)
    public static let copiedFeedbackDuration: TimeInterval = 1.5

    // MARK: - Border & Corner Radius

    /// Радиус закругления карточки реплики
    public static let cardCornerRadius: CGFloat = 6

    /// Толщина обводки карточки при активном воспроизведении
    public static let activeStrokeWidth: CGFloat = 2

    // MARK: - Animation

    /// Длительность анимации наведения
    public static let hoverAnimationDuration: TimeInterval = 0.15

    // MARK: - Opacity

    /// Opacity для вторичного текста (время начала)
    public static let secondaryTextOpacity: Double = 0.7
}

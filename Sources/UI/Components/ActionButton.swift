import SwiftUI

/// Переиспользуемый компонент для кнопок действий в UI
///
/// Поддерживает различные стили кнопок с иконками и текстом.
/// Используется для унификации внешнего вида кнопок в приложении.
///
/// ## Примеры использования:
///
/// ### Prominent кнопка с текстом и иконкой
/// ```swift
/// ActionButton(
///     icon: "arrow.counterclockwise",
///     title: "New File",
///     action: { selectNewFile() }
/// )
/// ```
///
/// ### Icon-only кнопка (настройки)
/// ```swift
/// IconButton(
///     icon: "gearshape.circle.fill",
///     color: .secondary,
///     action: { showSettings.toggle() }
/// )
/// ```
///
/// ### Icon-only кнопка с динамической иконкой
/// ```swift
/// IconButton(
///     icon: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill",
///     color: isExpanded ? .blue : .secondary,
///     helpText: "Toggle settings",
///     action: { isExpanded.toggle() }
/// )
/// ```
struct ActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.buttonContentSpacing) {
                Image(systemName: icon)
                    .font(.system(size: Constants.buttonIconSize))
                Text(title)
                    .font(.system(size: Constants.buttonTextSize))
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.mini)
    }
}

/// Icon-only кнопка для компактного отображения
///
/// Используется для кнопок без текста, например кнопки настроек.
struct IconButton: View {
    let icon: String
    let color: Color
    let helpText: String?
    let action: () -> Void

    init(
        icon: String,
        color: Color = .secondary,
        helpText: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.color = color
        self.helpText = helpText
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: Constants.iconButtonSize))
                .foregroundColor(color)
        }
        .buttonStyle(PlainButtonStyle())
        .help(helpText ?? "")
    }
}

// MARK: - Constants

private enum Constants {
    /// Размер иконки в кнопке с текстом
    static let buttonIconSize: CGFloat = 11

    /// Размер текста в кнопке
    static let buttonTextSize: CGFloat = 11

    /// Spacing между иконкой и текстом
    static let buttonContentSpacing: CGFloat = 4

    /// Размер иконки в icon-only кнопке
    static let iconButtonSize: CGFloat = 16
}

// MARK: - Previews

#Preview("Action Button") {
    VStack(spacing: 12) {
        ActionButton(
            icon: "arrow.counterclockwise",
            title: "New File",
            action: {}
        )

        ActionButton(
            icon: "folder",
            title: "Open",
            action: {}
        )

        ActionButton(
            icon: "arrow.down.doc",
            title: "Export",
            action: {}
        )
    }
    .padding()
}

#Preview("Icon Button") {
    HStack(spacing: 12) {
        IconButton(
            icon: "gearshape.circle.fill",
            color: .secondary,
            helpText: "Settings",
            action: {}
        )

        IconButton(
            icon: "chevron.up.circle.fill",
            color: .blue,
            helpText: "Collapse",
            action: {}
        )

        IconButton(
            icon: "chevron.down.circle.fill",
            color: .gray,
            helpText: "Expand",
            action: {}
        )
    }
    .padding()
}

#Preview("Mixed Buttons") {
    HStack(spacing: 12) {
        ActionButton(
            icon: "arrow.counterclockwise",
            title: "New File",
            action: {}
        )

        IconButton(
            icon: "gearshape.circle.fill",
            color: .secondary,
            helpText: "Settings",
            action: {}
        )
    }
    .padding()
}

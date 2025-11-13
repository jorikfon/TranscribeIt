import Foundation
import CoreGraphics

/// Константы для компонентов транскрипции (Header, Empty State, Settings Panel, Content)
enum TranscriptionViewConstants {

    // MARK: - HeaderView Constants

    enum Header {
        // Font Sizes
        static let titleFontSize: CGFloat = 14
        static let statusIconSize: CGFloat = 10
        static let statusTextSize: CGFloat = 10
        static let buttonIconSize: CGFloat = 10
        static let buttonTextSize: CGFloat = 10
        static let settingsIconSize: CGFloat = 14

        // Spacing
        static let statusIndicatorSpacing: CGFloat = 12
        static let iconTextSpacing: CGFloat = 4
        static let newFileButtonSpacing: CGFloat = 4

        // Padding
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 12

        // Progress Indicator
        static let progressScaleEffect: CGFloat = 0.5
        static let progressFrameSize: CGFloat = 10

        // Animation
        static let settingsToggleAnimationDuration: Double = 0.2
    }

    // MARK: - EmptyStateView Constants

    enum EmptyState {
        // Font Sizes
        static let iconSize: CGFloat = 48
        static let titleFontSize: CGFloat = 16
        static let subtitleFontSize: CGFloat = 12
        static let buttonFontSize: CGFloat = 13

        // Spacing
        static let verticalSpacing: CGFloat = 20

        // Padding
        static let buttonHorizontalPadding: CGFloat = 20
        static let buttonVerticalPadding: CGFloat = 10

        // Opacity
        static let iconOpacity: Double = 0.5
        static let subtitleOpacity: Double = 0.7
        static let captionOpacity: Double = 0.6
    }

    // MARK: - SettingsPanel Constants

    enum SettingsPanel {
        // Font Sizes
        static let titleFontSize: CGFloat = 13
        static let labelFontSize: CGFloat = 11
        static let pickerItemSmallFontSize: CGFloat = 10
        static let pickerItemFontSize: CGFloat = 11
        static let descriptionFontSize: CGFloat = 9
        static let descriptionIconSize: CGFloat = 9
        static let retranscribeButtonIconSize: CGFloat = 11
        static let retranscribeButtonTextSize: CGFloat = 11

        // Spacing
        static let mainVerticalSpacing: CGFloat = 12
        static let sectionHorizontalSpacing: CGFloat = 16
        static let labelVerticalSpacing: CGFloat = 6
        static let iconTextSpacing: CGFloat = 4
        static let buttonSpacing: CGFloat = 6

        // Padding
        static let mainPadding: CGFloat = 16
        static let buttonHorizontalPadding: CGFloat = 12
        static let buttonVerticalPadding: CGFloat = 6

        // Sizes
        static let languagePickerWidth: CGFloat = 150

        // Opacity
        static let descriptionOpacity: Double = 0.8
        static let backgroundOpacity: Double = 0.5
    }

    // MARK: - ContentView Constants

    enum Content {
        // Padding
        static let audioPlayerHorizontalPadding: CGFloat = 16
        static let audioPlayerVerticalPadding: CGFloat = 12
        static let textPadding: CGFloat = 16

        // Font Sizes
        static let textFontSize: CGFloat = 13
    }
}

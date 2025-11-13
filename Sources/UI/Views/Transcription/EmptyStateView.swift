import SwiftUI

/// Пустое состояние - отображается когда файл не выбран
struct EmptyStateView: View {
    typealias Constants = TranscriptionViewConstants.EmptyState

    var onSelectFile: () -> Void

    var body: some View {
        VStack(spacing: Constants.verticalSpacing) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: Constants.iconSize))
                .foregroundColor(.secondary.opacity(Constants.iconOpacity))

            Text("No audio file selected")
                .font(.system(size: Constants.titleFontSize, weight: .medium))
                .foregroundColor(.secondary)

            Text("Select an audio file to transcribe")
                .font(.system(size: Constants.subtitleFontSize))
                .foregroundColor(.secondary.opacity(Constants.subtitleOpacity))

            Button(action: {
                onSelectFile()
            }) {
                Label("Select Audio File", systemImage: "folder")
                    .font(.system(size: Constants.buttonFontSize))
                    .padding(.horizontal, Constants.buttonHorizontalPadding)
                    .padding(.vertical, Constants.buttonVerticalPadding)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Supported formats: WAV, MP3, M4A, AIFF, FLAC, AAC")
                .font(.caption)
                .foregroundColor(.secondary.opacity(Constants.captionOpacity))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

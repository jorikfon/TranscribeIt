import SwiftUI

/// Заголовок окна транскрипции с индикаторами статуса и управляющими кнопками
struct HeaderView: View {
    typealias Constants = TranscriptionViewConstants.Header
    @ObservedObject var viewModel: FileTranscriptionViewModel
    @ObservedObject var userSettings: UserSettings
    @Binding var showSettings: Bool

    var onSelectNewFile: () -> Void

    // Текущая транскрипция из ViewModel
    private var currentTranscription: FileTranscription? {
        viewModel.currentTranscription
    }

    var body: some View {
        HStack {
            // Имя файла
            if let transcription = currentTranscription {
                Text(transcription.fileName)
                    .font(.system(size: Constants.titleFontSize, weight: .semibold))
                    .foregroundColor(.primary)
            } else {
                Text("Stereo Call Transcription")
                    .font(.system(size: Constants.titleFontSize, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Модель и VAD
            HStack(spacing: Constants.statusIndicatorSpacing) {
                // Статус загрузки модели (показываем только если загружается, не когда готова)
                if let loadingStatus = viewModel.modelLoadingStatus, loadingStatus != "Model ready" {
                    LoadingStatusIndicator(text: loadingStatus, color: .orange)
                }

                // Показываем модель и VAD всегда когда они доступны (в том числе когда модель готова)
                if !viewModel.modelName.isEmpty {
                    StatusIndicator(icon: "cpu", text: viewModel.modelName, color: .blue)
                }

                // Статус GPU/Neural Engine
                if !viewModel.gpuStatus.isEmpty {
                    StatusIndicator(
                        icon: viewModel.gpuStatus.contains("ANE") ? "bolt.fill" : "circle.grid.3x3.fill",
                        text: viewModel.gpuStatus,
                        color: viewModel.gpuStatus.contains("ANE") ? .green : .orange
                    )
                }

                // Язык транскрибации
                StatusIndicator(
                    icon: "globe",
                    text: userSettings.transcriptionLanguage.isEmpty ? "Auto" : userSettings.transcriptionLanguage.uppercased(),
                    color: .purple
                )

                // VAD алгоритм
                if !viewModel.vadInfo.isEmpty {
                    StatusIndicator(icon: "waveform", text: viewModel.vadInfo, color: .green)
                }

                // Кнопка "New File" (если есть транскрипция)
                if viewModel.state == .completed {
                    ActionButton(
                        icon: "arrow.counterclockwise",
                        title: "New File",
                        action: onSelectNewFile
                    )
                }

                // Кнопка настроек (показывается только если есть файл)
                if viewModel.currentFileURL != nil {
                    IconButton(
                        icon: showSettings ? "chevron.up.circle.fill" : "gearshape.circle.fill",
                        color: showSettings ? .blue : .secondary,
                        helpText: "Настройки транскрибации",
                        action: {
                            withAnimation(.easeInOut(duration: Constants.settingsToggleAnimationDuration)) {
                                showSettings.toggle()
                            }
                        }
                    )
                }
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

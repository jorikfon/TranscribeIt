import SwiftUI

/// Контент окна транскрипции - отображает результаты транскрипции
struct TranscriptionContentView: View {
    typealias Constants = TranscriptionViewConstants.Content

    let transcription: FileTranscription
    @ObservedObject var viewModel: FileTranscriptionViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Аудио плеер
            if let fileURL = transcription.fileURL {
                AudioPlayerView(audioPlayer: viewModel.audioPlayer, fileURL: fileURL)
                    .padding(.horizontal, Constants.audioPlayerHorizontalPadding)
                    .padding(.vertical, Constants.audioPlayerVerticalPadding)
                    .background(Color(NSColor.controlBackgroundColor))
            }

            // Диалог или текст
            if let dialogue = transcription.dialogue, dialogue.isStereo {
                TimelineSyncedDialogueView(dialogue: dialogue, audioPlayer: viewModel.audioPlayer)
            } else {
                ScrollView {
                    Text(transcription.text)
                        .font(.system(size: Constants.textFontSize))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Constants.textPadding)
                }
            }
        }
        .onAppear {
            // Загружаем аудио файл при появлении
            if let fileURL = transcription.fileURL {
                do {
                    try viewModel.audioPlayer.loadAudio(from: fileURL)
                } catch {
                    LogManager.app.failure("Ошибка загрузки аудио", error: error)
                }
            }
        }
    }
}

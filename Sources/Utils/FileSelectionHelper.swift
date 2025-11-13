import AppKit

/// Helper для выбора аудио файлов через NSOpenPanel
///
/// Инкапсулирует логику отображения диалога выбора файла и валидации формата.
/// Используется в UI для упрощения кода view компонентов.
///
/// ## Поддерживаемые форматы
/// - WAV (Waveform Audio File Format)
/// - MP3 (MPEG Audio Layer 3)
/// - M4A (MPEG-4 Audio)
/// - AIFF (Audio Interchange File Format)
/// - FLAC (Free Lossless Audio Codec)
/// - AAC (Advanced Audio Coding)
///
/// ## Example
/// ```swift
/// FileSelectionHelper.selectAudioFile { selectedURL in
///     print("Selected: \(selectedURL.lastPathComponent)")
/// }
/// ```
enum FileSelectionHelper {
    /// Поддерживаемые форматы аудио файлов
    static let supportedFormats = ["wav", "mp3", "m4a", "aiff", "flac", "aac"]

    /// Отображает диалог выбора аудио файла
    ///
    /// - Parameter completion: Callback с выбранным URL файла (или nil если отменено)
    static func selectAudioFile(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Select Stereo Audio File"
        panel.prompt = "Select"
        panel.message = "Select a stereo telephone recording (left = speaker 1, right = speaker 2)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff, .mpeg4Audio]

        panel.begin { response in
            guard response == .OK, let fileURL = panel.url else {
                completion(nil)
                return
            }

            // Валидация формата файла
            if isValidAudioFormat(fileURL) {
                completion(fileURL)
            } else {
                LogManager.app.error("Неподдерживаемый формат файла: \(fileURL.pathExtension)")
                completion(nil)
            }
        }
    }

    /// Проверяет, поддерживается ли формат аудио файла
    ///
    /// - Parameter url: URL файла для проверки
    /// - Returns: true если формат поддерживается
    static func isValidAudioFormat(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedFormats.contains(ext)
    }

    /// Форматированная строка поддерживаемых форматов для отображения пользователю
    static var supportedFormatsString: String {
        supportedFormats.map { $0.uppercased() }.joined(separator: ", ")
    }
}

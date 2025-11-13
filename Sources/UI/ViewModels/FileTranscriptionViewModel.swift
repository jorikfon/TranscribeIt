import Foundation
import SwiftUI

/// ViewModel для окна транскрипции файлов
/// Упрощённая версия для работы с одним стерео файлом телефонных записей
public class FileTranscriptionViewModel: ObservableObject {
    @Published public var state: TranscriptionState = .idle
    @Published public var currentFile: String = ""
    @Published public var progress: Double = 0.0
    @Published public var modelName: String = ""  // Текущая модель Whisper
    @Published public var vadInfo: String = ""  // Информация о VAD алгоритме
    @Published public var modelLoadingStatus: String? = nil  // Статус загрузки модели в фоне
    @Published public var gpuStatus: String = ""  // Статус GPU/Neural Engine

    // Текущая транскрипция (только один файл)
    @Published public var currentTranscription: FileTranscription?

    // URL текущего файла для перезапуска
    @Published public var currentFileURL: URL?

    // Глобальный аудио плеер для воспроизведения
    public let audioPlayer: AudioPlayerManager

    public init(audioCache: AudioCache) {
        self.audioPlayer = AudioPlayerManager(audioCache: audioCache)
        self.state = .idle
        self.currentFile = ""
        self.progress = 0.0
        self.modelName = ""
        self.vadInfo = ""
        self.modelLoadingStatus = "Loading model in background..."
        self.currentTranscription = nil
        self.currentFileURL = nil
    }

    public func setModel(_ modelName: String) {
        self.modelName = modelName
    }

    /// Начать транскрипцию файла (только один файл)
    public func startTranscription(file: URL) {
        reset()
        self.currentFile = file.lastPathComponent
        self.currentFileURL = file  // Сохраняем URL для перезапуска
        self.state = .processing
        self.progress = 0.0
    }

    public func updateProgress(file: String, progress: Double) {
        self.currentFile = file
        self.progress = progress
    }

    /// Установить результат транскрипции (моно режим)
    public func setTranscription(file: String, text: String, fileURL: URL) {
        self.currentTranscription = FileTranscription(
            fileName: file,
            text: text,
            status: .success,
            dialogue: nil,
            fileURL: fileURL
        )
        self.currentFileURL = fileURL  // Обновляем URL
    }

    /// Установить результат диалога (стерео режим)
    public func setDialogue(file: String, dialogue: DialogueTranscription, fileURL: URL) {
        self.currentTranscription = FileTranscription(
            fileName: file,
            text: dialogue.formatted(),
            status: .success,
            dialogue: dialogue,
            fileURL: fileURL
        )
        self.currentFileURL = fileURL  // Обновляем URL
        LogManager.app.debug("setDialogue: \(file), turns: \(dialogue.turns.count), isStereo: \(dialogue.isStereo)")
    }

    /// Установить ошибку транскрипции
    public func setError(file: String, error: String) {
        self.currentTranscription = FileTranscription(
            fileName: file,
            text: error,
            status: .error,
            dialogue: nil,
            fileURL: nil
        )
    }

    public func complete() {
        self.state = .completed
        self.progress = 1.0
    }

    /// Сброс состояния для начала работы с новым файлом
    public func reset() {
        audioPlayer.stop()
        self.state = .idle
        self.currentFile = ""
        self.progress = 0.0
        self.currentTranscription = nil
        // Не сбрасываем currentFileURL - оставляем для перезапуска
    }

    public enum TranscriptionState {
        case idle
        case processing
        case completed
    }
}

/// Модель транскрипции файла
public struct FileTranscription: Identifiable {
    public let id = UUID()
    public let fileName: String
    public let text: String
    public let status: Status
    public let dialogue: DialogueTranscription?  // Опциональный диалог для стерео
    public let fileURL: URL?  // URL оригинального файла для воспроизведения

    public enum Status {
        case success
        case error
    }

    public init(fileName: String, text: String, status: Status, dialogue: DialogueTranscription?, fileURL: URL?) {
        self.fileName = fileName
        self.text = text
        self.status = status
        self.dialogue = dialogue
        self.fileURL = fileURL
    }
}

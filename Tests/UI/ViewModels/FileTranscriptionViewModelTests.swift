import XCTest
@testable import TranscribeItCore

/// Unit тесты для FileTranscriptionViewModel
///
/// Покрытие:
/// - Инициализация ViewModel
/// - Управление состоянием транскрипции (idle/processing/completed)
/// - Обновление прогресса
/// - Установка результатов (моно/стерео режим)
/// - Обработка ошибок
/// - Сброс состояния
/// - Взаимодействие с AudioPlayerManager
final class FileTranscriptionViewModelTests: XCTestCase {

    var viewModel: FileTranscriptionViewModel!
    var audioCache: AudioCache!

    override func setUp() {
        super.setUp()
        audioCache = AudioCache()
        viewModel = FileTranscriptionViewModel(audioCache: audioCache)
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    /// Тест: Проверка начального состояния ViewModel после инициализации
    func testInitialState() {
        XCTAssertEqual(viewModel.state, .idle, "Initial state should be idle")
        XCTAssertEqual(viewModel.currentFile, "", "Initial currentFile should be empty")
        XCTAssertEqual(viewModel.progress, 0.0, "Initial progress should be 0")
        XCTAssertEqual(viewModel.modelName, "", "Initial modelName should be empty")
        XCTAssertEqual(viewModel.vadInfo, "", "Initial vadInfo should be empty")
        XCTAssertNil(viewModel.currentTranscription, "Initial transcription should be nil")
        XCTAssertNil(viewModel.currentFileURL, "Initial fileURL should be nil")
        XCTAssertNotNil(viewModel.audioPlayer, "AudioPlayer should be initialized")
    }

    // MARK: - Model Management Tests

    /// Тест: Установка имени модели Whisper
    func testSetModel() {
        // When
        viewModel.setModel("whisper-large-v2")

        // Then
        XCTAssertEqual(viewModel.modelName, "whisper-large-v2")
    }

    /// Тест: Изменение имени модели
    func testSetModelMultipleTimes() {
        // Given
        viewModel.setModel("whisper-small")

        // When
        viewModel.setModel("whisper-medium")

        // Then
        XCTAssertEqual(viewModel.modelName, "whisper-medium")
    }

    // MARK: - Transcription Lifecycle Tests

    /// Тест: Начало транскрипции файла
    func testStartTranscription() {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/test_audio.wav")

        // When
        viewModel.startTranscription(file: testURL)

        // Then
        XCTAssertEqual(viewModel.state, .processing, "State should be processing")
        XCTAssertEqual(viewModel.currentFile, "test_audio.wav", "Current file should be set")
        XCTAssertEqual(viewModel.progress, 0.0, "Progress should be reset to 0")
        XCTAssertEqual(viewModel.currentFileURL, testURL, "File URL should be saved")
    }

    /// Тест: Начало транскрипции сбрасывает предыдущее состояние
    func testStartTranscriptionResetsState() {
        // Given - установим предыдущее состояние
        let oldURL = URL(fileURLWithPath: "/tmp/old.wav")
        viewModel.startTranscription(file: oldURL)
        viewModel.updateProgress(file: "old.wav", progress: 0.5)

        let oldTranscription = FileTranscription(
            fileName: "old.wav",
            text: "Old text",
            status: .success,
            dialogue: nil,
            fileURL: oldURL
        )
        viewModel.currentTranscription = oldTranscription

        // When - начнем новую транскрипцию
        let newURL = URL(fileURLWithPath: "/tmp/new.wav")
        viewModel.startTranscription(file: newURL)

        // Then - состояние должно быть сброшено
        XCTAssertEqual(viewModel.state, .processing)
        XCTAssertEqual(viewModel.currentFile, "new.wav")
        XCTAssertEqual(viewModel.progress, 0.0, "Progress should be reset")
        XCTAssertNil(viewModel.currentTranscription, "Previous transcription should be cleared")
        XCTAssertEqual(viewModel.currentFileURL, newURL, "New URL should be set")
    }

    /// Тест: Обновление прогресса транскрипции
    func testUpdateProgress() {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/test.wav")
        viewModel.startTranscription(file: testURL)

        // When
        viewModel.updateProgress(file: "test.wav", progress: 0.45)

        // Then
        XCTAssertEqual(viewModel.progress, 0.45, accuracy: 0.001)
        XCTAssertEqual(viewModel.currentFile, "test.wav")
    }

    /// Тест: Постепенное увеличение прогресса
    func testProgressIncreases() {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/test.wav")
        viewModel.startTranscription(file: testURL)

        // When
        viewModel.updateProgress(file: "test.wav", progress: 0.25)
        XCTAssertEqual(viewModel.progress, 0.25, accuracy: 0.001)

        viewModel.updateProgress(file: "test.wav", progress: 0.50)
        XCTAssertEqual(viewModel.progress, 0.50, accuracy: 0.001)

        viewModel.updateProgress(file: "test.wav", progress: 0.75)
        XCTAssertEqual(viewModel.progress, 0.75, accuracy: 0.001)

        // Then
        XCTAssertGreaterThan(viewModel.progress, 0.5)
    }

    /// Тест: Завершение транскрипции
    func testComplete() {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/test.wav")
        viewModel.startTranscription(file: testURL)
        viewModel.updateProgress(file: "test.wav", progress: 0.5)

        // When
        viewModel.complete()

        // Then
        XCTAssertEqual(viewModel.state, .completed)
        XCTAssertEqual(viewModel.progress, 1.0)
    }

    // MARK: - Transcription Result Tests

    /// Тест: Установка результата моно транскрипции
    func testSetTranscription() {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/test.wav")
        let transcriptionText = "This is a test transcription"

        // When
        viewModel.setTranscription(file: "test.wav", text: transcriptionText, fileURL: testURL)

        // Then
        XCTAssertNotNil(viewModel.currentTranscription)
        XCTAssertEqual(viewModel.currentTranscription?.fileName, "test.wav")
        XCTAssertEqual(viewModel.currentTranscription?.text, transcriptionText)
        XCTAssertEqual(viewModel.currentTranscription?.status, .success)
        XCTAssertNil(viewModel.currentTranscription?.dialogue, "Dialogue should be nil for mono")
        XCTAssertEqual(viewModel.currentTranscription?.fileURL, testURL)
        XCTAssertEqual(viewModel.currentFileURL, testURL)
    }

    /// Тест: Установка результата стерео диалога
    func testSetDialogue() {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/stereo.wav")

        let turn1 = DialogueTranscription.Turn(
            speaker: .left,
            text: "Hello, how are you?",
            startTime: 0.0,
            endTime: 2.0
        )

        let turn2 = DialogueTranscription.Turn(
            speaker: .right,
            text: "I'm fine, thank you!",
            startTime: 2.5,
            endTime: 4.5
        )

        let dialogue = DialogueTranscription(
            turns: [turn1, turn2],
            isStereo: true,
            totalDuration: 5.0
        )

        // When
        viewModel.setDialogue(file: "stereo.wav", dialogue: dialogue, fileURL: testURL)

        // Then
        XCTAssertNotNil(viewModel.currentTranscription)
        XCTAssertEqual(viewModel.currentTranscription?.fileName, "stereo.wav")
        XCTAssertEqual(viewModel.currentTranscription?.status, .success)
        XCTAssertNotNil(viewModel.currentTranscription?.dialogue, "Dialogue should be set for stereo")
        XCTAssertEqual(viewModel.currentTranscription?.dialogue?.turns.count, 2)
        XCTAssertEqual(viewModel.currentTranscription?.dialogue?.isStereo, true)
        XCTAssertEqual(viewModel.currentTranscription?.fileURL, testURL)
        XCTAssertEqual(viewModel.currentFileURL, testURL)
    }

    /// Тест: Форматирование диалога в текст
    func testSetDialogueFormatsText() {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/stereo.wav")

        let turn = DialogueTranscription.Turn(
            speaker: .left,
            text: "Test text",
            startTime: 0.0,
            endTime: 1.0
        )

        let dialogue = DialogueTranscription(
            turns: [turn],
            isStereo: true,
            totalDuration: 2.0
        )

        // When
        viewModel.setDialogue(file: "stereo.wav", dialogue: dialogue, fileURL: testURL)

        // Then
        XCTAssertNotNil(viewModel.currentTranscription?.text)
        XCTAssertFalse(viewModel.currentTranscription!.text.isEmpty, "Text should be formatted from dialogue")
        // formatted() метод создает форматированный текст из реплик
    }

    // MARK: - Error Handling Tests

    /// Тест: Установка ошибки транскрипции
    func testSetError() {
        // Given
        let errorMessage = "Failed to load audio file"

        // When
        viewModel.setError(file: "error.wav", error: errorMessage)

        // Then
        XCTAssertNotNil(viewModel.currentTranscription)
        XCTAssertEqual(viewModel.currentTranscription?.fileName, "error.wav")
        XCTAssertEqual(viewModel.currentTranscription?.text, errorMessage)
        XCTAssertEqual(viewModel.currentTranscription?.status, .error)
        XCTAssertNil(viewModel.currentTranscription?.dialogue, "Dialogue should be nil on error")
        XCTAssertNil(viewModel.currentTranscription?.fileURL, "File URL should be nil on error")
    }

    /// Тест: Ошибка после успешного начала транскрипции
    func testErrorAfterStartingTranscription() {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/test.wav")
        viewModel.startTranscription(file: testURL)
        viewModel.updateProgress(file: "test.wav", progress: 0.3)

        // When
        viewModel.setError(file: "test.wav", error: "Transcription timeout")

        // Then
        XCTAssertNotNil(viewModel.currentTranscription)
        XCTAssertEqual(viewModel.currentTranscription?.status, .error)
        XCTAssertEqual(viewModel.currentTranscription?.text, "Transcription timeout")
        // Прогресс и состояние остаются как были
        XCTAssertEqual(viewModel.progress, 0.3, accuracy: 0.001)
    }

    // MARK: - Reset Tests

    /// Тест: Сброс состояния
    func testReset() {
        // Given - установим состояние
        let testURL = URL(fileURLWithPath: "/tmp/test.wav")
        viewModel.startTranscription(file: testURL)
        viewModel.updateProgress(file: "test.wav", progress: 0.7)
        viewModel.setTranscription(file: "test.wav", text: "Some text", fileURL: testURL)
        viewModel.setModel("whisper-large")

        // When
        viewModel.reset()

        // Then
        XCTAssertEqual(viewModel.state, .idle, "State should be reset to idle")
        XCTAssertEqual(viewModel.currentFile, "", "Current file should be cleared")
        XCTAssertEqual(viewModel.progress, 0.0, "Progress should be reset")
        XCTAssertNil(viewModel.currentTranscription, "Transcription should be cleared")
        // currentFileURL не сбрасывается для возможности перезапуска
        XCTAssertEqual(viewModel.currentFileURL, testURL, "File URL should be preserved for retry")
        // modelName сохраняется
        XCTAssertEqual(viewModel.modelName, "whisper-large", "Model name should be preserved")
    }

    /// Тест: Сброс останавливает аудио плеер
    func testResetStopsAudioPlayer() {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/test.wav")
        viewModel.startTranscription(file: testURL)

        // Предполагаем, что аудио может играть
        // (в реальной ситуации нужен mock AudioPlayerManager)

        // When
        viewModel.reset()

        // Then
        // reset() вызывает audioPlayer.stop()
        XCTAssertFalse(viewModel.audioPlayer.state.playback.isPlaying, "Audio player should be stopped")
    }

    /// Тест: Множественный сброс состояния
    func testMultipleResets() {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/test.wav")
        viewModel.startTranscription(file: testURL)

        // When
        viewModel.reset()
        viewModel.reset()
        viewModel.reset()

        // Then - не должно быть ошибок при множественных сбросах
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(viewModel.currentFile, "")
        XCTAssertEqual(viewModel.progress, 0.0)
    }

    // MARK: - State Transition Tests

    /// Тест: Полный цикл успешной транскрипции (idle -> processing -> completed)
    func testSuccessfulTranscriptionFlow() {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/test.wav")

        // 1. Начальное состояние
        XCTAssertEqual(viewModel.state, .idle)

        // 2. Начало транскрипции
        viewModel.startTranscription(file: testURL)
        XCTAssertEqual(viewModel.state, .processing)
        XCTAssertEqual(viewModel.progress, 0.0)

        // 3. Обновление прогресса
        viewModel.updateProgress(file: "test.wav", progress: 0.5)
        XCTAssertEqual(viewModel.state, .processing)
        XCTAssertEqual(viewModel.progress, 0.5, accuracy: 0.001)

        // 4. Установка результата
        viewModel.setTranscription(file: "test.wav", text: "Result", fileURL: testURL)
        XCTAssertNotNil(viewModel.currentTranscription)

        // 5. Завершение
        viewModel.complete()
        XCTAssertEqual(viewModel.state, .completed)
        XCTAssertEqual(viewModel.progress, 1.0)
    }

    /// Тест: Цикл неудачной транскрипции (idle -> processing -> error)
    func testFailedTranscriptionFlow() {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/test.wav")

        // 1. Начало транскрипции
        viewModel.startTranscription(file: testURL)
        XCTAssertEqual(viewModel.state, .processing)

        // 2. Частичный прогресс
        viewModel.updateProgress(file: "test.wav", progress: 0.2)

        // 3. Ошибка
        viewModel.setError(file: "test.wav", error: "Audio format not supported")
        XCTAssertEqual(viewModel.currentTranscription?.status, .error)

        // Состояние остается processing (complete() не вызван)
        XCTAssertEqual(viewModel.state, .processing)
    }

    // MARK: - Edge Cases Tests

    /// Тест: Установка прогресса без начала транскрипции
    func testUpdateProgressWithoutStart() {
        // When
        viewModel.updateProgress(file: "test.wav", progress: 0.5)

        // Then - не должно вызывать ошибок
        XCTAssertEqual(viewModel.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(viewModel.currentFile, "test.wav")
    }

    /// Тест: Установка результата без начала транскрипции
    func testSetTranscriptionWithoutStart() {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/test.wav")

        // When
        viewModel.setTranscription(file: "test.wav", text: "Result", fileURL: testURL)

        // Then - должно работать корректно
        XCTAssertNotNil(viewModel.currentTranscription)
        XCTAssertEqual(viewModel.currentTranscription?.status, .success)
    }

    /// Тест: Завершение без начала транскрипции
    func testCompleteWithoutStart() {
        // When
        viewModel.complete()

        // Then
        XCTAssertEqual(viewModel.state, .completed)
        XCTAssertEqual(viewModel.progress, 1.0)
    }

    /// Тест: Пустое имя файла
    func testEmptyFileName() {
        // Given
        let testURL = URL(fileURLWithPath: "/")

        // When
        viewModel.startTranscription(file: testURL)

        // Then
        XCTAssertTrue(viewModel.currentFile.isEmpty || viewModel.currentFile == "/")
    }

    /// Тест: Прогресс выше 1.0
    func testProgressOverOne() {
        // When
        viewModel.updateProgress(file: "test.wav", progress: 1.5)

        // Then - ViewModel не валидирует прогресс, это ответственность вызывающего кода
        XCTAssertEqual(viewModel.progress, 1.5, accuracy: 0.001)
    }

    /// Тест: Отрицательный прогресс
    func testNegativeProgress() {
        // When
        viewModel.updateProgress(file: "test.wav", progress: -0.5)

        // Then
        XCTAssertEqual(viewModel.progress, -0.5, accuracy: 0.001)
    }

    // MARK: - File URL Persistence Tests

    /// Тест: URL файла сохраняется для перезапуска
    func testFileURLPersistsAfterReset() {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/test.wav")
        viewModel.startTranscription(file: testURL)

        // When
        viewModel.reset()

        // Then
        XCTAssertEqual(viewModel.currentFileURL, testURL, "File URL should persist for retry")
    }

    /// Тест: URL обновляется при новом файле
    func testFileURLUpdatesWithNewFile() {
        // Given
        let firstURL = URL(fileURLWithPath: "/tmp/first.wav")
        let secondURL = URL(fileURLWithPath: "/tmp/second.wav")

        viewModel.startTranscription(file: firstURL)
        XCTAssertEqual(viewModel.currentFileURL, firstURL)

        // When
        viewModel.startTranscription(file: secondURL)

        // Then
        XCTAssertEqual(viewModel.currentFileURL, secondURL)
    }

    /// Тест: URL обновляется при установке результата
    func testFileURLUpdatesWithResult() {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/test.wav")

        // When
        viewModel.setTranscription(file: "test.wav", text: "Text", fileURL: testURL)

        // Then
        XCTAssertEqual(viewModel.currentFileURL, testURL)
    }
}

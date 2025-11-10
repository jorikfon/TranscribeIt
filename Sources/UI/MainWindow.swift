import SwiftUI
import AppKit
import TranscribeItCore

// MARK: - Адаптивные цвета для тёмной темы
extension Color {
    /// Адаптивный цвет для Speaker 1 (левый канал)
    static var speaker1Background: Color {
        Color(NSColor.controlAccentColor).opacity(0.1)
    }

    static var speaker1Accent: Color {
        Color(NSColor.controlAccentColor)
    }

    /// Адаптивный цвет для Speaker 2 (правый канал)
    static var speaker2Background: Color {
        Color.orange.opacity(0.12)
    }

    static var speaker2Accent: Color {
        Color.orange
    }

    /// Адаптивный фон для колонок
    static var timelineColumnBackground: Color {
        Color(NSColor.controlBackgroundColor).opacity(0.3)
    }
}

/// Окно для отображения прогресса и результатов транскрипции файлов
/// Главное окно приложения для работы с одним стерео файлом телефонных записей
public class MainWindow: NSWindow, NSWindowDelegate {
    private var hostingController: NSHostingController<FileTranscriptionView>?
    public var viewModel: FileTranscriptionViewModel
    public var onClose: ((MainWindow) -> Void)?
    public var onStartTranscription: (([URL]) -> Void)?

    public convenience init() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let windowWidth: CGFloat = 900
        let windowHeight: CGFloat = 700

        let windowFrame = NSRect(
            x: screenFrame.midX - windowWidth / 2,
            y: screenFrame.midY - windowHeight / 2,
            width: windowWidth,
            height: windowHeight
        )

        // NSWindow инициализация
        self.init(
            contentRect: windowFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
    }

    public override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        // Инициализируем ViewModel
        self.viewModel = FileTranscriptionViewModel()

        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        // Настройка окна
        self.title = "TranscribeIt - Stereo Call Transcription"
        self.minSize = NSSize(width: 700, height: 500)
        self.delegate = self  // Устанавливаем delegate для обработки событий закрытия

        // Создаём SwiftUI view с ViewModel и callback
        let swiftUIView = FileTranscriptionView(
            viewModel: viewModel,
            onStartTranscription: { [weak self] files in
                self?.onStartTranscription?(files)
            }
        )
        let hosting = NSHostingController(rootView: swiftUIView)
        self.hostingController = hosting

        // Настраиваем content view
        self.contentView = hosting.view

        LogManager.app.info("MainWindow: NSWindow создано с SwiftUI")
    }

    // MARK: - NSWindowDelegate

    /// Вызывается при закрытии окна - останавливаем воспроизведение
    public func windowWillClose(_ notification: Notification) {
        viewModel.audioPlayer.stop()
        LogManager.app.info("MainWindow: Окно закрывается, воспроизведение остановлено")
    }

    /// Начать транскрипцию файлов
    public func startTranscription(files: [URL]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let file = files.first else { return }

            self.viewModel.startTranscription(file: file)
            self.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            // Вызываем callback для запуска реальной транскрипции
            self.onStartTranscription?(files)
        }
    }

    /// Закрыть окно
    public func hideWindow() {
        DispatchQueue.main.async { [weak self] in
            self?.orderOut(nil)
        }
    }

    deinit {
        LogManager.app.info("MainWindow: deinit - очищаем ресурсы")
        hostingController = nil
        onClose?(self)
    }
}

/// ViewModel для окна транскрипции файлов
/// Упрощённая версия для работы с одним стерео файлом телефонных записей
public class FileTranscriptionViewModel: ObservableObject {
    @Published public var state: TranscriptionState = .idle
    @Published public var currentFile: String = ""
    @Published public var progress: Double = 0.0
    @Published public var modelName: String = ""  // Текущая модель Whisper
    @Published public var vadInfo: String = ""  // Информация о VAD алгоритме
    @Published public var modelLoadingStatus: String? = nil  // Статус загрузки модели в фоне

    // Текущая транскрипция (только один файл)
    @Published public var currentTranscription: FileTranscription?

    // URL текущего файла для перезапуска
    @Published public var currentFileURL: URL?

    // Глобальный аудио плеер для воспроизведения
    public let audioPlayer = AudioPlayerManager()

    public init() {
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

/// SwiftUI view для окна транскрипции
struct FileTranscriptionView: View {
    @ObservedObject var viewModel: FileTranscriptionViewModel
    var onStartTranscription: (([URL]) -> Void)?

    @ObservedObject private var modelManager = ModelManager.shared
    @ObservedObject private var userSettings = UserSettings.shared

    @State private var showSettings: Bool = false
    @State private var selectedModel: String = ""
    @State private var selectedVADAlgorithm: UserSettings.VADAlgorithmType = .spectralTelephone
    @State private var selectedLanguage: String = "ru"

    // Текущая транскрипция из ViewModel
    private var currentTranscription: FileTranscription? {
        viewModel.currentTranscription
    }

    var body: some View {
        VStack(spacing: 0) {
            // Компактный заголовок
            HStack {
                // Имя файла
                if let transcription = currentTranscription {
                    Text(transcription.fileName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                } else {
                    Text("Stereo Call Transcription")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Модель и VAD
                HStack(spacing: 12) {
                    // Статус загрузки модели (показываем только если загружается, не когда готова)
                    if let loadingStatus = viewModel.modelLoadingStatus, loadingStatus != "Model ready" {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 10, height: 10)
                            Text(loadingStatus)
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                    }

                    // Показываем модель и VAD всегда когда они доступны (в том числе когда модель готова)
                    if !viewModel.modelName.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                            Text(viewModel.modelName)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Язык транскрибации
                    if !userSettings.transcriptionLanguage.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.system(size: 10))
                                .foregroundColor(.purple)
                            Text(userSettings.transcriptionLanguage.uppercased())
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.system(size: 10))
                                .foregroundColor(.purple)
                            Text("Auto")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    if !viewModel.vadInfo.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                            Text(viewModel.vadInfo)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Кнопка "New File" (если есть транскрипция)
                    if viewModel.state == .completed {
                        Button(action: {
                            selectNewFile()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 10))
                                Text("New File")
                                    .font(.system(size: 10))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    }

                    // Кнопка настроек (показывается только если есть файл)
                    if viewModel.currentFileURL != nil {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showSettings.toggle()
                            }
                        }) {
                            Image(systemName: showSettings ? "chevron.up.circle.fill" : "gearshape.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(showSettings ? .blue : .secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Настройки транскрибации")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Панель настроек (раскрывающаяся)
            if showSettings {
                TranscriptionSettingsPanel(
                    selectedModel: $selectedModel,
                    selectedVADAlgorithm: $selectedVADAlgorithm,
                    selectedLanguage: $selectedLanguage,
                    modelManager: modelManager,
                    onRetranscribe: {
                        retranscribeCurrentFile()
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }

            // Прогресс бар (если транскрибируется)
            if viewModel.state == .processing {
                ProgressView(value: viewModel.progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding(.horizontal, 16)
            }

            // Содержимое транскрипции
            if let transcription = currentTranscription {
                VStack(spacing: 0) {
                    // Аудио плеер
                    if let fileURL = transcription.fileURL {
                        AudioPlayerView(audioPlayer: viewModel.audioPlayer, fileURL: fileURL)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(NSColor.controlBackgroundColor))
                    }

                    // Диалог или текст
                    if let dialogue = transcription.dialogue, dialogue.isStereo {
                        TimelineSyncedDialogueView(dialogue: dialogue, audioPlayer: viewModel.audioPlayer)
                    } else {
                        ScrollView {
                            Text(transcription.text)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
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
            } else {
                // Пустое состояние - показываем кнопку выбора файла
                VStack(spacing: 20) {
                    Spacer()

                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("No audio file selected")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("Select an audio file to transcribe")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.7))

                    Button(action: {
                        selectAudioFile()
                    }) {
                        Label("Select Audio File", systemImage: "folder")
                            .font(.system(size: 13))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("Supported formats: WAV, MP3, M4A, AIFF, FLAC, AAC")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.6))

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            initializeSettings()
        }
    }

    // MARK: - File Selection

    private func selectAudioFile() {
        let panel = NSOpenPanel()
        panel.title = "Select Stereo Audio File"
        panel.prompt = "Select"
        panel.message = "Select a stereo telephone recording (left = speaker 1, right = speaker 2)"
        panel.allowsMultipleSelection = false  // Только один файл
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff, .mpeg4Audio]

        panel.begin { response in
            if response == .OK, let fileURL = panel.url {
                // Проверяем расширение файла
                let ext = fileURL.pathExtension.lowercased()
                guard ["wav", "mp3", "m4a", "aiff", "flac", "aac"].contains(ext) else {
                    LogManager.app.error("Неподдерживаемый формат файла: \(ext)")
                    return
                }

                // Вызываем callback с одним файлом
                onStartTranscription?([fileURL])
                LogManager.app.info("Выбран файл для транскрипции: \(fileURL.lastPathComponent)")
            }
        }
    }

    /// Выбор нового файла после завершения предыдущей транскрипции
    private func selectNewFile() {
        viewModel.reset()
        viewModel.currentFileURL = nil  // Сбрасываем URL для нового файла
        selectAudioFile()
    }

    /// Перезапустить транскрибацию текущего файла с новыми настройками
    private func retranscribeCurrentFile() {
        guard let fileURL = viewModel.currentFileURL else {
            LogManager.app.error("Невозможно перезапустить - нет URL файла")
            return
        }

        // Сохраняем выбранные настройки
        modelManager.saveCurrentModel(selectedModel)
        userSettings.vadAlgorithmType = selectedVADAlgorithm
        userSettings.transcriptionLanguage = selectedLanguage

        // Автоматически обновляем fileTranscriptionMode на основе выбранного алгоритма
        if selectedVADAlgorithm.isBatchMode {
            userSettings.fileTranscriptionMode = .batch
        } else {
            userSettings.fileTranscriptionMode = .vad
        }

        let modeInfo = selectedVADAlgorithm.isBatchMode ? "Batch" : "VAD"
        let langInfo = selectedLanguage.isEmpty ? "Auto" : selectedLanguage.uppercased()
        LogManager.app.info("Перезапуск транскрибации: модель=\(selectedModel), режим=\(modeInfo), алгоритм=\(selectedVADAlgorithm.displayName), язык=\(langInfo)")

        // Скрываем панель настроек
        withAnimation {
            showSettings = false
        }

        // Запускаем транскрибацию заново
        onStartTranscription?([fileURL])
    }
}

// Инициализация значений при появлении view
extension FileTranscriptionView {
    func initializeSettings() {
        // Инициализируем только один раз
        if selectedModel.isEmpty {
            selectedModel = modelManager.currentModel
        }
        selectedVADAlgorithm = userSettings.vadAlgorithmType
        selectedLanguage = userSettings.transcriptionLanguage
    }
}

/// Панель настроек транскрибации
struct TranscriptionSettingsPanel: View {
    @Binding var selectedModel: String
    @Binding var selectedVADAlgorithm: UserSettings.VADAlgorithmType
    @Binding var selectedLanguage: String
    @ObservedObject var modelManager: ModelManager
    var onRetranscribe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            HStack(spacing: 16) {
                // Выбор модели
                VStack(alignment: .leading, spacing: 6) {
                    Text("Whisper Model")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Picker("", selection: $selectedModel) {
                        ForEach(modelManager.supportedModels, id: \.name) { model in
                            HStack {
                                Text(model.displayName)
                                Text("(\(model.size), \(model.accuracy))")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .tag(model.name)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Выбор языка
                VStack(alignment: .leading, spacing: 6) {
                    Text("Language")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Picker("", selection: $selectedLanguage) {
                        Text("Auto-detect").tag("")
                        Text("Russian").tag("ru")
                        Text("English").tag("en")
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 150)
                }
            }

            // Выбор VAD алгоритма / режима
            VStack(alignment: .leading, spacing: 6) {
                Text("Segmentation Method")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Picker("", selection: $selectedVADAlgorithm) {
                    // Группа VAD алгоритмов
                    Section(header: Text("VAD Algorithms")) {
                        ForEach(UserSettings.VADAlgorithmType.allCases.filter { !$0.isBatchMode }) { vadType in
                            Text(vadType.displayName)
                                .font(.system(size: 11))
                                .tag(vadType)
                        }
                    }

                    // Batch режим отдельно
                    Section(header: Text("Alternative Mode")) {
                        ForEach(UserSettings.VADAlgorithmType.allCases.filter { $0.isBatchMode }) { vadType in
                            Text(vadType.displayName)
                                .font(.system(size: 11))
                                .tag(vadType)
                        }
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: .infinity, alignment: .leading)

                // Описание выбранного метода
                HStack(spacing: 4) {
                    Image(systemName: selectedVADAlgorithm.isBatchMode ? "square.grid.3x3.fill" : "waveform")
                        .font(.system(size: 9))
                        .foregroundColor(selectedVADAlgorithm.isBatchMode ? .orange : .green)

                    Text(selectedVADAlgorithm.description)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            // Кнопка перезапуска
            HStack {
                Spacer()
                Button(action: {
                    onRetranscribe()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                        Text("Retranscribe with New Settings")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}


/// Маппер для визуального сжатия периодов тишины на timeline
struct CompressedTimelineMapper {
    struct SilenceGap {
        let realStartTime: TimeInterval
        let realEndTime: TimeInterval
        let duration: TimeInterval
    }

    let silenceGaps: [SilenceGap]
    let minGapToCompress: TimeInterval = 0.5  // Сжимаем gaps > 0.5 секунды (агрессивное сжатие)
    let compressedGapDisplay: TimeInterval = 0.15  // Показываем как 0.15 секунды (минимальный зазор)

    /// Инициализирует mapper, анализируя реплики и находя периоды тишины
    /// ВАЖНО: Ищем промежутки, где ОБА спикера молчат одновременно
    init(turns: [DialogueTranscription.Turn]) {
        let sortedTurns = turns.sorted { $0.startTime < $1.startTime }
        var gaps: [SilenceGap] = []

        // Логирование для отладки
        LogManager.app.debug("CompressedTimelineMapper: Анализ \(sortedTurns.count) реплик для поиска gaps")

        guard !sortedTurns.isEmpty else {
            self.silenceGaps = []
            return
        }

        // 1. Создаем массив всех занятых временных интервалов
        var occupiedIntervals: [(start: TimeInterval, end: TimeInterval)] = []
        for turn in sortedTurns {
            occupiedIntervals.append((start: turn.startTime, end: turn.endTime))
        }

        // 2. Сортируем интервалы по началу
        occupiedIntervals.sort { $0.start < $1.start }

        // 3. Объединяем перекрывающиеся интервалы
        var mergedIntervals: [(start: TimeInterval, end: TimeInterval)] = []
        var currentInterval = occupiedIntervals[0]

        for i in 1..<occupiedIntervals.count {
            let nextInterval = occupiedIntervals[i]

            if nextInterval.start <= currentInterval.end {
                // Интервалы перекрываются или соприкасаются - объединяем
                currentInterval.end = max(currentInterval.end, nextInterval.end)
            } else {
                // Интервалы не перекрываются - сохраняем текущий и начинаем новый
                mergedIntervals.append(currentInterval)
                currentInterval = nextInterval
            }
        }
        mergedIntervals.append(currentInterval)

        LogManager.app.debug("  Объединено в \(mergedIntervals.count) непрерывных интервалов активности")

        // 4. Находим промежутки тишины между объединенными интервалами
        for i in 0..<(mergedIntervals.count - 1) {
            let currentEnd = mergedIntervals[i].end
            let nextStart = mergedIntervals[i + 1].start
            let gapDuration = nextStart - currentEnd

            // Сжимаем только длинные промежутки тишины (оба спикера молчат)
            if gapDuration > minGapToCompress {
                gaps.append(SilenceGap(
                    realStartTime: currentEnd,
                    realEndTime: nextStart,
                    duration: gapDuration
                ))
                LogManager.app.debug("  Тишина (оба молчат): \(String(format: "%.1f", currentEnd))s - \(String(format: "%.1f", nextStart))s (длительность: \(String(format: "%.1f", gapDuration))s)")
            }
        }

        self.silenceGaps = gaps
        LogManager.app.info("CompressedTimelineMapper: Найдено \(gaps.count) периодов тишины (оба спикера) для сжатия")
    }

    /// Преобразует реальное время в визуальную позицию (с учетом сжатия)
    func visualPosition(for realTime: TimeInterval) -> TimeInterval {
        var visualTime = realTime

        // Вычитаем сжатые интервалы для всех gaps, которые до этого времени
        for gap in silenceGaps {
            if realTime > gap.realStartTime {
                let compressionAmount = min(gap.duration - compressedGapDisplay, gap.duration)
                if realTime >= gap.realEndTime {
                    // Полностью прошли gap - вычитаем всю компрессию
                    visualTime -= compressionAmount
                } else {
                    // Внутри gap - частичная компрессия
                    let withinGap = realTime - gap.realStartTime
                    let ratio = withinGap / gap.duration
                    visualTime -= compressionAmount * ratio
                }
            }
        }

        return max(0, visualTime)
    }

    /// Возвращает общую визуальную длительность (сжатую)
    func totalVisualDuration(realDuration: TimeInterval) -> TimeInterval {
        let totalCompression = silenceGaps.reduce(0.0) { sum, gap in
            sum + (gap.duration - compressedGapDisplay)
        }
        return max(0, realDuration - totalCompression)
    }
}

/// Отображение диалога в виде двух синхронизированных по времени колонок
struct TimelineSyncedDialogueView: View {
    let dialogue: DialogueTranscription
    @ObservedObject var audioPlayer: AudioPlayerManager

    // Mapper для визуального сжатия тишины
    private var timelineMapper: CompressedTimelineMapper {
        CompressedTimelineMapper(turns: dialogue.turns)
    }

    // Визуальная длительность (с учетом сжатия)
    private var visualDuration: TimeInterval {
        timelineMapper.totalVisualDuration(realDuration: dialogue.totalDuration)
    }

    // Адаптивная высота: вычисляем оптимальный масштаб
    private var pixelsPerSecond: CGFloat {
        calculateAdaptiveScale()
    }

    // Максимальная и минимальная высота timeline
    private let maxTimelineHeight: CGFloat = 600  // Максимум 600px
    private let minPixelsPerSecond: CGFloat = 15  // Минимум 15px/sec (более компактно)
    private let maxPixelsPerSecond: CGFloat = 80  // Максимум 80px/sec (для очень коротких)

    /// Вычисляет адаптивный масштаб timeline на основе ВИЗУАЛЬНОЙ длительности (сжатой)
    private func calculateAdaptiveScale() -> CGFloat {
        // Если нет реплик, используем средний масштаб
        guard !dialogue.turns.isEmpty else { return 40 }

        // Используем ВИЗУАЛЬНУЮ длительность (с учетом сжатия тишины)
        let duration = visualDuration
        guard duration > 0 else { return 40 }

        // Вычисляем идеальный масштаб, чтобы вместить диалог в maxTimelineHeight
        let idealScale = maxTimelineHeight / CGFloat(duration)

        // Ограничиваем масштаб для читабельности
        return max(minPixelsPerSecond, min(maxPixelsPerSecond, idealScale))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Заголовок с информацией
            HStack {
                Image(systemName: "waveform.path")
                    .foregroundColor(.blue)
                Text("Timeline View")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                // Общая длительность
                Text(formatDuration(dialogue.totalDuration))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Divider()

            if dialogue.turns.isEmpty {
                Text("Нет распознанных реплик")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                // Две колонки с единой временной шкалой (показывает одновременную речь)
                ScrollView {
                    TimelineDialogueView(dialogue: dialogue, audioPlayer: audioPlayer)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
                .frame(maxHeight: 600)
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Новый вид: компактные блоки с индикаторами длительности
/// Высота блока = высота текста, слева цветная полоска = длительность
struct TimelineDialogueView: View {
    let dialogue: DialogueTranscription
    @ObservedObject var audioPlayer: AudioPlayerManager

    // Mapper для определения промежутков тишины
    private var timelineMapper: CompressedTimelineMapper {
        CompressedTimelineMapper(turns: dialogue.turns)
    }

    // Масштаб для индикатора длительности (px/sec)
    private let durationBarScale: CGFloat = 3.0  // 3px = 1 секунда

    // Структура для синхронизированной строки (левая и правая реплика на одном уровне)
    struct SyncedRow {
        let leftTurn: DialogueTranscription.Turn?
        let rightTurn: DialogueTranscription.Turn?
        let timestamp: TimeInterval  // Опорная временная метка для строки
    }

    // Синхронизированные строки - реплики с близкими временными метками на одном уровне
    private var syncedRows: [SyncedRow] {
        let leftTurns = dialogue.turns.filter { $0.speaker == .left }.sorted { $0.startTime < $1.startTime }
        let rightTurns = dialogue.turns.filter { $0.speaker == .right }.sorted { $0.startTime < $1.startTime }

        var rows: [SyncedRow] = []
        var leftIndex = 0
        var rightIndex = 0

        // Порог времени для объединения реплик в одну строку (0.5 секунды)
        let timeTolerance: TimeInterval = 0.5

        while leftIndex < leftTurns.count || rightIndex < rightTurns.count {
            let leftTurn = leftIndex < leftTurns.count ? leftTurns[leftIndex] : nil
            let rightTurn = rightIndex < rightTurns.count ? rightTurns[rightIndex] : nil

            if let left = leftTurn, let right = rightTurn {
                // Обе реплики есть - сравниваем время
                let timeDiff = abs(left.startTime - right.startTime)

                if timeDiff <= timeTolerance {
                    // Реплики близко по времени - объединяем в одну строку
                    let avgTime = (left.startTime + right.startTime) / 2
                    rows.append(SyncedRow(leftTurn: left, rightTurn: right, timestamp: avgTime))
                    leftIndex += 1
                    rightIndex += 1
                } else if left.startTime < right.startTime {
                    // Левая реплика раньше
                    rows.append(SyncedRow(leftTurn: left, rightTurn: nil, timestamp: left.startTime))
                    leftIndex += 1
                } else {
                    // Правая реплика раньше
                    rows.append(SyncedRow(leftTurn: nil, rightTurn: right, timestamp: right.startTime))
                    rightIndex += 1
                }
            } else if let left = leftTurn {
                // Только левая реплика осталась
                rows.append(SyncedRow(leftTurn: left, rightTurn: nil, timestamp: left.startTime))
                leftIndex += 1
            } else if let right = rightTurn {
                // Только правая реплика осталась
                rows.append(SyncedRow(leftTurn: nil, rightTurn: right, timestamp: right.startTime))
                rightIndex += 1
            }
        }

        return rows
    }

    // Вычисляет промежуток тишины между строками
    private func calculateGap(from currentRow: SyncedRow, to nextRow: SyncedRow) -> TimeInterval? {
        // Находим максимальное endTime в текущей строке
        var maxEndTime: TimeInterval = 0
        if let left = currentRow.leftTurn {
            maxEndTime = max(maxEndTime, left.endTime)
        }
        if let right = currentRow.rightTurn {
            maxEndTime = max(maxEndTime, right.endTime)
        }

        // Находим минимальное startTime в следующей строке
        var minStartTime: TimeInterval = .greatestFiniteMagnitude
        if let left = nextRow.leftTurn {
            minStartTime = min(minStartTime, left.startTime)
        }
        if let right = nextRow.rightTurn {
            minStartTime = min(minStartTime, right.startTime)
        }

        let gap = minStartTime - maxEndTime

        // Показываем индикатор только для значительных промежутков (>1 секунда)
        return gap > 1.0 ? gap : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Заголовки колонок
                HStack(spacing: 8) {
                    Text("Speaker 1")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.speaker1Accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.speaker1Background)
                        .cornerRadius(6)

                    Text("Speaker 2")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.speaker2Accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.speaker2Background)
                        .cornerRadius(6)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                // DEBUG: Показываем текущее время воспроизведения
                if audioPlayer.isPlaying {
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 10))
                        Text("Playing: \(String(format: "%.2f", audioPlayer.currentTime))s")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
                    .padding(.horizontal, 12)
                }

                // Синхронизированные реплики - реплики на одном уровне по времени
                VStack(spacing: 0) {
                    ForEach(Array(syncedRows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .top, spacing: 8) {
                            // Левая колонка
                            if let leftTurn = row.leftTurn {
                                CompactTurnCard(
                                    turn: leftTurn,
                                    speaker: .left,
                                    audioPlayer: audioPlayer,
                                    durationBarScale: durationBarScale
                                )
                                .frame(maxWidth: .infinity)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                            }

                            // Правая колонка
                            if let rightTurn = row.rightTurn {
                                CompactTurnCard(
                                    turn: rightTurn,
                                    speaker: .right,
                                    audioPlayer: audioPlayer,
                                    durationBarScale: durationBarScale
                                )
                                .frame(maxWidth: .infinity)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 12)

                        // Индикатор промежутка до следующей строки
                        if index < syncedRows.count - 1 {
                            let nextRow = syncedRows[index + 1]
                            if let gap = calculateGap(from: row, to: nextRow) {
                                SilenceIndicator(duration: gap, scale: durationBarScale)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    // Вычисляет промежуток тишины перед репликой (в рамках одного канала)
    private func getSilenceGapBefore(turn: DialogueTranscription.Turn, in turns: [DialogueTranscription.Turn]) -> TimeInterval? {
        // Находим предыдущую реплику того же спикера
        let sameChannelTurns = turns.filter { $0.speaker == turn.speaker }
        guard let currentIndex = sameChannelTurns.firstIndex(where: { $0.id == turn.id }), currentIndex > 0 else {
            return nil
        }

        let previousTurn = sameChannelTurns[currentIndex - 1]
        let gap = turn.startTime - previousTurn.endTime

        // Показываем индикатор только для значительных промежутков (>2 секунд)
        return gap > 2.0 ? gap : nil
    }
}

/// Индикатор промежутка тишины
struct SilenceIndicator: View {
    let duration: TimeInterval
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            // Пунктирная линия
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 2, height: min(CGFloat(duration) * scale, 20))
                .overlay(
                    Rectangle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .foregroundColor(.gray.opacity(0.5))
                )

            // Время промежутка
            Text("⋯ \(formatDuration(duration))")
                .font(.system(size: 8))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.vertical, 2)
        .padding(.leading, 4)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let mins = Int(seconds) / 60
            let secs = Int(seconds) % 60
            return String(format: "%dm %ds", mins, secs)
        }
    }
}

/// Компактная карточка реплики с индикатором длительности слева
struct CompactTurnCard: View {
    let turn: DialogueTranscription.Turn
    let speaker: DialogueTranscription.Turn.Speaker
    @ObservedObject var audioPlayer: AudioPlayerManager
    let durationBarScale: CGFloat

    @State private var isHovered: Bool = false
    @State private var showCopiedFeedback: Bool = false

    // Проверка активности
    private var isPlaying: Bool {
        audioPlayer.isPlaying &&
        audioPlayer.currentTime >= turn.startTime &&
        audioPlayer.currentTime <= turn.endTime
    }

    // Высота индикатора длительности (ограничена 60px максимум)
    private var durationBarHeight: CGFloat {
        min(max(CGFloat(turn.duration) * durationBarScale, 10), 60)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Цветная полоска длительности слева
            VStack(spacing: 2) {
                Rectangle()
                    .fill(speaker == .left ? Color.speaker1Accent : Color.speaker2Accent)
                    .frame(width: 3, height: durationBarHeight)
                    .cornerRadius(1.5)

                // Время начала
                Text(formatTime(turn.startTime))
                    .font(.system(size: 7, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .frame(height: durationBarHeight + 12)  // Фиксированная высота для VStack

            // Контент реплики
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 4) {
                    // Заголовок: длительность
                    Text(formatDuration(turn.duration))
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)

                    // Текст реплики - полное развертывание без ограничений
                    Text(turn.text)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
                .frame(maxWidth: .infinity)

                // Кнопка копирования (появляется при наведении)
                if isHovered {
                    Button(action: {
                        copyToClipboard()
                    }) {
                        ZStack {
                            // Фон кнопки
                            Circle()
                                .fill(Color(NSColor.controlBackgroundColor).opacity(0.9))
                                .frame(width: 20, height: 20)

                            // Иконка
                            Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(showCopiedFeedback ? .green : .secondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(6)
                    .transition(.opacity)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(speaker == .left ? Color.speaker1Background : Color.speaker2Background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                isPlaying ? (speaker == .left ? Color.speaker1Accent : Color.speaker2Accent) : Color.clear,
                                lineWidth: 2
                            )
                    )
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
        }
        .padding(.vertical, 2)
        .onTapGesture {
            // Клик → переход к времени реплики и воспроизведение
            audioPlayer.seekAndPlay(to: turn.startTime)
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(turn.text, forType: .string)

        // Показываем обратную связь
        withAnimation {
            showCopiedFeedback = true
        }

        // Скрываем галочку через 1.5 секунды
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedFeedback = false
            }
        }

        LogManager.app.info("Скопирован текст реплики: \(turn.text.prefix(50))...")
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        return String(format: "%.1fs", seconds)
    }
}


/// Аудио плеер для воспроизведения файла
struct AudioPlayerView: View {
    @ObservedObject var audioPlayer: AudioPlayerManager
    let fileURL: URL

    var body: some View {
        VStack(spacing: 8) {
            // Прогресс бар
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Фоновая дорожка
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                        .cornerRadius(2)

                    // Прогресс
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * CGFloat(audioPlayer.currentTime / max(audioPlayer.duration, 1)), height: 4)
                        .cornerRadius(2)
                }
                .frame(height: 4)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let newTime = Double(value.location.x / geometry.size.width) * audioPlayer.duration
                            audioPlayer.seek(to: newTime)
                        }
                )
            }
            .frame(height: 4)

            // Контролы плеера
            HStack(spacing: 12) {
                // Кнопка Play/Pause
                Button(action: {
                    audioPlayer.togglePlayback()
                }) {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())

                // Кнопка Моно/Стерео
                Button(action: {
                    audioPlayer.setMonoMode(!audioPlayer.monoMode)
                }) {
                    Image(systemName: audioPlayer.monoMode ? "speaker.wave.1" : "speaker.wave.2")
                        .font(.system(size: 16))
                        .foregroundColor(audioPlayer.monoMode ? .green : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(audioPlayer.monoMode ? "Моно режим (оба канала в обоих ушах)" : "Стерео режим")

                // Контрол скорости воспроизведения
                HStack(spacing: 4) {
                    Image(systemName: "gauge.medium")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button(action: {
                            audioPlayer.setPlaybackRate(Float(rate))
                        }) {
                            Text(formatRate(rate))
                                .font(.system(size: 9, weight: abs(audioPlayer.playbackRate - Float(rate)) < 0.01 ? .bold : .regular))
                                .foregroundColor(abs(audioPlayer.playbackRate - Float(rate)) < 0.01 ? .blue : .secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(abs(audioPlayer.playbackRate - Float(rate)) < 0.01 ? Color.blue.opacity(0.15) : Color.clear)
                                .cornerRadius(3)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // Текущее время
                Text(formatTime(audioPlayer.currentTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                // Общая длительность
                Text(formatTime(audioPlayer.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                // Усиление громкости (100% - 500%)
                HStack(spacing: 6) {
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 12))
                        .foregroundColor(audioPlayer.volumeBoost > 1.0 ? .orange : .secondary)

                    Slider(value: Binding(
                        get: { Double(audioPlayer.volumeBoost) },
                        set: { audioPlayer.setVolumeBoost(Float($0)) }
                    ), in: 1...5)
                    .frame(width: 60)

                    Text("\(Int(audioPlayer.volumeBoost * 100))%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(audioPlayer.volumeBoost > 1.0 ? .orange : .secondary)
                        .frame(width: 35, alignment: .trailing)
                }
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatRate(_ rate: Double) -> String {
        if rate == 1.0 {
            return "1×"
        } else {
            return String(format: "%.2g×", rate)
        }
    }
}

/// Visual Effect Blur для Liquid Glass эффекта
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

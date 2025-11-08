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
/// FIX: Используем NSPanel вместо NSWindow для предотвращения краша при закрытии
public class MainWindow: NSPanel, NSWindowDelegate {
    private var hostingController: NSHostingController<FileTranscriptionView>?
    public var viewModel: FileTranscriptionViewModel
    public var onClose: ((MainWindow) -> Void)?

    public convenience init() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let windowWidth: CGFloat = 700
        let windowHeight: CGFloat = 500

        let windowFrame = NSRect(
            x: screenFrame.midX - windowWidth / 2,
            y: screenFrame.midY - windowHeight / 2,
            width: windowWidth,
            height: windowHeight
        )

        // NSPanel инициализация (вместо NSWindow)
        self.init(
            contentRect: windowFrame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
    }

    public override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        // Инициализируем ViewModel
        self.viewModel = FileTranscriptionViewModel()

        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        // Настройка окна
        self.title = "File Transcription"
        self.isFloatingPanel = false
        self.becomesKeyOnlyIfNeeded = false
        self.delegate = self  // Устанавливаем delegate для обработки событий закрытия

        // Создаём SwiftUI view с ViewModel
        let swiftUIView = FileTranscriptionView(viewModel: viewModel)
        let hosting = NSHostingController(rootView: swiftUIView)
        self.hostingController = hosting

        // Настраиваем content view
        self.contentView = hosting.view

        LogManager.app.info("MainWindow: NSPanel создан с SwiftUI")
    }

    // MARK: - NSWindowDelegate

    /// Вызывается при закрытии окна - останавливаем воспроизведение
    public func windowWillClose(_ notification: Notification) {
        viewModel.globalAudioPlayer.stop()
        LogManager.app.info("MainWindow: Окно закрывается, воспроизведение остановлено")
    }

    /// Начать транскрипцию файлов
    public func startTranscription(files: [URL]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.viewModel.startTranscription(files: files)
            self.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
public class FileTranscriptionViewModel: ObservableObject {
    @Published public var state: TranscriptionState = .idle
    @Published public var currentFile: String = ""
    @Published public var progress: Double = 0.0
    @Published public var modelName: String = ""  // Текущая модель Whisper
    @Published public var vadInfo: String = ""  // Информация о VAD алгоритме

    // ВАЖНО: Используем willSet вместо @Published для массива, чтобы избежать проблем с памятью
    var transcriptions: [FileTranscription] = [] {
        willSet {
            objectWillChange.send()
        }
    }

    // Глобальный аудио плеер для всех транскрипций
    let globalAudioPlayer = AudioPlayerManager()

    private var fileQueue: [URL] = []
    private var currentIndex = 0

    public init() {
        // Простая инициализация без @Published массивов
        self.transcriptions = []
        self.fileQueue = []
        self.state = .idle
        self.currentFile = ""
        self.progress = 0.0
        self.currentIndex = 0
        self.modelName = ""
    }

    public func setModel(_ modelName: String) {
        self.modelName = modelName
    }

    public func startTranscription(files: [URL]) {
        self.fileQueue = files
        self.currentIndex = 0
        self.transcriptions = []
        self.state = .processing
        // Транскрипция будет запущена извне через AppDelegate
    }

    public func updateProgress(file: String, progress: Double) {
        self.currentFile = file
        self.progress = progress
    }

    public func addTranscription(file: String, text: String, fileURL: URL? = nil) {
        let transcription = FileTranscription(fileName: file, text: text, status: .success, dialogue: nil, fileURL: fileURL)
        transcriptions.append(transcription)
    }

    public func addDialogue(file: String, dialogue: DialogueTranscription, fileURL: URL? = nil) {
        let transcription = FileTranscription(
            fileName: file,
            text: dialogue.formatted(),
            status: .success,
            dialogue: dialogue,
            fileURL: fileURL
        )
        transcriptions.append(transcription)
    }

    /// Обновляет существующий диалог или создаёт новый (для постепенного добавления реплик)
    public func updateDialogue(file: String, dialogue: DialogueTranscription, fileURL: URL? = nil) {
        LogManager.app.debug("updateDialogue: \(file), turns: \(dialogue.turns.count), isStereo: \(dialogue.isStereo)")

        // Ищем существующую транскрипцию для этого файла
        if let index = transcriptions.firstIndex(where: { $0.fileName == file }) {
            // Обновляем существующую
            let updated = FileTranscription(
                fileName: file,
                text: dialogue.formatted(),
                status: .success,
                dialogue: dialogue,
                fileURL: fileURL
            )
            transcriptions[index] = updated
            LogManager.app.debug("Обновлена существующая транскрипция #\(index)")
        } else {
            // Создаём новую
            addDialogue(file: file, dialogue: dialogue, fileURL: fileURL)
            LogManager.app.debug("Создана новая транскрипция")
        }
    }

    public func addError(file: String, error: String) {
        let transcription = FileTranscription(fileName: file, text: error, status: .error, dialogue: nil, fileURL: nil)
        transcriptions.append(transcription)
    }

    public func complete() {
        self.state = .completed
        self.currentFile = ""
        self.progress = 1.0
    }

    public enum TranscriptionState {
        case idle
        case processing
        case completed
    }
}

/// Модель транскрипции файла
struct FileTranscription: Identifiable {
    let id = UUID()
    let fileName: String
    let text: String
    let status: Status
    let dialogue: DialogueTranscription?  // Опциональный диалог для стерео
    let fileURL: URL?  // URL оригинального файла для воспроизведения

    enum Status {
        case success
        case error
    }
}

/// SwiftUI view для окна транскрипции
struct FileTranscriptionView: View {
    @ObservedObject var viewModel: FileTranscriptionViewModel

    // Показываем только первую (текущую) транскрипцию
    private var currentTranscription: FileTranscription? {
        viewModel.transcriptions.first
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
                    Text("File Transcription")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Модель и VAD
                HStack(spacing: 12) {
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
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Прогресс бар (если транскрибируется)
            if viewModel.state == .processing {
                ProgressView(value: viewModel.progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
            }

            // Содержимое транскрипции
            if let transcription = currentTranscription {
                VStack(spacing: 0) {
                    // Аудио плеер
                    if let fileURL = transcription.fileURL {
                        AudioPlayerView(audioPlayer: viewModel.globalAudioPlayer, fileURL: fileURL)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(NSColor.controlBackgroundColor))
                    }

                    // Диалог или текст
                    if let dialogue = transcription.dialogue, dialogue.isStereo {
                        TimelineSyncedDialogueView(dialogue: dialogue, audioPlayer: viewModel.globalAudioPlayer)
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
                            try viewModel.globalAudioPlayer.loadAudio(from: fileURL)
                        } catch {
                            LogManager.app.failure("Ошибка загрузки аудио", error: error)
                        }
                    }
                }
            } else {
                // Пустое состояние
                Spacer()
                Text("No transcription yet")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }

}

/// Карточка с результатом транскрипции файла
struct TranscriptionResultCard: View {
    let transcription: FileTranscription
    @ObservedObject var audioPlayer: AudioPlayerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Имя файла
            HStack {
                Image(systemName: transcription.status == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(transcription.status == .success ? .green : .red)
                Text(transcription.fileName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()

                // Кнопка копирования
                if transcription.status == .success {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(transcription.text, forType: .string)
                        LogManager.app.success("Текст скопирован")
                    }) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // Аудио плеер (если есть URL файла)
            if let fileURL = transcription.fileURL {
                AudioPlayerView(audioPlayer: audioPlayer, fileURL: fileURL)
                    .padding(.vertical, 8)
            }

            // Текст транскрипции или диалог
            if let dialogue = transcription.dialogue, dialogue.isStereo {
                // Показываем диалог для стерео в виде двух синхронизированных колонок
                TimelineSyncedDialogueView(dialogue: dialogue, audioPlayer: audioPlayer)
            } else {
                // Обычный текст для моно
                Text(transcription.text)
                    .font(.system(size: 13))
                    .foregroundColor(transcription.status == .success ? .primary : .red)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
        .onAppear {
            // Загружаем аудио файл при появлении
            if let fileURL = transcription.fileURL {
                do {
                    try audioPlayer.loadAudio(from: fileURL)
                } catch {
                    LogManager.app.failure("Ошибка загрузки аудио", error: error)
                }
            }
        }
    }
}

/// Чат-подобное отображение диалога с timeline
struct DialogueChatView: View {
    let dialogue: DialogueTranscription
    @ObservedObject var audioPlayer: AudioPlayerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Заголовок с информацией
            HStack {
                Image(systemName: "headphones")
                    .foregroundColor(.blue)
                Text("Stereo Dialogue")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                // Общая длительность
                Text(formatDuration(dialogue.totalDuration))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Timeline с репликами (отсортированные по времени)
            // УБРАН ScrollView и maxHeight - используем естественный layout
            if dialogue.sortedByTime.isEmpty {
                Text("Нет распознанных реплик")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(dialogue.sortedByTime) { turn in
                        ChatMessageBubble(turn: turn, audioPlayer: audioPlayer)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Пузырь сообщения в стиле мессенджера
struct ChatMessageBubble: View {
    let turn: DialogueTranscription.Turn
    @ObservedObject var audioPlayer: AudioPlayerManager

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Левое выравнивание для Speaker 1
            if turn.speaker == .left {
                messageContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 60)  // Отступ справа
            } else {
                // Правое выравнивание для Speaker 2
                Spacer(minLength: 60)  // Отступ слева
                messageContent
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var messageContent: some View {
        VStack(alignment: turn.speaker == .left ? .leading : .trailing, spacing: 4) {
            // Заголовок с именем диктора и временем
            HStack(spacing: 6) {
                if turn.speaker == .left {
                    speakerLabel
                    timeLabel
                } else {
                    timeLabel
                    speakerLabel
                }
            }

            // Текст сообщения (кликабельный для перехода к времени)
            Text(turn.text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleColor)
                .cornerRadius(16)
                .multilineTextAlignment(turn.speaker == .left ? .leading : .trailing)
                .onTapGesture {
                    // Переход к времени реплики и начало воспроизведения
                    audioPlayer.seekAndPlay(to: turn.startTime)
                    LogManager.app.info("Переход к реплике: \(turn.startTime)s")
                }
                .help("Click to play from this time")
        }
    }

    private var speakerLabel: some View {
        Text(turn.speaker.displayName)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(turn.speaker == .left ? Color.speaker1Accent : Color.speaker2Accent)
    }

    private var timeLabel: some View {
        Text(formatTimestamp(turn.startTime))
            .font(.system(size: 9, weight: .regular))
            .foregroundColor(.secondary)
    }

    private var bubbleColor: Color {
        if turn.speaker == .left {
            return Color.speaker1Background
        } else {
            return Color.speaker2Background
        }
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
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
        }
        .padding(.vertical, 2)
        .onTapGesture {
            // Клик → переход к времени реплики и воспроизведение
            audioPlayer.seekAndPlay(to: turn.startTime)
        }
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

/// Карточка реплики для timeline view
struct TimelineTurnCard: View {
    let turn: DialogueTranscription.Turn
    let speaker: DialogueTranscription.Turn.Speaker
    @ObservedObject var audioPlayer: AudioPlayerManager

    private var isPlaying: Bool {
        audioPlayer.isPlaying &&
        audioPlayer.currentTime >= turn.startTime &&
        audioPlayer.currentTime <= turn.endTime
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Время (с DEBUG информацией)
            HStack {
                Text("\(formatTime(turn.startTime)) - \(formatTime(turn.endTime))")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Text(formatDuration(turn.duration))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            // Текст
            Text(turn.text)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(speaker == .left ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    isPlaying ? (speaker == .left ? Color.blue : Color.orange) : Color.clear,
                                    lineWidth: 2
                                )
                        )
                )
                .onTapGesture {
                    audioPlayer.seekAndPlay(to: turn.startTime)
                }
        }
        .padding(.vertical, 4)
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

/// Компактное отображение диалога - реплики последовательно без привязки к абсолютному времени

/// Временная шкала (ось времени) - с визуальным сжатием тишины
struct TimelineAxis: View {
    let totalDuration: TimeInterval  // визуальная длительность (сжатая)
    let pixelsPerSecond: CGFloat
    let timelineMapper: CompressedTimelineMapper
    let realDuration: TimeInterval  // реальная длительность

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Вертикальная линия
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 2)
                    .offset(x: 48)

                // Индикаторы сжатых участков (более заметные)
                ForEach(Array(timelineMapper.silenceGaps.enumerated()), id: \.offset) { index, gap in
                    let visualStart = timelineMapper.visualPosition(for: gap.realStartTime)
                    let visualEnd = timelineMapper.visualPosition(for: gap.realEndTime)
                    let visualMid = (visualStart + visualEnd) / 2
                    let savedSeconds = gap.duration - timelineMapper.compressedGapDisplay

                    // Фон для индикатора (полупрозрачный прямоугольник)
                    Rectangle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 50, height: CGFloat(visualEnd - visualStart) * pixelsPerSecond)
                        .offset(y: CGFloat(visualStart) * pixelsPerSecond)

                    // Пунктирная линия для сжатого участка (более толстая)
                    Path { path in
                        let startY = CGFloat(visualStart) * pixelsPerSecond
                        let endY = CGFloat(visualEnd) * pixelsPerSecond
                        path.move(to: CGPoint(x: 48, y: startY))
                        path.addLine(to: CGPoint(x: 48, y: endY))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 3, dash: [4, 4]))
                    .foregroundColor(.orange.opacity(0.8))

                    // Индикатор сжатия с информацией
                    ZStack {
                        // Фон для текста
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.9))
                            .frame(width: 46, height: 28)

                        VStack(spacing: 0) {
                            // Иконка сжатия
                            Text("⇅")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                            // Сохраненное время
                            Text("-\(Int(savedSeconds))s")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .offset(x: 25, y: CGFloat(visualMid) * pixelsPerSecond - 14)
                }

                // Временные метки (используем реальное время для меток)
                ForEach(timeMarks, id: \.self) { realTime in
                    let visualTime = timelineMapper.visualPosition(for: realTime)

                    HStack(spacing: 4) {
                        Text(formatTime(realTime))  // Показываем реальное время
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)

                        // Короткая горизонтальная черта
                        Rectangle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 6, height: 1)
                    }
                    .offset(y: CGFloat(visualTime) * pixelsPerSecond - 6)
                }
            }
            .frame(height: CGFloat(totalDuration) * pixelsPerSecond)
        }
        .frame(height: CGFloat(totalDuration) * pixelsPerSecond)
    }

    private var timeMarks: [TimeInterval] {
        // Адаптивный интервал: для коротких файлов 5 секунд, для длинных 10
        let interval: TimeInterval = realDuration < 60 ? 5 : 10
        var marks: [TimeInterval] = [0]
        var current = interval
        while current <= realDuration {
            marks.append(current)
            current += interval
        }
        return marks
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

/// Колонка для одного спикера
struct SpeakerColumn: View {
    let turns: [DialogueTranscription.Turn]
    let speaker: DialogueTranscription.Turn.Speaker
    let totalDuration: TimeInterval  // визуальная длительность (сжатая)
    let pixelsPerSecond: CGFloat
    @ObservedObject var audioPlayer: AudioPlayerManager
    let timelineMapper: CompressedTimelineMapper

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Фон колонки
                RoundedRectangle(cornerRadius: 8)
                    .fill(speaker == .left ? Color.blue.opacity(0.05) : Color.orange.opacity(0.05))

                // Заголовок колонки
                VStack {
                    Text(speaker.displayName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(speaker == .left ? .blue : .orange)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.8))

                    Spacer()
                }

                // Реплики, расположенные по ВИЗУАЛЬНОМУ времени (с учетом сжатия)
                ForEach(turns) { turn in
                    let visualStartTime = timelineMapper.visualPosition(for: turn.startTime)

                    TurnBlock(turn: turn, speaker: speaker, audioPlayer: audioPlayer)
                        .offset(y: CGFloat(visualStartTime) * pixelsPerSecond + 30) // +30 для заголовка
                        .padding(.horizontal, 8)
                }
            }
            .frame(height: CGFloat(totalDuration) * pixelsPerSecond + 30)
        }
        .frame(height: CGFloat(totalDuration) * pixelsPerSecond + 30)
    }
}

/// Блок с репликой на timeline
struct TurnBlock: View {
    let turn: DialogueTranscription.Turn
    let speaker: DialogueTranscription.Turn.Speaker
    @ObservedObject var audioPlayer: AudioPlayerManager

    @State private var isHovered = false

    var body: some View {
        // Текст реплики
        Text(turn.text)
            .font(.system(size: 11))
            .foregroundColor(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(blockColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(borderColor, lineWidth: isHovered ? 2 : 1)
                    )
            )
            .onTapGesture {
                // Переход к времени реплики
                audioPlayer.seekAndPlay(to: turn.startTime)
                LogManager.app.info("Переход к реплике: \(turn.startTime)s")
            }
            .onHover { hovering in
                isHovered = hovering
            }
            .help("Duration: \(String(format: "%.1f", turn.duration))s\nClick to play from this time")
    }

    private var blockColor: Color {
        if isHovered {
            return speaker == .left ? Color.blue.opacity(0.25) : Color.orange.opacity(0.25)
        } else {
            return speaker == .left ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15)
        }
    }

    private var borderColor: Color {
        if isHovered {
            return speaker == .left ? Color.blue.opacity(0.8) : Color.orange.opacity(0.8)
        } else {
            return speaker == .left ? Color.blue.opacity(0.3) : Color.orange.opacity(0.3)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
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

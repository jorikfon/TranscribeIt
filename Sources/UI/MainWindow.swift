import SwiftUI
import AppKit

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
    private let audioCache: AudioCache

    public convenience init(audioCache: AudioCache) {
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
            defer: false,
            audioCache: audioCache
        )
    }

    public init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool, audioCache: AudioCache) {
        // Инициализируем ViewModel с общим AudioCache
        self.audioCache = audioCache
        self.viewModel = FileTranscriptionViewModel(audioCache: audioCache)

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

// FileTranscriptionView moved to Sources/UI/Views/Transcription/FileTranscriptionView.swift
// Timeline components moved to Sources/UI/Views/Timeline/
// - TimelineSyncedDialogueView.swift
// - TimelineDialogueView.swift
// - SilenceIndicator.swift
// - CompactTurnCard.swift

// Audio components moved to Sources/UI/Views/Audio/
// - AudioPlayerView.swift

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

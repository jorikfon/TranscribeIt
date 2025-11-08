import Cocoa
import SwiftUI
import TranscribeItCore

/// Главный делегат приложения TranscribeIt
/// Управляет жизненным циклом и координирует сервисы транскрибации
class AppDelegate: NSObject, NSApplicationDelegate {
    // Сервисы
    private var menuBarController: MenuBarController?
    private var whisperService: WhisperService?
    private var fileTranscriptionService: FileTranscriptionService?

    // Храним массив окон транскрипции (strong references)
    private var transcriptionWindows: [MainWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        LogManager.app.info("=== TranscribeIt Starting ===")

        // Устанавливаем .regular чтобы приложение было видно в Dock
        NSApp.setActivationPolicy(.regular)
        LogManager.app.info("Activation policy: .regular (показано в Dock)")

        // Инициализация сервисов
        initializeServices()

        // Настройка menu bar
        setupMenuBar()

        // Асинхронная инициализация
        Task {
            await asyncInitialization()
        }
    }

    // MARK: - Initialization

    /// Инициализация всех сервисов
    private func initializeServices() {
        menuBarController = MenuBarController()

        // Используем сохраненную настройку модели из ModelManager
        let modelSize = ModelManager.shared.currentModel
        whisperService = WhisperService(modelSize: modelSize)
        LogManager.app.info("Инициализация WhisperService с моделью из настроек: \(modelSize)")

        // Инициализируем сервис транскрипции файлов
        if let whisperService = whisperService {
            fileTranscriptionService = FileTranscriptionService(whisperService: whisperService)
        }

        LogManager.app.success("Все сервисы инициализированы")
    }

    /// Настройка menu bar
    private func setupMenuBar() {
        guard let menuBarController = menuBarController else { return }

        // Обработчик открытия окна транскрибации
        menuBarController.onOpenTranscription = { [weak self] in
            self?.openTranscriptionWindow()
        }

        // Обработчик открытия настроек
        menuBarController.onOpenSettings = { [weak self] in
            self?.openSettings()
        }

        // Обработчик выхода
        menuBarController.onQuit = {
            NSApplication.shared.terminate(nil)
        }

        LogManager.app.info("MenuBar настроен")
    }

    /// Асинхронная инициализация (загрузка модели Whisper)
    private func asyncInitialization() async {
        guard let whisperService = whisperService else { return }

        do {
            // Загружаем модель Whisper
            try await whisperService.loadModel()

            // Проверяем разрешения
            await PermissionManager.shared.checkMicrophonePermission()

            LogManager.app.success("Асинхронная инициализация завершена")
        } catch {
            LogManager.app.error("Ошибка загрузки модели: \(error.localizedDescription)")
        }
    }

    // MARK: - Window Management

    /// Открывает окно транскрибации файлов
    func openTranscriptionWindow() {
        LogManager.app.info("Открываем окно транскрибации")

        guard let fileService = fileTranscriptionService else {
            LogManager.app.error("FileTranscriptionService не инициализирован")
            return
        }

        // Создаем новое окно
        let window = MainWindow()

        // TODO: Передать fileService в viewModel для запуска транскрибации

        // Обработчик закрытия
        window.onClose = { [weak self] closedWindow in
            self?.transcriptionWindows.removeAll { $0 === closedWindow }
            LogManager.app.info("Окно транскрибации закрыто, осталось окон: \(self?.transcriptionWindows.count ?? 0)")
        }

        // Добавляем в массив
        transcriptionWindows.append(window)

        // Показываем окно
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        LogManager.app.info("Окно транскрибации создано, всего окон: \(transcriptionWindows.count)")
    }

    /// Открывает окно с файлами для транскрибации
    func openTranscriptionWindow(with files: [URL]) {
        openTranscriptionWindow()

        if let window = transcriptionWindows.last {
            window.startTranscription(files: files)
        }
    }

    /// Открывает настройки приложения
    private func openSettings() {
        LogManager.app.info("Открываем окно настроек")
        // TODO: Создать SettingsView для TranscribeIt
    }

    // MARK: - File Handling

    /// Обработка открытия файлов через Finder
    func application(_ application: NSApplication, open urls: [URL]) {
        LogManager.app.info("Открыты файлы через Finder: \(urls.count)")

        // Фильтруем только аудио файлы
        let audioFiles = urls.filter { url in
            let ext = url.pathExtension.lowercased()
            return ["wav", "mp3", "m4a", "aiff", "flac", "aac"].contains(ext)
        }

        if audioFiles.isEmpty {
            LogManager.app.warning("Нет поддерживаемых аудио файлов")
            return
        }

        // Открываем окно транскрибации с файлами
        openTranscriptionWindow(with: audioFiles)
    }

    // MARK: - Termination

    func applicationWillTerminate(_ notification: Notification) {
        LogManager.app.info("=== TranscribeIt Shutting Down ===")

        // Закрываем все окна
        transcriptionWindows.removeAll()

        LogManager.app.info("Приложение завершено")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Не завершаем приложение при закрытии последнего окна
        // Menu bar остается активным
        return false
    }
}

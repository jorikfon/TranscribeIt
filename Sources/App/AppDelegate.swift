import Cocoa
import SwiftUI
import TranscribeItCore

/// Главный делегат приложения TranscribeIt
/// Управляет жизненным циклом и координирует сервисы транскрибации
class AppDelegate: NSObject, NSApplicationDelegate {
    // Сервисы
    private var whisperService: WhisperService?
    private var fileTranscriptionService: FileTranscriptionService?
    private var batchTranscriptionService: BatchTranscriptionService?

    // Главное окно транскрибации
    private var mainWindow: MainWindow?

    // Окно настроек
    private var settingsWindowController: SettingsWindowController?

    // Состояние загрузки модели
    private var isModelLoaded: Bool = false
    private var isModelLoading: Bool = false
    private var modelLoadError: Error?

    // CLI режим
    private var launchMode: CommandLineHandler.LaunchMode = .gui

    func applicationDidFinishLaunching(_ notification: Notification) {
        LogManager.app.info("=== TranscribeIt Starting ===")

        // Парсим аргументы командной строки
        let args = CommandLine.arguments
        let parseResult = CommandLineHandler.parseArguments(args)
        launchMode = parseResult.mode

        // Применяем настройки из командной строки
        if let modelSize = parseResult.modelSize {
            ModelManager.shared.saveCurrentModel(modelSize)
            LogManager.app.info("CLI: Использование модели \(modelSize)")
        }

        if let vadEnabled = parseResult.vadEnabled {
            UserSettings.shared.fileTranscriptionMode = vadEnabled ? .vad : .batch
            LogManager.app.info("CLI: VAD режим: \(vadEnabled)")
        }

        // Проверяем режим запуска
        switch launchMode {
        case .gui:
            // GUI режим - обычное приложение
            NSApp.setActivationPolicy(.regular)
            LogManager.app.info("Activation policy: .regular (desktop app)")

            setupMenuBar()
            initializeServices()
            openMainWindow()

            // Начинаем фоновую загрузку модели
            Task {
                await asyncInitialization()
            }

        case .cliBatch(let files, let outputFormat):
            // CLI режим - пакетная обработка
            NSApp.setActivationPolicy(.prohibited)  // Не показывать в Dock
            LogManager.app.info("CLI режим: обработка \(files.count) файлов, вывод: \(outputFormat)")

            initializeServices()

            // Запускаем пакетную обработку
            Task {
                await runCLIBatch(files: files, outputFormat: outputFormat)
            }
        }
    }

    // MARK: - Menu Bar

    /// Создаёт меню приложения
    private func setupMenuBar() {
        let mainMenu = NSMenu()

        // Меню приложения
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        // TranscribeIt → Settings... (⌘,)
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        appMenu.addItem(settingsItem)

        appMenu.addItem(NSMenuItem.separator())

        // TranscribeIt → Quit (⌘Q)
        let quitItem = NSMenuItem(
            title: "Quit TranscribeIt",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    // MARK: - Initialization

    /// Инициализация всех сервисов
    private func initializeServices() {
        // Используем сохраненную настройку модели из ModelManager
        let modelSize = ModelManager.shared.currentModel
        whisperService = WhisperService(modelSize: modelSize)
        LogManager.app.info("Инициализация WhisperService с моделью из настроек: \(modelSize)")

        // Инициализируем сервис транскрипции файлов
        if let whisperService = whisperService {
            fileTranscriptionService = FileTranscriptionService(whisperService: whisperService)
            batchTranscriptionService = BatchTranscriptionService(whisperService: whisperService)
        }

        LogManager.app.success("Все сервисы инициализированы")
    }

    /// Асинхронная фоновая загрузка модели Whisper
    private func asyncInitialization() async {
        guard let whisperService = whisperService else {
            await MainActor.run {
                self.modelLoadError = NSError(domain: "TranscribeIt", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to initialize WhisperService"
                ])
            }
            return
        }

        await MainActor.run {
            self.isModelLoading = true
            // Обновляем статус в главном окне
            self.mainWindow?.viewModel.modelLoadingStatus = "Loading model..."
        }

        do {
            LogManager.app.begin("Фоновая загрузка Whisper модели")

            try await whisperService.loadModel()

            LogManager.app.success("Whisper модель загружена в фоне")

            await MainActor.run {
                self.isModelLoaded = true
                self.isModelLoading = false
                self.mainWindow?.viewModel.modelLoadingStatus = "Model ready"
            }
        } catch {
            LogManager.app.error("Ошибка загрузки модели: \(error)")

            await MainActor.run {
                self.isModelLoaded = false
                self.isModelLoading = false
                self.modelLoadError = error
                self.mainWindow?.viewModel.modelLoadingStatus = "Model load failed"
            }
        }
    }

    // MARK: - Window Management

    /// Открывает главное окно транскрибации (вызывается при старте)
    private func openMainWindow() {
        LogManager.app.info("Открываем главное окно транскрибации")

        guard fileTranscriptionService != nil else {
            LogManager.app.error("FileTranscriptionService не инициализирован")
            return
        }

        // Создаем главное окно
        let window = MainWindow()

        // Обработчик запуска транскрибации
        window.onStartTranscription = { [weak self, weak window] files in
            guard let self = self, let window = window else { return }
            self.performTranscription(files: files, window: window)
        }

        // Обработчик закрытия - завершаем приложение
        window.onClose = { [weak self] _ in
            LogManager.app.info("Главное окно закрыто - завершаем приложение")
            self?.mainWindow = nil
            NSApp.terminate(nil)
        }

        // Сохраняем ссылку на главное окно
        mainWindow = window

        // Показываем окно
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        LogManager.app.info("Главное окно транскрибации создано")
    }

    /// Открывает настройки приложения (вызывается из меню)
    func openSettings() {
        LogManager.app.info("Открываем окно настроек")

        if let settingsWindow = settingsWindowController?.window, settingsWindow.isVisible {
            // Окно уже открыто, просто активируем его
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Создаем новое окно настроек
            settingsWindowController = SettingsWindowController()
            settingsWindowController?.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Transcription

    /// Выполняет транскрибацию файла (только один файл)
    private func performTranscription(files: [URL], window: MainWindow) {
        guard let fileService = fileTranscriptionService else {
            LogManager.app.error("FileTranscriptionService не инициализирован")
            return
        }

        // Берём только первый файл
        guard let file = files.first else {
            LogManager.app.error("Нет файлов для транскрибации")
            return
        }

        LogManager.app.info("Начинаем транскрибацию файла: \(file.lastPathComponent)")

        Task {
            // Ждём загрузки модели, если она ещё не загружена
            if !isModelLoaded {
                await MainActor.run {
                    window.viewModel.modelLoadingStatus = isModelLoading ? "Waiting for model to load..." : "Loading model..."
                }

                LogManager.app.info("Модель ещё не загружена, ожидаем...")

                // Ждём завершения загрузки (проверяем каждые 100ms)
                while isModelLoading {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                }

                // Проверяем, успешно ли загрузилась модель
                if let error = modelLoadError {
                    await MainActor.run {
                        window.viewModel.setError(
                            file: file.lastPathComponent,
                            error: "Model load failed: \(error.localizedDescription)"
                        )
                    }
                    return
                }

                LogManager.app.success("Модель загружена, начинаем транскрибацию")
            }

            // Обновляем модель и VAD информацию
            await MainActor.run {
                window.viewModel.setModel(ModelManager.shared.currentModel)
                window.viewModel.vadInfo = UserSettings.shared.vadAlgorithmType.displayName
                window.viewModel.modelLoadingStatus = nil
                window.viewModel.startTranscription(file: file)
            }

            do {
                // Обновляем прогресс
                await MainActor.run {
                    window.viewModel.updateProgress(file: file.lastPathComponent, progress: 0.0)
                }

                // Создаём BatchTranscriptionService для получения промежуточного прогресса
                if let whisperService = whisperService {
                    let batchService = BatchTranscriptionService(whisperService: whisperService)

                    // Подписываемся на обновления прогресса
                    batchService.onProgressUpdate = { [weak window] fileName, progress, partialDialogue in
                        Task { @MainActor in
                            window?.viewModel.updateProgress(file: fileName, progress: progress)
                            LogManager.app.debug("Progress: \(Int(progress * 100))%")
                        }
                    }

                    // Используем batch service для транскрибации с прогрессом
                    let dialogue = try await batchService.transcribe(url: file)

                    // Передаём DialogueTranscription напрямую в ViewModel
                    await MainActor.run {
                        window.viewModel.setDialogue(
                            file: file.lastPathComponent,
                            dialogue: dialogue,
                            fileURL: file
                        )
                    }
                } else {
                    // Если whisperService недоступен, используем старый метод
                    let dialogue = try await fileService.transcribeFileWithDialogue(at: file)

                    await MainActor.run {
                        window.viewModel.setDialogue(
                            file: file.lastPathComponent,
                            dialogue: dialogue,
                            fileURL: file
                        )
                    }
                }

                // Обновляем прогресс до 100%
                await MainActor.run {
                    window.viewModel.updateProgress(file: file.lastPathComponent, progress: 1.0)
                }

                LogManager.app.success("Транскрибация файла \(file.lastPathComponent) завершена")
            } catch {
                LogManager.app.error("Ошибка транскрибации файла \(file.lastPathComponent): \(error)")

                await MainActor.run {
                    window.viewModel.setError(
                        file: file.lastPathComponent,
                        error: error.localizedDescription
                    )
                }
            }

            // Завершаем транскрибацию
            await MainActor.run {
                window.viewModel.complete()
                LogManager.app.info("Транскрибация файла завершена")
            }
        }
    }

    // MARK: - CLI Batch Processing

    /// Выполняет пакетную обработку в CLI режиме
    private func runCLIBatch(files: [URL], outputFormat: CommandLineHandler.OutputFormat) async {
        guard let whisperService = whisperService,
              let batchService = batchTranscriptionService else {
            LogManager.app.error("CLI: Сервисы не инициализированы")
            print("{\"error\": \"Services not initialized\"}")
            exit(1)
        }

        // Загружаем модель
        LogManager.app.info("CLI: Загрузка модели...")
        do {
            try await whisperService.loadModel()
            LogManager.app.success("CLI: Модель загружена")
        } catch {
            LogManager.app.error("CLI: Ошибка загрузки модели: \(error)")
            print("{\"error\": \"Failed to load model: \(error.localizedDescription)\"}")
            exit(1)
        }

        // Выполняем транскрибацию
        let vadEnabled = UserSettings.shared.fileTranscriptionMode == .vad
        let results = await batchService.transcribeMultipleFiles(files: files, vadEnabled: vadEnabled)

        // Выводим результаты
        switch outputFormat {
        case .json:
            // JSON в консоль
            CommandLineHandler.printJSON(results: results)
            exit(0)

        case .gui:
            // Открываем GUI с результатами
            await MainActor.run {
                NSApp.setActivationPolicy(.regular)
                setupMenuBar()
                openMainWindowWithResults(results)
            }
        }
    }

    /// Открывает главное окно с готовыми результатами пакетной обработки
    private func openMainWindowWithResults(_ results: [TranscriptionResult]) {
        // TODO: Реализовать отображение результатов в GUI
        // Пока просто выводим JSON и закрываем
        LogManager.app.info("GUI вывод результатов пока не реализован, вывожу JSON")
        CommandLineHandler.printJSON(results: results)
        exit(0)
    }

    // MARK: - Application Lifecycle

    /// Не завершать приложение при закрытии последнего окна
    /// (окно настроек может быть открыто отдельно)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Завершаем только если закрыто главное окно
        return mainWindow == nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        LogManager.app.info("=== TranscribeIt Terminating ===")
    }
}

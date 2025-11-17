import Cocoa
import SwiftUI
import TranscribeItCore

/// Главный делегат приложения TranscribeIt
/// Управляет жизненным циклом и координирует сервисы транскрибации
class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Dependency Injection

    /// Контейнер зависимостей для управления сервисами
    private let dependencies: DependencyContainer

    // MARK: - Services

    /// Сервис Whisper для транскрибации
    private var whisperService: WhisperService?

    /// Сервис транскрибации файлов
    private var fileTranscriptionService: FileTranscriptionService?

    /// Сервис пакетной транскрибации
    private var batchTranscriptionService: BatchTranscriptionService?

    // MARK: - Windows

    /// Главное окно транскрибации
    private var mainWindow: MainWindow?

    /// Окно настроек
    private var settingsWindowController: SettingsWindowController?

    // MARK: - State

    /// Состояние загрузки модели
    private var isModelLoaded: Bool = false
    private var isModelLoading: Bool = false
    private var modelLoadError: Error?

    /// Режим запуска приложения (GUI или CLI)
    private var launchMode: CommandLineHandler.LaunchMode = .gui

    /// Текущая активная задача транскрибации (для отмены при перезапуске)
    private var currentTranscriptionTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Инициализирует AppDelegate с контейнером зависимостей
    ///
    /// - Parameter dependencies: Контейнер зависимостей
    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
        super.init()
        LogManager.app.info("AppDelegate инициализирован с DependencyContainer")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LogManager.app.info("=== TranscribeIt Starting ===")

        // Парсим аргументы командной строки
        let args = CommandLine.arguments
        let parseResult = CommandLineHandler.parseArguments(args)
        launchMode = parseResult.mode

        // Применяем настройки из командной строки
        if let modelSize = parseResult.modelSize {
            dependencies.modelManager.saveCurrentModel(modelSize)
            LogManager.app.info("CLI: Использование модели \(modelSize)")
        }

        if let vadEnabled = parseResult.vadEnabled {
            dependencies.userSettings.fileTranscriptionMode = vadEnabled ? .vad : .batch
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

    // MARK: - Service Initialization

    /// Инициализация всех сервисов через DependencyContainer
    ///
    /// Создаёт экземпляры WhisperService, FileTranscriptionService и BatchTranscriptionService
    /// используя настройки из контейнера зависимостей.
    private func initializeServices() {
        LogManager.app.begin("Инициализация сервисов через DependencyContainer")

        // Создаём WhisperService через фабричный метод
        whisperService = dependencies.makeWhisperService()

        // Инициализируем сервисы транскрипции
        if let whisperService = whisperService {
            fileTranscriptionService = dependencies.makeFileTranscriptionService(whisperService: whisperService)
            batchTranscriptionService = dependencies.makeBatchTranscriptionService(whisperService: whisperService)
        }

        LogManager.app.success("Все сервисы инициализированы через DI")
    }

    /// Асинхронная фоновая загрузка модели Whisper
    private func asyncInitialization() async {
        guard let whisperService = whisperService else {
            await MainActor.run {
                self.modelLoadError = TranscriptionError.serviceNotInitialized("WhisperService")
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

                // Обновляем статус GPU
                let gpuStatus = whisperService.isNeuralEngineAvailable ? "ANE+GPU" :
                                whisperService.isMetalAvailable ? "GPU" : "CPU"
                self.mainWindow?.viewModel.gpuStatus = gpuStatus
                self.mainWindow?.viewModel.modelName = whisperService.currentModelSize
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

        // Создаем главное окно с общим AudioCache из DI container
        let window = MainWindow(audioCache: dependencies.audioCache)

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
    ///
    /// Координирует процесс транскрибации: ожидает загрузки модели,
    /// выполняет транскрибацию и обрабатывает ошибки.
    ///
    /// - Parameters:
    ///   - files: Массив URL файлов (используется только первый файл)
    ///   - window: Главное окно для обновления UI
    private func performTranscription(files: [URL], window: MainWindow) {
        guard fileTranscriptionService != nil else {
            LogManager.app.error("FileTranscriptionService не инициализирован")
            return
        }

        guard let file = files.first else {
            LogManager.app.error("Нет файлов для транскрибации")
            return
        }

        LogManager.app.info("Начинаем транскрибацию файла: \(file.lastPathComponent)")

        // ВАЖНО: Отменяем предыдущую транскрибацию если она ещё выполняется
        if let previousTask = currentTranscriptionTask {
            LogManager.app.warning("Отменяем предыдущую транскрибацию перед запуском новой")
            previousTask.cancel()
            currentTranscriptionTask = nil
        }

        currentTranscriptionTask = Task {
            // Показываем статус отмены и сбрасываем прогресс
            await MainActor.run {
                window.viewModel.modelLoadingStatus = "Cancelling previous transcription..."
                window.viewModel.reset()  // Сбрасываем прогресс-бар
            }

            // Даём 100ms на завершение отмены предыдущей задачи
            do {
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                // Игнорируем ошибку отмены sleep
            }
            // 1. Ожидание загрузки модели
            do {
                try await waitForModelLoading(window: window, file: file)
            } catch is CancellationError {
                LogManager.app.info("Транскрибация отменена пользователем (этап загрузки модели)")
                await MainActor.run {
                    window.viewModel.reset()
                }
                return
            } catch {
                return  // Ошибка уже обработана в waitForModelLoading
            }

            // 2. Выполнение транскрибации
            do {
                try await executeTranscription(file: file, window: window)
                LogManager.app.success("Транскрибация файла \(file.lastPathComponent) завершена")
            } catch is CancellationError {
                LogManager.app.info("Транскрибация отменена пользователем (этап транскрибации)")
                await MainActor.run {
                    window.viewModel.reset()
                }
                return
            } catch {
                // 3. Обработка ошибок
                await handleTranscriptionError(error, file: file, window: window)
            }

            // Завершаем транскрибацию
            await MainActor.run {
                window.viewModel.complete()
                LogManager.app.info("Транскрибация файла завершена")
            }

            // Сбрасываем ссылку на завершенную задачу
            currentTranscriptionTask = nil
        }
    }

    /// Ожидает загрузки модели Whisper перед началом транскрибации
    ///
    /// Если модель ещё не загружена, метод ожидает завершения загрузки.
    /// При ошибке загрузки обновляет UI с сообщением об ошибке.
    ///
    /// - Parameters:
    ///   - window: Главное окно для обновления статуса
    ///   - file: Файл для транскрибации (для отображения ошибки)
    /// - Throws: Пробрасывает ошибку если модель не загрузилась
    private func waitForModelLoading(window: MainWindow, file: URL) async throws {
        guard !isModelLoaded else {
            // Модель уже загружена
            return
        }

        await MainActor.run {
            window.viewModel.modelLoadingStatus = isModelLoading ? "Waiting for model to load..." : "Loading model..."
        }

        LogManager.app.info("Модель ещё не загружена, ожидаем...")

        // Ждём завершения загрузки (проверяем каждые 100ms)
        while isModelLoading {
            // Проверяем отмену во время ожидания модели
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        // Проверяем, успешно ли загрузилась модель
        if let error = modelLoadError {
            await MainActor.run {
                window.viewModel.setError(
                    file: file.lastPathComponent,
                    error: "Model load failed: \(error.localizedDescription)"
                )
            }
            throw error
        }

        LogManager.app.success("Модель загружена, начинаем транскрибацию")
    }

    /// Выполняет транскрибацию аудио файла
    ///
    /// Создаёт BatchTranscriptionService, подписывается на обновления прогресса
    /// и выполняет транскрибацию с отображением прогресса в UI.
    ///
    /// - Parameters:
    ///   - file: URL файла для транскрибации
    ///   - window: Главное окно для обновления прогресса и результата
    /// - Throws: Пробрасывает ошибки транскрибации (TranscriptionError, WhisperError)
    private func executeTranscription(file: URL, window: MainWindow) async throws {
        guard let fileService = fileTranscriptionService else {
            throw TranscriptionError.serviceNotInitialized("FileTranscriptionService")
        }

        guard let whisperService = whisperService else {
            throw TranscriptionError.serviceNotInitialized("WhisperService")
        }

        // Проверяем, изменилась ли модель
        let currentModelInSettings = dependencies.modelManager.currentModel
        if whisperService.currentModelSize != currentModelInSettings {
            LogManager.app.info("Модель изменилась: \(whisperService.currentModelSize) → \(currentModelInSettings), перезагружаем...")

            await MainActor.run {
                window.viewModel.modelLoadingStatus = "Reloading model..."
            }

            try await whisperService.reloadModel(newModelSize: currentModelInSettings)

            await MainActor.run {
                window.viewModel.modelLoadingStatus = "Model ready"
                window.viewModel.modelName = whisperService.currentModelSize
            }
        }

        // Обновляем модель и VAD информацию через DI
        await MainActor.run {
            window.viewModel.setModel(dependencies.modelManager.currentModel)
            window.viewModel.vadInfo = dependencies.userSettings.vadAlgorithmType.displayName
            window.viewModel.modelLoadingStatus = nil
            window.viewModel.startTranscription(file: file)
        }

        // Обновляем прогресс
        await MainActor.run {
            window.viewModel.updateProgress(file: file.lastPathComponent, progress: 0.0)
        }

        // Создаём BatchTranscriptionService для получения промежуточного прогресса
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

        // Обновляем прогресс до 100%
        await MainActor.run {
            window.viewModel.updateProgress(file: file.lastPathComponent, progress: 1.0)
        }
    }

    /// Обрабатывает ошибки транскрибации с учётом их типов
    ///
    /// Распознаёт типизированные ошибки (TranscriptionError, WhisperError)
    /// и добавляет recovery suggestions для пользователя.
    ///
    /// - Parameters:
    ///   - error: Ошибка транскрибации
    ///   - file: URL файла, для которого произошла ошибка
    ///   - window: Главное окно для отображения ошибки
    private func handleTranscriptionError(_ error: Error, file: URL, window: MainWindow) async {
        if let transcriptionError = error as? TranscriptionError {
            // Обработка typed TranscriptionError с детальной информацией
            LogManager.app.error("Ошибка транскрибации файла \(file.lastPathComponent): \(transcriptionError)")

            await MainActor.run {
                var errorMessage = transcriptionError.localizedDescription

                // Добавляем recovery suggestion если есть
                if let suggestion = transcriptionError.recoverySuggestion {
                    errorMessage += "\n\n💡 \(suggestion)"
                }

                window.viewModel.setError(
                    file: file.lastPathComponent,
                    error: errorMessage
                )
            }
        } else if let whisperError = error as? WhisperError {
            // Обработка WhisperError
            LogManager.app.error("Ошибка Whisper для файла \(file.lastPathComponent): \(whisperError)")

            await MainActor.run {
                var errorMessage = whisperError.localizedDescription

                if let suggestion = whisperError.recoverySuggestion {
                    errorMessage += "\n\n💡 \(suggestion)"
                }

                window.viewModel.setError(
                    file: file.lastPathComponent,
                    error: errorMessage
                )
            }
        } else {
            // Fallback для других ошибок
            LogManager.app.error("Неизвестная ошибка транскрибации файла \(file.lastPathComponent): \(error)")

            await MainActor.run {
                window.viewModel.setError(
                    file: file.lastPathComponent,
                    error: error.localizedDescription
                )
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
        } catch let whisperError as WhisperError {
            LogManager.app.error("CLI: Ошибка загрузки модели: \(whisperError)")

            var errorMessage = whisperError.localizedDescription
            if let suggestion = whisperError.recoverySuggestion {
                errorMessage += " Suggestion: \(suggestion)"
            }

            print("{\"error\": \"Failed to load model\", \"details\": \"\(errorMessage)\"}")
            exit(1)
        } catch {
            LogManager.app.error("CLI: Неизвестная ошибка загрузки модели: \(error)")
            print("{\"error\": \"Failed to load model\", \"details\": \"\(error.localizedDescription)\"}")
            exit(1)
        }

        // Выполняем транскрибацию используя настройки из DI
        let vadEnabled = dependencies.userSettings.fileTranscriptionMode == .vad
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

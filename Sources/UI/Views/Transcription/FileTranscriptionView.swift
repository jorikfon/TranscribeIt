import SwiftUI

/// SwiftUI view для окна транскрипции
///
/// Главный компонент UI для работы с транскрипцией стерео телефонных записей.
/// Координирует работу всех подкомпонентов: HeaderView, SettingsPanel, EmptyStateView, ContentView.
///
/// ## Архитектура
/// - Использует MVVM паттерн: ViewModel управляет состоянием, View только отображает
/// - Делегирует бизнес-логику через callbacks (onStartTranscription)
/// - Разбит на композируемые компоненты для упрощения поддержки
///
/// ## Основные функции
/// - Выбор аудио файла через NSOpenPanel
/// - Отображение прогресса транскрипции
/// - Настройка параметров (модель, язык, VAD алгоритм)
/// - Перезапуск транскрипции с новыми настройками
/// - Выбор нового файла после завершения
///
/// ## Example
/// ```swift
/// FileTranscriptionView(
///     viewModel: viewModel,
///     onStartTranscription: { urls in
///         startTranscriptionProcess(urls)
///     }
/// )
/// ```
struct FileTranscriptionView: View {
    @ObservedObject var viewModel: FileTranscriptionViewModel
    var onStartTranscription: (([URL]) -> Void)?

    @ObservedObject private var modelManager = ModelManager.shared
    @ObservedObject private var userSettings = UserSettings.shared

    @State private var showSettings: Bool = false
    @State private var selectedModel: String = ""
    @State private var selectedVADAlgorithm: UserSettings.VADAlgorithmType = .spectralTelephone
    @State private var selectedLanguage: String = "ru"

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            settingsPanelSection
            progressSection
            contentSection
        }
        .onAppear(perform: initializeSettings)
    }

    // MARK: - View Components

    /// Секция заголовка с индикаторами и кнопками
    private var headerSection: some View {
        HeaderView(
            viewModel: viewModel,
            userSettings: userSettings,
            showSettings: $showSettings,
            onSelectNewFile: handleSelectNewFile
        )
    }

    /// Секция панели настроек (раскрывающаяся)
    @ViewBuilder
    private var settingsPanelSection: some View {
        if showSettings {
            SettingsPanel(
                selectedModel: $selectedModel,
                selectedVADAlgorithm: $selectedVADAlgorithm,
                selectedLanguage: $selectedLanguage,
                modelManager: modelManager,
                onRetranscribe: handleRetranscribe
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            Divider()
        }
    }

    /// Секция прогресс бара
    @ViewBuilder
    private var progressSection: some View {
        if viewModel.state == .processing {
            ProgressView(value: viewModel.progress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle())
                .padding(.horizontal, 16)
        }
    }

    /// Секция основного контента (результаты или пустое состояние)
    @ViewBuilder
    private var contentSection: some View {
        if let transcription = viewModel.currentTranscription {
            TranscriptionContentView(transcription: transcription, viewModel: viewModel)
        } else {
            EmptyStateView(onSelectFile: handleSelectFile)
        }
    }

    // MARK: - Actions

    /// Обработка выбора аудио файла
    private func handleSelectFile() {
        FileSelectionHelper.selectAudioFile { selectedURL in
            guard let fileURL = selectedURL else { return }

            // Настройки можно открыть вручную через кнопку в заголовке
            // Автоматическое открытие убрано для более чистого UX

            onStartTranscription?([fileURL])
            LogManager.app.info("Выбран файл для транскрипции: \(fileURL.lastPathComponent)")
        }
    }

    /// Обработка выбора нового файла после завершения транскрипции
    private func handleSelectNewFile() {
        viewModel.reset()
        viewModel.currentFileURL = nil
        handleSelectFile()
    }

    /// Обработка перезапуска транскрипции с новыми настройками
    private func handleRetranscribe() {
        guard let fileURL = viewModel.currentFileURL else {
            LogManager.app.error("Невозможно перезапустить - нет URL файла")
            return
        }

        saveSettingsAndUpdateMode()
        logRetranscriptionSettings()
        hideSettingsPanelWithAnimation()

        onStartTranscription?([fileURL])
    }

    // MARK: - Helpers

    /// Инициализирует настройки при первом появлении view
    private func initializeSettings() {
        if selectedModel.isEmpty {
            selectedModel = modelManager.currentModel
        }
        selectedVADAlgorithm = userSettings.vadAlgorithmType
        selectedLanguage = userSettings.transcriptionLanguage
    }

    /// Сохраняет выбранные настройки и обновляет режим транскрипции
    private func saveSettingsAndUpdateMode() {
        modelManager.saveCurrentModel(selectedModel)
        userSettings.vadAlgorithmType = selectedVADAlgorithm
        userSettings.transcriptionLanguage = selectedLanguage

        // Автоматически обновляем fileTranscriptionMode на основе выбранного алгоритма
        userSettings.fileTranscriptionMode = selectedVADAlgorithm.isBatchMode ? .batch : .vad
    }

    /// Логирует параметры перезапуска транскрипции
    private func logRetranscriptionSettings() {
        let modeInfo = selectedVADAlgorithm.isBatchMode ? "Batch" : "VAD"
        let langInfo = selectedLanguage.isEmpty ? "Auto" : selectedLanguage.uppercased()
        LogManager.app.info(
            "Перезапуск транскрибации: модель=\(selectedModel), режим=\(modeInfo), " +
            "алгоритм=\(selectedVADAlgorithm.displayName), язык=\(langInfo)"
        )
    }

    /// Скрывает панель настроек с анимацией
    private func hideSettingsPanelWithAnimation() {
        withAnimation {
            showSettings = false
        }
    }
}

import SwiftUI
import AppKit
import TranscribeItCore

/// Окно настроек TranscribeIt
/// Включает настройки моделей, словарей и дополнительные параметры
struct SettingsView: View {
    @ObservedObject var modelManager = ModelManager.shared
    @ObservedObject var userSettings = UserSettings.shared

    let dictionaryManager = VocabularyDictionariesManager.shared

    @State private var selectedSection: SettingsSection = .models
    @State private var showingDeleteAlert = false
    @State private var modelToDelete: String?

    enum SettingsSection: String, CaseIterable, Identifiable {
        case models = "Models"
        case vocabulary = "Vocabulary"
        case advanced = "Advanced"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .models: return "cpu"
            case .vocabulary: return "book.fill"
            case .advanced: return "gearshape.fill"
            }
        }

        var color: Color {
            switch self {
            case .models: return .purple
            case .vocabulary: return .green
            case .advanced: return .orange
            }
        }
    }

    var body: some View {
        ZStack {
            // Background
            Color(NSColor.windowBackgroundColor)

            // Content with Sidebar
            HStack(spacing: 0) {
                // Sidebar
                sidebarView
                    .frame(width: 200)

                Divider()

                // Content Area
                contentView
            }
        }
        .frame(width: 800, height: 600)
        .alert("Delete Model", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    deleteModel(model)
                }
            }
        } message: {
            Text("Are you sure you want to delete the \(modelToDelete ?? "") model? This action cannot be undone.")
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "text.microphone")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("TranscribeIt")
                            .font(.title3)
                            .fontWeight(.bold)

                        Text("Settings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }

            Divider()

            // Section buttons
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(SettingsSection.allCases) { section in
                        sectionButton(section)
                    }
                }
                .padding(.vertical, 8)
            }

            Spacer()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func sectionButton(_ section: SettingsSection) -> some View {
        Button(action: {
            selectedSection = section
        }) {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 14))
                    .foregroundColor(selectedSection == section ? section.color : .secondary)
                    .frame(width: 20)

                Text(section.rawValue)
                    .font(.system(size: 13))
                    .foregroundColor(selectedSection == section ? .primary : .secondary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedSection == section ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 8)
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch selectedSection {
                case .models:
                    modelsSection
                case .vocabulary:
                    vocabularySection
                case .advanced:
                    advancedSection
                }
            }
            .padding(24)
        }
    }

    // MARK: - Models Section

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(
                title: "Whisper Models",
                subtitle: "Choose the model that best fits your needs"
            )

            // Current model
            GroupBox {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Model")
                            .font(.headline)
                        Text(modelManager.currentModel)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if let model = modelManager.supportedModels.first(where: { $0.name == modelManager.currentModel }) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(model.displayName)
                                .font(.system(size: 13, weight: .semibold))
                            HStack(spacing: 4) {
                                Text("Speed:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(model.speed)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            HStack(spacing: 4) {
                                Text("Accuracy:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(model.accuracy)
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
                .padding(12)
            }

            Divider()

            // Available models
            Text("Available Models")
                .font(.headline)

            ForEach(modelManager.supportedModels, id: \.name) { model in
                modelRow(model)
            }
        }
    }

    private func modelRow(_ model: WhisperModel) -> some View {
        GroupBox {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(model.displayName)
                            .font(.system(size: 14, weight: .semibold))

                        if modelManager.currentModel == model.name {
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .cornerRadius(4)
                        }
                    }

                    HStack(spacing: 16) {
                        Label(model.size, systemImage: "externaldrive.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Label(model.speed, systemImage: "speedometer")
                            .font(.caption)
                            .foregroundColor(.blue)

                        Label(model.accuracy, systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                Spacer()

                // Download/Select buttons
                if modelManager.isModelDownloaded(model.name) {
                    HStack(spacing: 8) {
                        if modelManager.currentModel != model.name {
                            Button("Select") {
                                selectModel(model.name)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button(action: {
                            modelToDelete = model.name
                            showingDeleteAlert = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    if modelManager.isDownloading && modelManager.downloadingModel == model.name {
                        VStack(spacing: 4) {
                            ProgressView(value: modelManager.downloadProgress)
                                .frame(width: 120)
                            Text("\(Int(modelManager.downloadProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button("Download") {
                            downloadModel(model.name)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(modelManager.isDownloading)
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Vocabulary Section

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(
                title: "Predefined Vocabularies",
                subtitle: "Select dictionaries to improve transcription accuracy for technical terms"
            )

            // Predefined dictionaries
            Text("Available Dictionaries")
                .font(.headline)

            ForEach(dictionaryManager.predefinedDictionaries) { dictionary in
                dictionaryRow(dictionary)
            }

            Divider()

            // Custom prefill prompt section
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Custom Terms")
                        .font(.headline)

                    Text("Add additional technical terms or names not in the dictionaries above")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: Binding(
                        get: { userSettings.customPrefillPrompt },
                        set: { userSettings.customPrefillPrompt = $0 }
                    ))
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 80)
                    .border(Color.secondary.opacity(0.2))

                    Text("Example: MikoPBX, Asterisk, custom company names, etc.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(12)
            }
        }
    }

    private func dictionaryRow(_ dictionary: VocabularyDictionary) -> some View {
        GroupBox {
            HStack(spacing: 12) {
                // Checkbox
                Toggle("", isOn: Binding(
                    get: { userSettings.selectedDictionaryIds.contains(dictionary.id) },
                    set: { enabled in
                        if enabled {
                            if !userSettings.selectedDictionaryIds.contains(dictionary.id) {
                                userSettings.selectedDictionaryIds.append(dictionary.id)
                            }
                        } else {
                            userSettings.selectedDictionaryIds.removeAll { $0 == dictionary.id }
                        }
                    }
                ))
                .toggleStyle(.checkbox)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(dictionary.name)
                            .font(.system(size: 14, weight: .semibold))

                        Text(dictionary.category)
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.7))
                            .cornerRadius(4)
                    }

                    Text(dictionary.description)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(dictionary.terms.count) terms")
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                Spacer()
            }
            .padding(12)
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(
                title: "Advanced Settings",
                subtitle: "Additional transcription options"
            )

            Text("No advanced settings available. All transcription settings are now in the transcription window.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
        }
    }

    // MARK: - Helper Views

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private func selectModel(_ modelName: String) {
        modelManager.saveCurrentModel(modelName)
        LogManager.app.info("Model selected: \(modelName)")
    }

    private func downloadModel(_ modelName: String) {
        Task {
            do {
                try await modelManager.downloadModel(modelName)
            } catch {
                LogManager.app.error("Failed to download model: \(error)")
            }
        }
    }

    private func deleteModel(_ modelName: String) {
        do {
            try modelManager.deleteModel(modelName)
        } catch {
            LogManager.app.error("Failed to delete model: \(error)")
        }
    }
}

/// Контроллер окна настроек
public class SettingsWindowController: NSWindowController {
    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())

        self.init(window: window)
    }
}

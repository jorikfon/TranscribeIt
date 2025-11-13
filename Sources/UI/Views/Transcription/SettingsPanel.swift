import SwiftUI

/// Панель настроек транскрибации
struct SettingsPanel: View {
    typealias Constants = TranscriptionViewConstants.SettingsPanel

    @Binding var selectedModel: String
    @Binding var selectedVADAlgorithm: UserSettings.VADAlgorithmType
    @Binding var selectedLanguage: String
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var userSettings: UserSettings
    var onRetranscribe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.mainVerticalSpacing) {
            Text("Transcription Settings")
                .font(.system(size: Constants.titleFontSize, weight: .semibold))
                .foregroundColor(.primary)

            HStack(spacing: Constants.sectionHorizontalSpacing) {
                // Выбор модели
                VStack(alignment: .leading, spacing: Constants.labelVerticalSpacing) {
                    Text("Whisper Model")
                        .font(.system(size: Constants.labelFontSize, weight: .medium))
                        .foregroundColor(.secondary)

                    Picker("", selection: $selectedModel) {
                        ForEach(modelManager.supportedModels, id: \.name) { model in
                            HStack {
                                Text(model.displayName)
                                Text("(\(model.size), \(model.accuracy))")
                                    .font(.system(size: Constants.pickerItemSmallFontSize))
                                    .foregroundColor(.secondary)
                            }
                            .tag(model.name)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Выбор языка
                VStack(alignment: .leading, spacing: Constants.labelVerticalSpacing) {
                    Text("Language")
                        .font(.system(size: Constants.labelFontSize, weight: .medium))
                        .foregroundColor(.secondary)

                    Picker("", selection: $selectedLanguage) {
                        Text("Auto-detect").tag("")
                        Text("Russian").tag("ru")
                        Text("English").tag("en")
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: Constants.languagePickerWidth)
                }
            }

            // Выбор VAD алгоритма / режима
            VStack(alignment: .leading, spacing: Constants.labelVerticalSpacing) {
                Text("Segmentation Method")
                    .font(.system(size: Constants.labelFontSize, weight: .medium))
                    .foregroundColor(.secondary)

                Picker("", selection: $selectedVADAlgorithm) {
                    // Группа VAD алгоритмов
                    Section(header: Text("VAD Algorithms")) {
                        ForEach(UserSettings.VADAlgorithmType.allCases.filter { !$0.isBatchMode }) { vadType in
                            Text(vadType.displayName)
                                .font(.system(size: Constants.pickerItemFontSize))
                                .tag(vadType)
                        }
                    }

                    // Batch режим отдельно
                    Section(header: Text("Alternative Mode")) {
                        ForEach(UserSettings.VADAlgorithmType.allCases.filter { $0.isBatchMode }) { vadType in
                            Text(vadType.displayName)
                                .font(.system(size: Constants.pickerItemFontSize))
                                .tag(vadType)
                        }
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: .infinity, alignment: .leading)

                // Описание выбранного метода
                HStack(spacing: Constants.iconTextSpacing) {
                    Image(systemName: selectedVADAlgorithm.isBatchMode ? "square.grid.3x3.fill" : "waveform")
                        .font(.system(size: Constants.descriptionIconSize))
                        .foregroundColor(selectedVADAlgorithm.isBatchMode ? .orange : .green)

                    Text(selectedVADAlgorithm.description)
                        .font(.system(size: Constants.descriptionFontSize))
                        .foregroundColor(.secondary.opacity(Constants.descriptionOpacity))
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            // Warmup prompt section
            VStack(alignment: .leading, spacing: Constants.labelVerticalSpacing) {
                Text("Base Context Prompt")
                    .font(.system(size: Constants.labelFontSize, weight: .medium))
                    .foregroundColor(.secondary)

                Text("Base context prompt used for all transcriptions (helps model understand domain/terminology)")
                    .font(.system(size: Constants.descriptionFontSize))
                    .foregroundColor(.secondary.opacity(Constants.descriptionOpacity))

                TextEditor(text: Binding(
                    get: { userSettings.baseContextPrompt },
                    set: { userSettings.baseContextPrompt = $0 }
                ))
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 60)
                .border(Color.secondary.opacity(0.2))
            }

            // Кнопка перезапуска
            HStack {
                Spacer()
                Button(action: {
                    onRetranscribe()
                }) {
                    HStack(spacing: Constants.buttonSpacing) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: Constants.retranscribeButtonIconSize))
                        Text("Retranscribe with New Settings")
                            .font(.system(size: Constants.retranscribeButtonTextSize, weight: .medium))
                    }
                    .padding(.horizontal, Constants.buttonHorizontalPadding)
                    .padding(.vertical, Constants.buttonVerticalPadding)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(Constants.mainPadding)
        .background(Color(NSColor.controlBackgroundColor).opacity(Constants.backgroundOpacity))
    }
}

/// Alias для обратной совместимости
typealias TranscriptionSettingsPanel = SettingsPanel

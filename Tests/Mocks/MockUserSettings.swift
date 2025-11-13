import Foundation
@testable import TranscribeItCore

/// Mock-реализация UserSettingsProtocol для тестирования
/// Позволяет тестировать компоненты без реального UserSettings
public final class MockUserSettings: UserSettingsProtocol {
    // MARK: - Call Tracking

    public var addStopWordCallCount = 0
    public var removeStopWordCallCount = 0
    public var containsStopWordCallCount = 0
    public var addVocabularyCallCount = 0
    public var removeVocabularyCallCount = 0
    public var enableVocabularyCallCount = 0
    public var disableVocabularyCallCount = 0
    public var getEnabledVocabularyWordsCallCount = 0
    public var getPromptWithVocabularyCallCount = 0
    public var buildFullPrefillPromptCallCount = 0
    public var getVADAlgorithmForServiceCallCount = 0
    public var resetCallCount = 0

    // MARK: - Transcription Prompt

    public var useProgrammingPrompt: Bool = false
    public var customPrompt: String = ""

    public var effectivePrompt: String {
        if useProgrammingPrompt && !customPrompt.isEmpty {
            return "Programming prompt + \(customPrompt)"
        } else if useProgrammingPrompt {
            return "Programming prompt"
        } else {
            return customPrompt
        }
    }

    public var hasPrompt: Bool {
        return useProgrammingPrompt || !customPrompt.isEmpty
    }

    // MARK: - Recording Duration

    public var maxRecordingDuration: TimeInterval = 300.0 // 5 минут

    // MARK: - Stop Words

    public var stopWords: [String] = []

    public func addStopWord(_ word: String) {
        addStopWordCallCount += 1
        if !stopWords.contains(word) {
            stopWords.append(word)
        }
    }

    public func removeStopWord(_ word: String) {
        removeStopWordCallCount += 1
        stopWords.removeAll { $0 == word }
    }

    public func containsStopWord(_ text: String) -> Bool {
        containsStopWordCallCount += 1
        let lowercasedText = text.lowercased()
        return stopWords.contains { lowercasedText.contains($0.lowercased()) }
    }

    // MARK: - Vocabulary

    public var vocabularies: [CustomVocabulary] = []
    public var enabledVocabularies: Set<UUID> = []

    public func addVocabulary(name: String, words: [String]) {
        addVocabularyCallCount += 1
        let vocab = CustomVocabulary(name: name, words: words)
        vocabularies.append(vocab)
        enabledVocabularies.insert(vocab.id)
    }

    public func removeVocabulary(_ id: UUID) {
        removeVocabularyCallCount += 1
        vocabularies.removeAll { $0.id == id }
        enabledVocabularies.remove(id)
    }

    public func enableVocabulary(_ id: UUID) {
        enableVocabularyCallCount += 1
        enabledVocabularies.insert(id)
    }

    public func disableVocabulary(_ id: UUID) {
        disableVocabularyCallCount += 1
        enabledVocabularies.remove(id)
    }

    public func getEnabledVocabularyWords() -> [String] {
        getEnabledVocabularyWordsCallCount += 1
        return vocabularies
            .filter { enabledVocabularies.contains($0.id) }
            .flatMap { $0.words }
    }

    public func getPromptWithVocabulary() -> String {
        getPromptWithVocabularyCallCount += 1
        let words = getEnabledVocabularyWords()
        if words.isEmpty {
            return effectivePrompt
        } else {
            return "\(effectivePrompt)\nVocabulary: \(words.joined(separator: ", "))"
        }
    }

    // MARK: - Quality Enhancement

    public var useQualityEnhancement: Bool = false
    public var useTemperatureFallback: Bool = false
    public var compressionRatioThreshold: Float? = nil
    public var logProbThreshold: Float? = nil

    // MARK: - Vocabulary Dictionaries & Language

    public var selectedDictionaryIds: [String] = []
    public var customPrefillPrompt: String = ""
    public var transcriptionLanguage: String = "en"

    public func buildFullPrefillPrompt() -> String {
        buildFullPrefillPromptCallCount += 1

        var prompt = ""
        if !selectedDictionaryIds.isEmpty {
            prompt += "Dictionaries: \(selectedDictionaryIds.joined(separator: ", "))"
        }
        if !customPrefillPrompt.isEmpty {
            if !prompt.isEmpty {
                prompt += "\n"
            }
            prompt += customPrefillPrompt
        }
        return prompt
    }

    // MARK: - File Transcription

    public var fileTranscriptionMode: UserSettings.FileTranscriptionMode = .vad
    public var vadAlgorithmType: UserSettings.VADAlgorithmType = .spectralDefault

    public func getVADAlgorithmForService() -> (mode: String, algorithm: String) {
        getVADAlgorithmForServiceCallCount += 1

        let mode = fileTranscriptionMode.rawValue
        let algorithm = vadAlgorithmType.rawValue
        return (mode, algorithm)
    }

    // MARK: - Utilities

    public func reset() {
        resetCallCount += 1

        useProgrammingPrompt = false
        customPrompt = ""
        maxRecordingDuration = 300.0
        stopWords.removeAll()
        vocabularies.removeAll()
        enabledVocabularies.removeAll()
        useQualityEnhancement = false
        useTemperatureFallback = false
        compressionRatioThreshold = nil
        logProbThreshold = nil
        selectedDictionaryIds.removeAll()
        customPrefillPrompt = ""
        transcriptionLanguage = "en"
        fileTranscriptionMode = .vad
        vadAlgorithmType = .spectralDefault

        // Сброс счетчиков
        addStopWordCallCount = 0
        removeStopWordCallCount = 0
        containsStopWordCallCount = 0
        addVocabularyCallCount = 0
        removeVocabularyCallCount = 0
        enableVocabularyCallCount = 0
        disableVocabularyCallCount = 0
        getEnabledVocabularyWordsCallCount = 0
        getPromptWithVocabularyCallCount = 0
        buildFullPrefillPromptCallCount = 0
        getVADAlgorithmForServiceCallCount = 0
        resetCallCount = 0
    }

    // MARK: - Initialization

    public init() {}
}

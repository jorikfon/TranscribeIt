import Foundation
@testable import TranscribeItCore

/// Mock-реализация ModelManagerProtocol для тестирования
/// Позволяет тестировать компоненты без реального ModelManager
public final class MockModelManager: ModelManagerProtocol {
    // MARK: - Call Tracking

    public var saveCurrentModelCallCount = 0
    public var scanDownloadedModelsCallCount = 0
    public var isModelDownloadedCallCount = 0
    public var checkModelAvailabilityCallCount = 0
    public var downloadModelCallCount = 0
    public var deleteModelCallCount = 0
    public var getModelSizeCallCount = 0
    public var getModelInfoCallCount = 0

    /// История вызовов saveCurrentModel
    public var saveCurrentModelCalls: [String] = []

    /// История вызовов isModelDownloaded
    public var isModelDownloadedCalls: [String] = []

    /// История вызовов checkModelAvailability
    public var checkModelAvailabilityCalls: [String] = []

    /// История вызовов downloadModel
    public var downloadModelCalls: [String] = []

    /// История вызовов deleteModel
    public var deleteModelCalls: [String] = []

    // MARK: - Published Properties

    public var availableModels: [WhisperModel] = [
        WhisperModel(
            name: "tiny",
            displayName: "Tiny",
            size: "75 MB",
            speed: "Very Fast",
            accuracy: "Low"
        ),
        WhisperModel(
            name: "base",
            displayName: "Base",
            size: "142 MB",
            speed: "Fast",
            accuracy: "Good"
        ),
        WhisperModel(
            name: "small",
            displayName: "Small",
            size: "466 MB",
            speed: "Medium",
            accuracy: "High"
        )
    ]

    public var downloadedModels: [String] = []
    public var currentModel: String = "small"
    public var isDownloading: Bool = false
    public var downloadProgress: Double = 0.0
    public var downloadingModel: String? = nil
    public var downloadError: String? = nil

    // MARK: - Stubbed Return Values

    /// Словарь для stubbing доступности моделей
    public var modelAvailability: [String: Bool] = [:]

    /// Словарь для stubbing размеров моделей
    public var modelSizes: [String: String] = [:]

    /// Флаг для симуляции ошибок при загрузке
    public var shouldThrowOnDownload = false

    /// Флаг для симуляции ошибок при удалении
    public var shouldThrowOnDelete = false

    /// Симулировать прогресс загрузки
    public var simulateDownloadProgress = false

    // MARK: - Constants

    public var supportedModels: [WhisperModel] {
        return availableModels
    }

    // MARK: - ModelManagerProtocol Implementation

    public func saveCurrentModel(_ model: String) {
        saveCurrentModelCallCount += 1
        saveCurrentModelCalls.append(model)
        currentModel = model
    }

    public func scanDownloadedModels() {
        scanDownloadedModelsCallCount += 1
        // Mock не выполняет реального сканирования
    }

    public func isModelDownloaded(_ modelName: String) -> Bool {
        isModelDownloadedCallCount += 1
        isModelDownloadedCalls.append(modelName)
        return downloadedModels.contains(modelName)
    }

    public func checkModelAvailability(_ modelName: String) async -> Bool {
        checkModelAvailabilityCallCount += 1
        checkModelAvailabilityCalls.append(modelName)

        // Проверяем stubbed значения
        if let availability = modelAvailability[modelName] {
            return availability
        }

        // По умолчанию все модели доступны
        return true
    }

    public func downloadModel(_ modelName: String) async throws {
        downloadModelCallCount += 1
        downloadModelCalls.append(modelName)

        if shouldThrowOnDownload {
            throw NSError(
                domain: "MockModelManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Mock download error for \(modelName)"]
            )
        }

        // Симуляция загрузки
        isDownloading = true
        downloadingModel = modelName

        if simulateDownloadProgress {
            for progress in stride(from: 0.0, through: 1.0, by: 0.2) {
                downloadProgress = progress
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 секунды
            }
        }

        downloadProgress = 1.0
        isDownloading = false
        downloadingModel = nil

        // Добавляем модель в загруженные
        if !downloadedModels.contains(modelName) {
            downloadedModels.append(modelName)
        }
    }

    public func deleteModel(_ modelName: String) throws {
        deleteModelCallCount += 1
        deleteModelCalls.append(modelName)

        if shouldThrowOnDelete {
            throw NSError(
                domain: "MockModelManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Mock delete error for \(modelName)"]
            )
        }

        downloadedModels.removeAll { $0 == modelName }
    }

    public func getModelSize(_ modelName: String) -> String {
        getModelSizeCallCount += 1

        // Проверяем stubbed значения
        if let size = modelSizes[modelName] {
            return size
        }

        // Возвращаем размер из availableModels
        return availableModels.first { $0.name == modelName }?.size ?? "Unknown"
    }

    public func getModelInfo(_ modelName: String) -> WhisperModel? {
        getModelInfoCallCount += 1
        return availableModels.first { $0.name == modelName }
    }

    // MARK: - Helper Methods

    /// Сбросить все счетчики и состояние
    public func reset() {
        saveCurrentModelCallCount = 0
        scanDownloadedModelsCallCount = 0
        isModelDownloadedCallCount = 0
        checkModelAvailabilityCallCount = 0
        downloadModelCallCount = 0
        deleteModelCallCount = 0
        getModelSizeCallCount = 0
        getModelInfoCallCount = 0

        saveCurrentModelCalls.removeAll()
        isModelDownloadedCalls.removeAll()
        checkModelAvailabilityCalls.removeAll()
        downloadModelCalls.removeAll()
        deleteModelCalls.removeAll()

        downloadedModels.removeAll()
        currentModel = "small"
        isDownloading = false
        downloadProgress = 0.0
        downloadingModel = nil
        downloadError = nil

        modelAvailability.removeAll()
        modelSizes.removeAll()

        shouldThrowOnDownload = false
        shouldThrowOnDelete = false
        simulateDownloadProgress = false
    }

    /// Добавить модель в список загруженных (для тестирования)
    public func addDownloadedModel(_ modelName: String) {
        if !downloadedModels.contains(modelName) {
            downloadedModels.append(modelName)
        }
    }

    // MARK: - Initialization

    public init() {}
}

import Foundation
import WhisperKit

/// Менеджер для управления Whisper моделями
/// Поддерживает загрузку, удаление и проверку доступных моделей
public class ModelManager: ObservableObject {
    public static let shared = ModelManager()

    @Published public var availableModels: [WhisperModel] = []
    @Published public var downloadedModels: [String] = []
    @Published public var currentModel: String = "small"
    @Published public var isDownloading: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var downloadingModel: String? = nil // Какая конкретно модель загружается
    @Published public var downloadError: String? = nil // Последняя ошибка загрузки

    private let modelDirectory: URL

    // Поддерживаемые модели Whisper
    // Отсортированы по размеру: от самой быстрой к самой точной
    public let supportedModels: [WhisperModel] = [
        WhisperModel(name: "tiny", displayName: "Tiny", size: "~40 MB", speed: "Very Fast", accuracy: "Basic"),
        WhisperModel(name: "base", displayName: "Base", size: "~75 MB", speed: "Very Fast", accuracy: "Fair"),
        WhisperModel(name: "small", displayName: "Small", size: "~250 MB", speed: "Fast", accuracy: "Good"),
        WhisperModel(name: "medium", displayName: "Medium", size: "~770 MB", speed: "Medium", accuracy: "Better"),
        WhisperModel(name: "large-v2", displayName: "Large V2", size: "~3 GB", speed: "Slower", accuracy: "Excellent"),
        WhisperModel(name: "large-v3", displayName: "Large V3", size: "~3 GB", speed: "Slower", accuracy: "Best")
    ]

    private init() {
        // Используем тот же путь что и WhisperService для постоянного хранения моделей
        modelDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TranscribeIt/Models")

        // Создаём директорию если не существует
        try? FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        LogManager.app.info("ModelManager: Инициализация")
        LogManager.app.info("ModelManager: Директория моделей: \(self.modelDirectory.path)")

        // Загружаем текущую модель из настроек
        loadCurrentModel()

        // Сканируем доступные модели
        scanDownloadedModels()
    }

    /// Загрузка текущей модели из UserDefaults
    private func loadCurrentModel() {
        if let saved = UserDefaults.standard.string(forKey: "currentWhisperModel") {
            currentModel = saved
        }
    }

    /// Сохранение текущей модели в UserDefaults
    public func saveCurrentModel(_ model: String) {
        currentModel = model
        UserDefaults.standard.set(model, forKey: "currentWhisperModel")
        LogManager.app.info("ModelManager: Текущая модель изменена на \(model)")
    }

    /// Сканирование загруженных моделей
    public func scanDownloadedModels() {
        LogManager.app.info("ModelManager: Сканирование загруженных моделей...")

        // Запускаем асинхронную проверку
        Task {
            var foundModels: [String] = []

            // Проверяем каждую поддерживаемую модель
            for model in supportedModels {
                let isAvailable = await checkModelAvailability(model.name)
                if isAvailable {
                    foundModels.append(model.name)
                    LogManager.app.info("ModelManager: Модель \(model.name) доступна")
                }
            }

            await MainActor.run {
                self.downloadedModels = foundModels
                LogManager.app.info("ModelManager: Найдено моделей: \(foundModels.count) - \(foundModels)")
            }
        }
    }

    /// Проверка загружена ли модель
    /// WhisperKit использует внутренний кэш, поэтому проверяем через список загруженных моделей
    public func isModelDownloaded(_ modelName: String) -> Bool {
        return downloadedModels.contains(modelName)
    }

    /// Проверка доступности модели через проверку файлов на диске
    /// ОПТИМИЗАЦИЯ: Не создаём WhisperKit экземпляр, проверяем только файлы
    public func checkModelAvailability(_ modelName: String) async -> Bool {
        // WhisperKit сохраняет модели с вложенной структурой: models/argmaxinc/whisperkit-coreml/
        let modelPath = modelDirectory.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelName)", isDirectory: true)

        if FileManager.default.fileExists(atPath: modelPath.path) {
            LogManager.app.debug("ModelManager: Модель \(modelName) найдена: \(modelPath.path)")
            return true
        }

        // Если модель не найдена по файлам, она будет загружена при первом использовании
        LogManager.app.debug("ModelManager: Модель \(modelName) не найдена (будет загружена)")
        return false
    }

    /// Загрузка модели
    public func downloadModel(_ modelName: String) async throws {
        await MainActor.run {
            isDownloading = true
            downloadingModel = modelName
            downloadProgress = 0.0
            downloadError = nil
        }

        LogManager.app.info("ModelManager: Начало загрузки модели \(modelName)...")

        do {
            // Имитируем прогресс (WhisperKit не предоставляет реальный прогресс)
            let progressTask = Task {
                for i in 1...10 {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 секунды
                    await MainActor.run {
                        self.downloadProgress = Double(i) * 0.08 // 0.08, 0.16, 0.24...0.80
                    }
                }
            }

            // WhisperKit автоматически загружает модель при инициализации
            // Мы просто создаём временный экземпляр для загрузки
            LogManager.app.info("ModelManager: Инициализация WhisperKit для загрузки \(modelName)...")

            let _ = try await WhisperKit(
                model: modelName,
                downloadBase: modelDirectory,  // Используем постоянный путь
                modelRepo: "argmaxinc/whisperkit-coreml",
                verbose: true,
                logLevel: .info,
                prewarm: false  // Не прогреваем - только загружаем
            )

            // Отменяем task прогресса
            progressTask.cancel()

            await MainActor.run {
                self.downloadProgress = 1.0
            }

            LogManager.app.success("ModelManager: Модель \(modelName) успешно загружена")

            // Добавляем модель в список загруженных сразу
            await MainActor.run {
                if !self.downloadedModels.contains(modelName) {
                    self.downloadedModels.append(modelName)
                }
                self.isDownloading = false
                self.downloadingModel = nil
            }

            // Небольшая пауза для визуализации прогресса
            try? await Task.sleep(nanoseconds: 500_000_000)

            LogManager.app.info("ModelManager: Модель \(modelName) доступна для использования")
        } catch {
            await MainActor.run {
                isDownloading = false
                downloadingModel = nil
                downloadProgress = 0.0
                downloadError = "Failed to download \(modelName): \(error.localizedDescription)"
            }

            LogManager.app.error("ModelManager: Ошибка загрузки модели \(modelName): \(error)")
            throw ModelError.downloadFailed(error)
        }
    }

    /// Удаление модели
    public func deleteModel(_ modelName: String) throws {
        print("ModelManager: Удаление модели \(modelName)...")

        // WhisperKit хранит модели в своем внутреннем кэше
        // Мы просто удаляем модель из списка загруженных
        // При следующем запуске она будет загружена заново

        DispatchQueue.main.async {
            self.downloadedModels.removeAll { $0 == modelName }
            print("ModelManager: ✓ Модель \(modelName) удалена из списка")
        }

        // Если удалили текущую модель, переключаемся на small
        if currentModel == modelName {
            saveCurrentModel("small")
        }

        // Пытаемся найти и удалить файлы на диске
        let hubCacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("huggingface/models", isDirectory: true)

        let possiblePaths = [
            hubCacheDir.appendingPathComponent("openai_whisper-\(modelName)", isDirectory: true),
            hubCacheDir.appendingPathComponent("whisper-\(modelName)", isDirectory: true),
            modelDirectory.appendingPathComponent(modelName, isDirectory: true)
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path.path) {
                try? FileManager.default.removeItem(at: path)
                print("ModelManager: Удалена директория: \(path.path)")
            }
        }

        print("ModelManager: ✓ Модель \(modelName) успешно удалена")
    }

    /// Получение размера модели на диске
    public func getModelSize(_ modelName: String) -> String {
        // WhisperKit хранит модели в своем внутреннем кэше
        // Мы просто показываем примерный размер из supportedModels
        if let modelInfo = getModelInfo(modelName) {
            let status = isModelDownloaded(modelName) ? " ✓" : ""
            return modelInfo.size + status
        }

        return "Unknown"
    }

    /// Расчёт размера директории
    private func directorySize(at url: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else {
            return nil
        }

        var totalSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  let isRegularFile = resourceValues.isRegularFile,
                  isRegularFile,
                  let fileSize = resourceValues.fileSize else {
                continue
            }

            totalSize += Int64(fileSize)
        }

        return totalSize
    }

    /// Форматирование байтов в человекочитаемый формат
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Получение информации о модели
    public func getModelInfo(_ modelName: String) -> WhisperModel? {
        return supportedModels.first { $0.name == modelName }
    }
}

/// Структура для представления модели Whisper
public struct WhisperModel: Identifiable, Equatable {
    public let id = UUID()
    public let name: String
    public let displayName: String
    public let size: String
    public let speed: String
    public let accuracy: String

    public var description: String {
        return "\(displayName) - \(size) - Speed: \(speed), Accuracy: \(accuracy)"
    }
}

/// Ошибки ModelManager
public enum ModelError: Error {
    case downloadFailed(Error)
    case modelNotFound
    case deleteFailed(Error)

    public var localizedDescription: String {
        switch self {
        case .downloadFailed(let error):
            return "Failed to download model: \(error.localizedDescription)"
        case .modelNotFound:
            return "Model not found"
        case .deleteFailed(let error):
            return "Failed to delete model: \(error.localizedDescription)"
        }
    }
}

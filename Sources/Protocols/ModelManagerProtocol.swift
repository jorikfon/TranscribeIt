import Foundation

/// Протокол для управления Whisper моделями
/// Используется для улучшения тестируемости и снижения жесткой связанности
public protocol ModelManagerProtocol {
    // MARK: - Published Properties

    /// Список доступных моделей
    var availableModels: [WhisperModel] { get }

    /// Список загруженных моделей
    var downloadedModels: [String] { get }

    /// Текущая выбранная модель
    var currentModel: String { get }

    /// Флаг загрузки модели
    var isDownloading: Bool { get }

    /// Прогресс загрузки (0.0 - 1.0)
    var downloadProgress: Double { get }

    /// Модель, которая сейчас загружается
    var downloadingModel: String? { get }

    /// Последняя ошибка загрузки
    var downloadError: String? { get }

    // MARK: - Constants

    /// Поддерживаемые модели Whisper
    var supportedModels: [WhisperModel] { get }

    // MARK: - Methods

    /// Сохранение текущей модели
    /// - Parameter model: Название модели
    func saveCurrentModel(_ model: String)

    /// Сканирование загруженных моделей
    func scanDownloadedModels()

    /// Проверка загружена ли модель
    /// - Parameter modelName: Название модели
    /// - Returns: true если модель загружена
    func isModelDownloaded(_ modelName: String) -> Bool

    /// Проверка доступности модели
    /// - Parameter modelName: Название модели
    /// - Returns: true если модель доступна
    func checkModelAvailability(_ modelName: String) async -> Bool

    /// Загрузка модели
    /// - Parameter modelName: Название модели для загрузки
    func downloadModel(_ modelName: String) async throws

    /// Удаление модели
    /// - Parameter modelName: Название модели для удаления
    func deleteModel(_ modelName: String) throws

    /// Получение размера модели на диске
    /// - Parameter modelName: Название модели
    /// - Returns: Строка с размером модели
    func getModelSize(_ modelName: String) -> String

    /// Получение информации о модели
    /// - Parameter modelName: Название модели
    /// - Returns: Структура с информацией о модели
    func getModelInfo(_ modelName: String) -> WhisperModel?
}

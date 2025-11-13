import Foundation

/// Централизованный контейнер для управления всеми зависимостями приложения
///
/// DependencyContainer следует паттерну Service Locator и управляет
/// созданием и жизненным циклом всех сервисов приложения.
///
/// ## Использование
/// ```swift
/// let container = DependencyContainer()
/// let whisperService = container.makeWhisperService()
/// ```
///
/// ## Преимущества
/// - Явные зависимости - все зависимости видны в одном месте
/// - Легкое тестирование - можно заменить реальные сервисы на моки
/// - Единая точка конфигурации - все настройки в одном месте
public final class DependencyContainer {

    // MARK: - Shared Managers (синглтоны)

    /// Менеджер моделей Whisper (синглтон)
    /// Используем конкретный тип для доступа к mutable свойствам
    public let modelManager: ModelManager

    /// Настройки пользователя (синглтон)
    /// Используем конкретный тип для доступа к mutable свойствам
    public let userSettings: UserSettings

    /// Менеджер словарей и коррекций (синглтон)
    private let vocabularyManager: VocabularyManagerProtocol

    /// Кэш аудио данных (общий для всех сервисов)
    public let audioCache: AudioCache

    // MARK: - Initialization

    /// Инициализирует контейнер с явными зависимостями
    ///
    /// - Parameters:
    ///   - modelManager: Менеджер моделей Whisper
    ///   - userSettings: Настройки пользователя
    ///   - vocabularyManager: Менеджер словарей и коррекций
    ///   - audioCache: Кэш аудио данных
    public init(
        modelManager: ModelManager,
        userSettings: UserSettings,
        vocabularyManager: VocabularyManagerProtocol,
        audioCache: AudioCache
    ) {
        self.modelManager = modelManager
        self.userSettings = userSettings
        self.vocabularyManager = vocabularyManager
        self.audioCache = audioCache

        LogManager.app.info("DependencyContainer инициализирован")
    }

    // MARK: - Service Factories

    /// Создаёт WhisperService с текущей моделью из настроек
    ///
    /// - Returns: Настроенный экземпляр WhisperService
    public func makeWhisperService() -> WhisperService {
        let modelSize = modelManager.currentModel
        let service = WhisperService(
            modelSize: modelSize,
            vocabularyManager: vocabularyManager
        )

        LogManager.app.info("Создан WhisperService с моделью: \(modelSize)")
        return service
    }

    /// Создаёт FileTranscriptionService
    ///
    /// - Parameter whisperService: Сервис Whisper для транскрипции
    /// - Returns: Настроенный экземпляр FileTranscriptionService
    public func makeFileTranscriptionService(whisperService: WhisperService) -> FileTranscriptionService {
        let service = FileTranscriptionService(
            whisperService: whisperService,
            userSettings: userSettings,
            audioCache: audioCache
        )

        LogManager.app.info("Создан FileTranscriptionService с общим AudioCache")
        return service
    }

    /// Создаёт BatchTranscriptionService
    ///
    /// - Parameter whisperService: Сервис Whisper для транскрипции
    /// - Returns: Настроенный экземпляр BatchTranscriptionService
    public func makeBatchTranscriptionService(whisperService: WhisperService) -> BatchTranscriptionService {
        let service = BatchTranscriptionService(whisperService: whisperService)

        LogManager.app.info("Создан BatchTranscriptionService")
        return service
    }

}

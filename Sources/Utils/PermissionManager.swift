import Foundation
import AVFoundation
import ApplicationServices

/// Менеджер разрешений для всех необходимых системных доступов
/// CGEventTap требует Accessibility разрешение для перехвата клавиатурных событий
public class PermissionManager {
    public static let shared = PermissionManager()

    private init() {
        LogManager.permissions.info("Инициализация PermissionManager")
    }

    // MARK: - Accessibility Permissions

    /// Проверка разрешения Accessibility
    public func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        if trusted {
            LogManager.permissions.success("Accessibility разрешен")
        } else {
            LogManager.permissions.failure("Accessibility не разрешен", message: "Требуется для перехвата горячих клавиш")
        }
        return trusted
    }

    /// Запрос разрешения Accessibility (открывает System Settings)
    public func requestAccessibilityPermission() {
        LogManager.permissions.info("Открытие настроек Accessibility")

        // Создаем prompt для открытия System Settings
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Microphone Permissions

    /// Проверка разрешения на микрофон
    public func checkMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            LogManager.permissions.success("Микрофон разрешен")
            return true
        case .notDetermined:
            LogManager.permissions.info("Запрос разрешения на микрофон")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if granted {
                LogManager.permissions.success("Микрофон разрешен пользователем")
            } else {
                LogManager.permissions.failure("Микрофон отклонен", message: "Пользователь отказал в доступе")
            }
            return granted
        case .denied, .restricted:
            LogManager.permissions.failure("Микрофон недоступен", message: "Отказано или ограничено")
            return false
        @unknown default:
            LogManager.permissions.error("Микрофон: неизвестный статус авторизации")
            return false
        }
    }

    // MARK: - Check All Permissions

    /// Проверка всех необходимых разрешений
    public func checkAllPermissions() async -> PermissionStatus {
        LogManager.permissions.begin("Проверка разрешений")
        let accessibilityPermission = checkAccessibilityPermission()
        let micPermission = await checkMicrophonePermission()

        let status = PermissionStatus(accessibility: accessibilityPermission, microphone: micPermission)
        LogManager.permissions.info("\(status.description)")

        return status
    }

    // MARK: - Permission Guidance

    /// Показать инструкции по предоставлению разрешений
    public func showPermissionInstructions(for permission: PermissionType) -> String {
        switch permission {
        case .accessibility:
            return """
            Для работы PushToTalk требуется доступ Accessibility.
            Это необходимо для перехвата горячих клавиш.

            Как предоставить доступ:
            1. Откройте System Settings
            2. Перейдите в Privacy & Security
            3. Выберите Accessibility
            4. Нажмите кнопку "+" и добавьте PushToTalk
            5. Установите галочку напротив PushToTalk
            6. Перезапустите приложение
            """
        case .microphone:
            return """
            Для работы PushToTalk требуется доступ к микрофону.

            Как предоставить доступ:
            1. Откройте System Settings
            2. Перейдите в Privacy & Security
            3. Выберите Microphone
            4. Включите PushToTalk в списке
            5. Перезапустите приложение
            """
        }
    }
}

// MARK: - Supporting Types

/// Статус всех разрешений
public struct PermissionStatus {
    public let accessibility: Bool
    public let microphone: Bool

    public var allGranted: Bool {
        return accessibility && microphone
    }

    public var description: String {
        var status = "Permission Status:\n"
        status += "  - Accessibility: \(accessibility ? "✓" : "✗")\n"
        status += "  - Microphone: \(microphone ? "✓" : "✗")"
        return status
    }

    public init(accessibility: Bool, microphone: Bool) {
        self.accessibility = accessibility
        self.microphone = microphone
    }
}

/// Типы разрешений
public enum PermissionType {
    case accessibility
    case microphone
}

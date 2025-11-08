import Cocoa
import TranscribeItCore

/// Контроллер меню в статус-баре (menu bar)
public class MenuBarController {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    // Callbacks
    public var onOpenTranscription: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onQuit: (() -> Void)?

    public init() {
        setupMenuBar()
    }

    private func setupMenuBar() {
        // Создаем статус айтем
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Устанавливаем иконку
        if let button = statusItem?.button {
            // Используем системную иконку или текст
            button.title = "📝"
            button.toolTip = "TranscribeIt"
        }

        // Создаем меню
        menu = NSMenu()

        // Добавляем пункты меню
        let openItem = NSMenuItem(
            title: "Open Transcription Window",
            action: #selector(openTranscriptionClicked),
            keyEquivalent: "o"
        )
        openItem.target = self
        menu?.addItem(openItem)

        menu?.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettingsClicked),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu?.addItem(settingsItem)

        menu?.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(
            title: "About TranscribeIt",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu?.addItem(aboutItem)

        let quitItem = NSMenuItem(
            title: "Quit TranscribeIt",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu?.addItem(quitItem)

        // Устанавливаем меню
        statusItem?.menu = menu

        LogManager.app.info("MenuBar создан")
    }

    @objc private func openTranscriptionClicked() {
        LogManager.app.info("MenuBar: Открыть окно транскрибации")
        onOpenTranscription?()
    }

    @objc private func openSettingsClicked() {
        LogManager.app.info("MenuBar: Открыть настройки")
        onOpenSettings?()
    }

    @objc private func showAbout() {
        LogManager.app.info("MenuBar: О приложении")

        let alert = NSAlert()
        alert.messageText = "TranscribeIt"
        alert.informativeText = """
        Version 1.0.0

        Professional audio transcription for macOS.

        Powered by WhisperKit on Apple Silicon.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitClicked() {
        LogManager.app.info("MenuBar: Выход из приложения")
        onQuit?()
    }

    deinit {
        LogManager.app.info("MenuBarController: deinit")
    }
}

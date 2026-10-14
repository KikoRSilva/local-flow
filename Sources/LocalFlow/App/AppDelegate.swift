import AppKit

/// NSMenuItem that runs a closure.
private final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, enabled: Bool = true, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        state = checked ? .on : .off
        isEnabled = enabled
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let controller = DictationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
        controller.onChange = { [weak self] in self?.refreshIcon() }
        refreshIcon()
        controller.boot()
    }

    private func refreshIcon() {
        let symbol = controller.status == .ready ? "waveform" : "waveform.badge.exclamationmark"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "LocalFlow")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = controller.settings

        menu.addItem(disabled(controller.status.title))
        if controller.status == .ready {
            menu.addItem(disabled("Hold \(settings.hotkey.title) to talk · double-tap for hands-free"))
        }
        if settings.cleanup != .off && !controller.cleanupAvailable {
            menu.addItem(disabled("AI cleanup offline — run `ollama pull \(settings.ollamaModel)`"))
        }
        menu.addItem(.separator())

        menu.addItem(submenu("Hotkey", Hotkey.allCases.map { hotkey in
            ActionItem(hotkey.title, checked: settings.hotkey == hotkey) { [weak self] in
                self?.apply(settings.with(\.hotkey, hotkey))
            }
        }))
        menu.addItem(submenu("Whisper Model", WhisperModel.allCases.map { model in
            let suffix = ModelManager.isDownloaded(model) ? "" : " — download"
            return ActionItem(model.title + suffix, checked: settings.model == model) { [weak self] in
                self?.apply(settings.with(\.model, model))
            }
        }))
        menu.addItem(submenu("Language", Settings.languages.map { language in
            ActionItem(language.title, checked: settings.language == language.code) { [weak self] in
                self?.apply(settings.with(\.language, language.code))
            }
        }))
        menu.addItem(submenu("AI Cleanup", CleanupLevel.allCases.map { level in
            ActionItem(level.title, checked: settings.cleanup == level) { [weak self] in
                self?.apply(settings.with(\.cleanup, level))
            }
        }))
        let models = Array(Set(Settings.suggestedOllamaModels + [settings.ollamaModel])).sorted()
        menu.addItem(submenu("Cleanup Model (Ollama)", models.map { name in
            ActionItem(name, checked: settings.ollamaModel == name) { [weak self] in
                self?.apply(settings.with(\.ollamaModel, name))
            }
        }))
        menu.addItem(ActionItem("Sounds", checked: settings.sounds) { [weak self] in
            self?.apply(settings.with(\.sounds, !settings.sounds))
        })
        menu.addItem(.separator())

        menu.addItem(ActionItem("Paste Last Transcript", enabled: controller.lastTranscript != nil) { [weak self] in
            self?.controller.pasteLastTranscript()
        })
        menu.addItem(ActionItem("Edit Dictionary…") {
            _ = UserDictionary.load() // creates the file with examples on first use
            NSWorkspace.shared.open(AppPaths.dictionary)
        })
        menu.addItem(ActionItem("Open History") {
            NSWorkspace.shared.open(AppPaths.history)
        })
        menu.addItem(ActionItem("Privacy & Security Settings…") {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            url.map { _ = NSWorkspace.shared.open($0) }
        })
        menu.addItem(.separator())
        menu.addItem(ActionItem("Quit LocalFlow", key: "q") { NSApp.terminate(nil) })
    }

    private func apply(_ settings: Settings) {
        controller.update(settings)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        items.forEach(menu.addItem)
        parent.submenu = menu
        return parent
    }
}

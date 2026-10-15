import Foundation

struct Settings: Codable, Equatable {
    var hotkey: Hotkey = .fn
    var model: WhisperModel = .largeV3TurboQ5
    /// nil = auto-detect.
    var language: String?
    var cleanup: CleanupLevel = .medium
    var ollamaModel: String = "qwen3.5:latest"
    var sounds: Bool = true
    var showDockIcon: Bool = false

    init() {}

    /// Tolerant decoding so settings saved by older versions keep loading when new keys are added.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        hotkey = try container.decodeIfPresent(Hotkey.self, forKey: .hotkey) ?? defaults.hotkey
        model = try container.decodeIfPresent(WhisperModel.self, forKey: .model) ?? defaults.model
        language = try container.decodeIfPresent(String.self, forKey: .language)
        cleanup = try container.decodeIfPresent(CleanupLevel.self, forKey: .cleanup) ?? defaults.cleanup
        ollamaModel = try container.decodeIfPresent(String.self, forKey: .ollamaModel) ?? defaults.ollamaModel
        sounds = try container.decodeIfPresent(Bool.self, forKey: .sounds) ?? defaults.sounds
        showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? defaults.showDockIcon
    }

    static let languages: [(code: String?, title: String)] = [
        (nil, "Auto-detect"), ("en", "English"), ("pt", "Português"), ("es", "Español"), ("fr", "Français"),
    ]

    static let suggestedOllamaModels = ["qwen2.5:3b", "qwen2.5:7b", "llama3.2:3b", "gemma3:4b", "qwen3.5:latest"]

    func with<Value>(_ keyPath: WritableKeyPath<Settings, Value>, _ value: Value) -> Settings {
        var copy = self
        copy[keyPath: keyPath] = value
        return copy
    }
}

enum SettingsStore {
    private static let key = "settings.v1"

    static func load() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    static func save(_ settings: Settings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

import Foundation

enum AppPaths {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LocalFlow", isDirectory: true)
    }

    static var dictionary: URL { support.appendingPathComponent("dictionary.json") }
    static var history: URL { support.appendingPathComponent("history.jsonl") }
}

/// User vocabulary, replacements and snippets, stored as a JSON file.
struct UserDictionary: Codable, Sendable {
    /// Spellings to bias whisper and the formatter towards.
    let words: [String]
    /// Spoken phrase → replacement, applied after formatting.
    let replacements: [String: String]
    /// Trigger phrase → expansion text.
    let snippets: [String: String]

    static let empty = UserDictionary(words: [], replacements: [:], snippets: [:])

    static let example = UserDictionary(
        words: ["LocalFlow", "whisper.cpp", "Ollama"],
        replacements: ["local flow": "LocalFlow"],
        snippets: ["my email signature": "Best regards,\nYour Name"]
    )

    static func load() -> UserDictionary {
        let url = AppPaths.dictionary
        guard let data = try? Data(contentsOf: url) else {
            try? save(example)
            return example
        }
        do {
            return try JSONDecoder().decode(UserDictionary.self, from: data)
        } catch {
            Log.app.error("dictionary.json is invalid: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }

    static func save(_ dictionary: UserDictionary) throws {
        try FileManager.default.createDirectory(at: AppPaths.support, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(dictionary).write(to: AppPaths.dictionary, options: .atomic)
    }

    /// Whisper initial prompt; vocabulary in a natural sentence biases spelling.
    var whisperPrompt: String? {
        words.isEmpty ? nil : "Vocabulary: \(words.joined(separator: ", "))."
    }

    /// Applies replacements and snippets on word boundaries, longest phrase first.
    func apply(to text: String) -> String {
        let rules = replacements.merging(snippets) { _, snippet in snippet }
            .sorted { $0.key.count > $1.key.count }
        return rules.reduce(text) { result, rule in
            let pattern = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: rule.key)
                + #"(?![\p{L}\p{N}])"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return result
            }
            let range = NSRange(result.startIndex..., in: result)
            return regex.stringByReplacingMatches(
                in: result, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: rule.value))
        }
    }
}

struct HistoryEntry: Codable, Sendable {
    let date: Date
    let app: String?
    let bundleID: String?
    let rawText: String
    let finalText: String
    let audioSeconds: Double
    let transcribeMs: Int
    let cleanupMs: Int?
    let totalMs: Int
}

enum HistoryStore {
    static func append(_ entry: HistoryEntry) {
        do {
            try FileManager.default.createDirectory(at: AppPaths.support, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let line = try encoder.encode(entry) + Data("\n".utf8)
            if let handle = try? FileHandle(forWritingTo: AppPaths.history) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: AppPaths.history)
            }
        } catch {
            Log.app.error("Could not write history: \(error.localizedDescription, privacy: .public)")
        }
    }
}

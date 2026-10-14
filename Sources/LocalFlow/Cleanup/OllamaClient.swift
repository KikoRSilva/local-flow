import Foundation

enum OllamaError: LocalizedError {
    case badStatus(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let body): return "Ollama returned HTTP \(code): \(body)"
        case .emptyResponse: return "Ollama returned an empty response"
        }
    }
}

/// Minimal client for Ollama's /api/chat on localhost.
struct OllamaClient: Sendable {
    static let defaultBaseURL = URL(string: "http://127.0.0.1:11434")!

    let baseURL: URL

    init(baseURL: URL = OllamaClient.defaultBaseURL) {
        self.baseURL = baseURL
    }

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        struct Options: Encodable {
            let temperature: Double
            let num_predict: Int
        }

        let model: String
        let messages: [Message]
        let stream: Bool
        let keep_alive: String
        let options: Options
        let think: Bool?
    }

    private struct ChatResponse: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }

    func chat(model: String, system: String, user: String, timeout: TimeInterval) async throws -> String {
        let body = ChatRequest(
            model: model,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)],
            stream: false,
            keep_alive: "30m",
            options: .init(temperature: 0, num_predict: 1024),
            // Reasoning models (qwen3*) must not think: it costs seconds per dictation.
            think: Self.isThinkingModel(model) ? false : nil
        )
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw OllamaError.badStatus(status, String(decoding: data.prefix(300), as: UTF8.self))
        }
        let content = try JSONDecoder().decode(ChatResponse.self, from: data).message.content
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OllamaError.emptyResponse }
        return trimmed
    }

    /// Loads the model into memory so the first dictation isn't slow.
    func warmUp(model: String) async throws {
        _ = try await chat(model: model, system: "Reply with OK.", user: "OK", timeout: 120)
    }

    private static func isThinkingModel(_ model: String) -> Bool {
        let name = model.lowercased()
        return name.hasPrefix("qwen3") || name.hasPrefix("deepseek-r1") || name.hasPrefix("gpt-oss")
    }
}

import Foundation

enum WhisperModel: String, Codable, CaseIterable {
    case largeV3TurboQ5 = "ggml-large-v3-turbo-q5_0.bin"
    case largeV3Turbo = "ggml-large-v3-turbo.bin"
    case smallQ5 = "ggml-small-q5_1.bin"

    var title: String {
        switch self {
        case .largeV3TurboQ5: return "Large v3 Turbo Q5 (574 MB, recommended)"
        case .largeV3Turbo: return "Large v3 Turbo (1.6 GB, best)"
        case .smallQ5: return "Small Q5 (190 MB, fastest)"
        }
    }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(rawValue)")!
    }
}

enum ModelManagerError: LocalizedError {
    case downloadFailed(Int)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let status): return "Model download failed (HTTP \(status))"
        }
    }
}

/// Stores ggml models in ~/Library/Application Support/LocalFlow/Models.
enum ModelManager {
    static var directory: URL { AppPaths.support.appendingPathComponent("Models", isDirectory: true) }

    static func localURL(for model: WhisperModel) -> URL {
        directory.appendingPathComponent(model.rawValue)
    }

    static func isDownloaded(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: model).path)
    }

    /// Returns the local model path, downloading it first if needed.
    static func ensure(_ model: WhisperModel) async throws -> URL {
        let destination = localURL(for: model)
        if isDownloaded(model) { return destination }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (tempURL, response) = try await URLSession.shared.download(from: model.downloadURL)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            try? FileManager.default.removeItem(at: tempURL)
            throw ModelManagerError.downloadFailed(status)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }
}

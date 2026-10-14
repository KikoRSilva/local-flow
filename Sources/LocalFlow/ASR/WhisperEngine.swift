import CWhisper
import Foundation

enum WhisperError: LocalizedError {
    case modelLoadFailed(String)
    case notLoaded
    case inferenceFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path): return "Could not load whisper model at \(path)"
        case .notLoaded: return "Whisper model is not loaded yet"
        case .inferenceFailed(let code): return "Whisper inference failed (code \(code))"
        }
    }
}

/// whisper.cpp wrapper. All calls are serialised on one queue; the context is
/// not thread-safe. Uses the Metal backend (use_gpu) with flash attention.
final class WhisperEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "localflow.whisper", qos: .userInitiated)
    private var context: OpaquePointer?

    init() {
        whisper_log_set({ _, _, _ in }, nil)
    }

    deinit {
        if let context { whisper_free(context) }
    }

    func load(modelPath: String) async throws {
        try await run {
            if let old = self.context {
                whisper_free(old)
                self.context = nil
            }
            var params = whisper_context_default_params()
            params.use_gpu = true
            params.flash_attn = true
            guard let ctx = whisper_init_from_file_with_params(modelPath, params) else {
                throw WhisperError.modelLoadFailed(modelPath)
            }
            self.context = ctx
        }
    }

    /// - Parameters:
    ///   - language: ISO code ("en", "pt") or nil for auto-detect.
    ///   - prompt: biasing text, e.g. vocabulary from the user dictionary.
    func transcribe(_ samples: [Float], language: String?, prompt: String?) async throws -> String {
        try await run {
            guard let ctx = self.context else { throw WhisperError.notLoaded }
            let padded = Self.padToMinimum(samples)
            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.print_progress = false
            params.print_realtime = false
            params.print_timestamps = false
            params.print_special = false
            params.translate = false
            params.no_timestamps = true
            params.suppress_blank = true
            params.n_threads = Int32(max(4, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))

            let code: Int32 = (language ?? "auto").withCString { lang in
                params.language = lang
                return Self.withOptionalCString(prompt) { promptPtr in
                    params.initial_prompt = promptPtr
                    return padded.withUnsafeBufferPointer { buf in
                        whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
                    }
                }
            }
            guard code == 0 else { throw WhisperError.inferenceFailed(code) }

            let segments = (0..<whisper_full_n_segments(ctx)).compactMap { i -> String? in
                whisper_full_get_segment_text(ctx, i).map { String(cString: $0) }
            }
            return segments.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    /// whisper.cpp rejects input shorter than 1 s; pad with silence.
    private static func padToMinimum(_ samples: [Float]) -> [Float] {
        let minimum = Int(AudioRecorder.sampleRate * 1.1)
        guard samples.count < minimum else { return samples }
        return samples + [Float](repeating: 0, count: minimum - samples.count)
    }

    private static func withOptionalCString<R>(_ string: String?, _ body: (UnsafePointer<CChar>?) -> R) -> R {
        guard let string, !string.isEmpty else { return body(nil) }
        return string.withCString { body($0) }
    }
}

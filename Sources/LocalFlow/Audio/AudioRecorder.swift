@preconcurrency import AVFoundation
import Foundation

enum AudioRecorderError: LocalizedError {
    case noInputDevice
    case converterUnavailable

    var errorDescription: String? {
        switch self {
        case .noInputDevice: return "No microphone available"
        case .converterUnavailable: return "Cannot convert microphone audio to 16 kHz"
        }
    }
}

/// Captures the default input device as 16 kHz mono Float32 (whisper's native format).
/// No echo cancellation, noise suppression or AGC: whisper does best on raw audio.
final class AudioRecorder: @unchecked Sendable {
    static let sampleRate: Double = 16_000

    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var buffer: [Float] = []
    private var lastLevelEmit = Date.distantPast

    /// Called on the main queue with a 0...1 level, ~25 times per second.
    var onLevel: ((Float) -> Void)?

    func start() throws {
        stopEngine()
        lock.withLock { buffer = [] }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw AudioRecorderError.noInputDevice
        }
        guard
            let outFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: inFormat, to: outFormat)
        else {
            throw AudioRecorderError.converterUnavailable
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] pcm, _ in
            self?.consume(pcm, converter: converter, outFormat: outFormat)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    /// Stops capture and returns everything recorded since `start()`.
    func stop() -> [Float] {
        stopEngine()
        return lock.withLock { buffer }
    }

    private func stopEngine() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    private func consume(_ pcm: AVAudioPCMBuffer, converter: AVAudioConverter, outFormat: AVAudioFormat) {
        let ratio = outFormat.sampleRate / pcm.format.sampleRate
        let capacity = AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }

        // The input block runs synchronously inside convert(to:).
        nonisolated(unsafe) var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return pcm
        }
        if let error {
            Log.audio.error("Audio conversion failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let channel = out.floatChannelData?[0], out.frameLength > 0 else { return }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        lock.withLock { buffer.append(contentsOf: samples) }
        emitLevel(samples)
    }

    private func emitLevel(_ samples: [Float]) {
        let now = Date()
        guard now.timeIntervalSince(lastLevelEmit) > 0.04, let onLevel else { return }
        lastLevelEmit = now
        let level = min(1, Self.rms(samples) * 12)
        DispatchQueue.main.async { onLevel(level) }
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(samples.count)).squareRoot()
    }
}

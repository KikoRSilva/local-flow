import AppKit
import AVFoundation
import Foundation

/// Orchestrates hotkey → record → whisper → optional LLM cleanup → paste.
@MainActor
final class DictationController {
    enum Status: Equatable {
        case starting
        case needsPermissions(String)
        case downloadingModel(String)
        case loadingModel
        case ready
        case failed(String)

        var title: String {
            switch self {
            case .starting: return "Starting…"
            case .needsPermissions(let what): return "Needs permission: \(what)"
            case .downloadingModel(let name): return "Downloading \(name)…"
            case .loadingModel: return "Loading model…"
            case .ready: return "Ready"
            case .failed(let message): return "Error: \(message)"
            }
        }
    }

    private(set) var settings: Settings
    private(set) var status: Status = .starting { didSet { onChange?() } }
    private(set) var cleanupAvailable = false { didSet { onChange?() } }
    private(set) var lastTranscript: String?
    var onChange: (() -> Void)?

    private let recorder = AudioRecorder()
    private let whisper = WhisperEngine()
    private let ollama = OllamaClient()
    private let panel = StatusPanel()
    private lazy var tap = EventTap { [weak self] type, event in
        self?.handle(type, event) ?? false
    }

    private var state: DictationState = .idle
    private var timer: DispatchWorkItem?
    private var context: TextContext = .empty
    private var modelLoaded = false

    init() {
        settings = SettingsStore.load()
        recorder.onLevel = { [weak self] level in
            MainActor.assumeIsolated { self?.panel.model.level = level }
        }
    }

    // MARK: - Lifecycle

    func boot() {
        requestPermissions()
        startTapWhenPermitted()
        Task { await loadModel() }
        Task { await warmUpCleanup() }
    }

    func shutdown() {
        whisper.shutdown()
    }

    func update(_ newSettings: Settings) {
        let previous = settings
        settings = newSettings
        SettingsStore.save(newSettings)
        onChange?()
        if previous.model != newSettings.model {
            Task { await loadModel() }
        }
        if previous.ollamaModel != newSettings.ollamaModel
            || (previous.cleanup == .off && newSettings.cleanup != .off) {
            Task { await warmUpCleanup() }
        }
    }

    func pasteLastTranscript() {
        guard let lastTranscript else { return }
        Paster.paste(lastTranscript)
    }

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted { Log.app.error("Microphone access denied") }
        }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
    }

    private func startTapWhenPermitted() {
        if tap.start() {
            if case .needsPermissions = status { status = modelLoaded ? .ready : .loadingModel }
            return
        }
        status = .needsPermissions("Accessibility + Input Monitoring")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.startTapWhenPermitted() }
    }

    private func loadModel() async {
        let model = settings.model
        modelLoaded = false
        do {
            if !ModelManager.isDownloaded(model) { status = .downloadingModel(model.title) }
            let url = try await ModelManager.ensure(model)
            status = .loadingModel
            try await whisper.load(modelPath: url.path)
            guard model == settings.model else { return } // superseded by a newer choice
            modelLoaded = true
            if tap.isRunning { status = .ready }
            Log.app.info("Loaded \(model.rawValue, privacy: .public)")
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func warmUpCleanup() async {
        guard settings.cleanup != .off else { return }
        do {
            try await ollama.warmUp(model: settings.ollamaModel)
            cleanupAvailable = true
        } catch {
            cleanupAvailable = false
            Log.pipeline.error("Ollama unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Hotkey

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch type {
        case .flagsChanged where settings.hotkey.keyCodes.contains(keyCode):
            let now = ProcessInfo.processInfo.systemUptime
            dispatch(settings.hotkey.isDown(event.flags) ? .hotkeyDown(now) : .hotkeyUp(now))
            return true
        case .keyDown where state.isActive:
            if keyCode == KeyCode.escape {
                dispatch(.escape)
                return true
            }
            if keyCode == KeyCode.space && state.isHolding {
                dispatch(.space)
                return true
            }
            if state.isHolding { dispatch(.otherKey) }
            return false
        default:
            return false
        }
    }

    private func dispatch(_ event: DictationEvent) {
        let transition = DictationMachine.reduce(state, event)
        guard transition.state != state || !transition.effects.isEmpty else { return }
        state = transition.state
        transition.effects.forEach(perform)
    }

    private func perform(_ effect: DictationEffect) {
        switch effect {
        case .start:
            startRecording()
        case .lock:
            cancelTimer()
            Sound.lock.play(enabled: settings.sounds)
            panel.show(.locked)
            schedule(after: DictationMachine.maxDuration) { $0.dispatch(.maxDuration) }
        case .armDoubleTapTimer:
            schedule(after: DictationMachine.doubleTapWindow) { $0.dispatch(.doubleTapTimeout) }
        case .finish:
            cancelTimer()
            let samples = recorder.stop()
            Sound.stop.play(enabled: settings.sounds)
            panel.show(.transcribing)
            let capturedContext = context
            Task { await process(samples, context: capturedContext) }
        case .cancel:
            cancelTimer()
            _ = recorder.stop()
            panel.show(.hidden)
        }
    }

    private func startRecording() {
        guard modelLoaded else {
            state = .idle
            panel.flash(status.title)
            return
        }
        context = AXContextReader.capture()
        do {
            try recorder.start()
        } catch {
            state = .idle
            Sound.error.play(enabled: settings.sounds)
            panel.flash(error.localizedDescription)
            return
        }
        Sound.start.play(enabled: settings.sounds)
        panel.model.level = 0
        panel.show(.recording)
        schedule(after: DictationMachine.maxDuration) { $0.dispatch(.maxDuration) }
    }

    private func schedule(after seconds: TimeInterval, _ action: @escaping (DictationController) -> Void) {
        cancelTimer()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        timer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Pipeline

    private static let minSpeechSeconds = 0.3
    private static let silenceRMS: Float = 0.004
    private static let cleanupTimeout: TimeInterval = 6

    private func process(_ samples: [Float], context: TextContext) async {
        let started = Date()
        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        guard seconds >= Self.minSpeechSeconds, AudioRecorder.rms(samples) > Self.silenceRMS else {
            panel.flash("No speech detected", seconds: 1.2)
            return
        }

        let dictionary = UserDictionary.load()
        let raw: String
        do {
            raw = try await whisper.transcribe(samples, language: settings.language, prompt: dictionary.whisperPrompt)
        } catch {
            Sound.error.play(enabled: settings.sounds)
            panel.flash(error.localizedDescription)
            return
        }
        let transcribed = Date()
        let transcript = TextPostProcessor.stripArtifacts(raw)
        guard !transcript.isEmpty else {
            panel.flash("No speech detected", seconds: 1.2)
            return
        }

        let (formatted, cleanupMs) = await cleanUp(transcript, context: context, vocabulary: dictionary.words)
        let finalText = TextPostProcessor.join(dictionary.apply(to: formatted), after: context.beforeText)

        if context.isSecureField {
            panel.flash("Secure field: not pasting")
        } else {
            Paster.paste(finalText)
            panel.show(.hidden)
        }
        lastTranscript = finalText.trimmingCharacters(in: .whitespaces)

        let entry = HistoryEntry(
            date: started, app: context.appName, bundleID: context.bundleID,
            rawText: transcript, finalText: finalText, audioSeconds: seconds,
            transcribeMs: Int(transcribed.timeIntervalSince(started) * 1000),
            cleanupMs: cleanupMs, totalMs: Int(Date().timeIntervalSince(started) * 1000))
        Log.pipeline.info(
            "Dictation \(seconds, format: .fixed(precision: 1))s audio → whisper \(entry.transcribeMs)ms, cleanup \(cleanupMs ?? 0)ms, total \(entry.totalMs)ms")
        HistoryStore.append(entry)
    }

    /// Returns the formatted text and the time spent, or the raw transcript if
    /// cleanup is off, too short to matter, slow, or produced something unsafe.
    private func cleanUp(_ transcript: String, context: TextContext, vocabulary: [String]) async -> (String, Int?) {
        guard settings.cleanup != .off, TextPostProcessor.wordCount(transcript) >= 3 else {
            return (transcript, nil)
        }
        let started = Date()
        do {
            let output = try await ollama.chat(
                model: settings.ollamaModel,
                system: CleanupPrompt.system(level: settings.cleanup, category: context.category, vocabulary: vocabulary),
                user: CleanupPrompt.user(transcript: transcript, context: context),
                timeout: Self.cleanupTimeout)
            cleanupAvailable = true
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            guard let safe = CleanupPrompt.sanitize(output: output, transcript: transcript) else {
                Log.pipeline.warning("Cleanup output rejected; using raw transcript")
                return (transcript, elapsed)
            }
            return (safe, elapsed)
        } catch {
            cleanupAvailable = false
            Log.pipeline.error("Cleanup failed, pasting raw: \(error.localizedDescription, privacy: .public)")
            return (transcript, nil)
        }
    }
}

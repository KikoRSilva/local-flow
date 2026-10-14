import AppKit

enum Sound {
    case start
    case stop
    case lock
    case error

    private var systemName: String {
        switch self {
        case .start: return "Tink"
        case .stop: return "Pop"
        case .lock: return "Bottle"
        case .error: return "Basso"
        }
    }

    @MainActor
    func play(enabled: Bool) {
        guard enabled, let sound = NSSound(named: systemName)?.copy() as? NSSound else { return }
        sound.volume = 0.35
        sound.play()
    }
}

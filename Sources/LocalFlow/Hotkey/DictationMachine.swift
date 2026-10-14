import Foundation

/// Push-to-talk / hands-free gesture logic:
/// hold = push-to-talk; a short tap followed by a second press within the
/// double-tap window locks hands-free; pressing again while locked finishes.
enum DictationMode: Equatable {
    case holding
    case awaitingSecondTap
    case locked
}

enum DictationState: Equatable {
    case idle
    case recording(mode: DictationMode, startedAt: TimeInterval)

    var isActive: Bool { self != .idle }

    var isHolding: Bool {
        if case .recording(.holding, _) = self { return true }
        return false
    }
}

enum DictationEvent {
    case hotkeyDown(TimeInterval)
    case hotkeyUp(TimeInterval)
    case doubleTapTimeout
    case escape
    case space
    case otherKey
    case maxDuration
}

enum DictationEffect: Equatable {
    case start
    case lock
    case armDoubleTapTimer
    case finish
    case cancel
}

struct DictationTransition {
    let state: DictationState
    let effects: [DictationEffect]
}

enum DictationMachine {
    static let holdThreshold: TimeInterval = 0.5
    static let doubleTapWindow: TimeInterval = 0.5
    static let maxDuration: TimeInterval = 20 * 60

    static func reduce(_ state: DictationState, _ event: DictationEvent) -> DictationTransition {
        switch (state, event) {
        case (.idle, .hotkeyDown(let t)):
            return DictationTransition(state: .recording(mode: .holding, startedAt: t), effects: [.start])

        case (.recording(.holding, let start), .hotkeyUp(let t)):
            if t - start >= holdThreshold {
                return DictationTransition(state: .idle, effects: [.finish])
            }
            return DictationTransition(
                state: .recording(mode: .awaitingSecondTap, startedAt: start),
                effects: [.armDoubleTapTimer]
            )

        case (.recording(.awaitingSecondTap, let start), .hotkeyDown):
            return DictationTransition(state: .recording(mode: .locked, startedAt: start), effects: [.lock])

        case (.recording(.awaitingSecondTap, _), .doubleTapTimeout):
            return DictationTransition(state: .idle, effects: [.cancel])

        case (.recording(.locked, _), .hotkeyDown):
            return DictationTransition(state: .idle, effects: [.finish])

        case (.recording(.holding, let start), .space):
            return DictationTransition(state: .recording(mode: .locked, startedAt: start), effects: [.lock])

        case (.recording(.holding, _), .otherKey):
            // The hotkey is being used as a modifier for some other shortcut.
            return DictationTransition(state: .idle, effects: [.cancel])

        case (.recording, .escape):
            return DictationTransition(state: .idle, effects: [.cancel])

        case (.recording, .maxDuration):
            return DictationTransition(state: .idle, effects: [.finish])

        default:
            return DictationTransition(state: state, effects: [])
        }
    }
}

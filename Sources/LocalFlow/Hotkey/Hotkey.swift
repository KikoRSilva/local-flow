import CoreGraphics

/// Modifier-only hotkeys, detected from flagsChanged events.
enum Hotkey: String, Codable, CaseIterable {
    case fn
    case rightOption
    case rightCommand

    var title: String {
        switch self {
        case .fn: return "fn / Globe"
        case .rightOption: return "Right Option"
        case .rightCommand: return "Right Command"
        }
    }

    var keyCodes: Set<Int64> {
        switch self {
        case .fn: return [63, 179] // kVK_Function, Globe
        case .rightOption: return [61]
        case .rightCommand: return [54]
        }
    }

    /// Device-dependent flag bit telling us whether this exact key is down.
    private var flagMask: UInt64 {
        switch self {
        case .fn: return CGEventFlags.maskSecondaryFn.rawValue
        case .rightOption: return 0x40 // NX_DEVICERALTKEYMASK
        case .rightCommand: return 0x10 // NX_DEVICERCMDKEYMASK
        }
    }

    func isDown(_ flags: CGEventFlags) -> Bool {
        flags.rawValue & flagMask != 0
    }
}

enum KeyCode {
    static let escape: Int64 = 53
    static let space: Int64 = 49
}

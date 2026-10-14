import CoreGraphics
import Foundation

/// Session-level CGEventTap for key/modifier events. The handler runs on the
/// main run loop and returns `true` to swallow the event.
/// Only touched on the main thread (tap source is on the main run loop).
final class EventTap: @unchecked Sendable {
    typealias Handler = @MainActor (CGEventType, CGEvent) -> Bool

    private let handler: Handler
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Returns false when macOS refuses the tap (missing Input Monitoring / Accessibility).
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    me.reenable()
                    return Unmanaged.passUnretained(event)
                }
                // The tap's run-loop source lives on the main run loop.
                nonisolated(unsafe) let unsafeEvent = event
                let swallow = MainActor.assumeIsolated { me.handler(type, unsafeEvent) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    private func reenable() {
        guard let tap else { return }
        Log.hotkey.warning("Event tap was disabled, re-enabling")
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

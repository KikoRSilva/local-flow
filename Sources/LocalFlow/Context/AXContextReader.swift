import AppKit
import ApplicationServices

/// Snapshot of where the user is typing, captured at dictation start.
struct TextContext: Sendable {
    let appName: String?
    let bundleID: String?
    let windowTitle: String?
    let beforeText: String
    let selectedText: String
    let afterText: String
    let isSecureField: Bool

    var category: AppCategory { AppCategory.classify(bundleID: bundleID, windowTitle: windowTitle) }

    static let empty = TextContext(
        appName: nil, bundleID: nil, windowTitle: nil,
        beforeText: "", selectedText: "", afterText: "", isSecureField: false)
}

/// Reads the focused text field through the Accessibility API
/// (value + selected range, ≤500 chars either side of the cursor).
enum AXContextReader {
    static let maxContextChars = 500

    static func capture() -> TextContext {
        let app = NSWorkspace.shared.frontmostApplication
        let appElement = app.map { AXUIElementCreateApplication($0.processIdentifier) }

        if let appElement {
            // Electron/Chromium only build their AX tree when asked.
            AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }

        let windowTitle = appElement
            .flatMap { element(of: $0, kAXFocusedWindowAttribute) }
            .flatMap { string(of: $0, kAXTitleAttribute) }

        guard let focused = element(of: AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute) else {
            return TextContext(
                appName: app?.localizedName, bundleID: app?.bundleIdentifier, windowTitle: windowTitle,
                beforeText: "", selectedText: "", afterText: "", isSecureField: false)
        }

        let role = string(of: focused, kAXRoleAttribute)
        let subrole = string(of: focused, kAXSubroleAttribute)
        let isSecure = role == "AXSecureTextField" || subrole == kAXSecureTextFieldSubrole
        let (before, selected, after) = isSecure ? ("", "", "") : textAroundCursor(in: focused)

        return TextContext(
            appName: app?.localizedName,
            bundleID: app?.bundleIdentifier,
            windowTitle: windowTitle,
            beforeText: before,
            selectedText: selected,
            afterText: after,
            isSecureField: isSecure
        )
    }

    private static func textAroundCursor(in element: AXUIElement) -> (String, String, String) {
        guard let value = string(of: element, kAXValueAttribute) else { return ("", "", "") }
        let text = value as NSString
        guard let range = selectedRange(of: element),
              range.location >= 0, range.location + range.length <= text.length
        else {
            // No caret info: treat the whole value as preceding text.
            return (String(value.suffix(maxContextChars)), "", "")
        }
        let before = text.substring(to: range.location)
        let selected = text.substring(with: NSRange(location: range.location, length: range.length))
        let after = text.substring(from: range.location + range.length)
        return (
            String(before.suffix(maxContextChars)),
            String(selected.prefix(maxContextChars)),
            String(after.prefix(maxContextChars))
        )
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func element(of element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { return nil }
        // swiftlint:disable:next force_cast
        return (raw as! AXUIElement)
    }

    private static func string(of element: AXUIElement, _ attribute: String) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw as? String
    }
}

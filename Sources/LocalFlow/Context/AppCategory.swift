import Foundation

/// Where the text is going, used to pick a writing style for cleanup.
enum AppCategory: String, Codable {
    case email
    case workMessaging
    case personalMessaging
    case developer
    case other

    private static let byBundleID: [String: AppCategory] = [
        "com.apple.mail": .email,
        "com.microsoft.Outlook": .email,
        "com.readdle.smartemail-Mac": .email,
        "com.superhuman.electron": .email,
        "it.bloop.airmail2": .email,
        "com.tinyspeck.slackmacgap": .workMessaging,
        "com.microsoft.teams2": .workMessaging,
        "com.microsoft.teams": .workMessaging,
        "us.zoom.xos": .workMessaging,
        "com.linear": .workMessaging,
        "notion.id": .workMessaging,
        "com.apple.MobileSMS": .personalMessaging,
        "net.whatsapp.WhatsApp": .personalMessaging,
        "ru.keepcoder.Telegram": .personalMessaging,
        "org.whispersystems.signal-desktop": .personalMessaging,
        "com.hnc.Discord": .personalMessaging,
        "com.facebook.archon": .personalMessaging,
        "com.apple.dt.Xcode": .developer,
        "com.microsoft.VSCode": .developer,
        "com.todesktop.230313mzl4w4u92": .developer, // Cursor
        "dev.zed.Zed": .developer,
        "com.apple.Terminal": .developer,
        "com.googlecode.iterm2": .developer,
        "com.mitchellh.ghostty": .developer,
        "dev.warp.Warp-Stable": .developer,
    ]

    /// Browser tabs are classified by window title, since we don't read the URL.
    private static let byTitleKeyword: [(String, AppCategory)] = [
        ("gmail", .email),
        ("outlook", .email),
        ("inbox", .email),
        ("slack", .workMessaging),
        ("teams", .workMessaging),
        ("linear", .workMessaging),
        ("whatsapp", .personalMessaging),
        ("messenger", .personalMessaging),
        ("github", .developer),
    ]

    static func classify(bundleID: String?, windowTitle: String?) -> AppCategory {
        if let bundleID, let category = byBundleID[bundleID] { return category }
        let title = windowTitle?.lowercased() ?? ""
        return byTitleKeyword.first { title.contains($0.0) }?.1 ?? .other
    }

    var styleInstruction: String {
        switch self {
        case .email:
            return "The text is going into an email. Use complete, well-punctuated sentences and a polished tone. Use paragraphs where the speaker clearly changes topic."
        case .workMessaging:
            return "The text is going into a work chat. Keep it concise and professional-casual. A single short sentence does not need a trailing period."
        case .personalMessaging:
            return "The text is going into a personal chat. Keep the speaker's casual tone; light punctuation is fine."
        case .developer:
            return "The text is going into a code editor, terminal, or developer tool. Keep technical terms, code identifiers, commands and file names exactly as spoken. Do not add markdown."
        case .other:
            return "Use clear, natural punctuation and capitalization."
        }
    }
}

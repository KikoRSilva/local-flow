import Foundation

/// Deterministic text steps that run regardless of the LLM.
enum TextPostProcessor {
    private static let artifactPattern = try! NSRegularExpression(
        pattern: #"\[[^\]]*\]|\((?:music|silence|applause|laughs?|inaudible|blank_audio)[^)]*\)|\*[^*]+\*"#,
        options: [.caseInsensitive]
    )

    /// Common whisper hallucinations on near-silent input.
    private static let hallucinations: Set<String> = [
        "thank you.", "thanks for watching!", "thank you for watching.", "you", "bye.", ".", "obrigado.",
        "legendas pela comunidade amara.org",
    ]

    static func stripArtifacts(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        let cleaned = artifactPattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return hallucinations.contains(cleaned.lowercased()) ? "" : cleaned
    }

    /// Adds a leading space when inserting right after a word.
    static func join(_ text: String, after before: String) -> String {
        guard let last = before.last, let first = text.first else { return text }
        let noSpaceAfter: Set<Character> = ["(", "[", "{", "\"", "'", "/", "-", "@", "#"]
        let needsSpace = !last.isWhitespace && !noSpaceAfter.contains(last) && !first.isPunctuation
        return needsSpace ? " " + text : text
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

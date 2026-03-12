//
//  HighlightrManager.swift
//  Amazon Bedrock Client for Mac
//

import AppKit
import Highlightr

final class HighlightrManager: @unchecked Sendable {
    static let shared = HighlightrManager()

    private let highlightr: Highlightr?
    private let lock = NSLock()

    private init() {
        highlightr = Highlightr()
    }

    func highlight(code: String, language: String?, fontSize: CGFloat, isDark: Bool) -> NSAttributedString {
        lock.lock()
        defer { lock.unlock() }

        guard let highlightr = highlightr else {
            return fallback(code: code, fontSize: fontSize, isDark: isDark)
        }

        highlightr.setTheme(to: isDark ? "github-dark" : "github")
        highlightr.theme.setCodeFont(.monospacedSystemFont(ofSize: fontSize, weight: .regular))

        let lang = (language ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !lang.isEmpty, let result = highlightr.highlight(code, as: lang) {
            return result
        }
        if let result = highlightr.highlight(code) {
            return result
        }
        return fallback(code: code, fontSize: fontSize, isDark: isDark)
    }

    private func fallback(code: String, fontSize: CGFloat, isDark: Bool) -> NSAttributedString {
        NSAttributedString(string: code, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: isDark ? NSColor(white: 0.85, alpha: 1) : NSColor(white: 0.15, alpha: 1)
        ])
    }
}

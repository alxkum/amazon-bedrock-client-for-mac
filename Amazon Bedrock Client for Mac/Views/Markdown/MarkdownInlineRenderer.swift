//
//  MarkdownInlineRenderer.swift
//  Amazon Bedrock Client for Mac
//

import Foundation
import MarkdownKit

// Utility for extracting plain text from MarkdownKit.Text
// Used by search offset tracking
enum MarkdownTextHelper {
    static func textContent(_ text: MarkdownKit.Text) -> String {
        var result = ""
        for fragment in text {
            switch fragment {
            case .text(let str):
                result += String(str)
            case .code(let str):
                result += String(str)
            case .emph(let inner):
                result += textContent(inner)
            case .strong(let inner):
                result += textContent(inner)
            case .link(let inner, _, _):
                result += textContent(inner)
            case .autolink(_, let str):
                result += String(str)
            case .image(let alt, _, _):
                result += textContent(alt)
            case .html(let str):
                result += String(str)
            case .softLineBreak:
                result += " "
            case .hardLineBreak:
                result += "\n"
            case .delimiter(let char, let count, _):
                result += String(repeating: String(char), count: count)
            case .custom:
                break
            }
        }
        return result
    }
}

/*
 *  Extensions.swift
 *  Vendored from HighlighterSwift (MIT License)
 *  Copyright 2026, Tony Smith
 *  Copyright 2016, Juan-Pablo Illanes
 */

#if os(OSX)
import AppKit
#elseif os(iOS)
import UIKit
#endif


extension NSMutableAttributedString {

    func addParaStyle(with paraStyle: NSParagraphStyle) {
        beginEditing()
        self.enumerateAttribute(.paragraphStyle, in: NSMakeRange(0, self.length)) { (value, range, stop) in
            if let _ = value as? NSParagraphStyle {
                removeAttribute(.paragraphStyle, range: range)
                addAttribute(.paragraphStyle, value: paraStyle, range: range)
            }
        }
        endEditing()
    }
}


extension NSAttributedString {

    func components(separatedBy separator: String) -> [NSAttributedString] {
        var parts: [NSAttributedString] = []
        let subStrings = self.string.components(separatedBy: separator)
        var range = NSRange(location: 0, length: 0)
        for string in subStrings {
            range.length = string.utf16.count
            let attributedString = attributedSubstring(from: range)
            parts.append(attributedString)
            range.location += range.length + separator.utf16.count
        }
        return parts
    }
}


extension Scanner {

    func getNextCharacter(in outer: String) -> String {

        let string: NSString = self.string as NSString
        let idx: Int = self.currentIndex.utf16Offset(in: outer)
        let nextChar: String = string.substring(with: NSMakeRange(idx, 1))
        return nextChar
    }

    func skipNextCharacter() {

        self.currentIndex = self.string.index(after: self.currentIndex)
    }
}

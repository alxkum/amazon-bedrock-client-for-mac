//
//  MarkdownAttributedStringBuilder.swift
//  Amazon Bedrock Client for Mac
//

import AppKit
import MarkdownKit

struct CodeBlockInfo {
    let fullRange: NSRange   // label + code (for background panel drawing)
    let codeRange: NSRange   // code only (for copy button)
    let rawCode: String
    let language: String?
}

class MarkdownAttributedStringBuilder {
    let fontSize: CGFloat
    let isDark: Bool

    private(set) var result = NSMutableAttributedString()
    private(set) var codeBlocks: [CodeBlockInfo] = []
    private(set) var blockquoteRanges: [NSRange] = []

    private var baseFont: NSFont { .systemFont(ofSize: fontSize) }
    private var baseColor: NSColor {
        isDark ? NSColor(white: 0.88, alpha: 1) : NSColor(white: 0.1, alpha: 1)
    }
    private var secondaryColor: NSColor {
        isDark ? NSColor(white: 0.56, alpha: 1) : NSColor(white: 0.42, alpha: 1)
    }
    private var codeBackground: NSColor {
        isDark ? NSColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1) : NSColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1)
    }
    private var inlineCodeBackground: NSColor {
        isDark ? NSColor(red: 0.18, green: 0.20, blue: 0.23, alpha: 1) : NSColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1)
    }
    private var headerBackground: NSColor {
        isDark ? NSColor(red: 0.13, green: 0.15, blue: 0.18, alpha: 1) : NSColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1)
    }
    private var linkColor: NSColor {
        isDark ? NSColor(red: 0.30, green: 0.56, blue: 0.97, alpha: 1) : NSColor(red: 0.17, green: 0.40, blue: 0.81, alpha: 1)
    }
    private var blockquoteBarColor: NSColor {
        isDark ? NSColor(white: 0.5, alpha: 0.4) : NSColor(white: 0.5, alpha: 0.4)
    }

    init(fontSize: CGFloat, isDark: Bool) {
        self.fontSize = fontSize
        self.isDark = isDark
    }

    func build(from block: Block) -> NSMutableAttributedString {
        result = NSMutableAttributedString()
        codeBlocks = []
        blockquoteRanges = []

        if case .document(let blocks) = block {
            appendBlocks(blocks, indent: 0)
        } else {
            appendBlock(block, indent: 0)
        }

        // Remove trailing newlines
        while result.length > 0 && result.string.hasSuffix("\n\n") {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }

        return result
    }

    // MARK: - Block Rendering

    private func appendBlocks(_ blocks: Blocks, indent: CGFloat) {
        for (idx, block) in blocks.enumerated() {
            appendBlock(block, indent: indent)
            // Add paragraph spacing between blocks (but not after the last one)
            if idx < blocks.count - 1 {
                if !isCodeBlock(block) && !isCodeBlock(idx + 1 < blocks.count ? blocks[idx + 1] : nil) {
                    appendNewline()
                }
            }
        }
    }

    private func isCodeBlock(_ block: Block?) -> Bool {
        guard let block = block else { return false }
        switch block {
        case .fencedCode, .indentedCode: return true
        default: return false
        }
    }

    private func appendBlock(_ block: Block, indent: CGFloat) {
        switch block {
        case .document(let blocks):
            appendBlocks(blocks, indent: indent)

        case .paragraph(let text):
            appendParagraph(text, indent: indent)

        case .heading(let level, let text):
            appendHeading(level: level, text: text)

        case .blockquote(let blocks):
            appendBlockquote(blocks, indent: indent)

        case .list(let start, _, let items):
            appendList(start: start, items: items, indent: indent)

        case .listItem(_, _, let blocks):
            appendBlocks(blocks, indent: indent)

        case .fencedCode(let info, let lines):
            appendCodeBlock(info: info, lines: lines)

        case .indentedCode(let lines):
            appendCodeBlock(info: nil, lines: lines)

        case .thematicBreak:
            appendThematicBreak()

        case .table(let header, let alignments, let rows):
            appendTable(header: header, alignments: alignments, rows: rows)

        case .htmlBlock(let lines):
            let text = lines.joined(separator: "\n")
            let attrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: secondaryColor
            ]
            result.append(NSAttributedString(string: text + "\n", attributes: attrs))

        case .definitionList(let definitions):
            appendDefinitionList(definitions, indent: indent)

        case .referenceDef:
            break

        case .custom:
            break
        }
    }

    // MARK: - Paragraph

    private func appendParagraph(_ text: MarkdownKit.Text, indent: CGFloat) {
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.paragraphSpacing = 4
        if indent > 0 {
            paraStyle.headIndent = indent
            paraStyle.firstLineHeadIndent = indent
        }

        let attrStr = attributedString(from: text, baseFont: baseFont, baseColor: baseColor)
        attrStr.addAttribute(.paragraphStyle, value: paraStyle, range: NSRange(location: 0, length: attrStr.length))
        result.append(attrStr)
        appendNewline()
    }

    // MARK: - Heading

    private func appendHeading(level: Int, text: MarkdownKit.Text) {
        let headingSize: CGFloat
        switch level {
        case 1: headingSize = fontSize + 8
        case 2: headingSize = fontSize + 4
        case 3: headingSize = fontSize + 2
        case 4: headingSize = fontSize + 1
        default: headingSize = fontSize
        }

        let font = NSFont.boldSystemFont(ofSize: headingSize)
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.paragraphSpacingBefore = level <= 2 ? 8 : 4
        paraStyle.paragraphSpacing = 2

        let attrStr = attributedString(from: text, baseFont: font, baseColor: baseColor)
        attrStr.addAttribute(.paragraphStyle, value: paraStyle, range: NSRange(location: 0, length: attrStr.length))
        result.append(attrStr)
        appendNewline()
    }

    // MARK: - Blockquote

    private func appendBlockquote(_ blocks: Blocks, indent: CGFloat) {
        let quoteIndent: CGFloat = indent + 20
        let startPos = result.length

        for (idx, block) in blocks.enumerated() {
            appendBlock(block, indent: quoteIndent)
            if idx < blocks.count - 1 {
                appendNewline()
            }
        }

        let range = NSRange(location: startPos, length: result.length - startPos)
        blockquoteRanges.append(range)

        // Apply secondary color to blockquote content
        result.addAttribute(.foregroundColor, value: secondaryColor, range: range)

        // Apply indent via paragraph style
        result.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, subRange, _ in
            let para = (value as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            let newPara = para.mutableCopy() as! NSMutableParagraphStyle
            newPara.headIndent = quoteIndent
            newPara.firstLineHeadIndent = quoteIndent
            result.addAttribute(.paragraphStyle, value: newPara, range: subRange)
        }
    }

    // MARK: - List

    private func appendList(start: Int?, items: Blocks, indent: CGFloat) {
        let isOrdered = start != nil
        let startNum = start ?? 1
        let bulletIndent = indent + 20
        let textIndent = indent + 32

        for (idx, item) in items.enumerated() {
            let prefix: String
            if isOrdered {
                prefix = "\(startNum + idx).\t"
            } else {
                prefix = "\u{2022}\t"
            }

            let paraStyle = NSMutableParagraphStyle()
            paraStyle.headIndent = textIndent
            paraStyle.firstLineHeadIndent = bulletIndent
            paraStyle.tabStops = [NSTextTab(textAlignment: .left, location: textIndent)]
            paraStyle.paragraphSpacing = 2

            // Append bullet/number prefix
            let prefixAttrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: secondaryColor,
                .paragraphStyle: paraStyle
            ]
            result.append(NSAttributedString(string: prefix, attributes: prefixAttrs))

            // Append list item content
            if case .listItem(_, _, let childBlocks) = item {
                for (blockIdx, childBlock) in childBlocks.enumerated() {
                    switch childBlock {
                    case .paragraph(let text):
                        let attrStr = attributedString(from: text, baseFont: baseFont, baseColor: baseColor)
                        attrStr.addAttribute(.paragraphStyle, value: paraStyle, range: NSRange(location: 0, length: attrStr.length))
                        result.append(attrStr)
                    case .list(let nestedStart, _, let nestedItems):
                        appendNewline()
                        appendList(start: nestedStart, items: nestedItems, indent: textIndent)
                    default:
                        appendBlock(childBlock, indent: textIndent)
                    }
                    if blockIdx < childBlocks.count - 1 {
                        appendNewline()
                    }
                }
            } else {
                appendBlock(item, indent: textIndent)
            }
            appendNewline()
        }
    }

    // MARK: - Code Block

    private func appendCodeBlock(info: String?, lines: Lines) {
        let code = lines.joined(separator: "")
        let trimmedCode = code.hasSuffix("\n") ? String(code.dropLast()) : code

        let langLabel = (info ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let displayLabel = langLabel.isEmpty ? "code" : langLabel

        // Language label line
        let labelStart = result.length
        let labelParaStyle = NSMutableParagraphStyle()
        labelParaStyle.paragraphSpacingBefore = 12 //top margin
        labelParaStyle.paragraphSpacing = 0 //bottom padding (space before code)
        labelParaStyle.firstLineHeadIndent = 12 //left padding
        labelParaStyle.headIndent = 12 //left padding (wrapped line)
        labelParaStyle.tailIndent = -8 //right padding (negative = inset)

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize - 2, weight: .semibold),
            .foregroundColor: secondaryColor,
            .paragraphStyle: labelParaStyle
        ]
        result.append(NSAttributedString(string: "\(displayLabel)\n", attributes: labelAttrs))

        // Syntax-highlighted code
        let codeStart = result.length
        let highlighted = HighlightrManager.shared.highlight(
            code: trimmedCode,
            language: langLabel.isEmpty ? nil : langLabel,
            fontSize: fontSize - 2,
            isDark: isDark
        )
        let mutableHighlighted = NSMutableAttributedString(attributedString: highlighted)
        mutableHighlighted.append(NSAttributedString(string: "\n"))

        let highlightedRange = NSRange(location: 0, length: mutableHighlighted.length)

        // Strip any background color from Highlightr theme output
        mutableHighlighted.removeAttribute(.backgroundColor, range: highlightedRange)

        // Set paragraph style for code
        let codeParaStyle = NSMutableParagraphStyle()
        codeParaStyle.lineHeightMultiple = 1.1
        codeParaStyle.firstLineHeadIndent = 8 //left padding
        codeParaStyle.headIndent = 8 //left padding (wrapped lines)
        codeParaStyle.tailIndent = -8 //right padding (negative = inset)
        codeParaStyle.paragraphSpacingBefore = 0 //top padding each line
        codeParaStyle.paragraphSpacing = 0 //bottom padding each line
        mutableHighlighted.addAttribute(.paragraphStyle, value: codeParaStyle, range: highlightedRange)

        appendNewlineAsSpacer()
        result.append(mutableHighlighted)
        appendNewlineAsSpacer()

        let codeEnd = result.length
        let fullRange = NSRange(location: labelStart, length: codeEnd - labelStart)
        let codeRange = NSRange(location: codeStart, length: codeEnd - codeStart)

        codeBlocks.append(CodeBlockInfo(
            fullRange: fullRange,
            codeRange: codeRange,
            rawCode: trimmedCode,
            language: langLabel.isEmpty ? nil : langLabel
        ))

        // Trailing spacing
        let trailParaStyle = NSMutableParagraphStyle()
        let trailAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 2),
            .paragraphStyle: trailParaStyle
        ]
        result.append(NSAttributedString(string: "\n", attributes: trailAttrs))
    }

    // MARK: - Table

    private func appendTable(header: Row, alignments: Alignments, rows: Rows) {
        let colCount = header.count
        guard colCount > 0 else { return }

        let table = NSTextTable()
        table.numberOfColumns = colCount
        table.layoutAlgorithm = .fixedLayoutAlgorithm
        table.collapsesBorders = true

        // Header row
        appendTableRow(header, table: table, row: 0, colCount: colCount, alignments: alignments, isHeader: true)

        // Data rows
        for (idx, row) in rows.enumerated() {
            appendTableRow(row, table: table, row: idx + 1, colCount: colCount, alignments: alignments, isHeader: false)
        }
    }

    private func appendTableRow(_ row: Row, table: NSTextTable, row rowIdx: Int, colCount: Int, alignments: Alignments, isHeader: Bool) {
        for colIdx in 0..<colCount {
            let block = NSTextTableBlock(table: table, startingRow: rowIdx, rowSpan: 1, startingColumn: colIdx, columnSpan: 1)
            block.setWidth(0.5, type: .absoluteValueType, for: .border)
            block.setBorderColor(isDark ? NSColor(white: 0.3, alpha: 1) : NSColor(white: 0.8, alpha: 1))

            if isHeader {
                block.backgroundColor = headerBackground
            }

            let pct = CGFloat(100) / CGFloat(colCount)
            block.setValue(pct, type: .percentageValueType, for: .width)
            block.setWidth(8, type: .absoluteValueType, for: .padding)

            let paraStyle = NSMutableParagraphStyle()
            paraStyle.textBlocks = [block]
            let alignment = colIdx < alignments.count ? alignments[colIdx] : .undefined
            switch alignment {
            case .left, .undefined: paraStyle.alignment = .left
            case .right: paraStyle.alignment = .right
            case .center: paraStyle.alignment = .center
            }

            let font = isHeader ? NSFont.boldSystemFont(ofSize: fontSize) : baseFont
            let cellText: MarkdownKit.Text = colIdx < row.count ? row[colIdx] : MarkdownKit.Text()
            let attrStr = attributedString(from: cellText, baseFont: font, baseColor: baseColor)
            attrStr.addAttribute(.paragraphStyle, value: paraStyle, range: NSRange(location: 0, length: attrStr.length))

            result.append(attrStr)
            // Each cell ends with \n
            let newlineAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: paraStyle
            ]
            result.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
        }
    }

    // MARK: - Thematic Break

    private func appendThematicBreak() {
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.paragraphSpacingBefore = 8
        paraStyle.paragraphSpacing = 8
        paraStyle.alignment = .center

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize - 2),
            .foregroundColor: secondaryColor,
            .paragraphStyle: paraStyle
        ]
        result.append(NSAttributedString(string: String(repeating: "\u{2500}", count: 40) + "\n", attributes: attrs))
    }

    // MARK: - Definition List

    private func appendDefinitionList(_ definitions: Definitions, indent: CGFloat) {
        for def in definitions {
            let termFont = NSFont.boldSystemFont(ofSize: fontSize)
            let termStr = attributedString(from: def.item, baseFont: termFont, baseColor: baseColor)
            result.append(termStr)
            appendNewline()

            for descBlock in def.descriptions {
                appendBlock(descBlock, indent: indent + 20)
            }
            appendNewline()
        }
    }

    // MARK: - Inline Rendering

    private func attributedString(from text: MarkdownKit.Text, baseFont: NSFont, baseColor: NSColor) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for fragment in text {
            result.append(attributedString(from: fragment, baseFont: baseFont, baseColor: baseColor))
        }
        return result
    }

    private func attributedString(from fragment: TextFragment, baseFont: NSFont, baseColor: NSColor) -> NSMutableAttributedString {
        switch fragment {
        case .text(let str):
            return NSMutableAttributedString(string: String(str), attributes: [
                .font: baseFont,
                .foregroundColor: baseColor
            ])

        case .code(let str):
            let codeFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular)
            return NSMutableAttributedString(string: String(str), attributes: [
                .font: codeFont,
                .foregroundColor: baseColor,
                .backgroundColor: inlineCodeBackground
            ])

        case .emph(let inner):
            let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            return attributedString(from: inner, baseFont: italicFont, baseColor: baseColor)

        case .strong(let inner):
            let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
            return attributedString(from: inner, baseFont: boldFont, baseColor: baseColor)

        case .link(let inner, let url, _):
            let linkStr = attributedString(from: inner, baseFont: baseFont, baseColor: linkColor)
            if let urlStr = url, let linkURL = URL(string: urlStr) {
                let range = NSRange(location: 0, length: linkStr.length)
                linkStr.addAttribute(.link, value: linkURL, range: range)
                linkStr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            return linkStr

        case .autolink(_, let str):
            let urlStr = String(str)
            let linkStr = NSMutableAttributedString(string: urlStr, attributes: [
                .font: baseFont,
                .foregroundColor: linkColor
            ])
            if let linkURL = URL(string: urlStr) {
                let range = NSRange(location: 0, length: linkStr.length)
                linkStr.addAttribute(.link, value: linkURL, range: range)
                linkStr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            return linkStr

        case .image(let alt, _, _):
            let altText = plainText(from: alt)
            return NSMutableAttributedString(string: "[\(altText)]", attributes: [
                .font: baseFont,
                .foregroundColor: secondaryColor
            ])

        case .html(let str):
            return NSMutableAttributedString(string: String(str), attributes: [
                .font: baseFont,
                .foregroundColor: secondaryColor
            ])

        case .softLineBreak:
            return NSMutableAttributedString(string: " ", attributes: [.font: baseFont])

        case .hardLineBreak:
            return NSMutableAttributedString(string: "\n", attributes: [.font: baseFont])

        case .delimiter(let char, let count, _):
            return NSMutableAttributedString(string: String(repeating: String(char), count: count), attributes: [
                .font: baseFont,
                .foregroundColor: baseColor
            ])

        case .custom:
            return NSMutableAttributedString()
        }
    }

    // MARK: - Helpers

    private func appendNewline() {
        result.append(NSAttributedString(string: "\n", attributes: [.font: baseFont]))
    }

    private func appendNewlineAsSpacer() {
        result.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 6)]))
    }

    // MARK: - Public Color Accessors

    var codeBackgroundColor: NSColor { codeBackground }
    var headerBackgroundColor: NSColor { headerBackground }

    private func plainText(from text: MarkdownKit.Text) -> String {
        var out = ""
        for fragment in text {
            switch fragment {
            case .text(let s): out += String(s)
            case .code(let s): out += String(s)
            case .emph(let inner): out += plainText(from: inner)
            case .strong(let inner): out += plainText(from: inner)
            case .link(let inner, _, _): out += plainText(from: inner)
            case .autolink(_, let s): out += String(s)
            case .image(let alt, _, _): out += plainText(from: alt)
            case .html(let s): out += String(s)
            case .softLineBreak: out += " "
            case .hardLineBreak: out += "\n"
            case .delimiter(let c, let n, _): out += String(repeating: String(c), count: n)
            case .custom: break
            }
        }
        return out
    }
}

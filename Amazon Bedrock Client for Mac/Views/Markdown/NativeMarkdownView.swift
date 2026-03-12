//
//  NativeMarkdownView.swift
//  Amazon Bedrock Client for Mac
//

import SwiftUI
import AppKit
import MarkdownKit

// MARK: - Custom NSTextView for markdown rendering

class MarkdownTextView: NSTextView {
    var blockquoteRanges: [NSRange] = []
    var blockquoteBarColor: NSColor = NSColor(white: 0.5, alpha: 0.4)
    var codeBlocks: [CodeBlockInfo] = []
    var codeBlockBackground: NSColor = .clear
    var codeBlockHeaderBackground: NSColor = .clear

    // Copy button shown on hover
    private var copyButton: NSButton?
    private var hoveredCodeBlock: CodeBlockInfo?

    override func draw(_ dirtyRect: NSRect) {
        drawCodeBlockBackgrounds(dirtyRect)
        super.draw(dirtyRect)
        drawBlockquoteBars(dirtyRect)
    }

    private func drawBlockquoteBars(_ dirtyRect: NSRect) {
        guard let layoutManager = layoutManager, let textContainer = textContainer else { return }

        blockquoteBarColor.setFill()

        for range in blockquoteRanges {
            guard range.location < (textStorage?.length ?? 0) else { continue }
            let clampedRange = NSRange(
                location: range.location,
                length: min(range.length, (textStorage?.length ?? 0) - range.location)
            )
            let glyphRange = layoutManager.glyphRange(forCharacterRange: clampedRange, actualCharacterRange: nil)
            let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let barRect = NSRect(
                x: textContainerOrigin.x + boundingRect.minX - 14,
                y: textContainerOrigin.y + boundingRect.minY,
                width: 3,
                height: boundingRect.height
            )
            if barRect.intersects(dirtyRect) {
                let path = NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5)
                path.fill()
            }
        }
    }

    private func drawCodeBlockBackgrounds(_ dirtyRect: NSRect) {
        guard let layoutManager = layoutManager, let textContainer = textContainer else { return }
        let storageLength = textStorage?.length ?? 0

        for codeBlock in codeBlocks {
            guard codeBlock.fullRange.location < storageLength else { continue }
            let clampedFull = NSRange(
                location: codeBlock.fullRange.location,
                length: min(codeBlock.fullRange.length, storageLength - codeBlock.fullRange.location)
            )
            let clampedCode = NSRange(
                location: codeBlock.codeRange.location,
                length: min(codeBlock.codeRange.length, storageLength - codeBlock.codeRange.location)
            )

            // Full panel rect
            let fullGlyphRange = layoutManager.glyphRange(forCharacterRange: clampedFull, actualCharacterRange: nil)
            let fullRect = layoutManager.boundingRect(forGlyphRange: fullGlyphRange, in: textContainer)
            let panelRect = NSRect(
                x: textContainerOrigin.x,
                y: textContainerOrigin.y + fullRect.minY,
                width: textContainer.size.width,
                height: fullRect.height
            )

            guard panelRect.intersects(dirtyRect) else { continue }

            // Draw full background with rounded corners
            let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: 8, yRadius: 8)
            codeBlockBackground.setFill()
            panelPath.fill()

            // Header rect: from panel top to where code starts
            let codeGlyphRange = layoutManager.glyphRange(forCharacterRange: clampedCode, actualCharacterRange: nil)
            let codeRect = layoutManager.boundingRect(forGlyphRange: codeGlyphRange, in: textContainer)
            let headerRect = NSRect(
                x: panelRect.minX,
                y: panelRect.minY,
                width: panelRect.width,
                height: (textContainerOrigin.y + codeRect.minY) - panelRect.minY
            )

            if headerRect.height > 0 {
                // In flipped coords (NSTextView): minY = top, maxY = bottom
                // Round top-left and top-right corners only
                let headerPath = NSBezierPath()
                let r: CGFloat = 8
                // Start at bottom-left (square corner)
                headerPath.move(to: NSPoint(x: headerRect.minX, y: headerRect.maxY))
                // Left edge up to top-left rounded corner
                headerPath.line(to: NSPoint(x: headerRect.minX, y: headerRect.minY + r))
                headerPath.curve(to: NSPoint(x: headerRect.minX + r, y: headerRect.minY),
                                 controlPoint1: NSPoint(x: headerRect.minX, y: headerRect.minY),
                                 controlPoint2: NSPoint(x: headerRect.minX, y: headerRect.minY))
                // Top edge to top-right rounded corner
                headerPath.line(to: NSPoint(x: headerRect.maxX - r, y: headerRect.minY))
                headerPath.curve(to: NSPoint(x: headerRect.maxX, y: headerRect.minY + r),
                                 controlPoint1: NSPoint(x: headerRect.maxX, y: headerRect.minY),
                                 controlPoint2: NSPoint(x: headerRect.maxX, y: headerRect.minY))
                // Right edge down to bottom-right (square corner)
                headerPath.line(to: NSPoint(x: headerRect.maxX, y: headerRect.maxY))
                headerPath.close()

                codeBlockHeaderBackground.setFill()
                headerPath.fill()
            }
        }
    }

    // MARK: - Code Block Hover / Copy Button

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        updateCopyButton(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        removeCopyButton()
    }

    private func updateCopyButton(at point: NSPoint) {
        guard let layoutManager = layoutManager, let textContainer = textContainer else { return }

        let textPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let charIndex = layoutManager.characterIndex(
            for: textPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )

        // Check if hovering over a code block
        for codeBlock in codeBlocks {
            if NSLocationInRange(charIndex, codeBlock.fullRange) {
                if hoveredCodeBlock?.fullRange != codeBlock.fullRange {
                    showCopyButton(for: codeBlock)
                }
                return
            }
        }
        removeCopyButton()
    }

    private func showCopyButton(for codeBlock: CodeBlockInfo) {
        removeCopyButton()
        hoveredCodeBlock = codeBlock

        guard let layoutManager = layoutManager, let textContainer = textContainer else { return }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: codeBlock.fullRange, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

        let button = NSButton(frame: .zero)
        button.title = "Copy code"
        button.bezelStyle = .recessed
        button.isBordered = true
        button.font = .systemFont(ofSize: 11)
        button.target = self
        button.action = #selector(copyCodeAction)
        button.sizeToFit()

        let buttonX = textContainerOrigin.x + rect.maxX - button.frame.width - 8
        let buttonY = textContainerOrigin.y + rect.minY + 4
        button.frame.origin = NSPoint(x: buttonX, y: buttonY)

        addSubview(button)
        copyButton = button
    }

    private func removeCopyButton() {
        copyButton?.removeFromSuperview()
        copyButton = nil
        hoveredCodeBlock = nil
    }

    @objc private func copyCodeAction() {
        guard let code = hoveredCodeBlock?.rawCode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)

        // Feedback
        copyButton?.title = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton?.title = "Copy code"
        }
    }
}

// MARK: - NativeMarkdownView (NSViewRepresentable)

struct NativeMarkdownView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let searchRanges: [NSRange]
    let currentMatchIndex: Int
    @Binding var reportedHeight: CGFloat

    @SwiftUI.Environment(\.colorScheme) private var colorScheme

    init(text: String, fontSize: CGFloat, searchRanges: [NSRange] = [], currentMatchIndex: Int = -1, reportedHeight: Binding<CGFloat>? = nil) {
        self.text = text
        self.fontSize = fontSize
        self.searchRanges = searchRanges
        self.currentMatchIndex = currentMatchIndex
        self._reportedHeight = reportedHeight ?? .constant(0)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MarkdownTextView {
        let textView = MarkdownTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.isAutomaticLinkDetectionEnabled = false
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]

        // Set delegate for link clicks
        textView.delegate = context.coordinator

        applyContent(to: textView)
        return textView
    }

    func updateNSView(_ textView: MarkdownTextView, context: Context) {
        applyContent(to: textView)
    }

    private func applyContent(to textView: MarkdownTextView) {
        let isDark = colorScheme == .dark
        let parser = ExtendedMarkdownParser()
        let document = parser.parse(text)

        let builder = MarkdownAttributedStringBuilder(fontSize: fontSize, isDark: isDark)
        let attrStr = builder.build(from: document)

        // Apply search highlights
        applySearchHighlights(to: attrStr)

        // Only update if content changed
        let currentText = textView.textStorage?.string ?? ""
        if currentText != attrStr.string || !searchRanges.isEmpty {
            textView.textStorage?.setAttributedString(attrStr)
        }

        // Update metadata for drawing and hover
        textView.blockquoteRanges = builder.blockquoteRanges
        textView.blockquoteBarColor = isDark ? NSColor(white: 0.5, alpha: 0.4) : NSColor(white: 0.5, alpha: 0.4)
        textView.codeBlocks = builder.codeBlocks
        textView.codeBlockBackground = builder.codeBackgroundColor
        textView.codeBlockHeaderBackground = builder.headerBackgroundColor
        textView.needsDisplay = true

        // Measure and report height
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            layoutManager.ensureLayout(for: container)
            let usedRect = layoutManager.usedRect(for: container)
            let newHeight = ceil(usedRect.height) + textView.textContainerInset.height * 2 + 2

            DispatchQueue.main.async {
                if abs(self.reportedHeight - newHeight) > 1 {
                    self.reportedHeight = newHeight
                }
            }
        }
    }

    private func applySearchHighlights(to attrStr: NSMutableAttributedString) {
        guard !searchRanges.isEmpty else { return }

        for (idx, range) in searchRanges.enumerated() {
            guard range.location >= 0, range.location + range.length <= attrStr.length else { continue }

            if idx == currentMatchIndex {
                attrStr.addAttribute(.backgroundColor, value: NSColor.orange.withAlphaComponent(0.9), range: range)
                attrStr.addAttribute(.foregroundColor, value: NSColor.white, range: range)
            } else {
                attrStr.addAttribute(.backgroundColor, value: NSColor.yellow.withAlphaComponent(0.8), range: range)
                attrStr.addAttribute(.foregroundColor, value: NSColor.black, range: range)
            }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeMarkdownView

        init(parent: NativeMarkdownView) {
            self.parent = parent
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL {
                NSWorkspace.shared.open(url)
                return true
            }
            if let str = link as? String, let url = URL(string: str) {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        }
    }
}

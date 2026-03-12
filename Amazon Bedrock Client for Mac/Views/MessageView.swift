//
//  MessageView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import MarkdownKit
import Combine
import Foundation

// MARK: - LazyMarkdownView
struct LazyMarkdownView: View {
    let text: String
    let fontSize: CGFloat
    let searchRanges: [NSRange]
    let currentMatchIndex: Int

    @State private var contentHeight: CGFloat = 20

    init(text: String, fontSize: CGFloat, searchRanges: [NSRange] = [], currentMatchIndex: Int = -1) {
        self.text = text
        self.fontSize = fontSize
        self.searchRanges = searchRanges
        self.currentMatchIndex = currentMatchIndex
    }

    var body: some View {
        NativeMarkdownView(
            text: text,
            fontSize: fontSize,
            searchRanges: searchRanges,
            currentMatchIndex: currentMatchIndex,
            reportedHeight: $contentHeight
        )
        .frame(height: contentHeight)
    }
}

// MARK: - LazyImageView
// MARK: - Image Cache for Performance
private final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private var cache = NSCache<NSString, NSImage>()
    private let lock = NSLock()
    
    init() {
        cache.countLimit = 100
        cache.totalCostLimit = 200 * 1024 * 1024  // 200MB
    }
    
    func image(for key: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache.object(forKey: key as NSString)
    }
    
    func setImage(_ image: NSImage, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.setObject(image, forKey: key as NSString)
    }
}

struct LazyImageView: View {
    let imageData: String
    let size: CGFloat
    let onTap: () -> Void
    var isGeneratedImage: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var loadedImage: NSImage?
    @State private var isLoading = true
    
    private var displaySize: CGFloat {
        isGeneratedImage ? max(size, 400) : size
    }
    
    // Use hash of image data as cache key
    // For file references (img_xxx), use the reference directly
    // For base64, use hash of full string to ensure uniqueness
    private var cacheKey: String {
        if imageData.hasPrefix("img_") {
            return imageData  // File reference is already unique
        }
        // Use hash of full base64 string for uniqueness
        return "\(imageData.hashValue)"
    }
    
    var body: some View {
        Button(action: onTap) {
            Group {
                if let image = loadedImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: displaySize, maxHeight: displaySize)
                        .clipShape(RoundedRectangle(cornerRadius: isGeneratedImage ? 12 : 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: isGeneratedImage ? 12 : 10)
                                .stroke(
                                    colorScheme == .dark ?
                                    Color.white.opacity(0.15) :
                                        Color.primary.opacity(0.1),
                                    lineWidth: 1
                                )
                        )
                        .shadow(
                            color: Color.black.opacity(isGeneratedImage ? 0.15 : 0.05),
                            radius: isGeneratedImage ? 8 : 2,
                            x: 0,
                            y: isGeneratedImage ? 4 : 1
                        )
                } else if isLoading {
                    // Loading placeholder
                    RoundedRectangle(cornerRadius: isGeneratedImage ? 12 : 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                        .frame(width: displaySize * 0.8, height: displaySize * 0.6)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                        )
                } else {
                    // Error state
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                        .frame(width: size, height: size / 2)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadImageAsync()
        }
        .contextMenu {
            Button(action: copyImageToClipboard) {
                Label("Copy Image", systemImage: "doc.on.doc")
            }
            
            Button(action: saveImageToFile) {
                Label("Save Image...", systemImage: "square.and.arrow.down")
            }
        }
    }
    
    private func loadImageAsync() {
        // Check cache first
        if let cached = ImageCache.shared.image(for: cacheKey) {
            loadedImage = cached
            isLoading = false
            return
        }
        
        // Load image - handle both file references and base64
        let imageDataCopy = imageData
        let cacheKeyCopy = cacheKey
        
        Task {
            var image: NSImage?
            
            // Check if it's a file reference (img_xxx format)
            if imageDataCopy.hasPrefix("img_") {
                // Load from file on main actor
                if let data = await MainActor.run(body: { ImageStorageManager.shared.loadImage(imageDataCopy) }) {
                    image = NSImage(data: data)
                }
            } else if let data = Data(base64Encoded: imageDataCopy) {
                // Direct base64 decode
                image = NSImage(data: data)
            }
            
            await MainActor.run {
                if let img = image {
                    ImageCache.shared.setImage(img, for: cacheKeyCopy)
                    loadedImage = img
                }
                isLoading = false
            }
        }
    }
    
    private func copyImageToClipboard() {
        guard let image = loadedImage else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
    
    private func saveImageToFile() {
        guard let image = loadedImage else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]
        savePanel.nameFieldStringValue = "generated-image-\(Date().timeIntervalSince1970).png"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                if let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData) {
                    let fileExtension = url.pathExtension.lowercased()
                    let imageData: Data?
                    
                    if fileExtension == "png" {
                        imageData = bitmap.representation(using: .png, properties: [:])
                    } else {
                        imageData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95])
                    }
                    
                    if let data = imageData {
                        try? data.write(to: url)
                    }
                }
            }
        }
    }
}

// MARK: - GeneratedImageView (for AI-generated images)
struct GeneratedImageView: View {
    let imageBase64Strings: [String]
    let onTapImage: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Display images in a responsive grid
            ForEach(imageBase64Strings, id: \.self) { imageData in
                LazyImageView(
                    imageData: imageData,
                    size: 512,
                    onTap: { onTapImage(imageData) },
                    isGeneratedImage: true
                )
            }
        }
    }
}

// MARK: - GeneratedVideoView (for AI-generated videos)
import AVKit

struct GeneratedVideoView: View {
    let videoUrl: URL
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var player: AVPlayer?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Video player
            if let player = player {
                VideoPlayer(player: player)
                    .frame(width: 640, height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                colorScheme == .dark ?
                                Color.white.opacity(0.15) :
                                    Color.primary.opacity(0.1),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
            } else {
                // Loading placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    .frame(width: 640, height: 360)
                    .overlay(
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Loading video...")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    )
            }
            
            // Video controls
            HStack(spacing: 12) {
                Button(action: { openInFinder() }) {
                    Label("Show in Finder", systemImage: "folder")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                
                Button(action: { saveVideoToFile() }) {
                    Label("Save Video...", systemImage: "square.and.arrow.down")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
            }
            .foregroundColor(.secondary)
        }
        .onAppear {
            loadVideo()
        }
        .onDisappear {
            player?.pause()
        }
    }
    
    private func loadVideo() {
        guard FileManager.default.fileExists(atPath: videoUrl.path) else { return }
        player = AVPlayer(url: videoUrl)
    }
    
    private func openInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([videoUrl])
    }
    
    private func saveVideoToFile() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.mpeg4Movie]
        savePanel.nameFieldStringValue = "generated-video-\(Date().timeIntervalSince1970).mp4"
        
        savePanel.begin { response in
            if response == .OK, let destinationUrl = savePanel.url {
                try? FileManager.default.copyItem(at: videoUrl, to: destinationUrl)
            }
        }
    }
}

// MARK: - ExpandableMarkdownItem
struct ExpandableMarkdownItem: View {
    @State private var isExpanded = false
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    let header: String
    let text: String
    let fontSize: CGFloat
    let searchRanges: [NSRange]
    var summary: String? = nil  // Optional summary to show in header
    var isStreaming: Bool = false  // Whether content is still streaming
    
    init(header: String, text: String, fontSize: CGFloat, searchRanges: [NSRange] = [], summary: String? = nil, isStreaming: Bool = false) {
        self.header = header
        self.text = text
        self.fontSize = fontSize
        self.searchRanges = searchRanges
        self.summary = summary
        self.isStreaming = isStreaming
    }
    
    // Display text for header - shows summary if available
    private var displayHeader: String {
        if let summary = summary, !summary.isEmpty {
            return summary
        } else {
            return header
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Toggle button with summary
            Button(action: {
                isExpanded.toggle()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: fontSize - 4))
                        .foregroundColor(.secondary)
                    
                    // Show animated dots only when streaming without summary
                    if isStreaming && summary == nil {
                        ThinkingDotsView(fontSize: fontSize)
                    } else {
                        Text(displayHeader)
                            .font(.system(size: fontSize - 1, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(.borderless)
            
            // Expandable content
            if isExpanded {
                LazyMarkdownView(
                    text: text,
                    fontSize: fontSize - 2,
                    searchRanges: searchRanges
                )
                .padding(.leading, fontSize / 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    colorScheme == .dark ?
                    Color.white.opacity(0.05) :
                        Color.black.opacity(0.03)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    colorScheme == .dark ?
                    Color.white.opacity(0.1) :
                        Color.black.opacity(0.06),
                    lineWidth: 0.5
                )
        )
    }
}

// Separate view for animated dots using TimelineView
private struct ThinkingDotsView: View {
    let fontSize: CGFloat
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { timeline in
            let seconds = Calendar.current.component(.nanosecond, from: timeline.date) / 100_000_000
            let dotCount = (seconds % 3) + 1
            Text("Thinking" + String(repeating: ".", count: dotCount))
                .font(.system(size: fontSize - 1, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - MessageView
struct MessageView: View {
    let message: MessageData
    let searchResult: SearchMatch?  // Enhanced search result
    var adjustedFontSize: CGFloat = -1 // One size smaller
    
    @StateObject var viewModel = MessageViewModel()
    @Environment(\.fontSize) private var fontSize: CGFloat
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var isHovering = false
    @State private var currentHighlightIndex = 0
    @State private var scrollToMatchNotification: AnyCancellable?
    
    private let imageSize: CGFloat = 100
    
    var body: some View {
        Group {
            // Hide "ToolResult" messages - they are only for API history
            // Tool results are displayed in the assistant message's toolResult field
            if message.user == "ToolResult" {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        if message.user == "User" {
                            Spacer(minLength: 128)
                            userMessageBubble
                                .padding(.horizontal)
                        } else {
                            assistantMessageBubble
                                .padding(.horizontal)
                            Spacer()
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovering = hovering
                    }
                }
            }
        }
        .onAppear {
            setupScrollToMatchNotification()
        }
        .onDisappear {
            scrollToMatchNotification?.cancel()
        }
        .textSelection(.enabled)
    }
    
    // MARK: - Assistant Message Bubble
    private var assistantMessageBubble: some View {
        ZStack(alignment: .bottomTrailing) {
            // Main content
            VStack(alignment: .leading, spacing: 4) {
                // Message header with user name and timestamp
                messageHeader
                    .padding(.bottom, 2)
                
                // Message content with images and markdown
                assistantMessageContent
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ?
                          Color(NSColor.controlBackgroundColor).opacity(0.5) :
                            Color(NSColor.controlBackgroundColor).opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        colorScheme == .dark ?
                        Color.white.opacity(0.08) :
                            Color.black.opacity(0.06),
                        lineWidth: 0.5
                    )
            )
            
            // Copy button as overlay at bottom left
            Button(action: copyMessageToClipboard) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.8))
                    .padding(6)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ?
                                  Color.gray.opacity(0.3) :
                                    Color.white.opacity(0.9))
                            .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .offset(x: 8, y: 8)
            .opacity(isHovering ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
    }
    
    // MARK: - Assistant Content Components
    @ViewBuilder
    private var assistantMessageContent: some View {
        // Generated video (displayed with video player)
        if let videoUrl = message.videoUrl {
            GeneratedVideoView(videoUrl: videoUrl)
                .padding(.bottom, 8)
        }
        
        // Generated images (displayed larger for AI-generated content)
        if let imageBase64Strings = message.imageBase64Strings,
           !imageBase64Strings.isEmpty {
            GeneratedImageView(
                imageBase64Strings: imageBase64Strings
            ) { imageData in
                viewModel.selectImage(with: imageData)
            }
            .padding(.bottom, 8)
        }
        
        VStack(spacing: 8) {
            // Expandable "thinking" section
            if let thinking = message.thinking, !thinking.isEmpty {
                ExpandableMarkdownItem(
                    header: "Thinking",
                    text: thinking,
                    fontSize: fontSize + adjustedFontSize - 2,
                    searchRanges: searchResult?.ranges ?? [],
                    summary: message.thinkingSummary,
                    isStreaming: message.text.isEmpty  // Still streaming if no text yet
                )
                .padding(.vertical, 2)
            }
            
            // Main message content (skip if empty - e.g., video-only messages)
            if !message.text.isEmpty {
                LazyMarkdownView(
                    text: message.text,
                    fontSize: fontSize + adjustedFontSize,
                    searchRanges: searchResult?.ranges ?? []
                )
            }
            
            // Tool use information display
            if let toolUse = message.toolUse {
                ExpandableMarkdownItem(
                    header: "Using tool: \(toolUse.name)",
                    text: formatToolInput(toolUse.input),
                    fontSize: fontSize + adjustedFontSize - 2,
                    searchRanges: searchResult?.ranges ?? []
                )
                .padding(.vertical, 2)
            }

            // Expandable tool result section
            if let toolResult = message.toolResult, !toolResult.isEmpty {
                ExpandableMarkdownItem(
                    header: "Tool Result",
                    text: toolResult,
                    fontSize: fontSize + adjustedFontSize - 2,
                    searchRanges: searchResult?.ranges ?? []
                )
                .padding(.vertical, 2)
            }
        }
        .sheet(isPresented: $viewModel.isShowingImageModal) {
            if let data = viewModel.selectedImageData,
               let imageToShow = NSImage(base64Encoded: data) {
                ImagePreviewModal(
                    image: imageToShow,
                    filename: "image-\(Date().timeIntervalSince1970).png",
                    isPresented: $viewModel.isShowingImageModal
                )
            }
        }
    }
    
    // Helper function to format tool input parameters as JSON
    private func formatToolInput(_ input: JSONValue) -> String {
        return "```json\n\(prettyPrintJSON(input, indent: 0))\n```"
    }

    // Helper function for recursive pretty printing of JSONValue
    private func prettyPrintJSON(_ json: JSONValue, indent: Int) -> String {
        let indentString = String(repeating: "  ", count: indent)
        let childIndentString = String(repeating: "  ", count: indent + 1)
        
        switch json {
        case .string(let str):
            return "\"\(escapeString(str))\""
            
        case .number(let num):
            return "\(num)"
            
        case .bool(let bool):
            return bool ? "true" : "false"
            
        case .null:
            return "null"
            
        case .array(let arr):
            if arr.isEmpty {
                return "[]"
            }
            
            var result = "[\n"
            for (index, item) in arr.enumerated() {
                result += "\(childIndentString)\(prettyPrintJSON(item, indent: indent + 1))"
                if index < arr.count - 1 {
                    result += ","
                }
                result += "\n"
            }
            result += "\(indentString)]"
            return result
            
        case .object(let obj):
            if obj.isEmpty {
                return "{}"
            }
            
            var result = "{\n"
            let sortedKeys = obj.keys.sorted()
            for (index, key) in sortedKeys.enumerated() {
                if let value = obj[key] {
                    result += "\(childIndentString)\"\(key)\": \(prettyPrintJSON(value, indent: indent + 1))"
                    if index < sortedKeys.count - 1 {
                        result += ","
                    }
                    result += "\n"
                }
            }
            result += "\(indentString)}"
            return result
        }
    }

    // Helper function to escape special characters in strings
    private func escapeString(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
    
    // MARK: - User Message Bubble
    private var userMessageBubble: some View {
        // Cache complex views to avoid unnecessary recalculations
        let messageBackground = RoundedRectangle(cornerRadius: 16)
            .fill(Color.accentColor)
        
        let messageBorder = RoundedRectangle(cornerRadius: 16)
            .stroke(Color.clear, lineWidth: 0)
        
        return ZStack(alignment: .bottomTrailing) {
            // Main message content with optimized rendering
            VStack(alignment: .trailing, spacing: 6) {
                // Only load attachments if they exist
                if (message.imageBase64Strings?.isEmpty == false) ||
                   (message.documentBase64Strings?.isEmpty == false) ||
                   (message.pastedTexts?.isEmpty == false) {
                    
                    AttachmentsView(
                        imageBase64Strings: message.imageBase64Strings,
                        imageSize: imageSize,
                        onTapImage: viewModel.selectImage,
                        onSelectDocument: { data, ext, name in
                            viewModel.selectDocument(data: data, ext: ext, name: name)
                        },
                        documentBase64Strings: message.documentBase64Strings,
                        documentFormats: message.documentFormats,
                        documentNames: message.documentNames,
                        pastedTexts: message.pastedTexts,
                        alignment: .trailing
                    )
                }
                
                // Only create text if non-empty
                if !message.text.isEmpty {
                    textContent
                }
            }
            .padding(14)
            .background(messageBackground)
            .overlay(messageBorder)
            
            // Copy button — use opacity instead of conditional to preserve text selection
            copyButton
                .opacity(isHovering ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.2), value: isHovering)
                .allowsHitTesting(isHovering)
        }
        .sheet(isPresented: $viewModel.isShowingImageModal) {
            if let imageData = viewModel.selectedImageData,
               let imageToShow = NSImage(base64Encoded: imageData) {
                ImagePreviewModal(
                    image: imageToShow,
                    filename: "image-\(Date().timeIntervalSince1970).png",
                    isPresented: $viewModel.isShowingImageModal
                )
            }
        }
        .sheet(isPresented: $viewModel.isShowingDocumentModal) {
            if let docData = viewModel.selectedDocumentData {
                DocumentPreviewModal(
                    documentData: docData,
                    filename: viewModel.selectedDocumentName,
                    fileExtension: viewModel.selectedDocumentExt,
                    isPresented: $viewModel.isShowingDocumentModal
                )
            }
        }
    }

    // Extract text content to a separate computed property
    private var textContent: some View {
        Group {
            if let searchResult = searchResult, !searchResult.ranges.isEmpty {
                // Use optimized highlighting when search matches exist
                createHighlightedText(message.text, ranges: searchResult.ranges)
                    .font(.system(size: fontSize + adjustedFontSize))
            } else {
                // Render inline markdown (bold, italic, code, links, strikethrough)
                Text(userMarkdownString)
                    .font(.system(size: fontSize + adjustedFontSize))
            }
        }
    }

    private var userMarkdownString: AttributedString {
        let preprocessed = preprocessFencedCodeBlocks(message.text)
        var str = (try? AttributedString(
            markdown: preprocessed,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(message.text)
        str.foregroundColor = .white
        return str
    }

    /// Converts fenced code blocks into per-line inline code spans so the
    /// inline-only markdown parser preserves line breaks within them.
    private func preprocessFencedCodeBlocks(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "^```[^\\n]*\\n([\\s\\S]*?)^```",
            options: .anchorsMatchLines
        ) else { return text }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        var result = ""
        var lastEnd = text.startIndex

        for match in matches {
            guard let fullRange = Range(match.range, in: text),
                  let contentRange = Range(match.range(at: 1), in: text) else { continue }

            result += text[lastEnd..<fullRange.lowerBound]

            let content = String(text[contentRange])
            let trimmed = content.hasSuffix("\n") ? String(content.dropLast()) : content
            let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            result += lines.map { line -> String in
                if line.isEmpty { return "" }
                // Use double-backtick delimiters if the line contains backticks
                if line.contains("`") {
                    return "`` \(line) ``"
                }
                return "`\(line)`"
            }.joined(separator: "\n")

            lastEnd = fullRange.upperBound
        }

        result += text[lastEnd...]
        return result
    }

    // Extract copy button to a separate computed property
    private var copyButton: some View {
        Button(action: copyMessageToClipboard) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.9))
                .padding(6)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .offset(x: 8, y: 8)
    }

    // Enhanced text highlighting for search matches
    private func createHighlightedText(_ text: String, ranges: [NSRange]) -> SwiftUI.Text {
        if #available(macOS 12.0, *) {
            let highlightedText = TextHighlighter.createHighlightedText(
                text: text,
                searchRanges: ranges,
                fontSize: fontSize + adjustedFontSize,
                highlightColor: .yellow,
                textColor: .white,
                currentMatchIndex: currentHighlightIndex
            )
            return Text(highlightedText.attributedString)
        } else {
            // Fallback for older versions
            return Text(text)
        }
    }
    
    // MARK: - Shared Components
    
    private var messageHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(message.user)
                .font(.system(size: fontSize + adjustedFontSize, weight: .semibold))
                .foregroundColor(.primary) // Original color
            
            Text(format(date: message.sentTime))
                .font(.system(size: fontSize + adjustedFontSize - 2))
                .foregroundColor(.secondary) // Original color
        }
    }
    
    private func copyMessageToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.text, forType: .string)
    }
    
    private func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // MARK: - Search Match Scrolling
    
    private func setupScrollToMatchNotification() {
        scrollToMatchNotification = NotificationCenter.default
            .publisher(for: NSNotification.Name("ScrollToSearchMatch"))
            .sink { notification in
                guard let userInfo = notification.userInfo,
                      let messageIndex = userInfo["messageIndex"] as? Int,
                      let matchIndex = userInfo["matchIndex"] as? Int,
                      let searchQuery = userInfo["searchQuery"] as? String else {
                    return
                }
                
                // Check if this notification is for this message
                if let searchMatch = searchResult,
                   searchMatch.messageIndex == messageIndex {
                    currentHighlightIndex = matchIndex
                    scrollToSpecificMatch(matchIndex: matchIndex, searchQuery: searchQuery)
                }
            }
    }
    
    private func scrollToSpecificMatch(matchIndex: Int, searchQuery: String) {
        // Search highlighting is now handled natively via AttributedString
        // in NativeMarkdownView — no WebView JS needed.
        currentHighlightIndex = matchIndex
    }
}

// MARK: - MessageViewModel

class MessageViewModel: ObservableObject {
    @Published var selectedImageData: String? = nil
    @Published var isShowingImageModal: Bool = false
    @Published var selectedDocumentData: Data? = nil
    @Published var selectedDocumentExt: String = ""
    @Published var selectedDocumentName: String = ""
    @Published var isShowingDocumentModal: Bool = false
    @Published var currentHighlightedMatch: (messageIndex: Int, matchPositionIndex: Int)? = nil
    
    func selectImage(with data: String) {
        self.selectedImageData = data
        self.isShowingImageModal = true
    }
    
    func selectDocument(data: Data, ext: String, name: String) {
        self.selectedDocumentData = data
        self.selectedDocumentExt = ext
        self.selectedDocumentName = name
        self.isShowingDocumentModal = true
    }
    
    func clearSelection() {
        self.selectedImageData = nil
        self.isShowingImageModal = false
    }
}

// MARK: - NSImage Extension

extension NSImage {
    /// Initialize from base64 string or image file reference (img_xxx)
    /// Note: For file references, this loads synchronously from disk
    convenience init?(base64Encoded: String) {
        // Check if it's a file reference (img_xxx format)
        if base64Encoded.hasPrefix("img_") {
            // Read defaultDirectory from UserDefaults (same key as @AppStorage in SettingManager)
            // This avoids MainActor issues while staying in sync with SettingManager
            let defaultDir = UserDefaults.standard.string(forKey: "defaultDirector")
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Amazon Bedrock Client").path
            let baseDir = URL(fileURLWithPath: defaultDir)
            let filePath = baseDir.appendingPathComponent("generated_images/\(base64Encoded).png")
            guard let imageData = try? Data(contentsOf: filePath) else {
                return nil
            }
            self.init(data: imageData)
        } else {
            // Direct base64 decode
            guard let imageData = Data(base64Encoded: base64Encoded) else {
                return nil
            }
            self.init(data: imageData)
        }
    }
}

// MARK: - AttachmentsView

struct ImageGridView: View {
    let imageBase64Strings: [String]
    let imageSize: CGFloat
    let onTapImage: (String) -> Void
    var isGeneratedContent: Bool = false  // For AI-generated images
    
    var body: some View {
        if isGeneratedContent {
            // Vertical layout for generated images (larger display)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(imageBase64Strings, id: \.self) { imageData in
                    LazyImageView(
                        imageData: imageData,
                        size: max(imageSize, 400),
                        onTap: { onTapImage(imageData) },
                        isGeneratedImage: true
                    )
                }
            }
        } else {
            // Horizontal layout for user-attached images (thumbnails)
            HStack(spacing: 10) {
                ForEach(imageBase64Strings, id: \.self) { imageData in
                    LazyImageView(
                        imageData: imageData,
                        size: imageSize,
                        onTap: { onTapImage(imageData) },
                        isGeneratedImage: false
                    )
                }
            }
        }
    }
}

struct AttachmentsView: View {
    // Image properties
    let imageBase64Strings: [String]?
    let imageSize: CGFloat
    let onTapImage: (String) -> Void
    var onSelectDocument: (Data, String, String) -> Void

    // Document properties
    let documentBase64Strings: [String]?
    let documentFormats: [String]?
    let documentNames: [String]?
    
    // Pasted text properties
    let pastedTexts: [PastedTextInfo]?
    
    // Alignment control
    let alignment: HorizontalAlignment
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.fontSize) private var fontSize
    
    private var hasAttachments: Bool {
        return (imageBase64Strings?.isEmpty == false) ||
        (documentBase64Strings?.isEmpty == false) ||
        (pastedTexts?.isEmpty == false)
    }
    
    var body: some View {
        Group {
            if hasAttachments {
                HStack(spacing: 10) {
                    // Pasted text attachments (displayed as chips)
                    if let pastedTexts = pastedTexts, !pastedTexts.isEmpty {
                        ForEach(pastedTexts) { pastedText in
                            pastedTextContent(pastedText: pastedText)
                        }
                    }
                    
                    // Document attachments
                    if let documentBase64Strings = documentBase64Strings,
                       let documentFormats = documentFormats,
                       let documentNames = documentNames,
                       !documentBase64Strings.isEmpty {
                        
                        ForEach(0..<min(documentBase64Strings.count,
                                  min(documentFormats.count, documentNames.count)),
                               id: \.self) { index in
                            documentContent(name: documentNames[index], format: documentFormats[index])
                        }
                    }
                    
                    // Image attachments
                    if let imageBase64Strings = imageBase64Strings, !imageBase64Strings.isEmpty {
                        ForEach(imageBase64Strings, id: \.self) { imageData in
                            LazyImageView(imageData: imageData, size: imageSize) {
                                onTapImage(imageData)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Pasted text content view
    private func pastedTextContent(pastedText: PastedTextInfo) -> some View {
        Button(action: {
            if let data = pastedText.content.data(using: .utf8) {
                onSelectDocument(data, "txt", pastedText.filename)
            }
        }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(pastedText.preview)
                    .font(.system(size: fontSize - 3))
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 250, alignment: .leading)
                
                HStack(spacing: 6) {
                    Text("PASTED")
                        .font(.system(size: fontSize - 5, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                )
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ?
                          Color.white.opacity(0.08) :
                          Color.black.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pastedText.content, forType: .string)
            } label: {
                Label("Copy Content", systemImage: "doc.on.doc")
            }
        }
    }
    
    // Document content extracted to its own function
    private func documentContent(name: String, format: String) -> some View {
        let docColor = documentColor(for: format)
        let isTextFile = ["txt", "md"].contains(format.lowercased())
        let isPastedText = isTextFile && name.lowercased().contains("pasted")
        
        // Get text preview for all text documents (txt, md)
        let textPreview: String? = {
            if isTextFile,
               let index = documentNames?.firstIndex(of: name),
               let docStrings = documentBase64Strings,
               index < docStrings.count,
               let docData = Data(base64Encoded: docStrings[index]),
               let text = String(data: docData, encoding: .utf8) {
                let truncated = String(text.prefix(150))
                let cleaned = truncated
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.count > 100 ? String(cleaned.prefix(97)) + "..." : cleaned
            }
            return nil
        }()
        
        return Button(action: {
            if let index = documentNames?.firstIndex(of: name),
               let docStrings = documentBase64Strings,
               index < docStrings.count,
               let docData = Data(base64Encoded: docStrings[index]) {
                onSelectDocument(docData, format, name)
            }
        }) {
            if let preview = textPreview {
                // Text file preview style (Claude Desktop style)
                VStack(alignment: .leading, spacing: 6) {
                    Text(preview)
                        .font(.system(size: fontSize - 3))
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 250, alignment: .leading)
                    
                    HStack(spacing: 6) {
                        // Show "PASTED" for pasted text, filename for regular files
                        Text(isPastedText ? "PASTED" : name)
                            .font(.system(size: fontSize - 5, weight: .semibold))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        if !isPastedText {
                            Text("•")
                                .font(.system(size: fontSize - 5))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text(format.uppercased())
                                .font(.system(size: fontSize - 5, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                    )
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ?
                              Color.white.opacity(0.08) :
                              Color.black.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
            } else {
                // Regular document style
                HStack(spacing: 10) {
                    // Document icon with color
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(docColor.opacity(0.15))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: documentIcon(for: format))
                            .font(.system(size: 18))
                            .foregroundColor(docColor)
                    }
                    
                    // Document name
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: fontSize - 2, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text("\(format.uppercased()) document")
                            .font(.system(size: fontSize - 4))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ?
                              Color.gray.opacity(0.15) :
                              Color.gray.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(docColor.opacity(0.3), lineWidth: 1)
                )
            }
        }.buttonStyle(PlainButtonStyle())
    }
    
    // Helper function to determine document icon based on file extension
    private func documentIcon(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "txt", "md": return "doc.plaintext.fill"
        case "html": return "globe"
        default: return "doc.fill"
        }
    }
    
    // Helper function to determine document color based on file extension
    private func documentColor(for fileExtension: String) -> Color {
        switch fileExtension.lowercased() {
        case "pdf": return .red
        case "doc", "docx": return .blue
        case "xls", "xlsx", "csv": return .green
        case "txt", "md": return .gray
        case "html": return .orange
        default: return .gray
        }
    }
}

// MARK: - ImageViewerModal

struct ImageViewerModal: View {
    var image: NSImage
    var closeModal: () -> Void
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8).edgesIgnoringSafeArea(.all)
            
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .cornerRadius(10)
                .padding()
                .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                .contextMenu {
                    Button(action: {
                        copyNSImageToClipboard(image: image)
                    }) {
                        Text("Copy Image")
                        Image(systemName: "doc.on.doc")
                    }
                    
                    Button(action: {
                        saveImage(image)
                    }) {
                        Text("Save Image")
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: closeModal) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white)
                            .font(.title)
                            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 0)
                    }
                    .padding([.top, .trailing])
                    .buttonStyle(PlainButtonStyle())
                }
                Spacer()
            }
        }
    }
    
    func copyNSImageToClipboard(image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
    
    func saveImage(_ image: NSImage) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]
        savePanel.nameFieldStringValue = "image.png"
        
        savePanel.begin { response in
            if response == .OK {
                guard let url = savePanel.url else { return }
                
                if let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData) {
                    
                    let fileExtension = url.pathExtension.lowercased()
                    let imageData: Data?
                    
                    if fileExtension == "png" {
                        imageData = bitmap.representation(using: .png, properties: [:])
                    } else {
                        imageData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                    }
                    
                    if let data = imageData {
                        try? data.write(to: url)
                    }
                }
            }
        }
    }
}

// MARK: - NSImage Resizing Extension

extension NSImage {
    func resized(to targetSize: NSSize) -> NSImage? {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        defer { newImage.unlockFocus() }
        self.draw(in: NSRect(origin: .zero, size: targetSize),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: 1.0)
        return newImage
    }
    
    func resizedMaintainingAspectRatio(maxDimension: CGFloat) -> NSImage? {
        let aspectRatio = self.size.width / self.size.height
        let newSize: NSSize
        if self.size.width > self.size.height {
            newSize = NSSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = NSSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        return resized(to: newSize)
    }
    
    func compressedData(maxFileSize: Int, maxDimension: CGFloat, format: NSBitmapImageRep.FileType = .jpeg) -> Data? {
        guard let resizedImage = self.resizedMaintainingAspectRatio(maxDimension: maxDimension),
              let tiffRepresentation = resizedImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        
        var compressionFactor: CGFloat = 1.0
        var data = bitmapImage.representation(using: format, properties: [.compressionFactor: compressionFactor])
        
        while let imageData = data, imageData.count > maxFileSize && compressionFactor > 0 {
            compressionFactor -= 0.1
            data = bitmapImage.representation(using: format, properties: [.compressionFactor: compressionFactor])
        }
        
        return data
    }
}



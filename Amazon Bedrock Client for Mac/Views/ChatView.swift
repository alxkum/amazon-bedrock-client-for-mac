//
//  ChatView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import SwiftUI
import Combine

// MARK: - WebView Load Tracking

@MainActor
final class WebViewLoadTracker: ObservableObject {
    @Published private(set) var allLoaded: Bool = false
    private(set) var registeredCount: Int = 0
    private var completedCount: Int = 0
    private var isTracking: Bool = false

    func startTracking() {
        registeredCount = 0
        completedCount = 0
        allLoaded = false
        isTracking = true
    }

    func register() {
        guard isTracking else { return }
        registeredCount += 1
    }

    func markCompleted() {
        guard isTracking else { return }
        completedCount += 1
        if completedCount >= registeredCount {
            isTracking = false
            allLoaded = true
        }
    }
}

private struct WebViewLoadTrackerKey: EnvironmentKey {
    static let defaultValue: WebViewLoadTracker? = nil
}

extension EnvironmentValues {
    var webViewLoadTracker: WebViewLoadTracker? {
        get { self[WebViewLoadTrackerKey.self] }
        set { self[WebViewLoadTrackerKey.self] = newValue }
    }
}

struct BottomAnchorPreferenceKey: PreferenceKey {
    typealias Value = CGFloat
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct UserMessageOffsetsKey: PreferenceKey {
    typealias Value = [Int: CGFloat]
    nonisolated(unsafe) static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @StateObject private var sharedMediaDataSource = SharedMediaDataSource()
    @StateObject private var transcribeManager = TranscribeStreamingManager()
    @StateObject private var searchEngine = SearchEngine()
    @ObservedObject var backendModel: BackendModel
    
    @FocusState private var isSearchFocused: Bool
    @SwiftUI.Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    @State private var isAtBottom: Bool = true
    @State private var isSearchActive: Bool = false // Add search state tracking
    @State private var userMessageOffsets: [Int: CGFloat] = [:]
    @State private var isInitialLoad: Bool = true
    @State private var initialScrollTask: Task<Void, Never>? = nil
    @State private var showLoadingOverlay: Bool = false
    @StateObject private var webViewLoadTracker = WebViewLoadTracker()
    
    // Font size adjustment state
    @AppStorage("adjustedFontSize") private var adjustedFontSize: Int = -1
    
    // Enhanced search state
    @State private var showSearchBar: Bool = false
    @State private var searchQuery: String = ""
    @State private var currentMatchIndex: Int = 0
    @State private var searchResult: SearchResult = SearchResult(matches: [], totalMatches: 0, searchTime: 0)
    @State private var searchDebounceTimer: Timer?
    
    // Usage toast state
    @State private var showUsageToast: Bool = false
    @State private var currentUsage: String = ""
    @State private var usageToastTimer: Timer?
    
    init(chatId: String, backendModel: BackendModel) {
        let sharedMediaDataSource = SharedMediaDataSource()
        _viewModel = StateObject(
            wrappedValue: ChatViewModel(
                chatId: chatId,
                backendModel: backendModel,
                sharedMediaDataSource: sharedMediaDataSource
            )
        )
        _sharedMediaDataSource = StateObject(wrappedValue: sharedMediaDataSource)
        self._backendModel = ObservedObject(wrappedValue: backendModel)
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            if showSearchBar {
                enhancedFindBar
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
            
            VStack(spacing: 0) {
                placeholderView
                messageScrollView
                messageBarView
            }
            
            // Usage toast
            if showUsageToast && SettingManager.shared.showUsageInfo {
                VStack {
                    usageToastView
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(5)
                    Spacer()
                }
                .padding(.top, showSearchBar ? 80 : 12)
                .allowsHitTesting(false)
            }

            if showLoadingOverlay {
                loadingOverlayView
                    .zIndex(20)
            }
        }
        .environment(\.webViewLoadTracker, webViewLoadTracker)
        .onDisappear {
            showLoadingOverlay = false
            initialScrollTask?.cancel()
        }
        .onAppear {
            // Restore existing messages from disk or other storage
            viewModel.loadInitialData()

            // Show loading overlay when opening a chat with existing messages
            if !viewModel.messages.isEmpty {
                showLoadingOverlay = true
                webViewLoadTracker.startTracking()
            }

            // Set up usage handler for toast notifications
            viewModel.usageHandler = { usage in
                DispatchQueue.main.async {
                    showUsageToast(with: usage)
                }
            }
            
            // Handle quick access message if this is the target chat
            handleQuickAccessMessage()
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showSearchBar.toggle()
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(LiquidGlassToolbarButtonStyle())
                .help("Find")
                .keyboardShortcut("f", modifiers: [.command])
            }
        }
        .onChange(of: showSearchBar) { _, newValue in
            AppStateManager.shared.isSearchFieldActive = newValue && isSearchFocused
            if !newValue {
                clearSearch()
            }
        }
        .onChange(of: isSearchFocused) { _, newValue in
            AppStateManager.shared.isSearchFieldActive = showSearchBar && newValue
        }
        .onChange(of: searchQuery) { _, newQuery in
            performDebouncedSearch(query: newQuery)
        }
        .onAppear {
            registerKeyboardShortcuts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mcpServerConnected)) { notification in
            // Show toast when MCP server connects
            if let userInfo = notification.userInfo,
               let toolCount = userInfo["toolCount"] as? Int,
               let serverCount = userInfo["serverCount"] as? Int {
                let message = "🔧 MCP: \(toolCount) tool\(toolCount > 1 ? "s" : "") from \(serverCount) server\(serverCount > 1 ? "s" : "")"
                showUsageToast(with: message)
            }
        }
    }
    
    // MARK: - Keyboard Shortcuts
    
    private func registerKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers {
                case "+", "=":
                    increaseFontSize()
                    return nil
                case "-", "_":
                    decreaseFontSize()
                    return nil
                case "0":
                    resetFontSize()
                    return nil
                default:
                    break
                }
            }
            return event
        }
    }
    
    // MARK: - Font Size Controls
    
    private func increaseFontSize() {
        if adjustedFontSize < 8 {
            adjustedFontSize += 1
        }
    }
    
    private func decreaseFontSize() {
        if adjustedFontSize > -4 {
            adjustedFontSize -= 1
        }
    }
    
    private func resetFontSize() {
        adjustedFontSize = -1
    }
    
    // MARK: - Placeholder
    
    private var placeholderView: some View {
        VStack {
            if viewModel.messages.isEmpty {
                Spacer()
                Text(viewModel.selectedPlaceholder)
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .textSelection(.disabled)
    }
    
    // MARK: - Message Scroll View
    
    private var messageScrollView: some View {
        GeometryReader { outerGeo in
            ScrollViewReader { proxy in
                ZStack {
                    scrollableMessageList(outerGeo: outerGeo, proxy: proxy)
                    enhancedScrollToBottomButton(offsets: userMessageOffsets, proxy: proxy)
                }
                .onPreferenceChange(BottomAnchorPreferenceKey.self) { bottomY in
                    guard !isInitialLoad else {
                        // During initial load: re-scroll to bottom on every height change.
                        // This corrects for WebViews that finish loading after a previous scroll.
                        initialScrollTask?.cancel()
                        initialScrollTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms settle
                            guard !Task.isCancelled else { return }
                            proxy.scrollTo(Int.max, anchor: .bottom)
                            isAtBottom = true
                        }
                        return
                    }
                    handleBottomAnchorChange(bottomY, containerHeight: outerGeo.size.height)
                }
                .onPreferenceChange(UserMessageOffsetsKey.self) { offsets in
                    userMessageOffsets = offsets
                }
                .onChange(of: searchResult) { _, newResult in
                    jumpToFirstMatch(newResult, proxy: proxy)
                }
                .onChange(of: currentMatchIndex) { _, idx in
                    jumpToMatchIndex(idx, proxy: proxy)
                }
                .onChange(of: webViewLoadTracker.allLoaded) { _, loaded in
                    if loaded {
                        finishInitialLoad(proxy: proxy)
                    }
                }
            }
        }
    }
    
    private func scrollableMessageList(
        outerGeo: GeometryProxy,
        proxy: ScrollViewProxy
    ) -> some View {
        let messageList = VStack(spacing: 2) {
            ForEach(Array(viewModel.messages.enumerated()), id: \.offset) { idx, message in
                MessageView(
                    message: message,
                    searchResult: getSearchResultForMessage(idx),
                    adjustedFontSize: CGFloat(adjustedFontSize)
                )
                    .id(idx)
                    .frame(maxWidth: .infinity)
                    .anchorPreference(key: UserMessageOffsetsKey.self, value: .top) { anchor in
                        message.user == "User" ? [idx: outerGeo[anchor].y] : [:]
                    }
            }
            Color.clear
                .frame(height: 1)
                .id(Int.max)
                .anchorPreference(key: BottomAnchorPreferenceKey.self, value: .bottom) { anchor in
                    outerGeo[anchor].y
                }
        }
        .padding()

        return ScrollView {
            messageList
        }
        .modifier(ScrollEdgeEffectModifier())
        .task {
            // Short wait for WebViews to register during initial layout
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }

            // If no WebViews registered (e.g. only user messages), finish immediately
            if webViewLoadTracker.registeredCount == 0 {
                finishInitialLoad(proxy: proxy)
                return
            }

            // Safety net: if WebView callbacks never arrive, don't block forever
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            if isInitialLoad {
                finishInitialLoad(proxy: proxy)
            }
        }
    }
    
    private func enhancedScrollToBottomButton(
        offsets: [Int: CGFloat],
        proxy: ScrollViewProxy
    ) -> some View {
        Group {
            if !isAtBottom {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            let topMargin: CGFloat = 80
                            let nextUserMsg = offsets
                                .filter { $0.value > topMargin }
                                .min(by: { $0.value < $1.value })

                            if let next = nextUserMsg {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    proxy.scrollTo(next.key, anchor: .top)
                                }
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    proxy.scrollTo(Int.max, anchor: .bottom)
                                    isAtBottom = true
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(Color.accentColor)
                                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.gray.opacity(0.2), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .contentShape(Circle())
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        Spacer()
                    }
                    .padding(.bottom, 16)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
    }
    
    private var messageBarView: some View {
        MessageBarView(
            chatID: viewModel.chatId,
            userInput: $viewModel.userInput,
            sharedMediaDataSource: sharedMediaDataSource,
            transcribeManager: transcribeManager,
            sendMessage: viewModel.sendMessage,
            cancelSending: viewModel.cancelSending,
            modelId: viewModel.chatModel.id
        )
    }
    
    // MARK: - Find Bar Components
    
    private var searchFieldComponent: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
            
            TextField("Find in chat", text: $searchQuery)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 14))
                .frame(minWidth: 140)
                .focused($isSearchFocused)
                .onSubmit { goToNextMatch() }
                .onReceive(NotificationCenter.default.publisher(for: NSControl.textDidChangeNotification)) { _ in
                    // Additional change detection for more responsive search
                }
        }
    }
    
    private var matchCounterComponent: some View {
        HStack(spacing: 4) {
            if searchResult.totalMatches > 0 {
                Text("\(currentMatchIndex + 1) of \(searchResult.totalMatches)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                
                if searchResult.searchTime > 0.001 {
                    Text("(\(String(format: "%.1f", searchResult.searchTime * 1000))ms)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } else if !searchQuery.isEmpty {
                Text("No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text("Enter search term")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minWidth: 100, alignment: .leading)
    }
    
    private var navigationButtonsComponent: some View {
        HStack(spacing: 2) {
            Button(action: goToPrevMatch) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(searchResult.totalMatches == 0 ? Color.secondary.opacity(0.5) : Color.primary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(searchResult.totalMatches == 0)
            .help("Previous match")
            
            Button(action: goToNextMatch) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(searchResult.totalMatches == 0 ? Color.secondary.opacity(0.5) : Color.primary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(searchResult.totalMatches == 0)
            .help("Next match")
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
    
    private var doneButtonComponent: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showSearchBar = false
                clearSearch()
            }
        }) {
            Text("Done")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .keyboardShortcut(.escape, modifiers: [])
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private var enhancedFindBar: some View {
        HStack(spacing: 10) {
            searchFieldComponent
            matchCounterComponent
            navigationButtonsComponent
            Spacer().frame(width: 4)
            doneButtonComponent
        }
        .onAppear {
            isSearchFocused = true
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ?
                      Color(NSColor.windowBackgroundColor).opacity(0.95) :
                        Color(NSColor.windowBackgroundColor).opacity(0.95))
                .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
    
    // MARK: - Enhanced Search Logic
    
    private func performDebouncedSearch(query: String) {
        // Cancel previous timer
        searchDebounceTimer?.invalidate()
        
        // Set new timer for debounced search
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            Task { @MainActor in
                performSearch(query: query)
            }
        }
    }
    
    private func performSearch(query: String) {
        let result = searchEngine.search(query: query, in: viewModel.messages)
        
        DispatchQueue.main.async {
            self.searchResult = result
            self.currentMatchIndex = 0
        }
    }
    
    private func clearSearch() {
        searchQuery = ""
        searchResult = SearchResult(matches: [], totalMatches: 0, searchTime: 0)
        currentMatchIndex = 0
        searchDebounceTimer?.invalidate()
    }
    
    private func getSearchResultForMessage(_ messageIndex: Int) -> SearchMatch? {
        return searchResult.matches.first { $0.messageIndex == messageIndex }
    }
    
    private func handleBottomAnchorChange(_ bottomY: CGFloat, containerHeight: CGFloat) {
        guard !isInitialLoad else { return }
        let threshold: CGFloat = 50
        isAtBottom = (bottomY <= containerHeight + threshold)
    }

    private func finishInitialLoad(proxy: ScrollViewProxy) {
        guard isInitialLoad else { return }
        isAtBottom = true
        isInitialLoad = false
        proxy.scrollTo(Int.max, anchor: .bottom)
        withAnimation(.easeOut(duration: 0.1)) {
            showLoadingOverlay = false
        }
    }

    private func jumpToFirstMatch(_ result: SearchResult, proxy: ScrollViewProxy) {
        guard let firstMatch = result.matches.first else { return }
        scrollToMatch(messageIndex: firstMatch.messageIndex, matchIndex: 0, proxy: proxy)
    }
    
    private func jumpToMatchIndex(_ idx: Int, proxy: ScrollViewProxy) {
        guard searchResult.totalMatches > 0 else { return }
        
        // Find the message and match position for the current match index
        var currentCount = 0
        for match in searchResult.matches {
            let matchCount = match.ranges.count
            if idx < currentCount + matchCount {
                let localMatchIndex = idx - currentCount
                scrollToMatch(messageIndex: match.messageIndex, matchIndex: localMatchIndex, proxy: proxy)
                return
            }
            currentCount += matchCount
        }
    }
    
    private func scrollToMatch(messageIndex: Int, matchIndex: Int, proxy: ScrollViewProxy) {
        // Temporarily disable auto-scroll to bottom
        let wasAtBottom = isAtBottom
        isAtBottom = false
        
        withAnimation(.easeInOut(duration: 0.3)) {
            // First scroll to the message
            proxy.scrollTo(messageIndex, anchor: .center)
        }
        
        // Then notify the specific message to highlight and scroll to the exact match
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationCenter.default.post(
                name: NSNotification.Name("ScrollToSearchMatch"),
                object: nil,
                userInfo: [
                    "messageIndex": messageIndex,
                    "matchIndex": matchIndex,
                    "searchQuery": self.searchQuery
                ]
            )
            
            // Keep auto-scroll disabled for a bit longer to prevent interference
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Only restore auto-scroll if we were actually at bottom before
                if wasAtBottom {
                    self.isAtBottom = true
                }
            }
        }
    }
    
    private func goToPrevMatch() {
        guard searchResult.totalMatches > 0 else { return }
        if currentMatchIndex > 0 {
            currentMatchIndex -= 1
        } else {
            currentMatchIndex = searchResult.totalMatches - 1
        }
    }
    
    private func goToNextMatch() {
        guard searchResult.totalMatches > 0 else { return }
        if currentMatchIndex < searchResult.totalMatches - 1 {
            currentMatchIndex += 1
        } else {
            currentMatchIndex = 0
        }
    }
    
    // MARK: - Usage Toast
    
    private var usageToastView: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            Text(currentUsage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ?
                      Color(NSColor.windowBackgroundColor).opacity(0.95) :
                      Color(NSColor.windowBackgroundColor).opacity(0.95))
                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    private func showUsageToast(with usage: String) {
        currentUsage = usage
        
        // Cancel existing timer
        usageToastTimer?.invalidate()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showUsageToast = true
        }
        
        // Hide after 3 seconds
        usageToastTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            Task { @MainActor in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showUsageToast = false
                }
            }
        }
    }
    
    // MARK: - Loading Overlay

    private var loadingOverlayView: some View {
        ZStack {
            Rectangle()
                .fill(Color(NSColor.windowBackgroundColor))
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    // MARK: - Quick Access Message Handler
    
    private func handleQuickAccessMessage() {
        // Check if this chat is the target for a quick access message
        guard let targetChatId = AppCoordinator.shared.targetChatId,
              targetChatId == viewModel.chatId,
              AppCoordinator.shared.isProcessingQuickAccess else { return }
        
        let message = AppCoordinator.shared.quickAccessMessage ?? ""
        let attachments = AppCoordinator.shared.quickAccessAttachments
        
        // Must have either message or attachments
        guard !message.isEmpty || (attachments != nil && (!attachments!.images.isEmpty || !attachments!.documents.isEmpty)) else { return }
        
        print("DEBUG: Handling quick access message for chat: \(viewModel.chatId)")
        
        // Handle attachments if present
        if let attachments = attachments {
            // Copy attachments to the view model's shared media data source
            viewModel.sharedMediaDataSource.images = attachments.images
            viewModel.sharedMediaDataSource.documents = attachments.documents
            viewModel.sharedMediaDataSource.imageExtensions = attachments.imageExtensions
            viewModel.sharedMediaDataSource.imageFilenames = attachments.imageFilenames
            viewModel.sharedMediaDataSource.documentExtensions = attachments.documentExtensions
            viewModel.sharedMediaDataSource.documentFilenames = attachments.documentFilenames
            viewModel.sharedMediaDataSource.textPreviews = attachments.textPreviews
        }
        
        // Clear the message and attachments to prevent re-processing
        AppCoordinator.shared.quickAccessMessage = nil
        AppCoordinator.shared.quickAccessAttachments = nil
        
        // Send the message after a delay to ensure UI is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !message.isEmpty {
                self.viewModel.sendMessage(message)
            } else {
                // If only attachments, send empty message to trigger attachment sending
                self.viewModel.userInput = " " // Space to trigger send
                self.viewModel.sendMessage()
            }
        }
    }
}


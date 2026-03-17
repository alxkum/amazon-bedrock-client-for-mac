//
//  ChatModel.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import Foundation
import AWSBedrock

class ChatModel: Identifiable, Equatable, Hashable, @unchecked Sendable {
    var id: String
    var chatId: String
    var name: String
    var title: String
    var description: String
    let provider: String
    var lastMessageDate: Date
    var isManuallyRenamed: Bool = false // Track if user manually renamed this chat
    
    init(id: String, chatId: String, name: String, title: String, description: String, provider: String, lastMessageDate: Date, isManuallyRenamed: Bool = false) {
        self.id = id
        self.chatId = chatId
        self.name = name
        self.title = title
        self.description = description
        self.provider = provider
        self.lastMessageDate = lastMessageDate
        self.isManuallyRenamed = isManuallyRenamed
    }
    
    static func == (lhs: ChatModel, rhs: ChatModel) -> Bool {
        lhs.chatId == rhs.chatId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(chatId)
    }
    
    var displayName: String {
        var result = name
        // Strip region prefixes case-insensitively (from inference profiles)
        for prefix in ["Global ", "US "] {
            if result.lowercased().hasPrefix(prefix.lowercased()) {
                result = String(result.dropFirst(prefix.count))
            }
        }
        // Strip provider prefix case-insensitively (e.g. "Anthropic ", "Meta ", "Amazon ")
        let providerCandidates: [String]
        if !provider.isEmpty && !provider.contains("_") {
            providerCandidates = [provider]
        } else {
            // Inference profiles store type (e.g. "SYSTEM_DEFINED") as provider,
            // so fall back to common provider names
            providerCandidates = ["Anthropic", "Meta", "Amazon", "Mistral", "Cohere", "AI21 Labs", "Stability AI"]
        }
        for candidate in providerCandidates {
            let candidatePrefix = candidate + " "
            if result.lowercased().hasPrefix(candidatePrefix.lowercased()) {
                result = String(result.dropFirst(candidatePrefix.count))
                break
            }
        }
        return result
    }

    static func fromSummary(_ summary: BedrockClientTypes.FoundationModelSummary) -> ChatModel {
        ChatModel(
            id: summary.modelId ?? "",
            chatId: UUID().uuidString,
            name: summary.modelName ?? "",
            title: "New Chat",
            description: "\(summary.providerName ?? "") \(summary.modelName ?? "") (\(summary.modelId ?? ""))",
            provider: summary.providerName ?? "",
            lastMessageDate: Date()
        )
    }
    
    static func fromInferenceProfile(_ profileSummary: BedrockClientTypes.InferenceProfileSummary) -> ChatModel {
        return ChatModel(
            id: profileSummary.inferenceProfileId ?? "Unknown Id",  // Provide default if nil
            chatId: UUID().uuidString,  // Generate unique chatId
            name: profileSummary.inferenceProfileName ?? "Unknown Profile",  // Provide default if nil
            title: "Inference Profile: \(profileSummary.inferenceProfileName ?? "Unknown")",  // Provide default if nil
            description: profileSummary.description ?? "No description available",  // Provide default if nil
            provider: profileSummary.type?.rawValue ?? "Unknown Type",  // Use rawValue or default if nil
            lastMessageDate: profileSummary.updatedAt ?? Date()  // Use current date as default
        )
    }
}

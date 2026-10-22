//
//  LinkAI.swift
//  SaveLink
//
//  Summaries and tag suggestions with Apple's on-device model (Apple Intelligence).
//  Nothing is sent to a server.
//

import Foundation
import SwiftData
import FoundationModels

@Generable
nonisolated struct LinkInsights {
    @Guide(description: "A summary of the page in two or three short sentences, in the same language as the page.")
    var summary: String

    @Guide(description: "Short lowercase topic tags of one or two words, without #.", .count(1...3))
    var tags: [String]
}

enum LinkAI {
    enum AIError: LocalizedError {
        case unavailable(String)
        case noContent

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): return reason
            case .noContent: return "The page couldn't be read."
            }
        }
    }

    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Explains why Apple Intelligence can't be used, or nil when it can.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to use AI summaries."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading. Try again later."
        case .unavailable:
            return "Apple Intelligence isn't available right now."
        }
    }

    static func insights(for urlString: String, title: String) async throws -> LinkInsights {
        if let reason = unavailableReason { throw AIError.unavailable(reason) }
        guard let url = URL(string: Link.normalizedURLString(urlString)) else { throw AIError.noContent }

        let text = await pageText(from: url)
        guard text.count > 80 else { throw AIError.noContent }

        let session = LanguageModelSession(
            model: SystemLanguageModel(useCase: .contentTagging),
            instructions: "You summarize web pages that a user saved. Be factual and concise. Never invent details."
        )
        let prompt = """
        Title: \(title)
        URL: \(url.absoluteString)

        Page text:
        \(text)
        """
        return try await session.respond(to: prompt, generating: LinkInsights.self).content
    }

    /// Applies the summary and merges the suggested tags into the link.
    static func apply(_ insights: LinkInsights, to link: Link) {
        link.summary = insights.summary
        link.tags = TagFormatter.merge(link.tags, insights.tags)
        link.updatedAt = Date()
        link.modelContext?.saveAndBackup()
    }

    /// Downloads the page and returns its readable text, trimmed to fit the model's context.
    nonisolated static func pageText(from url: URL) async -> String {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return "" }

        let text = html
            .replacing(/(?is)<(script|style|noscript|svg|nav|footer|header)[^>]*>.*?<\/\1>/, with: " ")
            .replacing(/<[^>]+>/, with: " ")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(3500))
    }
}

/// Normalizes tags: lowercase, no #, no duplicates.
enum TagFormatter {
    static func clean(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .lowercased()
    }

    static func merge(_ existing: [String], _ new: [String]) -> [String] {
        var result = existing
        for tag in new.map(clean) where !tag.isEmpty && !result.contains(tag) {
            result.append(tag)
        }
        return result
    }
}

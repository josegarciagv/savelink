//
//  SmartSearch.swift
//  SaveLink
//
//  On-device meaning-based search: "recipe I saved last week" finds a link titled
//  "Easy weeknight pasta" even without matching words. Uses Apple's NaturalLanguage
//  sentence embeddings; nothing leaves the device.
//

import Foundation
import NaturalLanguage

enum SmartSearch {
    /// Links related to the query, best first. Exact text matches are expected to be shown separately.
    static func related(to query: String, in links: [Link], limit: Int = 10) -> [Link] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return [] }

        let (cleanQuery, dateRange) = extractDateRange(from: trimmed)
        var candidates = links
        if let dateRange {
            candidates = candidates.filter { dateRange.contains($0.createdAt) }
        }
        // Only a time phrase, like "last week": show everything saved then.
        guard !cleanQuery.isEmpty else {
            return Array(candidates.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
        }
        guard let embedding = embedding(for: cleanQuery) else { return [] }

        let scored = candidates.compactMap { link -> (Link, Double)? in
            let text = [link.name, link.summary, link.linkDescription, link.tags.joined(separator: " "), link.domain]
                .compactMap { $0 }
                .joined(separator: ". ")
            let distance = embedding.distance(between: cleanQuery.lowercased(), and: text.lowercased())
            // Cosine distance: 0 is identical, 2 is opposite.
            return distance < 1.05 ? (link, distance) : nil
        }
        return scored.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
    }

    private static func embedding(for text: String) -> NLEmbedding? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let language = recognizer.dominantLanguage ?? .english
        return NLEmbedding.sentenceEmbedding(for: language) ?? NLEmbedding.sentenceEmbedding(for: .english)
    }

    /// Understands "today", "yesterday", "this/last week", "this/last month" in English and Spanish.
    static func extractDateRange(from query: String) -> (String, ClosedRange<Date>?) {
        let calendar = Calendar.current
        let now = Date()
        let lower = query.lowercased()
        let phrases: [(keys: [String], range: () -> ClosedRange<Date>?)] = [
            (["today", "hoy"], { calendar.startOfDay(for: now)...now }),
            (["yesterday", "ayer"], {
                let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
                return start...calendar.startOfDay(for: now)
            }),
            (["last week", "semana pasada"], {
                guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now),
                      let last = calendar.dateInterval(of: .weekOfYear, for: thisWeek.start.addingTimeInterval(-1)) else { return nil }
                return last.start...last.end
            }),
            (["this week", "esta semana"], {
                calendar.dateInterval(of: .weekOfYear, for: now).map { $0.start...now }
            }),
            (["last month", "mes pasado"], {
                guard let thisMonth = calendar.dateInterval(of: .month, for: now),
                      let last = calendar.dateInterval(of: .month, for: thisMonth.start.addingTimeInterval(-1)) else { return nil }
                return last.start...last.end
            }),
            (["this month", "este mes"], {
                calendar.dateInterval(of: .month, for: now).map { $0.start...now }
            }),
        ]
        for phrase in phrases {
            for key in phrase.keys where lower.contains(key) {
                let cleaned = lower.replacingOccurrences(of: key, with: " ")
                    .replacing(/\b(from|of|saved|guardé|guardado|de|del|la|el)\b/, with: " ")
                    .replacing(/\s+/, with: " ")
                    .trimmingCharacters(in: .whitespaces)
                return (cleaned, phrase.range())
            }
        }
        return (query, nil)
    }
}

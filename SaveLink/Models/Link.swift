//
//  Link.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import Foundation
import SwiftData

// Every stored property has a default value: CloudKit (iCloud sync) requires it.
@Model
final class Link {
    var id: UUID = UUID()
    var name: String = ""
    var url: String = ""
    var linkDescription: String?
    var createdAt: Date = Date()
    var updatedAt: Date?
    var folder: Folder?
    var isFavorite: Bool = false
    var visitCount: Int = 0
    var lastOpenedAt: Date?
    var tags: [String] = []
    var isReadLater: Bool = false
    var reminderDate: Date?
    /// Set when the link is moved to Recently Deleted.
    var deletedAt: Date?
    /// On-device AI summary of the page.
    var summary: String?
    var isBroken: Bool = false
    var lastCheckedAt: Date?
    /// Readable text of the page, saved for offline reading.
    @Attribute(.externalStorage) var readerText: String?
    var readerSavedAt: Date?
    /// Paragraphs the user highlighted in the reader.
    var highlights: [String] = []
    var notes: String?

    init(name: String, url: String, linkDescription: String? = nil) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.linkDescription = linkDescription
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // Computed property to get last updated date
    var lastUpdatedDate: Date {
        return updatedAt ?? createdAt
    }

    /// Host without the "www." prefix, e.g. "apple.com".
    var domain: String {
        Link.domain(for: url)
    }

    var isTrashed: Bool {
        deletedAt != nil
    }
    
    /// Moves the link to Recently Deleted (kept for 30 days).
    func moveToTrash() {
        deletedAt = Date()
        isFavorite = false
        if reminderDate != nil {
            ReminderScheduler.cancel(for: self)
            reminderDate = nil
        }
    }
    
    static func domain(for urlString: String) -> String {
        guard let host = URL(string: normalizedURLString(urlString))?.host() else { return urlString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func faviconURL(for urlString: String) -> URL? {
        let host = domain(for: urlString)
        guard !host.isEmpty else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(host)")
    }

    /// Adds https:// when the scheme is missing and trims whitespace.
    static func normalizedURLString(_ string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("://") { return trimmed }
        return "https://" + trimmed
    }

    static func isValidURL(_ string: String) -> Bool {
        let normalized = normalizedURLString(string)
        guard let url = URL(string: normalized), let host = url.host()?.lowercased(), !host.isEmpty else { return false }
        // Non-web schemes (mailto:, tel:, custom app links) only need to parse.
        guard url.scheme == "http" || url.scheme == "https" else { return true }
        if host == "localhost" { return true }
        // Domain names ("sub.example.com") or IPv4 addresses.
        return host.wholeMatch(of: /([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,63}/) != nil
            || host.wholeMatch(of: /(\d{1,3}\.){3}\d{1,3}/) != nil
    }
}

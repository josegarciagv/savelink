//
//  BookmarkImporter.swift
//  SaveLink
//

import Foundation
import SwiftData

/// Imports bookmark files exported from Safari, Chrome, Firefox, Pocket or SaveLink.
/// All of them use the Netscape bookmarks HTML format.
enum BookmarkImporter {
    struct Entry {
        var folder: String
        var url: String
        var title: String
        var tags: [String]
        var isReadLater: Bool
    }

    struct Result {
        var imported = 0
        var duplicates = 0
        var skippedByLimit = 0
        var folders = 0
    }

    static func parse(_ html: String) -> [Entry] {
        let headingRegex = /<[hH][1-6][^>]*>(.*?)<\/[hH][1-6]>/
        let linkRegex = /<[aA]\s([^>]*)>(.*?)<\/[aA]>/
        let hrefRegex = /(?i)href\s*=\s*"([^"]*)"/
        let tagsRegex = /(?i)tags\s*=\s*"([^"]*)"/

        var entries: [Entry] = []
        var currentFolder = "Imported"

        for line in html.components(separatedBy: .newlines) {
            if let heading = line.firstMatch(of: headingRegex) {
                let name = decode(String(heading.1)).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { currentFolder = name }
            }
            for match in line.matches(of: linkRegex) {
                let attributes = String(match.1)
                guard let href = attributes.firstMatch(of: hrefRegex).map({ decode(String($0.1)) }),
                      href.hasPrefix("http") else { continue }
                let title = decode(stripTags(String(match.2))).trimmingCharacters(in: .whitespacesAndNewlines)
                let tags = attributes.firstMatch(of: tagsRegex).map {
                    String($0.1).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
                } ?? []
                entries.append(Entry(
                    folder: currentFolder,
                    url: href,
                    title: title.isEmpty ? Link.domain(for: href) : title,
                    tags: tags,
                    isReadLater: currentFolder.lowercased() == "unread"
                ))
            }
        }
        return entries
    }

    /// Adds the entries, reusing folders with the same name and skipping URLs already saved.
    static func importEntries(_ entries: [Entry], into context: ModelContext, linkLimit: Int?) -> Result {
        var result = Result()
        var folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        let existing = (try? context.fetch(FetchDescriptor<Link>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        var savedURLs = Set(existing.map { $0.url.lowercased() })
        var count = existing.count

        for entry in entries {
            let url = Link.normalizedURLString(entry.url)
            guard !savedURLs.contains(url.lowercased()) else {
                result.duplicates += 1
                continue
            }
            if let linkLimit, count >= linkLimit {
                result.skippedByLimit += 1
                continue
            }

            let folder: Folder
            if let match = folders.first(where: { $0.name.caseInsensitiveCompare(entry.folder) == .orderedSame && !$0.isLocked }) {
                folder = match
            } else {
                folder = Folder(name: entry.folder, pin: "", color: Theme.defaultFolderColor, icon: "square.and.arrow.down.fill")
                context.insert(folder)
                folders.append(folder)
                result.folders += 1
            }

            let link = Link(name: entry.title, url: url)
            link.tags = entry.tags
            link.isReadLater = entry.isReadLater
            link.folder = folder
            folder.links.append(link)
            context.insert(link)
            savedURLs.insert(url.lowercased())
            count += 1
            result.imported += 1
        }

        if result.imported > 0 {
            context.saveAndBackup()
        }
        return result
    }

    private static func stripTags(_ s: String) -> String {
        s.replacing(/<[^>]+>/, with: "")
    }

    private static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}

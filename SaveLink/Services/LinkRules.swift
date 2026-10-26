//
//  LinkRules.swift
//  SaveLink
//
//  "When a link is from youtube.com, put it in Videos and tag it #video."
//

import Foundation
import SwiftData
import Combine

struct LinkRule: Codable, Identifiable, Hashable {
    var id = UUID()
    /// Matched against the link's domain and URL, case-insensitive (e.g. "youtube.com").
    var pattern: String
    var folderID: UUID?
    var tags: [String] = []
    var markReadLater = false

    func matches(_ urlString: String) -> Bool {
        let needle = pattern.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return false }
        return Link.domain(for: urlString).lowercased().contains(needle)
            || urlString.lowercased().contains(needle)
    }
}

@MainActor
final class LinkRules: ObservableObject {
    static let shared = LinkRules()
    private let key = "linkRules"

    @Published var rules: [LinkRule] {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([LinkRule].self, from: data) {
            rules = decoded
        } else {
            rules = []
        }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(rules), forKey: key)
    }

    /// First rule that matches the URL, if any.
    func rule(for urlString: String) -> LinkRule? {
        rules.first { $0.matches(urlString) }
    }

    /// Applies the matching rule to a link that is being saved. When `overrideFolder` is false,
    /// the folder is only changed if the link has none.
    func apply(to link: Link, in context: ModelContext, overrideFolder: Bool) {
        guard let rule = rule(for: link.url) else { return }
        link.tags = TagFormatter.merge(link.tags, rule.tags)
        if rule.markReadLater { link.isReadLater = true }
        guard let folderID = rule.folderID, overrideFolder || link.folder == nil,
              let folders = try? context.fetch(FetchDescriptor<Folder>()),
              let target = folders.first(where: { $0.id == folderID }),
              target.id != link.folder?.id else { return }
        link.folder?.links.removeAll { $0.id == link.id }
        link.folder = target
        target.links.append(link)
    }
}

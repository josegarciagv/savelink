//
//  SharedStore.swift
//  SaveLink
//
//  Shared between the app and the Share extension through the App Group.
//  The extension never opens the SwiftData store: it reads a snapshot of the
//  folders and queues new links, which the app imports when it becomes active.
//

import Foundation

enum SharedStore {
    static let appGroupID = "group.gvwebsite.savelinks"
    static let freeLinkLimit = 50

    private static let foldersKey = "shared_folders"
    private static let pendingKey = "pending_links"
    private static let isProKey = "is_pro"
    private static let linkCountKey = "link_count"
    private static let widgetKey = "widget_snapshot"
    private static let savedURLsKey = "saved_urls"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    struct FolderSnapshot: Codable, Identifiable, Hashable {
        let id: UUID
        let name: String
        let icon: String
        let color: String
    }

    /// What the home screen widgets show.
    struct WidgetLink: Codable, Identifiable, Hashable {
        let id: UUID
        let name: String
        let domain: String
        let color: String
    }

    struct WidgetSnapshot: Codable {
        var favorites: [WidgetLink] = []
        var readLater: [WidgetLink] = []
        var recent: [WidgetLink] = []
        var linkCount = 0
        var readLaterCount = 0
    }

    struct PendingLink: Codable {
        let url: String
        let name: String
        let folderID: UUID?
        let isFavorite: Bool
        let createdAt: Date
    }

    // MARK: - Written by the app

    static func publish(folders: [FolderSnapshot], linkCount: Int) {
        guard let defaults else { return }
        defaults.set(try? JSONEncoder().encode(folders), forKey: foldersKey)
        defaults.set(linkCount, forKey: linkCountKey)
    }

    /// Lower-cased URLs of saved links, so extensions can spot duplicates.
    static func publish(savedURLs: [String]) {
        defaults?.set(savedURLs.map { $0.lowercased() }, forKey: savedURLsKey)
    }

    static func isAlreadySaved(_ url: String) -> Bool {
        let saved = Set(defaults?.stringArray(forKey: savedURLsKey) ?? [])
        let lower = url.lowercased()
        return saved.contains(lower) || saved.contains(lower.hasSuffix("/") ? String(lower.dropLast()) : lower + "/")
    }

    static func publish(widget snapshot: WidgetSnapshot) {
        defaults?.set(try? JSONEncoder().encode(snapshot), forKey: widgetKey)
    }

    static var widgetSnapshot: WidgetSnapshot {
        guard let data = defaults?.data(forKey: widgetKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return snapshot
    }

    static func publish(isPro: Bool) {
        defaults?.set(isPro, forKey: isProKey)
    }

    /// Returns and clears the links queued by the extension.
    static func takePendingLinks() -> [PendingLink] {
        guard let defaults,
              let data = defaults.data(forKey: pendingKey),
              let links = try? JSONDecoder().decode([PendingLink].self, from: data) else { return [] }
        defaults.removeObject(forKey: pendingKey)
        return links
    }

    // MARK: - Read by the extension

    static var folders: [FolderSnapshot] {
        guard let data = defaults?.data(forKey: foldersKey),
              let folders = try? JSONDecoder().decode([FolderSnapshot].self, from: data) else { return [] }
        return folders
    }

    static var pendingCount: Int {
        guard let data = defaults?.data(forKey: pendingKey),
              let links = try? JSONDecoder().decode([PendingLink].self, from: data) else { return 0 }
        return links.count
    }

    /// Free users can't queue links past the plan limit (including ones already waiting).
    static var canSaveMoreLinks: Bool {
        guard let defaults else { return false }
        if defaults.bool(forKey: isProKey) { return true }
        return defaults.integer(forKey: linkCountKey) + pendingCount < freeLinkLimit
    }

    static func enqueue(_ link: PendingLink) -> Bool {
        guard let defaults else { return false }
        var links: [PendingLink] = []
        if let data = defaults.data(forKey: pendingKey),
           let existing = try? JSONDecoder().decode([PendingLink].self, from: data) {
            links = existing
        }
        links.append(link)
        guard let data = try? JSONEncoder().encode(links) else { return false }
        defaults.set(data, forKey: pendingKey)
        return true
    }
}

// MARK: - Actions from widgets

extension SharedStore {
    private static let readMarksKey = "pending_read_marks"

    /// Called by the widget: hides the link from Read Later right away and
    /// queues the change for the app, which owns the database.
    static func markRead(_ id: UUID) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        var snapshot = widgetSnapshot
        snapshot.readLater.removeAll { $0.id == id }
        snapshot.readLaterCount = max(0, snapshot.readLaterCount - 1)
        publish(widget: snapshot)
        var marks = defaults.stringArray(forKey: readMarksKey) ?? []
        marks.append(id.uuidString)
        defaults.set(marks, forKey: readMarksKey)
    }

    /// Returns and clears the links marked as read from widgets.
    static func takeReadMarks() -> [UUID] {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return [] }
        let marks = defaults.stringArray(forKey: readMarksKey) ?? []
        defaults.removeObject(forKey: readMarksKey)
        return marks.compactMap(UUID.init(uuidString:))
    }
}

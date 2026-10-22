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

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    struct FolderSnapshot: Codable, Identifiable, Hashable {
        let id: UUID
        let name: String
        let icon: String
        let color: String
        let isLocked: Bool
    }

    /// What the home screen widgets show. Never includes links from PIN-protected folders.
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

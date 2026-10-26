//
//  AppIntents.swift
//  SaveLink
//
//  Siri, Shortcuts and Spotlight actions.
//

import AppIntents
import SwiftData
import Foundation
import UIKit

// MARK: - Entities

struct LinkEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Link"
    static let defaultQuery = LinkEntityQuery()

    let id: UUID
    let name: String
    let url: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(Link.domain(for: url))")
    }

    init(_ link: Link) {
        id = link.id
        name = link.name
        url = link.url
    }
}

struct LinkEntityQuery: EntityStringQuery {
    /// Links in Recently Deleted are not exposed to the system.
    @MainActor
    private func visibleLinks() -> [Link] {
        let links = (try? AppModelContainer.shared.mainContext.fetch(
            FetchDescriptor<Link>(predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        )) ?? []
        return links
    }

    func entities(for identifiers: [UUID]) async throws -> [LinkEntity] {
        await visibleLinks().filter { identifiers.contains($0.id) }.map(LinkEntity.init)
    }

    func entities(matching string: String) async throws -> [LinkEntity] {
        await visibleLinks().filter {
            $0.name.localizedCaseInsensitiveContains(string)
                || $0.url.localizedCaseInsensitiveContains(string)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(string) }
        }.map(LinkEntity.init)
    }

    func suggestedEntities() async throws -> [LinkEntity] {
        let links = await visibleLinks()
        let favorites = links.filter(\.isFavorite)
        return Array((favorites.isEmpty ? links : favorites).prefix(20)).map(LinkEntity.init)
    }
}

struct FolderEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Folder"
    static let defaultQuery = FolderEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct FolderEntityQuery: EntityQuery {
    @MainActor
    private func folders() -> [Folder] {
        (try? AppModelContainer.shared.mainContext.fetch(FetchDescriptor<Folder>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    func entities(for identifiers: [UUID]) async throws -> [FolderEntity] {
        await folders().filter { identifiers.contains($0.id) }.map { FolderEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [FolderEntity] {
        await folders().map { FolderEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - Intents

struct SaveLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Link"
    static let description = IntentDescription("Saves a web link to SaveLinks.")

    @Parameter(title: "URL")
    var url: URL

    @Parameter(title: "Name")
    var name: String?

    @Parameter(title: "Folder")
    var folder: FolderEntity?

    @Parameter(title: "Read Later", default: false)
    var readLater: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$url) to \(\.$folder)") {
            \.$name
            \.$readLater
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await save()
        return .result(dialog: "\(message)")
    }

    /// Saves the link and returns the message to show.
    @MainActor
    func save() async throws -> String {
        let context = AppModelContainer.shared.mainContext
        let activeCount = (try? context.fetchCount(FetchDescriptor<Link>(predicate: #Predicate { $0.deletedAt == nil }))) ?? 0
        guard SubscriptionManager.shared.canAddMoreLinks(currentCount: activeCount) else {
            return String(localized: "You've reached the free limit of 50 links. Open SaveLinks to upgrade.")
        }

        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        let target: Folder
        if let match = folders.first(where: { $0.id == folder?.id }) ?? folders.first {
            target = match
        } else {
            target = Folder(name: "Inbox", color: Theme.defaultFolderColor, icon: "tray.fill")
            context.insert(target)
        }

        let urlString = url.absoluteString
        var title = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty {
            title = await LinkMetadataFetcher.title(for: urlString) ?? Link.domain(for: urlString)
        }

        let link = Link(name: title, url: Link.normalizedURLString(urlString))
        link.isReadLater = readLater
        link.folder = target
        target.links.append(link)
        target.updatedAt = Date()
        context.insert(link)
        LinkRules.shared.apply(to: link, in: context, overrideFolder: folder == nil)
        context.saveAndBackup()
        return String(localized: "Saved \"\(title)\" to \(target.name).")
    }
}

/// For the Action button and Shortcuts: saves the link that's in the clipboard.
struct SaveClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Copied Link"
    static let description = IntentDescription("Saves the link in the clipboard to SaveLinks.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let pasteboard = UIPasteboard.general
        let text = pasteboard.url?.absoluteString ?? pasteboard.string ?? ""
        guard Link.isValidURL(text), let url = URL(string: Link.normalizedURLString(text)) else {
            return .result(dialog: "There's no link in the clipboard.")
        }
        var intent = SaveLinkIntent()
        intent.url = url
        intent.readLater = false
        let message = try await intent.save()
        return .result(dialog: "\(message)")
    }
}

struct OpenLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Saved Link"
    static let description = IntentDescription("Opens a link saved in SaveLinks.")
    static let openAppWhenRun = true

    @Parameter(title: "Link")
    var link: LinkEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        LinkOpener.shared.open(linkID: link.id)
        return .result()
    }
}

struct ReadLaterCountIntent: AppIntent {
    static let title: LocalizedStringResource = "Read Later Count"
    static let description = IntentDescription("Tells you how many links are waiting in Read Later.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let links = (try? AppModelContainer.shared.mainContext.fetch(
            FetchDescriptor<Link>(predicate: #Predicate { $0.deletedAt == nil && $0.isReadLater })
        )) ?? []
        let count = links.count
        let dialog: IntentDialog = count == 0 ? "Your Read Later list is empty." : "You have \(count) links to read later."
        return .result(value: count, dialog: dialog)
    }
}

struct SaveLinkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveLinkIntent(),
            phrases: [
                "Save a link in \(.applicationName)",
                "Add a link to \(.applicationName)"
            ],
            shortTitle: "Save Link",
            systemImageName: "link.badge.plus"
        )
        AppShortcut(
            intent: SaveClipboardIntent(),
            phrases: [
                "Save copied link in \(.applicationName)",
                "Save clipboard to \(.applicationName)"
            ],
            shortTitle: "Save Copied Link",
            systemImageName: "doc.on.clipboard"
        )
        AppShortcut(
            intent: OpenLinkIntent(),
            phrases: [
                "Open \(\.$link) in \(.applicationName)",
                "Open a saved link in \(.applicationName)"
            ],
            shortTitle: "Open Link",
            systemImageName: "safari"
        )
        AppShortcut(
            intent: ReadLaterCountIntent(),
            phrases: [
                "What do I have to read in \(.applicationName)",
                "Read later in \(.applicationName)"
            ],
            shortTitle: "Read Later",
            systemImageName: "book"
        )
    }
}

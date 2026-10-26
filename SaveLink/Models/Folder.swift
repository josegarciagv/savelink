//
//  Folder.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import Foundation
import SwiftData

// Every stored property has a default value and the relationship is optional:
// CloudKit (iCloud sync) requires both.
@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    var color: String = "007AFF" // Hex color string
    var createdAt: Date = Date()
    var updatedAt: Date?
    var icon: String = "folder.fill" // SF Symbol name
    var isPinned: Bool = false
    @Relationship(deleteRule: .cascade, originalName: "links", inverse: \Link.folder)
    var storedLinks: [Link]? = []
    
    var links: [Link] {
        get { storedLinks ?? [] }
        set { storedLinks = newValue }
    }

    init(name: String, color: String, icon: String = "folder.fill") {
        self.id = UUID()
        self.name = name
        self.color = color
        self.icon = icon
        self.createdAt = Date()
        self.updatedAt = Date()
        self.storedLinks = []
    }

    /// Links that aren't in Recently Deleted.
    var activeLinks: [Link] {
        links.filter { $0.deletedAt == nil }
    }
    
    // Computed property to get last updated date (from links or folder update)
    var lastUpdatedDate: Date {
        let folderUpdateDate = updatedAt ?? createdAt
        if let latestLink = links.max(by: { $0.createdAt < $1.createdAt }) {
            return latestLink.createdAt > folderUpdateDate ? latestLink.createdAt : folderUpdateDate
        }
        return folderUpdateDate
    }
}

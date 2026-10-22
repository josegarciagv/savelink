//
//  Folder.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import Foundation
import SwiftData

@Model
final class Folder {
    var id: UUID
    var name: String
    var pin: String
    var color: String // Hex color string
    var createdAt: Date
    var updatedAt: Date?
    @Relationship(deleteRule: .cascade) var links: [Link]
    
    init(name: String, pin: String, color: String) {
        self.id = UUID()
        self.name = name
        self.pin = pin
        self.color = color
        self.createdAt = Date()
        self.updatedAt = Date()
        self.links = []
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


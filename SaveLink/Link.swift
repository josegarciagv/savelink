//
//  Link.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import Foundation
import SwiftData

@Model
final class Link {
    var id: UUID
    var name: String
    var url: String
    var linkDescription: String?
    var createdAt: Date
    var updatedAt: Date?
    var folder: Folder?
    
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
}


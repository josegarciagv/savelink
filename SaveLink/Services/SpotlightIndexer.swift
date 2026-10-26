//
//  SpotlightIndexer.swift
//  SaveLink
//

import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Makes saved links searchable from the iPhone's Spotlight search.
/// Links in Recently Deleted are never indexed.
enum SpotlightIndexer {
    private static var pendingTask: Task<Void, Never>?

    static func reindex(_ links: [Link]) {
        let items = links
            .filter { !$0.isTrashed }
            .map { link -> CSSearchableItem in
                let attributes = CSSearchableItemAttributeSet(contentType: .url)
                attributes.title = link.name
                attributes.contentDescription = link.summary ?? link.linkDescription ?? link.domain
                attributes.contentURL = URL(string: link.url)
                attributes.keywords = link.tags + [link.domain, link.folder?.name ?? ""]
                return CSSearchableItem(uniqueIdentifier: link.id.uuidString, domainIdentifier: "links", attributeSet: attributes)
            }

        // Coalesce bursts of saves into one reindex.
        pendingTask?.cancel()
        pendingTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let index = CSSearchableIndex.default()
            try? await index.deleteSearchableItems(withDomainIdentifiers: ["links"])
            try? await index.indexSearchableItems(items)
        }
    }
}

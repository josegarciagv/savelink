//
//  WidgetIntents.swift
//  SaveLink
//
//  Intents run by interactive widgets. Compiled into the app and the widget extension.
//

import AppIntents
import WidgetKit
import Foundation

struct MarkReadIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark as Read"
    static let isDiscoverable = false

    @Parameter(title: "Link ID")
    var linkID: String

    init() {}

    init(linkID: UUID) {
        self.linkID = linkID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: linkID) {
            SharedStore.markRead(id)
            WidgetCenter.shared.reloadAllTimelines()
        }
        return .result()
    }
}

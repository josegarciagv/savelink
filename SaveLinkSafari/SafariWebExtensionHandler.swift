//
//  SafariWebExtensionHandler.swift
//  SaveLinkSafari
//
//  Receives "save" messages from the Safari toolbar button and queues the page
//  for the app, like the Share extension does.
//

import Foundation
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        let reply = handle(message ?? [:])

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    private func handle(_ message: [String: Any]) -> [String: Any] {
        guard message["action"] as? String == "save",
              let url = message["url"] as? String,
              url.lowercased().hasPrefix("http") else {
            return ["status": "error"]
        }
        guard SharedStore.canSaveMoreLinks else {
            return ["status": "limit"]
        }
        if SharedStore.isAlreadySaved(url) {
            return ["status": "duplicate"]
        }

        // Same default folder as the Share extension.
        let folder = SharedStore.folders.first
        let title = (message["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pending = SharedStore.PendingLink(
            url: url,
            name: title.isEmpty ? (URL(string: url)?.host() ?? url) : title,
            folderID: folder?.id,
            isFavorite: false,
            createdAt: Date()
        )
        guard SharedStore.enqueue(pending) else { return ["status": "error"] }
        return ["status": "saved", "folder": folder?.name ?? ""]
    }
}

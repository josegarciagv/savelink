//
//  ShareViewController.swift
//  SaveLinkShare
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Entry point of the Share extension: hosts the SwiftUI save form.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let item = extensionContext?.inputItems.first as? NSExtensionItem
        let pageTitle = item?.attributedContentText?.string
            ?? item?.attributedTitle?.string
        let providers = item?.attachments ?? []

        let root = ShareView(
            pageTitle: pageTitle,
            loadURL: { await Self.loadURL(from: providers) },
            onFinish: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        )
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    /// Finds a web URL in the shared items, or the first URL inside shared text.
    private static func loadURL(from providers: [NSItemProvider]) async -> String? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                return url.absoluteString
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
               let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
               let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let url = match.url {
                return url.absoluteString
            }
        }
        return nil
    }
}

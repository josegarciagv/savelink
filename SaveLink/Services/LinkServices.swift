//
//  LinkServices.swift
//  SaveLink
//

import SwiftUI
import SwiftData
import LinkPresentation
import CoreImage.CIFilterBuiltins
import Observation
import UniformTypeIdentifiers

// MARK: - Opening links

/// Opens links either in the in-app browser or in the default browser, and tracks visits.
@Observable
final class LinkOpener {
    static let shared = LinkOpener()

    var presentedURL: IdentifiableURL?

    private init() {}

    /// Opens a link by id (from a notification, widget, Spotlight or Siri).
    func open(linkID: UUID) {
        let context = AppModelContainer.shared.mainContext
        var descriptor = FetchDescriptor<Link>(predicate: #Predicate { $0.id == linkID && $0.deletedAt == nil })
        descriptor.fetchLimit = 1
        guard let link = try? context.fetch(descriptor).first else { return }
        open(link)
    }

    func open(_ link: Link) {
        guard let url = URL(string: Link.normalizedURLString(link.url)) else { return }
        link.visitCount += 1
        link.lastOpenedAt = Date()
        // Opening a Read Later link marks it as read.
        if link.isReadLater {
            link.isReadLater = false
            if link.reminderDate != nil {
                ReminderScheduler.cancel(for: link)
                link.reminderDate = nil
            }
        }
        link.modelContext?.saveAndBackup()
        Haptics.tap()

        let openInApp = UserDefaults.standard.object(forKey: "openLinksInApp") as? Bool ?? true
        let isWeb = url.scheme == "http" || url.scheme == "https"
        if openInApp && isWeb {
            presentedURL = IdentifiableURL(url: url)
        } else {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Metadata

enum LinkMetadataFetcher {
    /// Fetches the page title for a URL, or nil if it can't be loaded.
    static func title(for urlString: String) async -> String? {
        guard Link.isValidURL(urlString), let url = URL(string: Link.normalizedURLString(urlString)) else { return nil }
        let provider = LPMetadataProvider()
        provider.timeout = 8
        guard let metadata = try? await provider.startFetchingMetadata(for: url),
              let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        return title
    }
}

// MARK: - QR code

enum QRCodeGenerator {
    static func image(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Export

enum LinkExporter {
    /// Writes a Netscape bookmarks file (importable by Safari, Chrome, Firefox).
    static func bookmarksFile(folders: [Folder], fileName: String = "SaveLink Bookmarks") -> URL? {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }

        var html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>SaveLink Bookmarks</TITLE>
        <H1>SaveLink Bookmarks</H1>
        <DL><p>

        """
        for folder in folders {
            html += "    <DT><H3>\(escape(folder.name))</H3>\n    <DL><p>\n"
            for link in folder.activeLinks.sorted(by: { $0.createdAt < $1.createdAt }) {
                let added = Int(link.createdAt.timeIntervalSince1970)
                html += "        <DT><A HREF=\"\(escape(link.url))\" ADD_DATE=\"\(added)\">\(escape(link.name))</A>\n"
                if let description = link.linkDescription, !description.isEmpty {
                    html += "        <DD>\(escape(description))\n"
                }
            }
            html += "    </DL><p>\n"
        }
        html += "</DL><p>\n"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).html")
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("Failed to write export: \(error)")
            return nil
        }
    }
}

/// A folder shared as a bookmarks file. The file is only written when the user shares it.
/// Anyone can open it in a browser or import it into SaveLinks.
struct FolderBookmarks: Transferable {
    let folder: Folder

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .html) { item in
            let url = await MainActor.run {
                LinkExporter.bookmarksFile(folders: [item.folder], fileName: item.folder.name)
            }
            guard let url else { throw CocoaError(.fileWriteUnknown) }
            return SentTransferredFile(url)
        }
    }
}

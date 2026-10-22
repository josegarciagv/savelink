//
//  LinkComponents.swift
//  SaveLink
//

import SwiftUI
import SwiftData

// MARK: - Views

struct FaviconView: View {
    let urlString: String
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(color.opacity(0.12))
            AsyncImage(url: Link.faviconURL(for: urlString)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 0.55, height: size * 0.55)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.1, style: .continuous))
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(color)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

struct LinkRowView: View {
    let link: Link
    var showFolder = false

    var body: some View {
        HStack(spacing: 14) {
            FaviconView(urlString: link.url, color: .folder(link.folder?.color), size: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(link.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if link.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    if link.isReadLater {
                        Image(systemName: link.reminderDate == nil ? "book.fill" : "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if link.isBroken {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                if let description = link.linkDescription, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Text(link.domain)
                    if showFolder, let folder = link.folder {
                        Text("·")
                        Image(systemName: folder.icon)
                        Text(folder.name)
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                if !link.tags.isEmpty {
                    Text(link.tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.folder(link.folder?.color))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Context-menu actions shared by every place a link is listed.
struct LinkContextMenu: View {
    let link: Link
    var onMove: (() -> Void)? = nil

    var body: some View {
        Button {
            LinkOpener.shared.open(link)
        } label: {
            Label("Open", systemImage: "safari")
        }
        Button {
            UIPasteboard.general.string = link.url
            Haptics.success()
        } label: {
            Label("Copy URL", systemImage: "doc.on.doc")
        }
        if let url = URL(string: link.url) {
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        Button {
            link.isFavorite.toggle()
            link.modelContext?.saveAndBackup()
            Haptics.tap()
        } label: {
            Label(link.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: link.isFavorite ? "star.slash" : "star")
        }
        Button {
            link.isReadLater.toggle()
            if !link.isReadLater, link.reminderDate != nil {
                ReminderScheduler.cancel(for: link)
                link.reminderDate = nil
            }
            link.modelContext?.saveAndBackup()
            Haptics.tap()
        } label: {
            Label(link.isReadLater ? "Mark as Read" : "Read Later",
                  systemImage: link.isReadLater ? "checkmark.circle" : "book")
        }
        if let onMove {
            Button(action: onMove) {
                Label("Move to Folder", systemImage: "folder")
            }
        }
        Divider()
        Button(role: .destructive) {
            link.moveToTrash()
            link.modelContext?.saveAndBackup()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

/// Picks a destination folder for a link.

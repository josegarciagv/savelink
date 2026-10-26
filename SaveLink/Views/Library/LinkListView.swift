//
//  LinkListView.swift
//  SaveLink
//

import SwiftUI
import SwiftData

/// Smart lists that gather links from every folder.
enum LinkFilter: Hashable {
    case favorites
    case readLater
    case tag(String)
    case broken

    var title: String {
        switch self {
        case .favorites: return String(localized: "Favorites")
        case .readLater: return String(localized: "Read Later")
        case .tag(let tag): return String(localized: "#\(tag)")
        case .broken: return String(localized: "Broken Links")
        }
    }

    var icon: String {
        switch self {
        case .favorites: return "star.fill"
        case .readLater: return "book.fill"
        case .tag: return "number"
        case .broken: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .favorites: return .yellow
        case .readLater: return .orange
        case .tag: return Theme.brand
        case .broken: return .red
        }
    }

    func matches(_ link: Link) -> Bool {
        switch self {
        case .favorites: return link.isFavorite
        case .readLater: return link.isReadLater
        case .tag(let tag): return link.tags.contains(tag)
        case .broken: return link.isBroken
        }
    }
}

struct LinkListView: View {
    let filter: LinkFilter
    @Query(filter: #Predicate<Link> { $0.deletedAt == nil }, sort: \Link.createdAt, order: .reverse)
    private var allLinks: [Link]
    @State private var linkToMove: Link?
    @State private var isChecking = false
    @State private var checked = 0

    private var links: [Link] {
        allLinks.filter { filter.matches($0) }
    }

    var body: some View {
        List {
            if links.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: filter.icon)
                } description: {
                    Text(emptyMessage)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(links) { link in
                        NavigationLink(value: link) {
                            LinkRowView(link: link, showFolder: true)
                        }
                        .swipeActions(edge: .leading) {
                            if filter == .readLater {
                                Button {
                                    link.isReadLater = false
                                    if link.reminderDate != nil {
                                        ReminderScheduler.cancel(for: link)
                                        link.reminderDate = nil
                                    }
                                    link.modelContext?.saveAndBackup()
                                    Haptics.success()
                                } label: {
                                    Label("Read", systemImage: "checkmark")
                                }
                                .tint(.green)
                            } else {
                                Button {
                                    link.isFavorite.toggle()
                                    link.modelContext?.saveAndBackup()
                                    Haptics.tap()
                                } label: {
                                    Label("Favorite", systemImage: link.isFavorite ? "star.slash.fill" : "star.fill")
                                }
                                .tint(.yellow)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                link.moveToTrash()
                                link.modelContext?.saveAndBackup()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            LinkContextMenu(link: link) { linkToMove = link }
                        }
                    }
                } footer: {
                    if filter == .readLater {
                        Text("Links leave this list when you open them or swipe right.")
                    } else if filter == .broken {
                        Text("These pages returned an error or their site no longer exists.")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(filter.title)
        .toolbar {
            if filter == .broken {
                ToolbarItem(placement: .topBarTrailing) {
                    if isChecking {
                        ProgressView()
                    } else {
                        Button("Check Again") {
                            Task { await recheck() }
                        }
                    }
                }
            }
        }
        .sheet(item: $linkToMove) { link in
            MoveLinkView(link: link)
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .favorites: return String(localized: "No Favorites")
        case .readLater: return String(localized: "All Caught Up")
        case .tag: return String(localized: "No Links")
        case .broken: return String(localized: "No Broken Links")
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .favorites: return String(localized: "Tap the star on any link to add it here.")
        case .readLater: return String(localized: "Save links for later and they'll wait for you here.")
        case .tag: return String(localized: "No links use this tag yet.")
        case .broken: return String(localized: "Every link you checked still works.")
        }
    }

    private func recheck() async {
        isChecking = true
        _ = await BrokenLinkChecker.check(allLinks) { _ in }
        isChecking = false
    }
}

/// Links in Recently Deleted, restorable for 30 days.
struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Link> { $0.deletedAt != nil }, sort: \Link.deletedAt, order: .reverse)
    private var trashed: [Link]
    @State private var showEmptyConfirmation = false

    var body: some View {
        List {
            if trashed.isEmpty {
                ContentUnavailableView("Recently Deleted Is Empty", systemImage: "trash", description: Text("Deleted links stay here for 30 days."))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(trashed) { link in
                        trashRow(link)
                            .swipeActions(edge: .leading) {
                                Button {
                                    restore(link)
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    modelContext.delete(link)
                                    modelContext.saveAndBackup()
                                } label: {
                                    Label("Delete Forever", systemImage: "trash.slash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    restore(link)
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                Button(role: .destructive) {
                                    modelContext.delete(link)
                                    modelContext.saveAndBackup()
                                } label: {
                                    Label("Delete Forever", systemImage: "trash.slash")
                                }
                            }
                    }
                } footer: {
                    Text("Swipe right to restore. Links are permanently deleted after 30 days.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Recently Deleted")
        .toolbar {
            if !trashed.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Empty", role: .destructive) {
                        showEmptyConfirmation = true
                    }
                    .tint(.red)
                }
            }
        }
        .confirmationDialog("Permanently delete \(trashed.count) links?", isPresented: $showEmptyConfirmation, titleVisibility: .visible) {
            Button("Delete Forever", role: .destructive) {
                trashed.forEach { modelContext.delete($0) }
                modelContext.saveAndBackup()
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    @ViewBuilder
    private func trashRow(_ link: Link) -> some View {
        let daysLeft = max(0, 30 - Calendar.current.dateComponents([.day], from: link.deletedAt ?? .now, to: .now).day!)
        HStack(spacing: 14) {
            FaviconView(urlString: link.url, color: .folder(link.folder?.color), size: 44)
                .saturation(0)
            VStack(alignment: .leading, spacing: 3) {
                Text(link.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(link.domain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(daysLeft == 1 ? "1 day" : "\(daysLeft) days")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func restore(_ link: Link) {
        withAnimation {
            link.deletedAt = nil
            modelContext.saveAndBackup()
        }
        Haptics.success()
    }
}

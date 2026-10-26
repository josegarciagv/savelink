//
//  FolderDetailView.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import SwiftUI
import SwiftData

struct FolderDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let folder: Folder
    @State private var showAddLink = false
    @State private var showEditFolder = false
    @State private var searchText = ""
    @State private var favoritesOnly = false
    @State private var linkToMove: Link?
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<Link.ID>()
    @State private var showBulkMove = false
    @State private var showBulkTags = false
    @State private var bulkTags: [String] = []

    private var selectedLinks: [Link] {
        folder.activeLinks.filter { selection.contains($0.id) }
    }
    @AppStorage("linkSortOrder") private var linkSortOrder: String = "newToOld"

    enum LinkSortOrder: String, CaseIterable {
        case newToOld = "newToOld"
        case oldToNew = "oldToNew"
        case lastUpdated = "lastUpdated"
        case name = "name"
        case mostOpened = "mostOpened"

        var displayName: String {
            switch self {
            case .newToOld: return String(localized: "New to Old")
            case .oldToNew: return String(localized: "Old to New")
            case .lastUpdated: return String(localized: "Last Updated")
            case .name: return String(localized: "Name (A–Z)")
            case .mostOpened: return String(localized: "Most Opened")
            }
        }
    }

    private var tint: Color { .folder(folder.color) }

    var sortedLinks: [Link] {
        var links = folder.activeLinks
        if favoritesOnly {
            links = links.filter(\.isFavorite)
        }
        if !searchText.isEmpty {
            links = links.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.url.localizedCaseInsensitiveContains(searchText)
                    || ($0.linkDescription?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        let order = LinkSortOrder(rawValue: linkSortOrder) ?? .newToOld
        switch order {
        case .newToOld:
            return links.sorted { $0.createdAt > $1.createdAt }
        case .oldToNew:
            return links.sorted { $0.createdAt < $1.createdAt }
        case .lastUpdated:
            return links.sorted { $0.lastUpdatedDate > $1.lastUpdatedDate }
        case .name:
            return links.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .mostOpened:
            return links.sorted { $0.visitCount > $1.visitCount }
        }
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            }

            if folder.activeLinks.isEmpty {
                Section {
                    emptyState
                        .listRowBackground(Color.clear)
                }
            } else if sortedLinks.isEmpty {
                Section {
                    ContentUnavailableView.search(text: searchText)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(sortedLinks) { link in
                        NavigationLink(value: link) {
                            LinkRowView(link: link)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                link.isFavorite.toggle()
                                link.modelContext?.saveAndBackup()
                                Haptics.tap()
                            } label: {
                                Label("Favorite", systemImage: link.isFavorite ? "star.slash.fill" : "star.fill")
                            }
                            .tint(.yellow)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                link.moveToTrash()
                                link.modelContext?.saveAndBackup()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                UIPasteboard.general.string = link.url
                                Haptics.success()
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .tint(.gray)
                        }
                        .contextMenu {
                            LinkContextMenu(link: link) { linkToMove = link }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .tint(tint)
        .environment(\.editMode, $editMode)
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search in \(folder.name)")
        .toolbar {
            if editMode.isEditing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        withAnimation { editMode = .inactive }
                        selection.removeAll()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    bulkActions
                }
            } else {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            withAnimation { editMode = .active }
                        } label: {
                            Label("Select Links", systemImage: "checkmark.circle")
                        }
                        .disabled(folder.activeLinks.isEmpty)
                        Divider()
                        Toggle(isOn: $favoritesOnly) {
                            Label("Favorites Only", systemImage: "star")
                        }
                        // Sort options live in a submenu so the main menu stays short.
                        Picker(selection: $linkSortOrder) {
                            ForEach(LinkSortOrder.allCases, id: \.rawValue) { order in
                                Text(order.displayName).tag(order.rawValue)
                            }
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                        }
                        .pickerStyle(.menu)
                        Divider()
                        ShareLink(item: FolderBookmarks(folder: folder), preview: SharePreview(folder.name)) {
                            Label("Share Folder", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            showEditFolder = true
                        } label: {
                            Label("Edit Folder", systemImage: "pencil")
                        }
                    } label: {
                        Image(systemName: favoritesOnly ? "line.3.horizontal.decrease.circle.fill" : "ellipsis.circle")
                    }

                    Button {
                        showAddLink = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showBulkMove) {
            BulkMoveView(links: selectedLinks) {
                selection.removeAll()
                editMode = .inactive
            }
        }
        .sheet(isPresented: $showBulkTags) {
            NavigationStack {
                Form {
                    Section {
                        TagEditor(tags: $bulkTags, color: tint)
                    } footer: {
                        Text("These tags are added to the \(selection.count) selected links.")
                    }
                }
                .navigationTitle("Add Tags")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showBulkTags = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            for link in selectedLinks {
                                link.tags = TagFormatter.merge(link.tags, bulkTags)
                            }
                            folder.modelContext?.saveAndBackup()
                            bulkTags = []
                            showBulkTags = false
                            Haptics.success()
                        }
                        .fontWeight(.semibold)
                        .disabled(bulkTags.isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAddLink) {
            AddLinkView(folder: folder)
        }
        .sheet(isPresented: $showEditFolder) {
            FolderFormView(folder: folder) {
                // Navigate back to HomeView when folder is deleted
                dismiss()
            }
        }
        .sheet(item: $linkToMove) { link in
            MoveLinkView(link: link)
        }
    }

    @ViewBuilder
    private var bulkActions: some View {
        let none = selection.isEmpty
        Button {
            showBulkMove = true
        } label: {
            Label("Move", systemImage: "folder")
        }
        .disabled(none)
        Spacer()
        Button {
            showBulkTags = true
        } label: {
            Label("Tag", systemImage: "number")
        }
        .disabled(none)
        Spacer()
        Button {
            let makeFavorite = selectedLinks.contains { !$0.isFavorite }
            selectedLinks.forEach { $0.isFavorite = makeFavorite }
            folder.modelContext?.saveAndBackup()
            Haptics.tap()
        } label: {
            Label("Favorite", systemImage: "star")
        }
        .disabled(none)
        Spacer()
        Button(role: .destructive) {
            selectedLinks.forEach { $0.moveToTrash() }
            folder.modelContext?.saveAndBackup()
            selection.removeAll()
            Haptics.success()
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(none)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: folder.icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                HStack(spacing: 12) {
                    headerStat("\(folder.activeLinks.count)", icon: "link")
                    headerStat("\(folder.activeLinks.filter(\.isFavorite).count)", icon: "star.fill")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func headerStat(_ text: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(tint)
            Text("No links yet")
                .font(.title3.weight(.semibold))
            Text("Save your first link to this folder.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                showAddLink = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Link")
                }
                .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    NavigationStack {
        FolderDetailView(folder: Folder(name: "Test", color: "007AFF"))
    }
    .modelContainer(for: [Folder.self, Link.self], inMemory: true)
}

/// Moves several links at once.
struct BulkMoveView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.name) private var folders: [Folder]
    let links: [Link]
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List(folders) { folder in
                Button {
                    for link in links where link.folder?.id != folder.id {
                        link.folder?.links.removeAll { $0.id == link.id }
                        link.folder = folder
                        folder.links.append(link)
                    }
                    folder.updatedAt = Date()
                    folder.modelContext?.saveAndBackup()
                    Haptics.success()
                    onDone()
                    dismiss()
                } label: {
                    Label {
                        Text(folder.name).foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: folder.icon).foregroundStyle(Color.folder(folder.color))
                    }
                }
            }
            .navigationTitle("Move \(links.count) Links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

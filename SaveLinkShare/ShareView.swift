//
//  ShareView.swift
//  SaveLinkShare
//

import SwiftUI

struct ShareView: View {
    let pageTitle: String?
    let loadURL: () async -> String?
    let onFinish: () -> Void

    private let brand = Color(red: 0.2, green: 0.4, blue: 0.8)
    private let folders = SharedStore.folders

    @State private var url: String?
    @State private var name = ""
    @State private var selectedFolderID: UUID?
    @State private var isFavorite = false
    @State private var isLoading = true
    @State private var saved = false

    private var selectedFolder: SharedStore.FolderSnapshot? {
        folders.first { $0.id == selectedFolderID }
    }

    private var domain: String {
        guard let url, let host = URL(string: url)?.host() else { return url ?? "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if saved {
                    savedView
                } else if url == nil {
                    message(icon: "link.badge.plus", title: "No link found", text: "Share a web page to save it to SaveLinks.")
                } else if !SharedStore.canSaveMoreLinks {
                    message(icon: "lock.fill", title: "Free limit reached", text: "You've saved \(SharedStore.freeLinkLimit) links. Open SaveLinks to upgrade to PRO for unlimited links.")
                } else {
                    form
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Save to SaveLinks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onFinish)
                }
                if !saved && url != nil && SharedStore.canSaveMoreLinks {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .tint(brand)
        .task {
            url = await loadURL()
            name = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            selectedFolderID = folders.first(where: { !$0.isLocked })?.id ?? folders.first?.id
            isLoading = false
        }
    }

    private var form: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    AsyncImage(url: URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(domain)")) { image in
                        image.resizable().scaledToFit().frame(width: 26, height: 26)
                    } placeholder: {
                        Image(systemName: "globe").foregroundStyle(brand)
                    }
                    .frame(width: 44, height: 44)
                    .background(brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name.isEmpty ? domain : name)
                            .font(.headline)
                            .lineLimit(2)
                        Text(domain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Details") {
                TextField("Name", text: $name)
                Toggle(isOn: $isFavorite) {
                    Label("Favorite", systemImage: isFavorite ? "star.fill" : "star")
                }
                .tint(.yellow)
            }

            Section {
                if folders.isEmpty {
                    Label("Will be saved to \"Inbox\"", systemImage: "tray.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Picker(selection: $selectedFolderID) {
                        ForEach(folders) { folder in
                            Label(folder.name, systemImage: folder.isLocked ? "lock.fill" : folder.icon)
                                .tag(Optional(folder.id))
                        }
                    } label: {
                        Label("Folder", systemImage: selectedFolder?.icon ?? "folder")
                    }
                }
            } header: {
                Text("Folder")
            } footer: {
                Text("The link will appear in SaveLinks the next time you open the app.")
            }
        }
    }

    private var savedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: saved)
            Text("Saved!")
                .font(.title2.weight(.bold))
            if let selectedFolder {
                Text("Added to \(selectedFolder.name)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func message(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(brand)
            Text(title)
                .font(.title3.weight(.bold))
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private func save() {
        guard let url else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let pending = SharedStore.PendingLink(
            url: url,
            name: trimmed.isEmpty ? domain : trimmed,
            folderID: selectedFolderID,
            isFavorite: isFavorite,
            createdAt: Date()
        )
        guard SharedStore.enqueue(pending) else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.snappy) { saved = true }
        Task {
            try? await Task.sleep(for: .seconds(1))
            onFinish()
        }
    }
}

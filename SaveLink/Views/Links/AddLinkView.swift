//
//  AddLinkView.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import SwiftUI
import SwiftData

struct AddLinkView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Link> { $0.deletedAt == nil }) private var allLinks: [Link]
    @Query(sort: \Folder.name) private var folders: [Folder]
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showSubscriptionView = false
    @State private var showLinkLimitAlert = false
    @FocusState private var urlFocused: Bool

    @State private var selectedFolderID: UUID?
    @State private var linkName = ""
    @State private var url: String
    @State private var linkDescription = ""
    @State private var isFavorite = false
    @State private var showQRScanner = false
    @State private var scannedURL: String?
    @State private var autoFilledName: String?
    @State private var isFetchingTitle = false
    @State private var tags: [String] = []
    @State private var isReadLater = false
    @State private var aiSummary: String?
    @State private var isSuggesting = false
    @State private var aiMessage: String?

    init(folder: Folder? = nil, initialURL: String = "") {
        _selectedFolderID = State(initialValue: folder?.id)
        _url = State(initialValue: initialURL)
    }

    private var selectedFolder: Folder? {
        folders.first { $0.id == selectedFolderID }
    }

    private var tint: Color { .folder(selectedFolder?.color) }
    private var urlIsValid: Bool { Link.isValidURL(url) }

    private var duplicate: Link? {
        let normalized = Link.normalizedURLString(url).lowercased()
        guard urlIsValid else { return nil }
        return allLinks.first { $0.url.lowercased() == normalized }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "link")
                            .foregroundStyle(tint)
                        TextField("https://example.com", text: $url)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($urlFocused)
                        if !url.isEmpty {
                            Button {
                                url = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 12) {
                        PasteButton(payloadType: String.self) { strings in
                            if let first = strings.first {
                                url = first.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                        .buttonBorderShape(.capsule)
                        .labelStyle(.titleAndIcon)

                        Spacer()

                        Button {
                            if subscriptionManager.canUseQRScanner {
                                showQRScanner = true
                            } else {
                                showSubscriptionView = true
                            }
                        } label: {
                            Label("Scan QR", systemImage: subscriptionManager.canUseQRScanner ? "qrcode.viewfinder" : "lock.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(subscriptionManager.canUseQRScanner ? tint : .secondary)
                    }
                } header: {
                    Text("URL")
                } footer: {
                    if !url.isEmpty && !urlIsValid {
                        Text("This doesn't look like a valid URL.")
                            .foregroundStyle(.red)
                    } else if let duplicate {
                        Label("Already saved as \"\(duplicate.name)\"\(duplicate.folder.map { " in \($0.name)" } ?? "")", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else if !subscriptionManager.canUseQRScanner {
                        Text("QR code scanner is a Premium feature.")
                    }
                }

                if urlIsValid {
                    Section {
                        HStack(spacing: 14) {
                            FaviconView(urlString: url, color: tint, size: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(linkName.isEmpty ? Link.domain(for: url) : linkName)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text(Link.domain(for: url))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isFetchingTitle {
                                ProgressView()
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Preview")
                    }
                }

                Section("Details") {
                    TextField("Name", text: $linkName)
                    TextField("Description (optional)", text: $linkDescription, axis: .vertical)
                        .lineLimit(2...5)
                    Toggle(isOn: $isFavorite) {
                        Label("Favorite", systemImage: isFavorite ? "star.fill" : "star")
                    }
                    .tint(.yellow)
                    Toggle(isOn: $isReadLater) {
                        Label("Read Later", systemImage: "book.fill")
                    }
                    .tint(.orange)
                }
                
                Section {
                    TagEditor(tags: $tags, knownTags: Array(Set(allLinks.flatMap(\.tags))).sorted(), color: tint)
                    Button {
                        suggestWithAI()
                    } label: {
                        HStack {
                            Image(systemName: subscriptionManager.canUseAI ? "sparkles" : "lock.fill")
                            Text("Suggest Tags & Summary")
                            Spacer()
                            if isSuggesting {
                                ProgressView()
                            } else if !subscriptionManager.canUseAI {
                                Text("PRO")
                                    .font(.caption2.weight(.heavy))
                                    .foregroundStyle(Theme.brand)
                            }
                        }
                    }
                    .disabled(!urlIsValid || isSuggesting)
                } header: {
                    Text("Tags")
                } footer: {
                    if let aiMessage {
                        Text(aiMessage)
                    } else if let aiSummary {
                        Text(aiSummary)
                    } else {
                        Text("Created privately on your device with Apple Intelligence.")
                    }
                }

                Section {
                    if folders.isEmpty {
                        Label("Will be saved to a new \"Inbox\" folder", systemImage: "tray.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(selection: $selectedFolderID) {
                            ForEach(folders) { folder in
                                Label(folder.name, systemImage: folder.icon)
                                    .tag(Optional(folder.id))
                            }
                        } label: {
                            Label("Folder", systemImage: selectedFolder?.icon ?? "folder")
                        }
                    }
                } header: {
                    Text("Folder")
                }
            }
            .navigationTitle("New Link")
            .navigationBarTitleDisplayMode(.inline)
            .tint(tint)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveLink()
                    }
                    .fontWeight(.semibold)
                    .disabled(!urlIsValid)
                }
            }
            .onAppear {
                if selectedFolderID == nil {
                    selectedFolderID = folders.first(where: { !$0.isLocked })?.id ?? folders.first?.id
                }
                if url.isEmpty { urlFocused = true }
            }
            .task(id: url) {
                await fetchTitle()
            }
            .sheet(isPresented: $showQRScanner) {
                QRScannerView(scannedCode: $scannedURL)
            }
            .sheet(isPresented: $showSubscriptionView) {
                SubscriptionView()
            }
            .alert("Link Limit Reached", isPresented: $showLinkLimitAlert) {
                Button("OK", role: .cancel) { }
                Button("Upgrade") {
                    showSubscriptionView = true
                }
            } message: {
                Text("You've reached the free plan limit of 50 links. Upgrade to Premium for unlimited links.")
            }
            .onChange(of: scannedURL) { oldValue, newValue in
                if let scannedURL = newValue, !scannedURL.isEmpty {
                    url = scannedURL
                    // Clear the scanned URL after using it
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.scannedURL = nil
                    }
                }
            }
        }
    }

    private func suggestWithAI() {
        guard subscriptionManager.canUseAI else {
            showSubscriptionView = true
            return
        }
        isSuggesting = true
        aiMessage = nil
        Task {
            defer { isSuggesting = false }
            do {
                let insights = try await LinkAI.insights(for: url, title: linkName)
                withAnimation(.snappy) { tags = TagFormatter.merge(tags, insights.tags) }
                aiSummary = insights.summary
                if linkDescription.isEmpty { linkDescription = insights.summary }
                Haptics.success()
            } catch {
                aiMessage = error.localizedDescription
            }
        }
    }
    
    /// Fills the name with the page title unless the user typed their own.
    private func fetchTitle() async {
        guard urlIsValid, linkName.isEmpty || linkName == autoFilledName else { return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        isFetchingTitle = true
        defer { isFetchingTitle = false }
        let title = await LinkMetadataFetcher.title(for: url)
        guard !Task.isCancelled, linkName.isEmpty || linkName == autoFilledName else { return }
        let newName = title ?? Link.domain(for: url)
        linkName = newName
        autoFilledName = newName
    }

    private func saveLink() {
        // Check link limit
        if !subscriptionManager.canAddMoreLinks(currentCount: allLinks.count) {
            showLinkLimitAlert = true
            Haptics.error()
            return
        }

        let folder: Folder
        if let selectedFolder {
            folder = selectedFolder
        } else {
            folder = Folder(name: "Inbox", pin: "", color: Theme.defaultFolderColor, icon: "tray.fill")
            modelContext.insert(folder)
        }

        let trimmedName = linkName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = linkDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let newLink = Link(
            name: trimmedName.isEmpty ? Link.domain(for: url) : trimmedName,
            url: Link.normalizedURLString(url),
            linkDescription: trimmedDescription.isEmpty ? nil : trimmedDescription
        )
        newLink.isFavorite = isFavorite
        newLink.isReadLater = isReadLater
        newLink.tags = tags
        newLink.summary = aiSummary
        newLink.folder = folder
        folder.links.append(newLink)
        folder.updatedAt = Date()
        modelContext.insert(newLink)
        modelContext.saveAndBackup()
        Haptics.success()
        dismiss()
    }
}

#Preview {
    AddLinkView(initialURL: "apple.com")
        .modelContainer(for: [Folder.self, Link.self], inMemory: true)
}

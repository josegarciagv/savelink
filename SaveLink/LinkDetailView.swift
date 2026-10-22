//
//  LinkDetailView.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import SwiftUI
import SwiftData

struct LinkDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let link: Link
    let folderColor: String
    @State private var showEditView = false
    @State private var showShareSheet = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Link Icon
                HStack {
                    Spacer()
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(Color(hex: folderColor) ?? Color(red: 0.2, green: 0.4, blue: 0.8))
                    Spacer()
                }
                .padding(.top, 40)
                
                // Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(link.name)
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal)
                
                // Description
                if let linkDescription = link.linkDescription, !linkDescription.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(linkDescription)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal)
                }
                
                // URL
                VStack(alignment: .leading, spacing: 8) {
                    Text("URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(link.url)
                        .font(.body)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                }
                .padding(.horizontal)
                
                // Action Buttons
                VStack(spacing: 15) {
                    let folderColorValue = Color(hex: folderColor) ?? Color(red: 0.2, green: 0.4, blue: 0.8)
                    
                    Button(action: openInBrowser) {
                        HStack {
                            Image(systemName: "safari")
                            Text("Open in Browser")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(folderColorValue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    Button(action: copyURL) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("Copy URL")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(folderColorValue.opacity(0.1))
                        .foregroundColor(folderColorValue)
                        .cornerRadius(12)
                    }
                    
                    Button(action: { showShareSheet = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(folderColorValue.opacity(0.1))
                        .foregroundColor(folderColorValue)
                        .cornerRadius(12)
                    }
                    
                    Button(action: { showEditView = true }) {
                        HStack {
                            Image(systemName: "pencil")
                            Text("Edit")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(folderColorValue.opacity(0.1))
                        .foregroundColor(folderColorValue)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
            }
            .padding(.bottom, 40)
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditView) {
            EditLinkView(link: link, folderColor: folderColor) {
                // Navigate back to FolderDetailView when link is deleted
                dismiss()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [link.url])
        }
    }
    
    private func openInBrowser() {
        if let url = URL(string: link.url) {
            UIApplication.shared.open(url)
        }
    }
    
    private func copyURL() {
        UIPasteboard.general.string = link.url
    }
}

struct EditLinkView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let link: Link
    let folderColor: String
    var onDelete: (() -> Void)? = nil
    @State private var linkName: String
    @State private var url: String
    @State private var linkDescription: String
    @State private var showDeleteConfirmation = false
    
    init(link: Link, folderColor: String, onDelete: (() -> Void)? = nil) {
        self.link = link
        self.folderColor = folderColor
        self.onDelete = onDelete
        _linkName = State(initialValue: link.name)
        _url = State(initialValue: link.url)
        _linkDescription = State(initialValue: link.linkDescription ?? "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $linkName)
                } header: {
                    Text("Information")
                        .foregroundColor(Color(hex: folderColor) ?? Color(red: 0.2, green: 0.4, blue: 0.8))
                }
                
                Section {
                    TextField("URL", text: $url)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                } header: {
                    Text("URL")
                        .foregroundColor(Color(hex: folderColor) ?? Color(red: 0.2, green: 0.4, blue: 0.8))
                }
                
                Section {
                    TextField("Description (optional)", text: $linkDescription, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Description")
                        .foregroundColor(Color(hex: folderColor) ?? Color(red: 0.2, green: 0.4, blue: 0.8))
                }
                
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Link")
                        }
                    }
                }
            }
            .navigationTitle("Edit Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Color(hex: folderColor) ?? Color(red: 0.2, green: 0.4, blue: 0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .foregroundColor(Color(hex: folderColor) ?? Color(red: 0.2, green: 0.4, blue: 0.8))
                    .disabled(linkName.isEmpty || url.isEmpty)
                }
            }
            .sheet(isPresented: $showDeleteConfirmation) {
                DeleteLinkConfirmationView(
                    linkName: link.name,
                    linkCount: 1,
                    onConfirm: {
                        modelContext.delete(link)
                        do {
                            try modelContext.save()
                            // Backup to UserDefaults after deletion
                            let folderDescriptor = FetchDescriptor<Folder>()
                            let linkDescriptor = FetchDescriptor<Link>()
                            if let allFolders = try? modelContext.fetch(folderDescriptor),
                               let allLinks = try? modelContext.fetch(linkDescriptor) {
                                DataManager.shared.backupFolders(allFolders)
                                DataManager.shared.backupLinks(allLinks)
                            }
                        } catch {
                            print("Failed to save context after deletion: \(error)")
                        }
                        showDeleteConfirmation = false
                        dismiss()
                        // Call onDelete callback to navigate back to FolderDetailView
                        onDelete?()
                    },
                    onCancel: {
                        showDeleteConfirmation = false
                    }
                )
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
            }
        }
    }
    
    private func saveChanges() {
        link.name = linkName
        link.url = url
        link.linkDescription = linkDescription.isEmpty ? nil : linkDescription
        link.updatedAt = Date()
        // Update folder's updatedAt when link is edited
        link.folder?.updatedAt = Date()
        
        // Explicitly save to ensure persistence
        do {
            try modelContext.save()
            // Backup to UserDefaults
            let folderDescriptor = FetchDescriptor<Folder>()
            let linkDescriptor = FetchDescriptor<Link>()
            if let allFolders = try? modelContext.fetch(folderDescriptor),
               let allLinks = try? modelContext.fetch(linkDescriptor) {
                DataManager.shared.backupFolders(allFolders)
                DataManager.shared.backupLinks(allLinks)
            }
        } catch {
            print("Failed to save link changes: \(error)")
        }
        
        dismiss()
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        LinkDetailView(link: Link(name: "Test", url: "https://example.com", linkDescription: "Test description"), folderColor: "007AFF")
    }
    .modelContainer(for: [Folder.self, Link.self], inMemory: true)
}


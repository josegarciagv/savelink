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
    @Query private var allLinks: [Link]
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showSubscriptionView = false
    @State private var showLinkLimitAlert = false
    
    let folder: Folder
    let folderColor: String
    @State private var linkName = ""
    @State private var url = ""
    @State private var linkDescription = ""
    @State private var showQRScanner = false
    @State private var scannedURL: String?
    
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
                    HStack {
                        TextField("URL", text: $url)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                        
                        if subscriptionManager.canUseQRScanner {
                            Button(action: {
                                showQRScanner = true
                            }) {
                                Image(systemName: "camera.fill")
                                    .foregroundColor(Color(hex: folderColor) ?? Color(red: 0.2, green: 0.4, blue: 0.8))
                                    .font(.title3)
                            }
                        } else {
                            Button(action: {
                                showSubscriptionView = true
                            }) {
                                Image(systemName: "camera.fill")
                                    .foregroundColor(.secondary)
                                    .font(.title3)
                            }
                        }
                    }
                } header: {
                    Text("URL")
                        .foregroundColor(Color(hex: folderColor) ?? Color(red: 0.2, green: 0.4, blue: 0.8))
                } footer: {
                    if subscriptionManager.canUseQRScanner {
                        Text("Tap the camera icon to scan a QR code")
                            .font(.caption)
                    } else {
                        Text("Upgrade to Premium to use QR code scanner")
                            .font(.caption)
                    }
                }
                
                Section {
                    TextField("Description (optional)", text: $linkDescription, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Description")
                        .foregroundColor(Color(hex: folderColor) ?? Color(red: 0.2, green: 0.4, blue: 0.8))
                }
            }
            .navigationTitle("New Link")
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
                        saveLink()
                    }
                    .foregroundColor(Color(hex: folderColor) ?? Color(red: 0.2, green: 0.4, blue: 0.8))
                    .disabled(linkName.isEmpty || url.isEmpty || !isValidURL(url))
                }
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
    
    private func isValidURL(_ string: String) -> Bool {
        var urlString = string
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        return URL(string: urlString) != nil
    }
    
    private func saveLink() {
        // Check link limit
        let currentLinkCount = allLinks.count
        if !subscriptionManager.canAddMoreLinks(currentCount: currentLinkCount) {
            showLinkLimitAlert = true
            return
        }
        
        var urlString = url
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        
        let newLink = Link(
            name: linkName,
            url: urlString,
            linkDescription: linkDescription.isEmpty ? nil : linkDescription
        )
        newLink.folder = folder
        folder.links.append(newLink)
        folder.updatedAt = Date()
        modelContext.insert(newLink)
        
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
            print("Failed to save link: \(error)")
        }
        
        dismiss()
    }
}

#Preview {
    AddLinkView(folder: Folder(name: "Test", pin: "1234", color: "007AFF"), folderColor: "007AFF")
        .modelContainer(for: [Folder.self, Link.self], inMemory: true)
}


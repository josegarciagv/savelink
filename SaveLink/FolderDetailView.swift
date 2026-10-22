//
//  FolderDetailView.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import SwiftUI
import SwiftData

struct FolderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let folder: Folder
    @State private var showAddLink = false
    @State private var showEditFolder = false
    @State private var showPinEntry = false
    @State private var enteredPin = ""
    @State private var isUnlocked = false
    @AppStorage("linkSortOrder") private var linkSortOrder: String = "newToOld"
    
    enum LinkSortOrder: String, CaseIterable {
        case newToOld = "newToOld"
        case oldToNew = "oldToNew"
        case lastUpdated = "lastUpdated"
        
        var displayName: String {
            switch self {
            case .newToOld: return "New to Old"
            case .oldToNew: return "Old to New"
            case .lastUpdated: return "Last Updated"
            }
        }
    }
    
    var sortedLinks: [Link] {
        let order = LinkSortOrder(rawValue: linkSortOrder) ?? .newToOld
        switch order {
        case .newToOld:
            return folder.links.sorted { $0.createdAt > $1.createdAt }
        case .oldToNew:
            return folder.links.sorted { $0.createdAt < $1.createdAt }
        case .lastUpdated:
            return folder.links.sorted { link1, link2 in
                let date1 = link1.lastUpdatedDate
                let date2 = link2.lastUpdatedDate
                return date1 > date2
            }
        }
    }
    
    var body: some View {
        Group {
            if !isUnlocked {
                PinEntryView(
                    folderName: folder.name,
                    correctPin: folder.pin,
                    pin: $enteredPin,
                    onSuccess: {
                        isUnlocked = true
                        enteredPin = ""
                    }
                )
                .onAppear {
                    if folder.pin.isEmpty {
                        isUnlocked = true
                    }
                }
            } else {
                VStack {
                    if folder.links.isEmpty {
                        Spacer()
                        VStack(spacing: 20) {
                            Image(systemName: "link")
                                .font(.system(size: 60))
                                .foregroundColor(Color(hex: folder.color) ?? Color(red: 0.2, green: 0.4, blue: 0.8))
                            Text("No links")
                                .font(.title2)
                                .foregroundColor(.primary)
                            Text("Tap the + button to add your first link")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(sortedLinks) { link in
                                NavigationLink {
                                    LinkDetailView(link: link, folderColor: folder.color)
                                } label: {
                                    LinkRowView(link: link, folderColor: folder.color)
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
                .navigationTitle(folder.name)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    if isUnlocked {
                        ToolbarItemGroup(placement: .navigationBarTrailing) {
                            Menu {
                                Picker("Sort", selection: $linkSortOrder) {
                                    ForEach(LinkSortOrder.allCases, id: \.rawValue) { order in
                                        Text(order.displayName).tag(order.rawValue)
                                    }
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .foregroundColor(Color(hex: folder.color) ?? Color(red: 0.2, green: 0.4, blue: 0.8))
                            }
                            
                            Button(action: { showEditFolder = true }) {
                                Image(systemName: "pencil")
                                    .foregroundColor(Color(hex: folder.color) ?? Color(red: 0.2, green: 0.4, blue: 0.8))
                            }
                            Button(action: { showAddLink = true }) {
                                Image(systemName: "plus")
                                    .foregroundColor(Color(hex: folder.color) ?? Color(red: 0.2, green: 0.4, blue: 0.8))
                            }
                        }
                    }
                }
                .sheet(isPresented: $showAddLink) {
                    AddLinkView(folder: folder, folderColor: folder.color)
                }
                .sheet(isPresented: $showEditFolder) {
                    EditFolderView(folder: folder) {
                        // Navigate back to HomeView when folder is deleted
                        dismiss()
                    }
                }
                .onAppear {
                    if folder.pin.isEmpty {
                        isUnlocked = true
                    }
                }
            }
        }
    }
}

struct LinkRowView: View {
    let link: Link
    let folderColor: String
    
    var body: some View {
        HStack {
            Image(systemName: "link.circle.fill")
                .font(.title2)
                .foregroundColor(Color(hex: folderColor) ?? Color(red: 0.2, green: 0.4, blue: 0.8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(link.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                if let linkDescription = link.linkDescription, !linkDescription.isEmpty {
                    Text(linkDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Text(link.url)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct PinEntryView: View {
    let folderName: String
    let correctPin: String
    @Binding var pin: String
    let onSuccess: () -> Void
    @State private var showError = false
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var isAuthenticating = false
    @FocusState private var isPinFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "lock.fill")
                .font(.system(size: 60))
                .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
            
            Text("Protected Folder")
                .font(.title)
                .foregroundColor(.primary)
            
            Text(folderName)
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 20) {
                // PIN Input with circles
                HStack(spacing: 20) {
                    ForEach(0..<4) { index in
                        ZStack {
                            Circle()
                                .stroke(showError ? Color.red : Color(red: 0.2, green: 0.4, blue: 0.8), lineWidth: 2)
                                .frame(width: 50, height: 50)
                            
                            if pin.count > index {
                                Circle()
                                    .fill(Color(red: 0.2, green: 0.4, blue: 0.8))
                                    .frame(width: 20, height: 20)
                            }
                        }
                    }
                }
                .padding(.vertical, 10)
                
                // Text field for PIN input - visible but styled
                ZStack {
                    // Background for better visibility
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 250, height: 60)
                    
                    SecureField("Enter PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .font(.system(size: 18, weight: .medium))
                        .multilineTextAlignment(.center)
                        .frame(width: 250, height: 60)
                        .focused($isPinFieldFocused)
                        .onChange(of: pin) { oldValue, newValue in
                            if newValue.count > 4 {
                                pin = String(newValue.prefix(4))
                            }
                            if newValue.count == 4 {
                                if pin == correctPin {
                                    onSuccess()
                                } else {
                                    showError = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                        pin = ""
                                        showError = false
                                        isPinFieldFocused = true
                                    }
                                }
                            }
                        }
                }
                .padding(.vertical, 10)
                
                if showError {
                    Text("Incorrect PIN")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                // Face ID / Touch ID Button - Only show if folder has PIN and subscription allows it
                if !correctPin.isEmpty && 
                   SubscriptionManager.shared.canUseFaceID &&
                   authManager.isBiometricEnabled && 
                   authManager.biometricType() != "None" {
                    Button(action: {
                        authenticateWithBiometric()
                    }) {
                        HStack {
                            Image(systemName: authManager.biometricType() == "Face ID" ? "faceid" : "touchid")
                                .font(.title2)
                            Text("Use \(authManager.biometricType())")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(red: 0.2, green: 0.4, blue: 0.8))
                        .cornerRadius(12)
                    }
                    .disabled(isAuthenticating)
                    .padding(.horizontal, 40)
                    .padding(.top, 10)
                }
            }
        }
        .padding()
        .onAppear {
            // Only auto-authenticate with Face ID if folder has PIN and subscription allows it
            if !correctPin.isEmpty &&
               SubscriptionManager.shared.canUseFaceID &&
               authManager.isBiometricEnabled && 
               authManager.biometricType() != "None" {
                authenticateWithBiometric()
            } else {
                // Auto-focus PIN field if no Face ID
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isPinFieldFocused = true
                }
            }
        }
    }
    
    private func authenticateWithBiometric() {
        isAuthenticating = true
        authManager.authenticate { success, error in
            isAuthenticating = false
            if success {
                onSuccess()
            }
        }
    }
}

#Preview {
    NavigationStack {
        FolderDetailView(folder: Folder(name: "Test", pin: "1234", color: "007AFF"))
    }
    .modelContainer(for: [Folder.self, Link.self], inMemory: true)
}


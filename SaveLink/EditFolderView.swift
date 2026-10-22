//
//  EditFolderView.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import SwiftUI
import SwiftData

struct EditFolderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showSubscriptionView = false
    @State private var showDeleteConfirmation = false
    
    let folder: Folder
    var onDelete: (() -> Void)? = nil
    @State private var folderName: String
    @State private var pin: String
    @State private var selectedColor: String
    
    let colors = ["007AFF", "FF3B30", "34C759", "FF9500", "AF52DE", "FF2D55", "5AC8FA", "FFCC00"]
    
    init(folder: Folder, onDelete: (() -> Void)? = nil) {
        self.folder = folder
        self.onDelete = onDelete
        _folderName = State(initialValue: folder.name)
        _pin = State(initialValue: folder.pin)
        _selectedColor = State(initialValue: folder.color)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Folder name", text: $folderName)
                } header: {
                    Text("Information")
                        .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                }
                
                Section {
                    if subscriptionManager.canUsePIN {
                        SecureField("PIN (optional)", text: $pin)
                            .keyboardType(.numberPad)
                            .onChange(of: pin) { oldValue, newValue in
                                if newValue.count > 4 {
                                    pin = String(newValue.prefix(4))
                                }
                            }
                    } else {
                        Button(action: {
                            showSubscriptionView = true
                        }) {
                            HStack {
                                Text("PIN Protection")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.secondary)
                                Text("Premium")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Security PIN")
                        .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                } footer: {
                    if subscriptionManager.canUsePIN {
                        Text("Enter a PIN of up to 4 digits to protect this folder (optional)")
                    } else {
                        Text("Upgrade to Premium to use PIN protection")
                    }
                }
                
                Section {
                    if subscriptionManager.canUseColors {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 20) {
                            ForEach(colors, id: \.self) { color in
                                Button(action: {
                                    withAnimation {
                                        selectedColor = color
                                    }
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: color) ?? Color(red: 0.2, green: 0.4, blue: 0.8))
                                            .frame(width: 50, height: 50)
                                        
                                        if selectedColor == color {
                                            Circle()
                                                .stroke(Color(red: 0.2, green: 0.4, blue: 0.8), lineWidth: 3)
                                                .frame(width: 50, height: 50)
                                            
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.white)
                                                .font(.system(size: 16, weight: .bold))
                                        }
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.vertical)
                    } else {
                        Button(action: {
                            showSubscriptionView = true
                        }) {
                            HStack {
                                Text("Custom Colors")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "paintpalette.fill")
                                    .foregroundColor(.secondary)
                                Text("Premium")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Color")
                        .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                } footer: {
                    if !subscriptionManager.canUseColors {
                        Text("Upgrade to Premium to use custom folder colors")
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Folder")
                        }
                    }
                }
            }
            .navigationTitle("Edit Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                    .disabled(folderName.isEmpty)
                }
            }
            .sheet(isPresented: $showSubscriptionView) {
                SubscriptionView()
            }
            .sheet(isPresented: $showDeleteConfirmation) {
                DeleteFolderConfirmationView(
                    folderName: folder.name,
                    folderCount: 1,
                    onConfirm: {
                        modelContext.delete(folder)
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
                        // Call onDelete callback to navigate back to HomeView
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
        folder.name = folderName
        // Only save PIN if subscription allows it
        folder.pin = subscriptionManager.canUsePIN ? pin : ""
        // Use default color if colors are not available
        folder.color = subscriptionManager.canUseColors ? selectedColor : "007AFF"
        folder.updatedAt = Date()
        
        // Explicitly save to ensure persistence
        do {
            try modelContext.save()
            // Backup to UserDefaults
            let descriptor = FetchDescriptor<Folder>()
            if let allFolders = try? modelContext.fetch(descriptor) {
                DataManager.shared.backupFolders(allFolders)
            }
        } catch {
            print("Failed to save folder changes: \(error)")
        }
        
        dismiss()
    }
}

#Preview {
    EditFolderView(folder: Folder(name: "Test", pin: "1234", color: "007AFF"))
        .modelContainer(for: [Folder.self, Link.self], inMemory: true)
}


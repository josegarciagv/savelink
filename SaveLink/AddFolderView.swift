//
//  AddFolderView.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import SwiftUI
import SwiftData

struct AddFolderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showSubscriptionView = false
    
    @State private var folderName = ""
    @State private var pin = ""
    @State private var selectedColor = "007AFF" // Default blue
    
    let colors = ["007AFF", "FF3B30", "34C759", "FF9500", "AF52DE", "FF2D55", "5AC8FA", "FFCC00"]
    
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
            }
            .navigationTitle("New Folder")
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
                        saveFolder()
                    }
                    .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                    .disabled(folderName.isEmpty)
                }
            }
            .sheet(isPresented: $showSubscriptionView) {
                SubscriptionView()
            }
        }
    }
    
    private func saveFolder() {
        // Use default color if colors are not available
        let color = subscriptionManager.canUseColors ? selectedColor : "007AFF"
        // Clear PIN if PIN is not available
        let folderPin = subscriptionManager.canUsePIN ? pin : ""
        
        let newFolder = Folder(name: folderName, pin: folderPin, color: color)
        modelContext.insert(newFolder)
        
        // Explicitly save to ensure persistence
        do {
            try modelContext.save()
            // Backup to UserDefaults
            let descriptor = FetchDescriptor<Folder>()
            if let allFolders = try? modelContext.fetch(descriptor) {
                DataManager.shared.backupFolders(allFolders)
            }
        } catch {
            print("Failed to save folder: \(error)")
        }
        
        dismiss()
    }
}

#Preview {
    AddFolderView()
        .modelContainer(for: [Folder.self, Link.self], inMemory: true)
}


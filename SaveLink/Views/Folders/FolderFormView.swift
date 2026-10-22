//
//  FolderFormView.swift
//  SaveLink
//

import SwiftUI
import SwiftData

/// Creates a new folder, or edits `folder` when one is passed.
struct FolderFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showSubscriptionView = false
    @State private var showDeleteConfirmation = false
    @FocusState private var nameFocused: Bool

    let folder: Folder?
    var onDelete: (() -> Void)? = nil

    @State private var folderName: String
    @State private var pin: String
    @State private var selectedColor: String
    @State private var selectedIcon: String

    init(folder: Folder? = nil, onDelete: (() -> Void)? = nil) {
        self.folder = folder
        self.onDelete = onDelete
        _folderName = State(initialValue: folder?.name ?? "")
        _pin = State(initialValue: folder?.pin ?? "")
        _selectedColor = State(initialValue: folder?.color ?? Theme.defaultFolderColor)
        _selectedIcon = State(initialValue: folder?.icon ?? Theme.defaultFolderIcon)
    }

    private var isEditing: Bool { folder != nil }
    private var tint: Color { .folder(subscriptionManager.canUseColors ? selectedColor : Theme.defaultFolderColor) }
    private var trimmedName: String { folderName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var pinIsValid: Bool { pin.isEmpty || pin.count == 4 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                Section("Name") {
                    TextField("Folder name", text: $folderName)
                        .focused($nameFocused)
                        .submitLabel(.done)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                        ForEach(Theme.folderIcons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                                Haptics.tap()
                            } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .frame(width: 48, height: 48)
                                    .foregroundStyle(selectedIcon == icon ? .white : tint)
                                    .background(selectedIcon == icon ? tint : tint.opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    if subscriptionManager.canUseColors {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                            ForEach(Theme.folderColors, id: \.self) { color in
                                Button {
                                    withAnimation(.snappy) { selectedColor = color }
                                    Haptics.tap()
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color.folder(color))
                                            .frame(width: 38, height: 38)
                                        if selectedColor == color {
                                            Circle()
                                                .strokeBorder(Color.folder(color), lineWidth: 3)
                                                .frame(width: 48, height: 48)
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .frame(width: 48, height: 48)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        premiumRow(title: "Custom Colors", icon: "paintpalette.fill")
                    }
                } header: {
                    Text("Color")
                } footer: {
                    if !subscriptionManager.canUseColors {
                        Text("Upgrade to Premium to use custom folder colors")
                    }
                }

                Section {
                    if subscriptionManager.canUsePIN {
                        SecureField("4-digit PIN (optional)", text: $pin)
                            .keyboardType(.numberPad)
                            .onChange(of: pin) { _, newValue in
                                let digits = String(newValue.filter(\.isNumber).prefix(4))
                                if digits != newValue { pin = digits }
                            }
                    } else {
                        premiumRow(title: "PIN Protection", icon: "lock.fill")
                    }
                } header: {
                    Text("Security")
                } footer: {
                    if subscriptionManager.canUsePIN {
                        Text(pinIsValid ? "Protected folders ask for the PIN (or Face ID) before opening and stay out of search and favorites." : "The PIN must have exactly 4 digits.")
                            .foregroundStyle(pinIsValid ? Color.secondary : Color.red)
                    } else {
                        Text("Upgrade to Premium to use PIN protection")
                    }
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Folder", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Folder" : "New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty || !pinIsValid)
                }
            }
            .tint(tint)
            .onAppear {
                if !isEditing { nameFocused = true }
            }
            .sheet(isPresented: $showSubscriptionView) {
                SubscriptionView()
            }
            .sheet(isPresented: $showDeleteConfirmation) {
                if let folder {
                    DeleteFolderConfirmationView(
                        folderName: folder.name,
                        folderCount: 1,
                        onConfirm: {
                            modelContext.delete(folder)
                            modelContext.saveAndBackup()
                            showDeleteConfirmation = false
                            dismiss()
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
    }

    private var preview: some View {
        VStack(spacing: 10) {
            Image(systemName: selectedIcon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: tint.opacity(0.35), radius: 12, y: 6)
            Text(trimmedName.isEmpty ? "Folder name" : trimmedName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(trimmedName.isEmpty ? .secondary : .primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .animation(.snappy, value: selectedIcon)
        .animation(.snappy, value: selectedColor)
    }

    private func premiumRow(title: String, icon: String) -> some View {
        Button {
            showSubscriptionView = true
        } label: {
            HStack {
                Label(title, systemImage: icon)
                    .foregroundStyle(.primary)
                Spacer()
                Text("PRO")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.brand.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.brand)
            }
        }
    }

    private func save() {
        let color = subscriptionManager.canUseColors ? selectedColor : Theme.defaultFolderColor
        let folderPin = subscriptionManager.canUsePIN ? pin : ""

        if let folder {
            folder.name = trimmedName
            folder.pin = folderPin
            folder.color = color
            folder.icon = selectedIcon
            folder.updatedAt = Date()
        } else {
            modelContext.insert(Folder(name: trimmedName, pin: folderPin, color: color, icon: selectedIcon))
        }
        modelContext.saveAndBackup()
        Haptics.success()
        dismiss()
    }
}

#Preview {
    FolderFormView()
        .modelContainer(for: [Folder.self, Link.self], inMemory: true)
}

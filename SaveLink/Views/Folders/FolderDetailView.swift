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
    @State private var isUnlocked = false
    @State private var searchText = ""
    @State private var favoritesOnly = false
    @State private var linkToMove: Link?
    @AppStorage("linkSortOrder") private var linkSortOrder: String = "newToOld"

    enum LinkSortOrder: String, CaseIterable {
        case newToOld = "newToOld"
        case oldToNew = "oldToNew"
        case lastUpdated = "lastUpdated"
        case name = "name"
        case mostOpened = "mostOpened"

        var displayName: String {
            switch self {
            case .newToOld: return "New to Old"
            case .oldToNew: return "Old to New"
            case .lastUpdated: return "Last Updated"
            case .name: return "Name (A–Z)"
            case .mostOpened: return "Most Opened"
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
        Group {
            if isUnlocked || !folder.isLocked {
                content
            } else {
                PinEntryView(folderName: folder.name, correctPin: folder.pin, tint: tint) {
                    withAnimation(.snappy) { isUnlocked = true }
                }
            }
        }
        .tint(tint)
    }

    private var content: some View {
        List {
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
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search in \(folder.name)")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Toggle(isOn: $favoritesOnly) {
                        Label("Favorites Only", systemImage: "star")
                    }
                    Picker("Sort", selection: $linkSortOrder) {
                        ForEach(LinkSortOrder.allCases, id: \.rawValue) { order in
                            Text(order.displayName).tag(order.rawValue)
                        }
                    }
                    Divider()
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
                    if folder.isLocked {
                        headerStat("Protected", icon: "lock.fill")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func headerStat(_ text: String, icon: String) -> some View {
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

struct PinEntryView: View {
    let folderName: String
    let correctPin: String
    var tint: Color = Theme.brand
    let onSuccess: () -> Void

    @State private var pin = ""
    @State private var showError = false
    @State private var shakes: CGFloat = 0
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var isAuthenticating = false

    private var canUseBiometrics: Bool {
        SubscriptionManager.shared.canUseFaceID &&
        authManager.isBiometricEnabled &&
        authManager.biometricType() != "None"
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(tint.gradient, in: Circle())

            VStack(spacing: 6) {
                Text(folderName)
                    .font(.title2.weight(.bold))
                Text(showError ? "Incorrect PIN, try again" : "Enter PIN to open this folder")
                    .font(.subheadline)
                    .foregroundStyle(showError ? .red : .secondary)
            }

            HStack(spacing: 22) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(index < pin.count ? (showError ? Color.red : tint) : Color.clear)
                        .overlay(Circle().strokeBorder(showError ? Color.red : tint, lineWidth: 2))
                        .frame(width: 16, height: 16)
                }
            }
            .modifier(ShakeEffect(animatableData: shakes))

            Spacer()

            keypad
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            if canUseBiometrics {
                authenticateWithBiometric()
            }
        }
    }

    private var keypad: some View {
        let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]
        return VStack(spacing: 16) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 24) {
                    ForEach(row, id: \.self) { digit in
                        keyButton(digit)
                    }
                }
            }
            HStack(spacing: 24) {
                if canUseBiometrics {
                    Button(action: authenticateWithBiometric) {
                        Image(systemName: authManager.biometricType() == "Face ID" ? "faceid" : "touchid")
                            .font(.system(size: 28))
                            .foregroundStyle(tint)
                            .frame(width: 76, height: 76)
                    }
                    .disabled(isAuthenticating)
                } else {
                    Color.clear.frame(width: 76, height: 76)
                }
                keyButton("0")
                Button {
                    if !pin.isEmpty { pin.removeLast() }
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 24))
                        .foregroundStyle(.primary)
                        .frame(width: 76, height: 76)
                }
                .opacity(pin.isEmpty ? 0.3 : 1)
            }
        }
    }

    private func keyButton(_ digit: String) -> some View {
        Button {
            press(digit)
        } label: {
            Text(digit)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 76, height: 76)
                .background(Color(.secondarySystemGroupedBackground), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func press(_ digit: String) {
        guard pin.count < 4 else { return }
        Haptics.tap()
        showError = false
        pin.append(digit)
        guard pin.count == 4 else { return }
        if pin == correctPin {
            Haptics.success()
            onSuccess()
        } else {
            Haptics.error()
            showError = true
            withAnimation(.default) { shakes += 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pin = ""
            }
        }
    }

    private func authenticateWithBiometric() {
        isAuthenticating = true
        authManager.authenticate { success, error in
            isAuthenticating = false
            if success {
                Haptics.success()
                onSuccess()
            }
        }
    }
}

struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4), y: 0))
    }
}

#Preview {
    NavigationStack {
        FolderDetailView(folder: Folder(name: "Test", pin: "1234", color: "007AFF"))
    }
    .modelContainer(for: [Folder.self, Link.self], inMemory: true)
}

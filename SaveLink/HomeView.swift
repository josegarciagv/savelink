//
//  HomeView.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var folders: [Folder]
    @Query private var allLinks: [Link]
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showAddFolder = false
    @State private var showSettings = false
    @AppStorage("folderSortOrder") private var sortOrder: String = "newToOld"
    
    enum SortOrder: String, CaseIterable {
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
    
    var sortedFolders: [Folder] {
        let order = SortOrder(rawValue: sortOrder) ?? .newToOld
        switch order {
        case .newToOld:
            return folders.sorted { $0.createdAt > $1.createdAt }
        case .oldToNew:
            return folders.sorted { $0.createdAt < $1.createdAt }
        case .lastUpdated:
            return folders.sorted { folder1, folder2 in
                let date1 = folder1.lastUpdatedDate
                let date2 = folder2.lastUpdatedDate
                return date1 > date2
            }
        }
    }
    
    var totalLinks: Int {
        allLinks.count
    }
    
    var linkLimitReached: Bool {
        !subscriptionManager.canAddMoreLinks(currentCount: totalLinks)
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if folders.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "folder.fill")
                            .font(.system(size: 60))
                            .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                        Text("No folders")
                            .font(.title2)
                            .foregroundColor(.primary)
                        Text("Tap the + button to create your first folder")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(sortedFolders) { folder in
                            NavigationLink {
                                FolderDetailView(folder: folder)
                            } label: {
                                FolderRowView(folder: folder)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.caption)
                        if subscriptionManager.subscriptionStatus == .subscribed {
                            Text("\(totalLinks) links")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        } else {
                            Text("\(totalLinks)/50 links")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                    .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(SortOrder.allCases, id: \.rawValue) { order in
                                Text(order.displayName).tag(order.rawValue)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                    }
                    
                    Button(action: { showAddFolder = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                    }
                }
            }
            .sheet(isPresented: $showAddFolder) {
                AddFolderView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .tint(Color(red: 0.2, green: 0.4, blue: 0.8))
    }
}

struct FolderRowView: View {
    let folder: Folder
    
    var hasPIN: Bool {
        !folder.pin.isEmpty
    }
    
    var body: some View {
        HStack {
            // Folder icon with color
            Image(systemName: "folder.fill")
                .font(.system(size: 40))
                .foregroundColor(Color(hex: folder.color) ?? Color(red: 0.2, green: 0.4, blue: 0.8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("\(folder.links.count) links")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Lock icon for folders with PIN
            if hasPIN {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: folder.color) ?? Color(red: 0.2, green: 0.4, blue: 0.8))
                    .padding(.trailing, 4)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Folder.self, Link.self], inMemory: true)
}


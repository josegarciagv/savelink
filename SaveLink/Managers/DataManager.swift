//
//  DataManager.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import Foundation
import SwiftData
import Security
import WidgetKit

class DataManager {
    static let shared = DataManager()
    
    private let foldersStorageKey = "saved_folders"
    private let linksStorageKey = "saved_links"
    private let keychainService = "com.savelink.data"
    
    private init() {}
    
    // MARK: - Backup to iCloud Keychain and Local Storage
    
    func backupFolders(_ folders: [Folder]) {
        let folderData = folders.map { folder in
            [
                "id": folder.id.uuidString,
                "name": folder.name,
                "pin": folder.pin,
                "color": folder.color,
                "icon": folder.icon,
                "isPinned": folder.isPinned,
                "createdAt": folder.createdAt.timeIntervalSince1970,
                "updatedAt": folder.updatedAt?.timeIntervalSince1970 ?? folder.createdAt.timeIntervalSince1970
            ]
        }
        
        // Encode to JSON for Keychain storage
        if let jsonData = try? JSONSerialization.data(withJSONObject: folderData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            // Save to iCloud Keychain (persists across app deletions)
            KeychainHelper.save(key: foldersStorageKey, value: jsonString, service: keychainService)
        }
        
        // The local copy is an unencrypted plist: leave out PINs and protected folders.
        let publicFolderData = folderData.filter { ($0["pin"] as? String ?? "").isEmpty }
        UserDefaults.standard.set(publicFolderData, forKey: foldersStorageKey)
        UserDefaults.standard.synchronize()
    }
    
    func backupLinks(_ links: [Link]) {
        let linkData = links.map { link in
            var data: [String: Any] = [
                "id": link.id.uuidString,
                "name": link.name,
                "url": link.url,
                "isFavorite": link.isFavorite,
                "visitCount": link.visitCount,
                "tags": link.tags,
                "isReadLater": link.isReadLater,
                "isTrashed": link.isTrashed,
                "createdAt": link.createdAt.timeIntervalSince1970,
                "updatedAt": link.lastUpdatedDate.timeIntervalSince1970
            ]
            
            if let description = link.linkDescription {
                data["linkDescription"] = description
            }
            
            if let folderId = link.folder?.id {
                data["folderId"] = folderId.uuidString
            }
            
            return data
        }
        
        // Encode to JSON for Keychain storage
        if let jsonData = try? JSONSerialization.data(withJSONObject: linkData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            // Save to iCloud Keychain (persists across app deletions)
            KeychainHelper.save(key: linksStorageKey, value: jsonString, service: keychainService)
        }
        
        // The local copy is an unencrypted plist: leave out links from protected folders.
        let lockedFolderIDs = Set(links.filter(\.isLocked).compactMap { $0.folder?.id.uuidString })
        let publicLinkData = linkData.filter { !lockedFolderIDs.contains($0["folderId"] as? String ?? "") }
        UserDefaults.standard.set(publicLinkData, forKey: linksStorageKey)
        UserDefaults.standard.synchronize()
    }
    
    // MARK: - Restore from iCloud Keychain or Local Storage
    
    func restoreFolders(modelContext: ModelContext) -> [Folder] {
        // Try iCloud Keychain first, then fallback to local
        var folderData: [[String: Any]]?
        
        // Try to restore from iCloud Keychain
        if let keychainData = KeychainHelper.read(key: foldersStorageKey, service: keychainService),
           let jsonData = keychainData.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]],
           !decoded.isEmpty {
            folderData = decoded
            print("✅ Restoring folders from iCloud Keychain")
        } else if let localData = UserDefaults.standard.array(forKey: foldersStorageKey) as? [[String: Any]], !localData.isEmpty {
            folderData = localData
            print("✅ Restoring folders from local backup")
        }
        
        guard let folderData = folderData else {
            return []
        }
        
        var restoredFolders: [Folder] = []
        
        for data in folderData {
            guard let idString = data["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let name = data["name"] as? String,
                  let pin = data["pin"] as? String,
                  let color = data["color"] as? String,
                  let createdAtTimestamp = data["createdAt"] as? TimeInterval else {
                continue
            }
            
            let folder = Folder(name: name, pin: pin, color: color)
            folder.id = id
            folder.createdAt = Date(timeIntervalSince1970: createdAtTimestamp)
            
            if let updatedAtTimestamp = data["updatedAt"] as? TimeInterval {
                folder.updatedAt = Date(timeIntervalSince1970: updatedAtTimestamp)
            }
            folder.icon = data["icon"] as? String ?? Theme.defaultFolderIcon
            folder.isPinned = data["isPinned"] as? Bool ?? false
            
            modelContext.insert(folder)
            restoredFolders.append(folder)
        }
        
        return restoredFolders
    }
    
    func restoreLinks(modelContext: ModelContext, folders: [Folder]) -> [Link] {
        // Try iCloud Keychain first, then fallback to local
        var linkData: [[String: Any]]?
        
        // Try to restore from iCloud Keychain
        if let keychainData = KeychainHelper.read(key: linksStorageKey, service: keychainService),
           let jsonData = keychainData.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]],
           !decoded.isEmpty {
            linkData = decoded
            print("✅ Restoring links from iCloud Keychain")
        } else if let localData = UserDefaults.standard.array(forKey: linksStorageKey) as? [[String: Any]], !localData.isEmpty {
            linkData = localData
            print("✅ Restoring links from local backup")
        }
        
        guard let linkData = linkData else {
            return []
        }
        
        var restoredLinks: [Link] = []
        var folderMap: [UUID: Folder] = [:]
        
        for folder in folders {
            folderMap[folder.id] = folder
        }
        
        for data in linkData {
            guard let idString = data["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let name = data["name"] as? String,
                  let url = data["url"] as? String,
                  let createdAtTimestamp = data["createdAt"] as? TimeInterval else {
                continue
            }
            
            let description = data["linkDescription"] as? String
            let link = Link(name: name, url: url, linkDescription: description)
            link.id = id
            link.createdAt = Date(timeIntervalSince1970: createdAtTimestamp)
            
            if let updatedAtTimestamp = data["updatedAt"] as? TimeInterval {
                link.updatedAt = Date(timeIntervalSince1970: updatedAtTimestamp)
            }
            link.isFavorite = data["isFavorite"] as? Bool ?? false
            link.visitCount = data["visitCount"] as? Int ?? 0
            link.tags = data["tags"] as? [String] ?? []
            link.isReadLater = data["isReadLater"] as? Bool ?? false
            if data["isTrashed"] as? Bool == true {
                link.deletedAt = Date()
            }
            
            // Restore folder relationship
            if let folderIdString = data["folderId"] as? String,
               let folderId = UUID(uuidString: folderIdString),
               let folder = folderMap[folderId] {
                link.folder = folder
                folder.links.append(link)
            }
            
            modelContext.insert(link)
            restoredLinks.append(link)
        }
        
        return restoredLinks
    }
    
    // MARK: - Clear Backup
    
    func clearBackup() {
        // Clear from iCloud Keychain
        KeychainHelper.delete(key: foldersStorageKey, service: keychainService)
        KeychainHelper.delete(key: linksStorageKey, service: keychainService)
        
        // Clear from local
        UserDefaults.standard.removeObject(forKey: foldersStorageKey)
        UserDefaults.standard.removeObject(forKey: linksStorageKey)
        UserDefaults.standard.synchronize()
    }
}

// MARK: - Save + Backup

extension ModelContext {
    /// Saves pending changes and refreshes the Keychain/UserDefaults backup.
    func saveAndBackup() {
        do {
            try save()
            if let allFolders = try? fetch(FetchDescriptor<Folder>()),
               let allLinks = try? fetch(FetchDescriptor<Link>()) {
                DataManager.shared.backupFolders(allFolders)
                DataManager.shared.backupLinks(allLinks)
            }
            publishSharedSnapshot()
        } catch {
            print("Failed to save context: \(error)")
        }
    }
    
    /// Shares the folder list with the Share extension, refreshes the widgets and the Spotlight index.
    func publishSharedSnapshot() {
        let folders = (try? fetch(FetchDescriptor<Folder>(sortBy: [SortDescriptor(\.name)]))) ?? []
        let links = (try? fetch(FetchDescriptor<Link>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        SharedStore.publish(
            folders: folders.map {
                SharedStore.FolderSnapshot(id: $0.id, name: $0.name, icon: $0.icon, color: $0.color, isLocked: $0.isLocked)
            },
            linkCount: links.count
        )
        
        let visible = links.filter { !$0.isLocked }
        func widgetLinks(_ links: [Link]) -> [SharedStore.WidgetLink] {
            links.prefix(8).map {
                SharedStore.WidgetLink(id: $0.id, name: $0.name, domain: $0.domain, color: $0.folder?.color ?? Theme.defaultFolderColor)
            }
        }
        let readLater = visible.filter(\.isReadLater).sorted { $0.createdAt > $1.createdAt }
        SharedStore.publish(widget: SharedStore.WidgetSnapshot(
            favorites: widgetLinks(visible.filter(\.isFavorite).sorted { $0.lastUpdatedDate > $1.lastUpdatedDate }),
            readLater: widgetLinks(readLater),
            recent: widgetLinks(visible.sorted { $0.createdAt > $1.createdAt }),
            linkCount: links.count,
            readLaterCount: readLater.count
        ))
        WidgetCenter.shared.reloadAllTimelines()
        SpotlightIndexer.reindex(links)
    }
    
    /// Permanently removes links that have been in Recently Deleted for more than 30 days.
    func purgeOldTrash() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let expired = (try? fetch(FetchDescriptor<Link>(predicate: #Predicate { $0.deletedAt != nil }))) ?? []
        let toDelete = expired.filter { ($0.deletedAt ?? .now) < cutoff }
        guard !toDelete.isEmpty else { return }
        toDelete.forEach { delete($0) }
        saveAndBackup()
    }
    
    /// Imports links saved from the Share extension. Returns how many were added.
    @discardableResult
    func importPendingLinks() -> Int {
        let pending = SharedStore.takePendingLinks()
        guard !pending.isEmpty else { return 0 }
        
        var folders = (try? fetch(FetchDescriptor<Folder>())) ?? []
        for item in pending {
            let folder: Folder
            if let match = folders.first(where: { $0.id == item.folderID }) ?? folders.first(where: { !$0.isLocked }) {
                folder = match
            } else {
                folder = Folder(name: "Inbox", pin: "", color: Theme.defaultFolderColor, icon: "tray.fill")
                insert(folder)
                folders.append(folder)
            }
            let link = Link(name: item.name, url: Link.normalizedURLString(item.url))
            link.createdAt = item.createdAt
            link.updatedAt = item.createdAt
            link.isFavorite = item.isFavorite
            link.folder = folder
            folder.links.append(link)
            folder.updatedAt = Date()
            insert(link)
        }
        saveAndBackup()
        return pending.count
    }
}

// MARK: - Keychain Helper (similar to GV PDF)

struct KeychainHelper {
    static func save(key: String, value: String, service: String) {
        let data = value.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: true, // Sincronizar con iCloud Keychain
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // Eliminar cualquier valor existente
        SecItemDelete(query as CFDictionary)
        
        // Agregar el nuevo valor
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("⚠️ Error guardando en Keychain: \(status)")
        }
    }
    
    static func read(key: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        
        return nil
    }
    
    static func delete(key: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: true
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}


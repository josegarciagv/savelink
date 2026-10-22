//
//  DataManager.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import Foundation
import SwiftData
import Security

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
        
        // Also save locally as backup
        UserDefaults.standard.set(folderData, forKey: foldersStorageKey)
        UserDefaults.standard.synchronize()
    }
    
    func backupLinks(_ links: [Link]) {
        let linkData = links.map { link in
            var data: [String: Any] = [
                "id": link.id.uuidString,
                "name": link.name,
                "url": link.url,
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
        
        // Also save locally as backup
        UserDefaults.standard.set(linkData, forKey: linksStorageKey)
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


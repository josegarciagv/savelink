//
//  SaveLinkApp.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import SwiftUI
import SwiftData

@main
struct SaveLinkApp: App {
    @AppStorage("colorScheme") private var colorScheme: String = "system"
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Folder.self,
            Link.self,
        ])
        
        // Ensure the application support directory exists
        let fileManager = FileManager.default
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        // Configure CloudKit for iCloud sync and persistence
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If CloudKit fails, try without CloudKit as fallback
            print("⚠️ CloudKit initialization failed, trying local storage: \(error)")
            let fallbackConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            do {
                return try ModelContainer(for: schema, configurations: [fallbackConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()
    
    var colorSchemeMode: ColorScheme? {
        switch colorScheme {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil // system
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(colorSchemeMode)
                .task {
                    // Restore data from UserDefaults backup on app launch
                    await restoreDataIfNeeded()
                }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func restoreDataIfNeeded() async {
        let context = sharedModelContainer.mainContext
        
        // Check if we have data in SwiftData
        let descriptor = FetchDescriptor<Folder>()
        let existingFolders = (try? context.fetch(descriptor)) ?? []
        
        // If no data in SwiftData, try to restore from UserDefaults
        if existingFolders.isEmpty {
            let restoredFolders = DataManager.shared.restoreFolders(modelContext: context)
            if !restoredFolders.isEmpty {
                let restoredLinks = DataManager.shared.restoreLinks(modelContext: context, folders: restoredFolders)
                do {
                    try context.save()
                    print("✅ Restored \(restoredFolders.count) folders and \(restoredLinks.count) links from backup")
                } catch {
                    print("❌ Failed to save restored data: \(error)")
                }
            }
        }
    }
}

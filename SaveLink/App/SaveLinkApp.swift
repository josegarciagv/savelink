//
//  SaveLinkApp.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import SwiftUI
import SwiftData
import UserNotifications

/// One container for the app and its App Intents (Siri, Shortcuts, Spotlight).
enum AppModelContainer {
    static let cloudKitContainerID = "iCloud.gvwebsite.savelinks"
    
    /// True when the store was opened with iCloud sync (false if CloudKit was unavailable).
    private(set) static var isCloudSyncActive = false
    
    static let shared: ModelContainer = {
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
        // groupContainer: .none keeps the store in the app's own container. Without it,
        // SwiftData moves to the App Group (added for the Share extension) and existing
        // users would open an empty database.
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .none,
            cloudKitDatabase: .private(cloudKitContainerID)
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            isCloudSyncActive = true
            return container
        } catch {
            // If CloudKit fails, try without CloudKit as fallback
            print("⚠️ CloudKit initialization failed, trying local storage: \(error)")
            let fallbackConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                groupContainer: .none
            )
            do {
                return try ModelContainer(for: schema, configurations: [fallbackConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()
}

@main
struct SaveLinkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("colorScheme") private var colorScheme: String = "system"
    
    var sharedModelContainer: ModelContainer { AppModelContainer.shared }
    
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
                    sharedModelContainer.mainContext.purgeOldTrash()
                    sharedModelContainer.mainContext.removeDuplicates()
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

/// Opens the link when the user taps a reminder notification.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        WatchSync.shared.activate()
        return true
    }
    
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
    
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let linkID = (response.notification.request.content.userInfo["linkID"] as? String).flatMap(UUID.init(uuidString:))
        await MainActor.run {
            if let linkID {
                LinkOpener.shared.open(linkID: linkID)
            }
        }
    }
}

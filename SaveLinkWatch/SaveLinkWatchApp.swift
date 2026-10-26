//
//  SaveLinkWatchApp.swift
//  SaveLinkWatch
//
//  Read Later and Favorites on Apple Watch. The iPhone sends a small snapshot
//  and marking as read is sent back.
//

import SwiftUI
import WatchConnectivity
import Combine

@MainActor
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchStore()

    @Published private(set) var snapshot = SharedStore.WidgetSnapshot()
    private let cacheKey = "watch_snapshot"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(SharedStore.WidgetSnapshot.self, from: data) {
            snapshot = cached
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func markRead(_ link: SharedStore.WidgetLink) {
        snapshot.readLater.removeAll { $0.id == link.id }
        snapshot.readLaterCount = max(0, snapshot.readLaterCount - 1)
        cache()
        WCSession.default.transferUserInfo(["markRead": link.id.uuidString])
    }

    private func apply(_ context: [String: Any]) {
        guard let data = context["snapshot"] as? Data,
              let decoded = try? JSONDecoder().decode(SharedStore.WidgetSnapshot.self, from: data) else { return }
        snapshot = decoded
        cache()
    }

    private func cache() {
        UserDefaults.standard.set(try? JSONEncoder().encode(snapshot), forKey: cacheKey)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.apply(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }
}

@main
struct SaveLinkWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchHomeView()
        }
    }
}

struct WatchHomeView: View {
    @ObservedObject private var store = WatchStore.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.snapshot.readLater.isEmpty {
                        Label("All caught up", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.snapshot.readLater) { link in
                        NavigationLink {
                            WatchLinkView(link: link, canMarkRead: true)
                        } label: {
                            WatchLinkRow(link: link)
                        }
                    }
                } header: {
                    Label("Read Later", systemImage: "book.fill")
                        .foregroundStyle(.orange)
                }

                if !store.snapshot.favorites.isEmpty {
                    Section {
                        ForEach(store.snapshot.favorites) { link in
                            NavigationLink {
                                WatchLinkView(link: link, canMarkRead: false)
                            } label: {
                                WatchLinkRow(link: link)
                            }
                        }
                    } header: {
                        Label("Favorites", systemImage: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                }
            }
            .navigationTitle("SaveLinks")
        }
    }
}

private struct WatchLinkRow: View {
    let link: SharedStore.WidgetLink

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(link.name)
                .font(.headline)
                .lineLimit(2)
            Text(link.domain)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WatchLinkView: View {
    @Environment(\.dismiss) private var dismiss
    let link: SharedStore.WidgetLink
    let canMarkRead: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(link.name)
                    .font(.headline)
                Text(link.domain)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if canMarkRead {
                    Button {
                        WatchStore.shared.markRead(link)
                        dismiss()
                    } label: {
                        Label("Mark as Read", systemImage: "checkmark")
                    }
                    .tint(.orange)
                }
                Text("Open it on your iPhone to read the page.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

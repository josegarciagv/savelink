//
//  WatchSync.swift
//  SaveLink
//
//  Sends the Read Later / Favorites snapshot to the Apple Watch app and applies
//  "mark as read" taps that come back from it.
//

import Foundation
import WatchConnectivity
import SwiftData

final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ snapshot: SharedStore.WidgetSnapshot) {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? session.updateApplicationContext(["snapshot": data])
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.send(SharedStore.widgetSnapshot) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let id = (userInfo["markRead"] as? String).flatMap(UUID.init(uuidString:)) else { return }
        Task { @MainActor in
            SharedStore.markRead(id)
            AppModelContainer.shared.mainContext.applyWidgetReadMarks()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}

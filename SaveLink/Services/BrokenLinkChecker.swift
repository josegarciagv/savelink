//
//  BrokenLinkChecker.swift
//  SaveLink
//

import Foundation
import SwiftData

/// Checks whether saved pages still exist. Requests go straight to each site.
enum BrokenLinkChecker {
    enum Status: Sendable {
        case ok, broken, unknown
    }

    /// Checks every link, a few at a time, and updates `isBroken`. Returns how many are broken.
    static func check(_ links: [Link], progress: @escaping (Int) -> Void) async -> Int {
        let items = links.compactMap { link -> (UUID, URL)? in
            guard let url = URL(string: link.url), url.scheme?.hasPrefix("http") == true else { return nil }
            return (link.id, url)
        }
        var results: [UUID: Status] = [:]
        var done = 0

        await withTaskGroup(of: (UUID, Status).self) { group in
            var iterator = items.makeIterator()
            for _ in 0..<6 {
                guard let (id, url) = iterator.next() else { break }
                group.addTask { (id, await status(for: url)) }
            }
            for await (id, linkStatus) in group {
                results[id] = linkStatus
                done += 1
                progress(done)
                if let (nextID, nextURL) = iterator.next() {
                    group.addTask { (nextID, await status(for: nextURL)) }
                }
            }
        }

        var broken = 0
        for link in links {
            guard let status = results[link.id], status != .unknown else { continue }
            link.isBroken = status == .broken
            link.lastCheckedAt = Date()
            if link.isBroken { broken += 1 }
        }
        links.first?.modelContext?.saveAndBackup()
        return broken
    }

    nonisolated static func status(for url: URL) async -> Status {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = "HEAD"
        request.setValue("Mozilla/5.0 (iPhone) SaveLinks", forHTTPHeaderField: "User-Agent")
        do {
            var (_, response) = try await URLSession.shared.data(for: request)
            // Some servers don't support HEAD; retry with GET.
            if let http = response as? HTTPURLResponse, http.statusCode == 405 || http.statusCode == 501 {
                request.httpMethod = "GET"
                (_, response) = try await URLSession.shared.data(for: request)
            }
            guard let http = response as? HTTPURLResponse else { return .unknown }
            switch http.statusCode {
            case 200..<400, 401, 403, 429: return .ok   // reachable, maybe blocking bots
            case 404, 410: return .broken
            case 500...: return .broken
            default: return .unknown
            }
        } catch let error as URLError {
            switch error.code {
            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .badServerResponse, .secureConnectionFailed:
                return .broken
            default:
                return .unknown   // offline, timeout, cancelled: don't judge
            }
        } catch {
            return .unknown
        }
    }
}

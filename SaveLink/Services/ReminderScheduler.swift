//
//  ReminderScheduler.swift
//  SaveLink
//

import Foundation
import SwiftData
import UserNotifications

/// Local "read this later" reminders. Everything stays on the device.
enum ReminderScheduler {
    enum Preset: String, CaseIterable, Identifiable {
        case inOneHour, tonight, tomorrowMorning, weekend

        var id: String { rawValue }

        var title: String {
            switch self {
            case .inOneHour: return "In 1 Hour"
            case .tonight: return "Tonight (8 PM)"
            case .tomorrowMorning: return "Tomorrow (9 AM)"
            case .weekend: return "This Weekend"
            }
        }

        var icon: String {
            switch self {
            case .inOneHour: return "clock"
            case .tonight: return "moon"
            case .tomorrowMorning: return "sunrise"
            case .weekend: return "sofa"
            }
        }

        var date: Date {
            let calendar = Calendar.current
            let now = Date()
            switch self {
            case .inOneHour:
                return now.addingTimeInterval(3600)
            case .tonight:
                let tonight = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
                return tonight > now ? tonight : now.addingTimeInterval(3600)
            case .tomorrowMorning:
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
                return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
            case .weekend:
                let saturday = calendar.nextDate(after: now, matching: DateComponents(weekday: 7), matchingPolicy: .nextTime) ?? now
                return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: saturday) ?? saturday
            }
        }
    }

    private static func identifier(for link: Link) -> String {
        "reminder-\(link.id.uuidString)"
    }

    /// Schedules a reminder and marks the link as Read Later. Returns false if notifications are off.
    @discardableResult
    static func schedule(for link: Link, at date: Date) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Time to read"
        content.body = link.name
        content.subtitle = link.domain
        content.sound = .default
        content.userInfo = ["url": link.url, "linkID": link.id.uuidString]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier(for: link), content: content, trigger: trigger)

        do {
            try await center.add(request)
            link.reminderDate = date
            link.isReadLater = true
            link.modelContext?.saveAndBackup()
            return true
        } catch {
            print("Failed to schedule reminder: \(error)")
            return false
        }
    }

    static func cancel(for link: Link) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: link)])
    }
}

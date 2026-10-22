//
//  Theme.swift
//  SaveLink
//

import SwiftUI
import UIKit

enum Theme {
    static let brand = Color(red: 0.2, green: 0.4, blue: 0.8)
    static let defaultFolderColor = "007AFF"
    static let defaultFolderIcon = "folder.fill"

    static let folderColors = [
        "007AFF", "5856D6", "AF52DE", "FF2D55",
        "FF3B30", "FF9500", "FFCC00", "34C759",
        "00C7BE", "5AC8FA", "A2845E", "8E8E93"
    ]

    static let folderIcons = [
        "folder.fill", "briefcase.fill", "book.fill", "graduationcap.fill",
        "cart.fill", "gamecontroller.fill", "music.note", "film.fill",
        "heart.fill", "star.fill", "airplane", "fork.knife",
        "newspaper.fill", "hammer.fill", "paintbrush.fill", "dumbbell.fill",
        "house.fill", "person.2.fill", "chevron.left.forwardslash.chevron.right", "photo.fill"
    ]

    static let cardRadius: CGFloat = 20
}

extension Color {
    /// Folder color from a hex string, falling back to the brand color.
    static func folder(_ hex: String?) -> Color {
        guard let hex else { return Theme.brand }
        return Color(hex: hex) ?? Theme.brand
    }
}

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

/// Rounded card background used across the app.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

extension View {
    func card() -> some View {
        modifier(CardBackground())
    }
}

/// Wraps a URL so it can drive `.sheet(item:)`.
struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

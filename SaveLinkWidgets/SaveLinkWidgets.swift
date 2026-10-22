//
//  SaveLinkWidgets.swift
//  SaveLinkWidgets
//
//  Home Screen and Lock Screen widgets. They read a snapshot the app writes to the
//  App Group, so links from PIN-protected folders never appear here.
//

import WidgetKit
import SwiftUI

private let brand = Color(red: 0.2, green: 0.4, blue: 0.8)

// MARK: - Timeline

struct LinksEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedStore.WidgetSnapshot

    static let sample = LinksEntry(date: .now, snapshot: SharedStore.WidgetSnapshot(
        favorites: [
            .init(id: UUID(), name: "Apple", domain: "apple.com", color: "007AFF"),
            .init(id: UUID(), name: "Wikipedia", domain: "wikipedia.org", color: "34C759"),
            .init(id: UUID(), name: "GitHub", domain: "github.com", color: "5856D6"),
            .init(id: UUID(), name: "Recipes", domain: "nytimes.com", color: "FF9500")
        ],
        readLater: [
            .init(id: UUID(), name: "How to build better habits", domain: "medium.com", color: "FF9500"),
            .init(id: UUID(), name: "The future of foldables", domain: "theverge.com", color: "AF52DE"),
            .init(id: UUID(), name: "Swift concurrency guide", domain: "swift.org", color: "FF3B30")
        ],
        recent: [],
        linkCount: 42,
        readLaterCount: 3
    ))
}

struct LinksProvider: TimelineProvider {
    func placeholder(in context: Context) -> LinksEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (LinksEntry) -> Void) {
        completion(context.isPreview ? .sample : LinksEntry(date: .now, snapshot: SharedStore.widgetSnapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LinksEntry>) -> Void) {
        // The app reloads timelines whenever links change; this is only a fallback.
        let entry = LinksEntry(date: .now, snapshot: SharedStore.widgetSnapshot)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }
}

// MARK: - Shared pieces

private func color(_ hex: String) -> Color {
    var value: UInt64 = 0
    guard hex.count == 6, Scanner(string: hex).scanHexInt64(&value) else { return brand }
    return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
}

private func openURL(_ link: SharedStore.WidgetLink) -> URL {
    URL(string: "savelink://open?id=\(link.id.uuidString)")!
}

/// Rounded square with the first letter of the site, tinted with the folder color.
struct LinkBadge: View {
    let link: SharedStore.WidgetLink
    var size: CGFloat = 32

    var body: some View {
        Text(String(link.domain.prefix(1)).uppercased())
            .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color(link.color).gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct LinkLine: View {
    let link: SharedStore.WidgetLink

    var body: some View {
        SwiftUI.Link(destination: openURL(link)) {
            HStack(spacing: 10) {
                LinkBadge(link: link, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(link.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(link.domain)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct WidgetHeader: View {
    let title: String
    let icon: String
    let tint: Color
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(title)
                .font(.subheadline.weight(.bold))
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EmptyWidgetMessage: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Favorites widget

struct FavoritesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LinksEntry

    private var links: [SharedStore.WidgetLink] { entry.snapshot.favorites }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: "Favorites", icon: "star.fill", tint: .yellow)
            if links.isEmpty {
                EmptyWidgetMessage(icon: "star", text: "Star links in SaveLinks to see them here.")
            } else {
                switch family {
                case .systemSmall:
                    smallGrid
                case .systemMedium:
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        ForEach(links.prefix(4)) { LinkLine(link: $0) }
                    }
                default:
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(links.prefix(7)) { LinkLine(link: $0) }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    /// 2×2 grid of site badges for the small size.
    private var smallGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(links.prefix(4)) { link in
                SwiftUI.Link(destination: openURL(link)) {
                    VStack(spacing: 3) {
                        LinkBadge(link: link, size: 36)
                        Text(link.name)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

struct FavoritesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FavoritesWidget", provider: LinksProvider()) { entry in
            FavoritesWidgetView(entry: entry)
        }
        .configurationDisplayName("Favorites")
        .description("Your favorite links, one tap away.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Read Later widget

struct ReadLaterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LinksEntry

    private var links: [SharedStore.WidgetLink] { entry.snapshot.readLater }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(min(entry.snapshot.readLaterCount, 10)), in: 0...10) {
                Image(systemName: "book.fill")
            } currentValueLabel: {
                Text("\(entry.snapshot.readLaterCount)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetURL(URL(string: "savelink://readlater"))
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("\(entry.snapshot.readLaterCount) to read", systemImage: "book.fill")
                    .font(.headline)
                if let first = links.first {
                    Text(first.name)
                        .font(.caption)
                        .lineLimit(2)
                }
            }
            .widgetURL(URL(string: "savelink://readlater"))
            .containerBackground(for: .widget) { Color.clear }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "book.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(entry.snapshot.readLaterCount)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(entry.snapshot.readLaterCount == 1 ? "link to read" : "links to read")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(URL(string: "savelink://readlater"))
            .containerBackground(for: .widget) {
                LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        default:
            VStack(alignment: .leading, spacing: 10) {
                WidgetHeader(title: "Read Later", icon: "book.fill", tint: .orange, count: entry.snapshot.readLaterCount)
                if links.isEmpty {
                    EmptyWidgetMessage(icon: "checkmark.circle", text: "All caught up!")
                } else {
                    ForEach(links.prefix(family == .systemLarge ? 7 : 3)) { LinkLine(link: $0) }
                    Spacer(minLength: 0)
                }
            }
            .containerBackground(for: .widget) {
                Color(.systemBackground)
            }
        }
    }
}

struct ReadLaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReadLaterWidget", provider: LinksProvider()) { entry in
            ReadLaterWidgetView(entry: entry)
        }
        .configurationDisplayName("Read Later")
        .description("Links waiting for you to read.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Bundle

@main
struct SaveLinkWidgetBundle: WidgetBundle {
    var body: some Widget {
        FavoritesWidget()
        ReadLaterWidget()
    }
}

#Preview(as: .systemMedium) {
    FavoritesWidget()
} timeline: {
    LinksEntry.sample
}

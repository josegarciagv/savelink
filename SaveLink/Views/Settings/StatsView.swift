//
//  StatsView.swift
//  SaveLink
//

import SwiftUI
import SwiftData
import Charts

/// Reading and saving habits.
struct StatsView: View {
    @Query(filter: #Predicate<Link> { $0.deletedAt == nil }) private var links: [Link]

    private var visible: [Link] { links }

    private struct WeekCount: Identifiable {
        let week: Date
        let count: Int
        var id: Date { week }
    }

    private var savedPerWeek: [WeekCount] {
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return (0..<8).reversed().map { offset in
            let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek)!
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
            return WeekCount(week: start, count: links.filter { $0.createdAt >= start && $0.createdAt < end }.count)
        }
    }

    private var topDomains: [(domain: String, count: Int)] {
        Dictionary(grouping: visible, by: \.domain)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { $0 }
    }

    private var mostOpened: [Link] {
        visible.filter { $0.visitCount > 0 }.sorted { $0.visitCount > $1.visitCount }.prefix(5).map { $0 }
    }

    private var totalOpens: Int { links.reduce(0) { $0 + $1.visitCount } }
    private var readCount: Int { links.filter { $0.lastOpenedAt != nil }.count }

    var body: some View {
        List {
            Section {
                HStack(spacing: 0) {
                    tile("\(links.count)", "Saved", "link")
                    tile("\(totalOpens)", "Opens", "safari")
                    tile(links.isEmpty ? "0%" : "\(readCount * 100 / links.count)%", "Read", "checkmark.circle")
                }
                .padding(.vertical, 6)
            }

            Section("Saved per Week") {
                Chart(savedPerWeek) { item in
                    BarMark(
                        x: .value("Week", item.week, unit: .weekOfYear),
                        y: .value("Links", item.count)
                    )
                    .foregroundStyle(Theme.brand.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 180)
                .padding(.vertical, 8)
                .accessibilityLabel("Links saved in each of the last 8 weeks")
            }

            if !topDomains.isEmpty {
                Section("Top Sites") {
                    ForEach(topDomains, id: \.domain) { item in
                        HStack(spacing: 12) {
                            FaviconView(urlString: item.domain, color: Theme.brand, size: 30)
                            Text(item.domain)
                            Spacer()
                            Text("\(item.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }

            if !mostOpened.isEmpty {
                Section("Most Opened") {
                    ForEach(mostOpened) { link in
                        HStack {
                            Text(link.name).lineLimit(1)
                            Spacer()
                            Text("\(link.visitCount)×")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle("Statistics")
    }

    private func tile(_ value: String, _ label: LocalizedStringKey, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(Theme.brand)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

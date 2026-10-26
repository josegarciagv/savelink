//
//  SettingsView.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import SwiftUI
import SwiftData
import StoreKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.modelContext) private var modelContext
    @AppStorage("colorScheme") private var colorScheme: String = "system"
    @AppStorage("openLinksInApp") private var openLinksInApp = true
    @Query private var folders: [Folder]
    @Query(filter: #Predicate<Link> { $0.deletedAt == nil }) private var links: [Link]
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showSubscriptionView = false
    @State private var showShareExtensionHelp = false
    @State private var showFaceIDHelp = false
    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var isCheckingLinks = false
    @State private var checkedLinks = 0
    @State private var checkMessage: String?

    private let appStoreURL = URL(string: "https://apps.apple.com/app/id6757314064")!
    private let privacyURL = URL(string: "https://gvpdf.com/saveurl")!
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private let contactEmail = "juanitovilleda502@gmail.com"

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

    private var isSubscribed: Bool {
        subscriptionManager.subscriptionStatus == .subscribed
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    planCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("General") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsLabel("Appearance", icon: "circle.lefthalf.filled", color: .indigo)
                        Picker("Appearance", selection: $colorScheme) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)

                    Toggle(isOn: $openLinksInApp) {
                        SettingsLabel("Open Links in App", icon: "safari.fill", color: .blue)
                    }

                    Button {
                        showShareExtensionHelp = true
                    } label: {
                        SettingsRow("Save from Safari", icon: "square.and.arrow.down.fill", color: .green)
                    }
                    
                    NavigationLink {
                        AppIconPicker()
                    } label: {
                        SettingsLabel("App Icon", icon: "app.badge.fill", color: .pink)
                    }
                    
                    NavigationLink {
                        StatsView()
                    } label: {
                        SettingsLabel("Statistics", icon: "chart.bar.fill", color: .teal)
                    }
                }

                Section {
                    Button {
                        showFaceIDHelp = true
                    } label: {
                        SettingsRow("Lock with Face ID", icon: "faceid", color: .green)
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("iOS can lock or hide SaveLinks with Face ID, so nobody else can open it.")
                }

                Section {
                    HStack(spacing: 0) {
                        statItem("\(links.count)", "Links")
                        Divider()
                        statItem("\(folders.count)", "Folders")
                        Divider()
                        statItem("\(links.filter(\.isFavorite).count)", "Favorites")
                    }
                    .padding(.vertical, 6)

                    Button {
                        showImporter = true
                    } label: {
                        SettingsRow("Import Bookmarks", icon: "square.and.arrow.down.fill", color: .teal)
                    }
                    
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            SettingsRow("Export Bookmarks", icon: "square.and.arrow.up.fill", color: .orange)
                        }
                    }
                    
                    Button {
                        Task { await checkLinks() }
                    } label: {
                        HStack {
                            SettingsLabel("Check for Broken Links", icon: "stethoscope", color: .red)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isCheckingLinks {
                                Text("\(checkedLinks)/\(links.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isCheckingLinks || links.isEmpty)
                    
                    NavigationLink {
                        RulesView()
                    } label: {
                        SettingsLabel("Automatic Rules", icon: "wand.and.stars", color: .purple)
                    }
                    
                    NavigationLink {
                        TrashView()
                    } label: {
                        SettingsLabel("Recently Deleted", icon: "trash.fill", color: .gray)
                    }
                } header: {
                    Text("Your Data")
                } footer: {
                    Text("Import or export bookmarks from Safari, Chrome, Firefox or Pocket (HTML file).")
                }
                
                Section {
                    SettingsLabel("“Hey Siri, save a link in SaveLinks”", icon: "waveform", color: .purple)
                        .font(.subheadline)
                    SettingsLabel("“What do I have to read in SaveLinks”", icon: "book.fill", color: .orange)
                        .font(.subheadline)
                } header: {
                    Text("Siri & Shortcuts")
                } footer: {
                    Text("You'll also find SaveLinks actions in the Shortcuts app, Spotlight and on the Home Screen as widgets.")
                }

                
                Section("Support") {
                    Button {
                        requestReview()
                    } label: {
                        SettingsRow("Rate SaveLinks", icon: "star.fill", color: .yellow)
                    }
                    ShareLink(item: appStoreURL) {
                        SettingsRow("Share App", icon: "heart.fill", color: .pink)
                    }
                    if let mailURL = URL(string: "mailto:\(contactEmail)?subject=SaveLinks%20\(appVersion.replacingOccurrences(of: " ", with: "%20"))") {
                        SwiftUI.Link(destination: mailURL) {
                            SettingsRow("Contact Support", icon: "envelope.fill", color: .blue)
                        }
                    }
                }

                Section {
                    SwiftUI.Link(destination: privacyURL) {
                        SettingsRow("Privacy Policy", icon: "hand.raised.fill", color: .gray, external: true)
                    }
                    SwiftUI.Link(destination: termsURL) {
                        SettingsRow("Terms of Use", icon: "doc.text.fill", color: .gray, external: true)
                    }
                } header: {
                    Text("Legal")
                } footer: {
                    Text("SaveLinks \(appVersion)")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Theme.brand)
            .sheet(isPresented: $showSubscriptionView) {
                SubscriptionView()
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.html, .plainText]) { result in
                importBookmarks(result)
            }
            .alert("Import Bookmarks", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
                Button("OK", role: .cancel) { }
                if importMessage?.contains("PRO") == true {
                    Button("Upgrade") { showSubscriptionView = true }
                }
            } message: {
                Text(importMessage ?? "")
            }
            .alert("Link Check Complete", isPresented: Binding(get: { checkMessage != nil }, set: { if !$0 { checkMessage = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(checkMessage ?? "")
            }
            .sheet(isPresented: $showShareExtensionHelp) {
                ShareExtensionHelpView()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showFaceIDHelp) {
                HelpStepsView(
                    title: "Lock with Face ID",
                    intro: "iOS protects SaveLinks for you. It works even when you're not using the app.",
                    steps: [
                        ("Go to your Home Screen", "house"),
                        ("Touch and hold the SaveLinks icon", "hand.tap"),
                        ("Choose Require Face ID", "faceid"),
                    ]
                )
                .presentationDetents([.medium])
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                exportURL = LinkExporter.bookmarksFile(folders: folders)
                await subscriptionManager.checkSubscriptionStatus()
                // Load products to show pricing in the plan card
                if !isSubscribed {
                    await subscriptionManager.loadProducts()
                }
            }
            .preferredColorScheme(colorSchemeMode)
        }
    }

    private func importBookmarks(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        
        guard let data = try? Data(contentsOf: url),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            importMessage = String(localized: "The file couldn't be read.")
            return
        }
        let entries = BookmarkImporter.parse(html)
        guard !entries.isEmpty else {
            importMessage = String(localized: "No links were found in this file. Export your bookmarks as HTML and try again.")
            return
        }
        let limit = isSubscribed ? nil : SharedStore.freeLinkLimit
        let summary = BookmarkImporter.importEntries(entries, into: modelContext, linkLimit: limit)
        var lines = [String(localized: "Imported \(summary.imported) links into \(summary.folders) new folders.")]
        if summary.duplicates > 0 { lines.append(String(localized: "\(summary.duplicates) were already saved.")) }
        if summary.skippedByLimit > 0 { lines.append(String(localized: "\(summary.skippedByLimit) were skipped because of the free 50-link limit. Upgrade to PRO to import them all.")) }
        importMessage = lines.joined(separator: " ")
        exportURL = LinkExporter.bookmarksFile(folders: folders)
        Haptics.success()
    }
    
    private func checkLinks() async {
        let toCheck = links
        isCheckingLinks = true
        checkedLinks = 0
        let broken = await BrokenLinkChecker.check(toCheck) { done in
            checkedLinks = done
        }
        isCheckingLinks = false
        checkMessage = broken == 0
            ? String(localized: "All \(toCheck.count) links work.")
            : String(localized: "\(broken) of \(toCheck.count) links look broken. Find them in Broken Links on the Home screen.")
    }
    
    private var planCard: some View {
        Button {
            showSubscriptionView = true
        } label: {
            HStack(spacing: 16) {
                Image(systemName: isSubscribed ? "crown.fill" : "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(isSubscribed ? "SaveLinks PRO" : "Upgrade to PRO")
                        .font(.headline)
                    Text(planSubtitle)
                        .font(.subheadline)
                        .opacity(0.85)
                        .lineLimit(2)
                }
                .foregroundStyle(.white)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(18)
            .background(
                LinearGradient(colors: isSubscribed ? [Color.orange, Color.pink] : [Theme.brand, Color(red: 0.42, green: 0.32, blue: 0.86)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var planSubtitle: String {
        if isSubscribed {
            return String(localized: "All features unlocked. Thank you!")
        }
        if let monthly = subscriptionManager.availableProducts.first(where: { $0.id.contains("monthly") }) {
            return String(localized: "Unlimited links, AI summaries and more from \(monthly.displayPrice)/month")
        }
        return String(localized: "Unlimited links, AI summaries, QR scanner and colors")
    }

    private func statItem(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Icon in a colored rounded square followed by a title, like the system Settings app.
struct SettingsLabel: View {
    let title: LocalizedStringKey
    let icon: String
    let color: Color

    init(_ title: LocalizedStringKey, icon: String, color: Color) {
        self.title = title
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
        }
    }
}

/// A tappable settings row with an optional badge and trailing chevron.
struct SettingsRow: View {
    let title: LocalizedStringKey
    let icon: String
    let color: Color
    var badge: String? = nil
    var external = false

    init(_ title: LocalizedStringKey, icon: String, color: Color, badge: String? = nil, external: Bool = false) {
        self.title = title
        self.icon = icon
        self.color = color
        self.badge = badge
        self.external = external
    }

    var body: some View {
        HStack {
            SettingsLabel(title, icon: icon, color: color)
                .foregroundStyle(.primary)
            Spacer()
            if let badge {
                Text(badge)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.brand.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.brand)
            }
            Image(systemName: external ? "arrow.up.right" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Explains how to save links from Safari and other apps with the share extension.
struct ShareExtensionHelpView: View {
    var body: some View {
        HelpStepsView(
            title: "Save from Safari",
            intro: "Save links from Safari or any app in two taps.",
            steps: [
                ("Tap the Share button", "square.and.arrow.up"),
                ("Choose SaveLinks in the app row (tap More if you don't see it)", "ellipsis"),
                ("Pick a folder and tap Save", "checkmark.circle.fill"),
            ]
        )
    }
}

/// A short numbered how-to shown in a sheet.
struct HelpStepsView: View {
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    let intro: LocalizedStringKey
    let steps: [(text: LocalizedStringKey, icon: String)]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Text(intro)
                    .font(.body)
                    .foregroundStyle(.secondary)
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 14) {
                        Text("\(index + 1)")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Theme.brand.gradient, in: Circle())
                        Text(step.text)
                            .font(.body.weight(.medium))
                        Spacer(minLength: 0)
                        Image(systemName: step.icon)
                            .foregroundStyle(Theme.brand)
                    }
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Folder.self, Link.self], inMemory: true)
}

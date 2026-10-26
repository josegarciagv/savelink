//
//  HomeView.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import SwiftUI
import SwiftData
import CoreSpotlight

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var folders: [Folder]
    @Query(filter: #Predicate<Link> { $0.deletedAt == nil }) private var allLinks: [Link]
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var opener = LinkOpener.shared
    @State private var showAddFolder = false
    @State private var showSettings = false
    @State private var showSubscription = false
    @State private var addLinkRequest: AddLinkRequest?
    @State private var folderToEdit: Folder?
    @State private var folderToDelete: Folder?
    @State private var linkToMove: Link?
    @State private var searchText = ""
    @State private var clipboardHasURL = false
    @State private var dismissedClipboardChange = -1
    @State private var path = NavigationPath()
    @State private var sidebarSelection: SidebarItem? = .home
    @Query(filter: #Predicate<Link> { $0.deletedAt != nil }) private var trashedLinks: [Link]
    @AppStorage("folderSortOrder") private var sortOrder: String = "newToOld"
    @AppStorage("folderLayout") private var folderLayout: String = "grid"

    struct AddLinkRequest: Identifiable {
        let id = UUID()
        var folder: Folder?
        var url: String = ""
    }

    /// Sections of the sidebar shown on wide screens (iPhone Duo unfolded, iPad).
    enum SidebarItem: Hashable {
        case home
        case filter(LinkFilter)
        case trash
        case folder(Folder)
    }

    enum SortOrder: String, CaseIterable {
        case newToOld = "newToOld"
        case oldToNew = "oldToNew"
        case lastUpdated = "lastUpdated"
        case name = "name"

        var displayName: String {
            switch self {
            case .newToOld: return String(localized: "New to Old")
            case .oldToNew: return String(localized: "Old to New")
            case .lastUpdated: return String(localized: "Last Updated")
            case .name: return String(localized: "Name (A–Z)")
            }
        }
    }

    /// Pinned folders first, then the chosen order.
    var sortedFolders: [Folder] {
        let order = SortOrder(rawValue: sortOrder) ?? .newToOld
        let sorted: [Folder]
        switch order {
        case .newToOld:
            sorted = folders.sorted { $0.createdAt > $1.createdAt }
        case .oldToNew:
            sorted = folders.sorted { $0.createdAt < $1.createdAt }
        case .lastUpdated:
            sorted = folders.sorted { $0.lastUpdatedDate > $1.lastUpdatedDate }
        case .name:
            sorted = folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return sorted.filter(\.isPinned) + sorted.filter { !$0.isPinned }
    }

    var favoriteLinks: [Link] {
        allLinks.filter(\.isFavorite).sorted { $0.lastUpdatedDate > $1.lastUpdatedDate }
    }

    var recentLinks: [Link] {
        Array(allLinks.sorted { $0.createdAt > $1.createdAt }.prefix(5))
    }

    var readLaterLinks: [Link] {
        allLinks.filter(\.isReadLater).sorted { $0.createdAt > $1.createdAt }
    }

    var brokenCount: Int {
        allLinks.filter(\.isBroken).count
    }

    /// Tags from visible links, most used first.
    var allTags: [String] {
        let counts = allLinks.flatMap(\.tags).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }

    var isSubscribed: Bool {
        subscriptionManager.subscriptionStatus == .subscribed
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPhone Duo unfolded and iPad: sidebar + content.
                NavigationSplitView {
                    sidebar
                } detail: {
                    NavigationStack(path: $path) {
                        detailRoot
                            .linkDestinations()
                    }
                    .id(sidebarSelection)
                }
            } else {
                // iPhone and iPhone Duo folded.
                NavigationStack(path: $path) {
                    homeScreen
                        .linkDestinations()
                }
            }
        }
        .tint(Theme.brand)
        .sheet(isPresented: $showAddFolder) {
            FolderFormView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showSubscription) {
            SubscriptionView()
        }
        .sheet(item: $addLinkRequest) { request in
            AddLinkView(folder: request.folder, initialURL: request.url)
        }
        .sheet(item: $folderToEdit) { folder in
            FolderFormView(folder: folder)
        }
        .sheet(item: $linkToMove) { link in
            MoveLinkView(link: link)
        }
        .deleteFolderAlert(
            isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }),
            folder: folderToDelete
        ) {
            if let folder = folderToDelete, sidebarSelection == .folder(folder) {
                sidebarSelection = .home
            }
            folderToDelete = nil
        }
        .fullScreenCover(item: $opener.presentedURL) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
        .onAppear {
            checkClipboard()
            syncShareExtension()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                checkClipboard()
                syncShareExtension()
                // Catch renewals, expirations and refunds that happened while away.
                Task { await subscriptionManager.checkSubscriptionStatus() }
            }
        }
        .onChange(of: sidebarSelection) { _, _ in
            path = NavigationPath()
        }
        .onOpenURL(perform: handleDeepLink)
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            // Tapped a link in Spotlight search.
            if let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
               let id = UUID(uuidString: identifier) {
                LinkOpener.shared.open(linkID: id)
            }
        }
    }

    /// Home content with search, used as the root on compact screens and as "Home" in the sidebar.
    private var homeScreen: some View {
        Group {
            if !searchText.isEmpty {
                searchResults
            } else if folders.isEmpty {
                onboarding
            } else {
                dashboard
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("SaveLink")
        .searchable(text: $searchText, prompt: "Search links, tags and folders")
        .toolbar {
            if horizontalSizeClass != .regular {
                ToolbarItem(placement: .topBarLeading) {
                    settingsButton
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                addMenu
            }
        }
    }

    private var settingsButton: some View {
        Button(action: { showSettings = true }) {
            Image(systemName: "gearshape")
        }
    }

    private var addMenu: some View {
        Menu {
            Button {
                addLinkRequest = AddLinkRequest(folder: { if case .folder(let folder) = sidebarSelection { return folder } else { return nil } }())
            } label: {
                Label("New Link", systemImage: "link.badge.plus")
            }
            Button {
                showAddFolder = true
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
        } label: {
            Image(systemName: "plus")
                .fontWeight(.semibold)
        }
    }

    // MARK: - Sidebar (wide screens)

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            Section {
                Label("Home", systemImage: "house.fill")
                    .tag(SidebarItem.home)
                sidebarFilterRow(.favorites, count: favoriteLinks.count)
                sidebarFilterRow(.readLater, count: readLaterLinks.count)
                if brokenCount > 0 {
                    sidebarFilterRow(.broken, count: brokenCount)
                }
                Label("Recently Deleted", systemImage: "trash")
                    .badge(trashedLinks.count)
                    .tag(SidebarItem.trash)
            }

            Section("Folders") {
                ForEach(sortedFolders) { folder in
                    HStack(spacing: 10) {
                        Image(systemName: folder.icon)
                            .foregroundStyle(Color.folder(folder.color))
                            .frame(width: 24)
                        Text(folder.name)
                            .lineLimit(1)
                        Spacer()
                        Text("\(folder.activeLinks.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .tag(SidebarItem.folder(folder))
                    .contextMenu { folderMenu(folder) }
                }
            }

            if !allTags.isEmpty {
                Section("Tags") {
                    ForEach(allTags.prefix(20), id: \.self) { tag in
                        Label("#\(tag)", systemImage: "number")
                            .tag(SidebarItem.filter(.tag(tag)))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SaveLink")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                settingsButton
            }
        }
    }

    private func sidebarFilterRow(_ filter: LinkFilter, count: Int) -> some View {
        Label {
            Text(filter.title)
        } icon: {
            Image(systemName: filter.icon)
                .foregroundStyle(filter.color)
        }
        .badge(count)
        .tag(SidebarItem.filter(filter))
    }

    @ViewBuilder
    private var detailRoot: some View {
        switch sidebarSelection {
        case .filter(let filter):
            LinkListView(filter: filter)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { addMenu } }
        case .trash:
            TrashView()
        case .folder(let folder):
            FolderDetailView(folder: folder)
                .id(folder.id)
        case .home, .none:
            homeScreen
        }
    }

    /// Opens a smart list: in the sidebar on wide screens, pushed on compact ones.
    private func show(_ filter: LinkFilter) {
        if horizontalSizeClass == .regular {
            sidebarSelection = .filter(filter)
        } else {
            path = NavigationPath()
            path.append(filter)
        }
    }

    /// savelink://open?id=…, savelink://add, savelink://readlater, savelink://favorites
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "savelink" else { return }
        switch url.host() {
        case "open":
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "id" }?.value
                .flatMap(UUID.init(uuidString:))
            if let id { LinkOpener.shared.open(linkID: id) }
        case "add":
            addLinkRequest = AddLinkRequest()
        case "paste":
            // From the Control Center button: save whatever link is in the clipboard.
            let pasteboard = UIPasteboard.general
            addLinkRequest = AddLinkRequest(url: pasteboard.url?.absoluteString ?? pasteboard.string ?? "")
        case "readlater":
            show(.readLater)
        case "favorites":
            show(.favorites)
        default:
            break
        }
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                statsCard

                if clipboardHasURL {
                    clipboardBanner
                }

                libraryTiles

                if !readLaterLinks.isEmpty {
                    section("Read Later", icon: "book.fill", trailing: seeAll(.readLater)) {
                        VStack(spacing: 0) {
                            ForEach(readLaterLinks.prefix(3)) { link in
                                dashboardLinkRow(link, isLast: link.id == readLaterLinks.prefix(3).last?.id)
                            }
                        }
                        .card()
                    }
                }

                if !favoriteLinks.isEmpty {
                    section("Favorites", icon: "star.fill") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(favoriteLinks) { link in
                                    NavigationLink(value: link) {
                                        FavoriteCard(link: link)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu { LinkContextMenu(link: link) { linkToMove = link } }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.horizontal, -16)
                    }
                }

                section("Folders", icon: "folder.fill", trailing: folderControls) {
                    if folderLayout == "grid" {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                            ForEach(sortedFolders) { folder in
                                folderLink(folder) { FolderCard(folder: folder) }
                            }
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(sortedFolders) { folder in
                                folderLink(folder) { FolderRowView(folder: folder) }
                                if folder.id != sortedFolders.last?.id {
                                    Divider().padding(.leading, 70)
                                }
                            }
                        }
                        .card()
                    }
                }

                if !allTags.isEmpty {
                    section("Tags", icon: "number") {
                        FlowLayout(spacing: 8) {
                            ForEach(allTags.prefix(24), id: \.self) { tag in
                                NavigationLink(value: LinkFilter.tag(tag)) {
                                    TagChip(tag: tag)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !recentLinks.isEmpty {
                    section("Recently Added", icon: "clock.fill") {
                        VStack(spacing: 0) {
                            ForEach(recentLinks) { link in
                                dashboardLinkRow(link, isLast: link.id == recentLinks.last?.id)
                            }
                        }
                        .card()
                    }
                }
            }
            .padding()
            .padding(.bottom, 20)
        }
        .animation(.snappy, value: folderLayout)
        .animation(.snappy, value: clipboardHasURL)
    }

    private func dashboardLinkRow(_ link: Link, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            NavigationLink(value: link) {
                HStack {
                    LinkRowView(link: link, showFolder: true)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .contextMenu { LinkContextMenu(link: link) { linkToMove = link } }
            if !isLast {
                Divider().padding(.leading, 74)
            }
        }
    }

    private func seeAll(_ filter: LinkFilter) -> some View {
        NavigationLink(value: filter) {
            Text("See All")
                .font(.subheadline.weight(.semibold))
        }
    }

    /// Smart lists, like the Reminders app.
    private var libraryTiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            libraryTile(title: "Favorites", icon: "star.fill", color: .yellow, count: favoriteLinks.count, value: LinkFilter.favorites)
            libraryTile(title: "Read Later", icon: "book.fill", color: .orange, count: readLaterLinks.count, value: LinkFilter.readLater)
            if brokenCount > 0 {
                libraryTile(title: "Broken", icon: "exclamationmark.triangle.fill", color: .red, count: brokenCount, value: LinkFilter.broken)
            }
            if !trashedLinks.isEmpty {
                libraryTile(title: "Deleted", icon: "trash.fill", color: .gray, count: trashedLinks.count, value: LibraryRoute.trash)
            }
        }
    }

    private func libraryTile<Value: Hashable>(title: LocalizedStringKey, icon: String, color: Color, count: Int, value: Value) -> some View {
        NavigationLink(value: value) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(color.gradient, in: Circle())
                    Spacer()
                    Text("\(count)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .card()
        }
        .buttonStyle(.plain)
    }

    private func folderLink<RowLabel: View>(_ folder: Folder, @ViewBuilder label: () -> RowLabel) -> some View {
        NavigationLink(value: folder) {
            label()
        }
        .buttonStyle(.plain)
        .contextMenu { folderMenu(folder) }
    }

    @ViewBuilder
    private func folderMenu(_ folder: Folder) -> some View {
        Button {
            folder.isPinned.toggle()
            modelContext.saveAndBackup()
            Haptics.tap()
        } label: {
            Label(folder.isPinned ? "Unpin" : "Pin to Top", systemImage: folder.isPinned ? "pin.slash" : "pin")
        }
        Button {
            addLinkRequest = AddLinkRequest(folder: folder)
        } label: {
            Label("Add Link", systemImage: "link.badge.plus")
        }
        Button {
            folderToEdit = folder
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Divider()
        Button(role: .destructive) {
            folderToDelete = folder
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var folderControls: some View {
        HStack(spacing: 14) {
            Menu {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.rawValue) { order in
                        Text(order.displayName).tag(order.rawValue)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            Button {
                folderLayout = folderLayout == "grid" ? "list" : "grid"
                Haptics.tap()
            } label: {
                Image(systemName: folderLayout == "grid" ? "list.bullet" : "square.grid.2x2")
            }
        }
        .font(.subheadline.weight(.semibold))
    }

    private func section<Content: View>(_ title: LocalizedStringKey, icon: String, @ViewBuilder content: () -> Content) -> some View {
        section(title, icon: icon, trailing: EmptyView(), content: content)
    }

    private func section<Content: View, Trailing: View>(
        _ title: LocalizedStringKey,
        icon: String,
        trailing: Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.title3.weight(.bold))
                    .labelStyle(SectionLabelStyle())
                Spacer()
                trailing
            }
            content()
        }
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                statItem(value: allLinks.count, label: "Links", icon: "link")
                statItem(value: folders.count, label: "Folders", icon: "folder.fill")
                statItem(value: readLaterLinks.count, label: "To Read", icon: "book.fill")
            }

            if !isSubscribed {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Free plan")
                        Spacer()
                        Text("\(allLinks.count)/50 links")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    ProgressView(value: Double(min(allLinks.count, 50)), total: 50)
                        .tint(.white)
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(colors: [Theme.brand, Color(red: 0.42, green: 0.32, blue: 0.86)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: Theme.brand.opacity(0.3), radius: 14, y: 8)
    }

    private func statItem(value: Int, label: LocalizedStringKey, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text("\(value)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var clipboardBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.title3)
                .foregroundStyle(Theme.brand)
                .frame(width: 40, height: 40)
                .background(Theme.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Link in clipboard")
                    .font(.subheadline.weight(.semibold))
                Text("Save it with one tap")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Save") {
                let pasteboard = UIPasteboard.general
                let url = pasteboard.url?.absoluteString ?? pasteboard.string ?? ""
                dismissedClipboardChange = pasteboard.changeCount
                clipboardHasURL = false
                addLinkRequest = AddLinkRequest(url: url)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            Button {
                dismissedClipboardChange = UIPasteboard.general.changeCount
                clipboardHasURL = false
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .card()
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Imports links saved from Safari and refreshes the folder list the extension shows.
    private func syncShareExtension() {
        modelContext.applyWidgetReadMarks()
        if modelContext.importPendingLinks() > 0 {
            Haptics.success()
        } else {
            modelContext.publishSharedSnapshot()
        }
    }
    
    private func checkClipboard() {
        let pasteboard = UIPasteboard.general
        // hasURLs doesn't read the clipboard, so it doesn't trigger the paste prompt.
        clipboardHasURL = pasteboard.hasURLs && pasteboard.changeCount != dismissedClipboardChange
    }

    // MARK: - Onboarding

    private var onboarding: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Theme.brand.gradient)
                    .padding(.top, 12)
                VStack(spacing: 8) {
                    Text("Welcome to SaveLink")
                        .font(.title.weight(.bold))
                    Text("Keep all your favorite links organized in folders.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 16) {
                    onboardingRow("folder.fill", "Organize", "Group links in colorful folders with icons.")
                    onboardingRow("star.fill", "Favorites", "Keep the links you use most one tap away.")
                    onboardingRow("book.fill", "Read Later", "Save pages to read offline, with reminders.")
                    onboardingRow("doc.on.clipboard.fill", "Fast", "Save copied links and auto-fill their titles.")
                }
                .padding(20)
                .card()

                VStack(spacing: 12) {
                    Button {
                        showAddFolder = true
                    } label: {
                        Label("Create a Folder", systemImage: "folder.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))

                    Button {
                        addLinkRequest = AddLinkRequest()
                    } label: {
                        Label("Save a Link", systemImage: "link.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                }

                if !isSubscribed {
                    Button {
                        showSubscription = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Theme.brand.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Try PRO Free")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("Unlimited links, AI summaries, QR scanner and more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .card()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
    }

    private func onboardingRow(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Theme.brand)
                .frame(width: 36, height: 36)
                .background(Theme.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Search

    private var searchResults: some View {
        let matchingFolders = folders.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        let tagQuery = TagFormatter.clean(searchText)
        let matchingLinks = allLinks.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.url.localizedCaseInsensitiveContains(searchText)
                || $0.tags.contains { $0.hasPrefix(tagQuery) }
                || ($0.summary?.localizedCaseInsensitiveContains(searchText) ?? false)
                || ($0.linkDescription?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        .sorted { $0.createdAt > $1.createdAt }
        let matchingIDs = Set(matchingLinks.map(\.id))
        let relatedLinks = SmartSearch.related(to: searchText, in: allLinks)
            .filter { !matchingIDs.contains($0.id) }

        return List {
            if matchingFolders.isEmpty && matchingLinks.isEmpty && relatedLinks.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .listRowBackground(Color.clear)
            }
            if !matchingFolders.isEmpty {
                Section("Folders") {
                    ForEach(matchingFolders) { folder in
                        NavigationLink(value: folder) {
                            FolderRowView(folder: folder, compact: true)
                        }
                    }
                }
            }
            if !matchingLinks.isEmpty {
                Section("Links") {
                    ForEach(matchingLinks) { link in
                        NavigationLink(value: link) {
                            LinkRowView(link: link, showFolder: true)
                        }
                        .contextMenu { LinkContextMenu(link: link) { linkToMove = link } }
                    }
                }
            }
            if !relatedLinks.isEmpty {
                Section {
                    ForEach(relatedLinks) { link in
                        NavigationLink(value: link) {
                            LinkRowView(link: link, showFolder: true)
                        }
                        .contextMenu { LinkContextMenu(link: link) { linkToMove = link } }
                    }
                } header: {
                    Label("Related", systemImage: "sparkle.magnifyingglass")
                } footer: {
                    Text("Found by meaning, privately on your device. Try “recipes from last week”.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Components

private struct SectionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .font(.subheadline)
                .foregroundStyle(Theme.brand)
            configuration.title
        }
    }
}

struct FolderCard: View {
    let folder: Folder

    var body: some View {
        let tint = Color.folder(folder.color)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: folder.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Spacer()
                if folder.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(tint)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(folder.activeLinks.count == 1 ? "1 link" : "\(folder.activeLinks.count) links")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct FolderRowView: View {
    let folder: Folder
    var compact = false

    var body: some View {
        let tint = Color.folder(folder.color)
        HStack(spacing: 14) {
            Image(systemName: folder.icon)
                .font(.system(size: compact ? 15 : 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: compact ? 34 : 42, height: compact ? 34 : 42)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(folder.activeLinks.count == 1 ? "1 link" : "\(folder.activeLinks.count) links")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if folder.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(tint)
            }
            if !compact {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, compact ? 0 : 16)
        .padding(.vertical, compact ? 2 : 12)
        .contentShape(Rectangle())
    }
}

struct FavoriteCard: View {
    let link: Link

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FaviconView(urlString: link.url, color: .folder(link.folder?.color), size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(link.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2, reservesSpace: true)
                Text(link.domain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(width: 150, alignment: .leading)
        .card()
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Folder.self, Link.self], inMemory: true)
}

enum LibraryRoute: Hashable {
    case trash
}

extension View {
    /// Navigation destinations shared by every navigation stack in the app.
    func linkDestinations() -> some View {
        self
            .navigationDestination(for: Folder.self) { folder in
                FolderDetailView(folder: folder)
            }
            .navigationDestination(for: Link.self) { link in
                LinkDetailView(link: link)
            }
            .navigationDestination(for: LinkFilter.self) { filter in
                LinkListView(filter: filter)
            }
            .navigationDestination(for: LibraryRoute.self) { _ in
                TrashView()
            }
    }
}

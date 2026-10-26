//
//  LinkDetailView.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import SwiftUI
import SwiftData

struct LinkDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let link: Link
    @State private var showEditView = false
    @State private var showMoveView = false
    @State private var showQRCode = false
    @State private var showReader = false
    @State private var copied = false
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showSubscriptionView = false
    @State private var isSummarizing = false
    @State private var aiError: String?
    @State private var showCustomReminder = false
    @State private var customReminderDate = Date().addingTimeInterval(3600)
    @State private var showNotificationsOff = false

    private var tint: Color { .folder(link.folder?.color) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if link.isBroken {
                    brokenBanner
                }
                actions
                readerCard
                readLaterCard
                aiCard
                details
            }
            .padding()
            // Keep a readable width on the iPhone Duo inner display and iPad.
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .tint(tint)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    withAnimation(.snappy) { link.isFavorite.toggle() }
                    link.modelContext?.saveAndBackup()
                    Haptics.tap()
                } label: {
                    Image(systemName: link.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(link.isFavorite ? .yellow : tint)
                        .contentTransition(.symbolEffect(.replace))
                }
                Button("Edit") { showEditView = true }
            }
        }
        .sheet(isPresented: $showEditView) {
            EditLinkView(link: link) {
                // Navigate back when link is deleted
                dismiss()
            }
        }
        .sheet(isPresented: $showMoveView) {
            MoveLinkView(link: link)
        }
        .fullScreenCover(isPresented: $showReader) {
            ReaderView(link: link)
        }
        .sheet(isPresented: $showQRCode) {
            QRCodeSheet(link: link)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSubscriptionView) {
            SubscriptionView()
        }
        .sheet(isPresented: $showCustomReminder) {
            NavigationStack {
                DatePicker("Remind me", selection: $customReminderDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Custom Reminder")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showCustomReminder = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Set") {
                                showCustomReminder = false
                                scheduleReminder(at: customReminderDate)
                            }
                            .fontWeight(.semibold)
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Notifications Are Off", isPresented: $showNotificationsOff) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("Allow notifications for SaveLinks to get reading reminders.")
        }
    }
    
    // MARK: - Read later & reminders
    
    private var brokenBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("This link may be broken")
                    .font(.subheadline.weight(.semibold))
                Text("The page returned an error the last time it was checked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
    
    private var readLaterCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: Binding(
                get: { link.isReadLater },
                set: { newValue in
                    link.isReadLater = newValue
                    if !newValue, link.reminderDate != nil {
                        ReminderScheduler.cancel(for: link)
                        link.reminderDate = nil
                    }
                    link.modelContext?.saveAndBackup()
                    Haptics.tap()
                }
            )) {
                Label {
                    Text("Read Later")
                } icon: {
                    Image(systemName: "book.fill")
                        .foregroundStyle(.orange)
                }
            }
            .tint(.orange)
            .padding()
            
            Divider().padding(.leading)
            
            HStack {
                Label {
                    if let date = link.reminderDate, date > .now {
                        Text("Reminder \(date.formatted(.relative(presentation: .named)))")
                    } else {
                        Text("Remind Me")
                    }
                } icon: {
                    Image(systemName: link.reminderDate == nil ? "bell" : "bell.fill")
                        .foregroundStyle(.orange)
                }
                Spacer()
                Menu {
                    ForEach(ReminderScheduler.Preset.allCases) { preset in
                        Button {
                            scheduleReminder(at: preset.date)
                        } label: {
                            Label(preset.title, systemImage: preset.icon)
                        }
                    }
                    Button {
                        showCustomReminder = true
                    } label: {
                        Label("Pick Date & Time…", systemImage: "calendar")
                    }
                    if link.reminderDate != nil {
                        Divider()
                        Button(role: .destructive) {
                            ReminderScheduler.cancel(for: link)
                            link.reminderDate = nil
                            link.modelContext?.saveAndBackup()
                        } label: {
                            Label("Remove Reminder", systemImage: "bell.slash")
                        }
                    }
                } label: {
                    Text(link.reminderDate == nil ? "Set" : "Change")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding()
        }
        .card()
    }
    
    private func scheduleReminder(at date: Date) {
        Task {
            let scheduled = await ReminderScheduler.schedule(for: link, at: date)
            if scheduled {
                Haptics.success()
            } else {
                showNotificationsOff = true
            }
        }
    }
    
    // MARK: - AI summary
    
    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Summary", systemImage: "apple.intelligence")
                    .font(.headline)
                    .foregroundStyle(
                        LinearGradient(colors: [.orange, .pink, .purple, .blue], startPoint: .leading, endPoint: .trailing)
                    )
                Spacer()
                if isSummarizing {
                    ProgressView()
                }
            }
            
            if let summary = link.summary, !summary.isEmpty {
                Text(summary)
                    .font(.callout)
                    .textSelection(.enabled)
            } else if let aiError {
                Text(aiError)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Get a short summary and suggested tags, created privately on your device with Apple Intelligence.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            
            Button {
                summarize()
            } label: {
                HStack {
                    Image(systemName: subscriptionManager.canUseAI ? "sparkles" : "lock.fill")
                    Text(link.summary == nil ? "Summarize" : "Summarize Again")
                    if !subscriptionManager.canUseAI {
                        Text("PRO")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.brand.opacity(0.15), in: Capsule())
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .disabled(isSummarizing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .card()
    }
    
    private func summarize() {
        guard subscriptionManager.canUseAI else {
            showSubscriptionView = true
            return
        }
        isSummarizing = true
        aiError = nil
        Task {
            defer { isSummarizing = false }
            do {
                let insights = try await LinkAI.insights(for: link.url, title: link.name)
                withAnimation { LinkAI.apply(insights, to: link) }
                Haptics.success()
            } catch {
                aiError = error.localizedDescription
                Haptics.error()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            FaviconView(urlString: link.url, color: tint, size: 88)
                .shadow(color: tint.opacity(0.25), radius: 16, y: 8)
            VStack(spacing: 6) {
                Text(link.name)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(link.domain)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !link.tags.isEmpty {
                FlowLayout {
                    ForEach(link.tags, id: \.self) { tag in
                        NavigationLink(value: LinkFilter.tag(tag)) {
                            TagChip(tag: tag, color: tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            // The main action sits right under the title, no scrolling needed.
            Button {
                LinkOpener.shared.open(link)
            } label: {
                Label("Open Link", systemImage: "safari.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal)
        .card()
    }

    private var actions: some View {
        HStack(spacing: 12) {
            actionButton(copied ? "Copied" : "Copy", icon: copied ? "checkmark" : "doc.on.doc") {
                UIPasteboard.general.string = link.url
                Haptics.success()
                withAnimation { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation { copied = false }
                }
            }
            if let url = URL(string: link.url) {
                ShareLink(item: url) {
                    actionLabel("Share", icon: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            }
            actionButton("QR Code", icon: "qrcode") { showQRCode = true }
            actionButton("Move", icon: "folder") { showMoveView = true }
        }
    }

    private func actionButton(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(title, icon: icon)
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .frame(height: 24)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .card()
    }

    /// Offline copy, highlights and notes.
    private var readerCard: some View {
        Button {
            showReader = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: link.readerText == nil ? "arrow.down.doc.fill" : "doc.text.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.readerText == nil ? "Save for Offline Reading" : "Read Offline")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Group {
                        if link.readerText == nil {
                            Text("Read without internet, highlight and take notes")
                        } else {
                            Text("\(link.highlights.count) highlights\(link.notes?.isEmpty == false ? " · Notes" : "")")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .card()
        }
        .buttonStyle(.plain)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let description = link.linkDescription, !description.isEmpty {
                detailRow("Description") {
                    Text(description)
                }
                Divider().padding(.leading)
            }
            detailRow("URL") {
                Text(link.url)
                    .textSelection(.enabled)
                    .foregroundStyle(tint)
            }
            Divider().padding(.leading)
            if let folder = link.folder {
                detailRow("Folder") {
                    HStack(spacing: 8) {
                        Image(systemName: folder.icon)
                            .foregroundStyle(tint)
                        Text(folder.name)
                    }
                }
                Divider().padding(.leading)
            }
            HStack(spacing: 0) {
                stat("Added", value: link.createdAt.formatted(.dateTime.day().month(.abbreviated).year()))
                Divider().frame(height: 36)
                stat("Opened", value: "\(link.visitCount)×")
                Divider().frame(height: 36)
                stat("Last opened", value: link.lastOpenedAt?.formatted(.relative(presentation: .named)) ?? String(localized: "Never"))
            }
            .padding(.vertical, 12)
        }
        .card()
    }

    private func detailRow<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private func stat(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct EditLinkView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.name) private var folders: [Folder]

    let link: Link
    var onDelete: (() -> Void)? = nil
    @State private var linkName: String
    @State private var url: String
    @State private var linkDescription: String
    @State private var selectedFolderID: UUID?
    @State private var tags: [String]
    @State private var isReadLater: Bool
    @Query(filter: #Predicate<Link> { $0.deletedAt == nil }) private var allLinks: [Link]
    @State private var showDeleteConfirmation = false

    init(link: Link, onDelete: (() -> Void)? = nil) {
        self.link = link
        self.onDelete = onDelete
        _linkName = State(initialValue: link.name)
        _url = State(initialValue: link.url)
        _linkDescription = State(initialValue: link.linkDescription ?? "")
        _selectedFolderID = State(initialValue: link.folder?.id)
        _tags = State(initialValue: link.tags)
        _isReadLater = State(initialValue: link.isReadLater)
    }

    private var tint: Color { .folder(folders.first { $0.id == selectedFolderID }?.color) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $linkName)
                    TextField("Description (optional)", text: $linkDescription, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    TextField("URL", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("URL")
                } footer: {
                    if !Link.isValidURL(url) {
                        Text("This doesn't look like a valid URL.")
                            .foregroundStyle(.red)
                    }
                }

                Section("Tags") {
                    TagEditor(tags: $tags, knownTags: Array(Set(allLinks.flatMap(\.tags))).sorted(), color: tint)
                }
                
                Section {
                    Toggle(isOn: $isReadLater) {
                        Label("Read Later", systemImage: "book.fill")
                    }
                    .tint(.orange)
                }
                
                Section("Folder") {
                    Picker(selection: $selectedFolderID) {
                        ForEach(folders) { folder in
                            Label(folder.name, systemImage: folder.icon)
                                .tag(Optional(folder.id))
                        }
                    } label: {
                        Text("Folder")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Link", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Link")
            .navigationBarTitleDisplayMode(.inline)
            .tint(tint)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .disabled(linkName.trimmingCharacters(in: .whitespaces).isEmpty || !Link.isValidURL(url))
                }
            }
            .confirmationDialog("Delete “\(link.name)”?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Move to Recently Deleted", role: .destructive) {
                    link.moveToTrash()
                    modelContext.saveAndBackup()
                    Haptics.success()
                    dismiss()
                    // Navigate back to the folder
                    onDelete?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can restore it from Recently Deleted for 30 days.")
            }
        }
    }

    private func saveChanges() {
        link.name = linkName.trimmingCharacters(in: .whitespacesAndNewlines)
        if link.url != Link.normalizedURLString(url) {
            link.isBroken = false
            link.summary = nil
        }
        link.url = Link.normalizedURLString(url)
        let trimmedDescription = linkDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        link.linkDescription = trimmedDescription.isEmpty ? nil : trimmedDescription
        link.updatedAt = Date()
        link.tags = tags
        link.isReadLater = isReadLater
        if !isReadLater, link.reminderDate != nil {
            ReminderScheduler.cancel(for: link)
            link.reminderDate = nil
        }

        if let newFolder = folders.first(where: { $0.id == selectedFolderID }), newFolder.id != link.folder?.id {
            link.folder?.links.removeAll { $0.id == link.id }
            link.folder = newFolder
            newFolder.links.append(link)
        }
        // Update folder's updatedAt when link is edited
        link.folder?.updatedAt = Date()

        modelContext.saveAndBackup()
        Haptics.success()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        LinkDetailView(link: Link(name: "Apple", url: "https://apple.com", linkDescription: "Test description"))
    }
    .modelContainer(for: [Folder.self, Link.self], inMemory: true)
}

//
//  RulesView.swift
//  SaveLink
//

import SwiftUI
import SwiftData

struct RulesView: View {
    @ObservedObject private var store = LinkRules.shared
    @State private var editing: LinkRule?

    var body: some View {
        List {
            if store.rules.isEmpty {
                ContentUnavailableView {
                    Label("No Rules", systemImage: "wand.and.stars")
                } description: {
                    Text("Sort new links automatically. For example: links from youtube.com go to Videos with the #video tag.")
                } actions: {
                    Button("Add Rule") { editing = LinkRule(pattern: "") }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(store.rules) { rule in
                        Button {
                            editing = rule
                        } label: {
                            RuleRow(rule: rule)
                        }
                    }
                    .onDelete { store.rules.remove(atOffsets: $0) }
                    .onMove { store.rules.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Rules run when you save a link from the app, Safari, Siri or an import. The first matching rule wins.")
                }
            }
        }
        .navigationTitle("Rules")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = LinkRule(pattern: "")
                } label: {
                    Image(systemName: "plus")
                }
            }
            if !store.rules.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule)
        }
    }
}

private struct RuleRow: View {
    let rule: LinkRule
    @Query private var folders: [Folder]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rule.pattern)
                .font(.headline)
                .foregroundStyle(.primary)
            HStack(spacing: 6) {
                if let folder = folders.first(where: { $0.id == rule.folderID }) {
                    Label(folder.name, systemImage: folder.icon)
                }
                if !rule.tags.isEmpty {
                    Text(rule.tags.map { "#\($0)" }.joined(separator: " "))
                }
                if rule.markReadLater {
                    Label("Read Later", systemImage: "book.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = LinkRules.shared
    @Query(sort: \Folder.name) private var folders: [Folder]
    @State var rule: LinkRule

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("youtube.com", text: $rule.pattern)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("When the link contains")
                }
                Section("Then") {
                    Picker(selection: $rule.folderID) {
                        Text("Don't change").tag(UUID?.none)
                        ForEach(folders) { folder in
                            Label(folder.name, systemImage: folder.icon).tag(Optional(folder.id))
                        }
                    } label: {
                        Label("Move to Folder", systemImage: "folder")
                    }
                    Toggle(isOn: $rule.markReadLater) {
                        Label("Add to Read Later", systemImage: "book")
                    }
                }
                Section("Add Tags") {
                    TagEditor(tags: $rule.tags)
                }
            }
            .navigationTitle("Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let index = store.rules.firstIndex(where: { $0.id == rule.id }) {
                            store.rules[index] = rule
                        } else {
                            store.rules.append(rule)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(rule.pattern.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

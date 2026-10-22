//
//  MoveLinkView.swift
//  SaveLink
//

import SwiftUI
import SwiftData

struct MoveLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.name) private var folders: [Folder]
    let link: Link

    var body: some View {
        NavigationStack {
            List(folders) { folder in
                Button {
                    move(to: folder)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: folder.icon)
                            .foregroundStyle(Color.folder(folder.color))
                            .frame(width: 28)
                        Text(folder.name)
                            .foregroundStyle(.primary)
                        if folder.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if link.folder?.id == folder.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.folder(folder.color))
                        }
                    }
                }
            }
            .navigationTitle("Move to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func move(to folder: Folder) {
        guard link.folder?.id != folder.id else { dismiss(); return }
        link.folder?.links.removeAll { $0.id == link.id }
        link.folder = folder
        folder.links.append(link)
        folder.updatedAt = Date()
        link.updatedAt = Date()
        link.modelContext?.saveAndBackup()
        Haptics.success()
        dismiss()
    }
}

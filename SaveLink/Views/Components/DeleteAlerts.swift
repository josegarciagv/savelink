//
//  DeleteAlerts.swift
//  SaveLink
//
//  Native confirmations for actions that can't be undone.
//

import SwiftUI
import SwiftData

extension View {
    /// Asks before deleting a folder and the links inside it.
    func deleteFolderAlert(isPresented: Binding<Bool>, folder: Folder?, onDeleted: @escaping () -> Void = {}) -> some View {
        let count = folder?.activeLinks.count ?? 0
        return alert(
            Text("Delete “\(folder?.name ?? "")”?"),
            isPresented: isPresented
        ) {
            Button("Delete Folder", role: .destructive) {
                guard let folder, let context = folder.modelContext else { return }
                context.delete(folder)
                context.saveAndBackup()
                Haptics.success()
                onDeleted()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if count == 0 {
                Text("This folder is empty. This can't be undone.")
            } else if count == 1 {
                Text("Its link will be deleted too. This can't be undone.")
            } else {
                Text("Its \(count) links will be deleted too. This can't be undone.")
            }
        }
    }
}

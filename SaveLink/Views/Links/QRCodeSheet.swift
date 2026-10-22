//
//  QRCodeSheet.swift
//  SaveLink
//

import SwiftUI

struct QRCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let link: Link

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let image = QRCodeGenerator.image(for: link.url) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260)
                        .padding(20)
                        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)

                    VStack(spacing: 4) {
                        Text(link.name)
                            .font(.headline)
                        Text(link.domain)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)

                    ShareLink(item: Image(uiImage: image), preview: SharePreview(link.name, image: Image(uiImage: image))) {
                        Label("Share QR Code", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.folder(link.folder?.color), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 32)
                } else {
                    ContentUnavailableView("Can't create QR code", systemImage: "qrcode")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

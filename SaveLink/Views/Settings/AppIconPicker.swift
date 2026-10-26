//
//  AppIconPicker.swift
//  SaveLink
//

import SwiftUI
import UIKit

struct AppIconPicker: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var current = UIApplication.shared.alternateIconName
    @State private var showSubscriptionView = false

    private let icons: [(name: String?, title: LocalizedStringKey, preview: String)] = [
        (nil, "Ocean", "IconPreview-Default"),
        ("AppIcon-Sunset", "Sunset", "IconPreview-Sunset"),
        ("AppIcon-Mint", "Mint", "IconPreview-Mint"),
        ("AppIcon-Graphite", "Graphite", "IconPreview-Graphite"),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 20)], spacing: 24) {
                ForEach(icons, id: \.preview) { icon in
                    let selected = current == icon.name
                    let locked = icon.name != nil && !subscriptionManager.isPro
                    Button {
                        select(icon.name, locked: locked)
                    } label: {
                        VStack(spacing: 10) {
                            Image(icon.preview)
                                .resizable()
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .strokeBorder(selected ? Theme.brand : .clear, lineWidth: 3)
                                        .padding(-5)
                                )
                                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                            HStack(spacing: 4) {
                                if locked {
                                    Image(systemName: "lock.fill").font(.caption2)
                                }
                                Text(icon.title)
                                    .font(.subheadline.weight(selected ? .semibold : .regular))
                            }
                            .foregroundStyle(selected ? Theme.brand : .primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("App Icon")
        .sheet(isPresented: $showSubscriptionView) {
            SubscriptionView()
        }
    }

    private func select(_ name: String?, locked: Bool) {
        guard !locked else {
            showSubscriptionView = true
            return
        }
        guard name != current else { return }
        UIApplication.shared.setAlternateIconName(name) { error in
            if error == nil {
                current = name
                Haptics.success()
            }
        }
    }
}

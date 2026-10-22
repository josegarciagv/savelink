//
//  SubscriptionView.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var selectedProduct: Product?
    @State private var showPurchaseError = false
    @State private var purchaseError: String = ""
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?
    @State private var showManageSubscriptions = false
    @State private var trialEligible = false

    private let privacyURL = URL(string: "https://gvpdf.com/saveurl")!
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private var isSubscribed: Bool {
        subscriptionManager.subscriptionStatus == .subscribed
    }

    private var monthly: Product? {
        subscriptionManager.availableProducts.first { $0.id.contains("monthly") }
    }

    private var yearly: Product? {
        subscriptionManager.availableProducts.first { $0.id.contains("year") }
    }

    /// Percentage saved by paying yearly instead of 12 months.
    private var yearlySavings: Int? {
        guard let monthly, let yearly, monthly.price > 0 else { return nil }
        let fullYear = NSDecimalNumber(decimal: monthly.price * 12).doubleValue
        let yearPrice = NSDecimalNumber(decimal: yearly.price).doubleValue
        let savings = Int(((1 - yearPrice / fullYear) * 100).rounded())
        return savings > 0 ? savings : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    features
                    if isSubscribed {
                        subscribedCard
                    } else {
                        plans
                    }
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.bottom, isSubscribed ? 30 : 140)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                if !isSubscribed {
                    purchaseBar
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .task {
                await subscriptionManager.loadProducts()
                // Pre-select the yearly plan (best value)
                if selectedProduct == nil {
                    selectedProduct = yearly ?? subscriptionManager.availableProducts.first
                }
                await updateTrialEligibility()
            }
            .onChange(of: selectedProduct) { _, _ in
                Task { await updateTrialEligibility() }
            }
            .alert("Purchase Error", isPresented: $showPurchaseError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(purchaseError)
            }
            .alert("Restore Purchases", isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
                Button("OK", role: .cancel) {
                    if isSubscribed { dismiss() }
                }
            } message: {
                Text(restoreMessage ?? "")
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        }
        .tint(Theme.brand)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: isSubscribed ? "crown.fill" : "sparkles")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 92, height: 92)
                .background(
                    LinearGradient(colors: isSubscribed ? [.orange, .pink] : [Theme.brand, Color(red: 0.42, green: 0.32, blue: 0.86)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                )
                .shadow(color: Theme.brand.opacity(0.35), radius: 18, y: 10)

            Text(isSubscribed ? "You're PRO" : "SaveLinks PRO")
                .font(.largeTitle.weight(.bold))
            Text(isSubscribed ? "Every feature is unlocked. Thanks for supporting SaveLinks!" : "Unlimited links and every premium feature.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaywallFeature(icon: "infinity", color: .blue, title: "Unlimited links", subtitle: "Free plan is limited to 50")
            PaywallFeature(icon: "sparkles", color: .pink, title: "AI summaries & tags", subtitle: "Private, on-device Apple Intelligence")
            PaywallFeature(icon: "lock.fill", color: .green, title: "PIN-protected folders", subtitle: "Keep private links private")
            PaywallFeature(icon: "faceid", color: .teal, title: "Face ID & Touch ID", subtitle: "Unlock folders instantly")
            PaywallFeature(icon: "qrcode.viewfinder", color: .purple, title: "QR code scanner", subtitle: "Save links from any QR code")
            PaywallFeature(icon: "paintpalette.fill", color: .orange, title: "Custom folder colors", subtitle: "12 colors to organize your way")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var plans: some View {
        VStack(spacing: 12) {
            if subscriptionManager.isLoading && subscriptionManager.availableProducts.isEmpty {
                ProgressView()
                    .padding()
            } else if subscriptionManager.availableProducts.isEmpty {
                VStack(spacing: 8) {
                    Text("Plans couldn't be loaded.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task { await subscriptionManager.loadProducts() }
                    }
                }
                .padding()
            } else {
                ForEach(subscriptionManager.availableProducts.sorted { $0.price > $1.price }, id: \.id) { product in
                    SubscriptionPlanCard(
                        product: product,
                        isSelected: selectedProduct?.id == product.id,
                        savings: product.id == yearly?.id ? yearlySavings : nil,
                        onSelect: {
                            withAnimation(.snappy) { selectedProduct = product }
                            Haptics.tap()
                        }
                    )
                }
            }
        }
    }

    private var subscribedCard: some View {
        VStack(spacing: 14) {
            Label("Your subscription is active", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Button {
                showManageSubscriptions = true
            } label: {
                Text("Manage Subscription")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 14))
        }
        .padding(20)
        .card()
    }

    private var footer: some View {
        VStack(spacing: 14) {
            if !isSubscribed {
                Button {
                    Task { await restore() }
                } label: {
                    if isRestoring {
                        ProgressView()
                    } else {
                        Text("Restore Purchases")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .disabled(isRestoring)

                Text("Subscriptions renew automatically unless canceled at least 24 hours before the end of the current period. Payment is charged to your Apple Account. Manage or cancel anytime in your App Store account settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
                SwiftUI.Link("Terms of Use", destination: termsURL)
                Text("•").foregroundStyle(.tertiary)
                SwiftUI.Link("Privacy Policy", destination: privacyURL)
            }
            .font(.caption.weight(.medium))
        }
    }

    private var purchaseBar: some View {
        VStack(spacing: 8) {
            Button {
                if let selectedProduct {
                    Task { await purchaseProduct(selectedProduct) }
                }
            } label: {
                Group {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(trialEligible ? "Start Free Trial" : "Continue")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(Theme.brand.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(isPurchasing || selectedProduct == nil)

            if let selectedProduct {
                Text(priceCaption(for: selectedProduct))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: - Helpers

    private func priceCaption(for product: Product) -> String {
        let period = product.id.contains("year") ? "year" : "month"
        if trialEligible, let offer = product.subscription?.introductoryOffer {
            return "\(offer.period.displayText) free, then \(product.displayPrice)/\(period). Cancel anytime."
        }
        return "\(product.displayPrice)/\(period). Cancel anytime."
    }

    private func updateTrialEligibility() async {
        guard let subscription = selectedProduct?.subscription,
              subscription.introductoryOffer?.paymentMode == .freeTrial else {
            trialEligible = false
            return
        }
        trialEligible = await subscription.isEligibleForIntroOffer
    }

    private func purchaseProduct(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let success = try await subscriptionManager.purchase(product)
            if success {
                Haptics.success()
                dismiss()
            }
        } catch {
            purchaseError = error.localizedDescription
            showPurchaseError = true
        }
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        await subscriptionManager.restorePurchases()
        restoreMessage = isSubscribed
            ? "Your PRO subscription has been restored."
            : "No active subscription was found for this Apple Account."
    }
}

private extension Product.SubscriptionPeriod {
    var displayText: String {
        let unitName: String
        switch unit {
        case .day: unitName = value == 7 ? "week" : "day"
        case .week: unitName = "week"
        case .month: unitName = "month"
        case .year: unitName = "year"
        @unknown default: unitName = "period"
        }
        if unit == .day && value == 7 { return "1 week" }
        return value == 1 ? "1 \(unitName)" : "\(value) \(unitName)s"
    }
}

struct PaywallFeature: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.green)
        }
    }
}

struct SubscriptionPlanCard: View {
    let product: Product
    let isSelected: Bool
    var savings: Int? = nil
    let onSelect: () -> Void

    private var isYearly: Bool { product.id.contains("year") }

    private var monthlyEquivalent: String? {
        guard isYearly else { return nil }
        return (product.price / 12).formatted(product.priceFormatStyle)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Theme.brand : Color.secondary.opacity(0.5))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(isYearly ? "Yearly" : "Monthly")
                            .font(.headline)
                        if let savings {
                            Text("SAVE \(savings)%")
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.green, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    if let monthlyEquivalent {
                        Text("\(monthlyEquivalent)/month, billed yearly")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Billed monthly")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.headline)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Theme.brand : Color.clear, lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                if isYearly {
                    Text("BEST VALUE")
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.brand, in: Capsule())
                        .foregroundStyle(.white)
                        .offset(x: -12, y: -10)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SubscriptionView()
}

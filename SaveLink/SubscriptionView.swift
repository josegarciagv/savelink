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
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    // Header
                    VStack(spacing: 10) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 60))
                            .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                        
                        if subscriptionManager.subscriptionStatus == .subscribed {
                            Text("Current Plan")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("You have access to all premium features")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("Upgrade to Premium")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("Unlock all features and unlimited links")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 20)
                    
                    // Current Status
                    if subscriptionManager.subscriptionStatus == .subscribed {
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("You are subscribed to Premium")
                                    .font(.headline)
                                    .foregroundColor(.green)
                            }
                            
                            Text("To manage or cancel your subscription, please visit your iPhone Settings > Apple ID > Subscriptions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    // Features Comparison
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Features")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        FeatureRow(
                            feature: "Links",
                            free: "50 links",
                            premium: "Unlimited",
                            icon: "link"
                        )
                        
                        FeatureRow(
                            feature: "QR Code Scanner",
                            free: "Not available",
                            premium: "Available",
                            icon: "camera.fill"
                        )
                        
                        FeatureRow(
                            feature: "PIN Protection",
                            free: "Not available",
                            premium: "Available",
                            icon: "lock.fill"
                        )
                        
                        FeatureRow(
                            feature: "Face ID / Touch ID",
                            free: "Not available",
                            premium: "Available",
                            icon: "faceid"
                        )
                        
                        FeatureRow(
                            feature: "Custom Colors",
                            free: "Not available",
                            premium: "Available",
                            icon: "paintpalette.fill"
                        )
                    }
                    .padding(.vertical)
                    
                    // Subscription Plans
                    if subscriptionManager.subscriptionStatus != .subscribed {
                        VStack(spacing: 16) {
                            Text("Choose a Plan")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            if subscriptionManager.isLoading {
                                ProgressView()
                                    .padding()
                            } else {
                                ForEach(subscriptionManager.availableProducts, id: \.id) { product in
                                    SubscriptionPlanCard(
                                        product: product,
                                        isSelected: selectedProduct?.id == product.id,
                                        onSelect: {
                                            selectedProduct = product
                                        }
                                    )
                                }
                            }
                            
                            if let selectedProduct = selectedProduct {
                                Button(action: {
                                    Task {
                                        await purchaseProduct(selectedProduct)
                                    }
                                }) {
                                    HStack {
                                        if isPurchasing {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        } else {
                                            Text("Subscribe")
                                                .fontWeight(.semibold)
                                        }
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(red: 0.2, green: 0.4, blue: 0.8))
                                    .cornerRadius(12)
                                }
                                .disabled(isPurchasing)
                                .padding(.horizontal)
                            }
                            
                            // Restore Purchases, Terms, and Privacy (Paywall links)
                            VStack(spacing: 12) {
                                Button(action: {
                                    Task {
                                        await subscriptionManager.restorePurchases()
                                    }
                                }) {
                                    Text("Restore Purchases")
                                        .font(.subheadline)
                                        .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                                }
                                
                                HStack(spacing: 16) {
                                    Button(action: {
                                        if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        Text("Terms")
                                            .font(.subheadline)
                                            .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                                    }
                                    
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    
                                    Button(action: {
                                        if let url = URL(string: "https://gvpdf.com/saveurl") {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        Text("Privacy")
                                            .font(.subheadline)
                                            .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                                    }
                                }
                            }
                            .padding(.top, 10)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 30)
            }
            .navigationTitle(subscriptionManager.subscriptionStatus == .subscribed ? "Current Plan" : "Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                }
            }
            .task {
                await subscriptionManager.loadProducts()
                // Auto-select first product if available
                if selectedProduct == nil, let firstProduct = subscriptionManager.availableProducts.first {
                    selectedProduct = firstProduct
                }
            }
            .alert("Purchase Error", isPresented: $showPurchaseError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(purchaseError)
            }
        }
    }
    
    private func purchaseProduct(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        
        do {
            let success = try await subscriptionManager.purchase(product)
            if success {
                dismiss()
            }
        } catch {
            purchaseError = error.localizedDescription
            showPurchaseError = true
        }
    }
    
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

struct FeatureRow: View {
    let feature: String
    let free: String
    let premium: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(feature)
                    .font(.headline)
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Free")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(free)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    
                    Text("→")
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Premium")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(premium)
                            .font(.subheadline)
                            .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                            .fontWeight(.semibold)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct SubscriptionPlanCard: View {
    let product: Product
    let isSelected: Bool
    let onSelect: () -> Void
    
    var displayName: String {
        if product.id.contains("monthly") {
            return "Monthly"
        } else if product.id.contains("year") {
            return "Yearly"
        }
        return product.displayName
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(displayName)
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                        }
                    }
                    
                    Text(product.displayPrice)
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if product.id.contains("year") {
                        Text("Best Value")
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(isSelected ? Color(red: 0.2, green: 0.4, blue: 0.8).opacity(0.1) : Color(.systemGray6))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color(red: 0.2, green: 0.4, blue: 0.8) : Color.clear, lineWidth: 2)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

#Preview {
    SubscriptionView()
}


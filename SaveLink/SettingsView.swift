//
//  SettingsView.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("colorScheme") private var colorScheme: String = "system"
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showSubscriptionView = false
    
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
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if subscriptionManager.subscriptionStatus == .subscribed {
                        // View Current Plan button for subscribed users
                        Button(action: {
                            showSubscriptionView = true
                        }) {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                                Text("View Current Plan")
                                Spacer()
                                Text("Premium")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        // Current plan status for free users
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                            Text("Current Plan")
                            Spacer()
                            Text("Free")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Account")
                }
                
                // Separate section for Upgrade to PRO card
                if subscriptionManager.subscriptionStatus != .subscribed {
                    Section {
                        VStack(spacing: 16) {
                            // Header with icon and pricing
                            HStack {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Upgrade to Premium")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    if !subscriptionManager.availableProducts.isEmpty {
                                        let monthlyProduct = subscriptionManager.availableProducts.first(where: { $0.id.contains("monthly") })
                                        let yearlyProduct = subscriptionManager.availableProducts.first(where: { $0.id.contains("year") })
                                        
                                        if let monthly = monthlyProduct {
                                            Text("Starting at \(monthly.displayPrice)/month")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        } else if let yearly = yearlyProduct {
                                            Text("Starting at \(yearly.displayPrice)/year")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                    } else if subscriptionManager.isLoading {
                                        Text("Loading prices...")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Unlock all features")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            
                            Divider()
                            
                            // FREE vs PRO Comparison
                            VStack(alignment: .leading, spacing: 12) {
                                Text("FREE vs PRO:")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    PlanComparisonRow(feature: "Links", free: "50", pro: "Unlimited")
                                    PlanComparisonRow(feature: "QR Scanner", free: "❌", pro: "✅")
                                    PlanComparisonRow(feature: "PIN Protection", free: "❌", pro: "✅")
                                    PlanComparisonRow(feature: "Face ID/Touch ID", free: "❌", pro: "✅")
                                    PlanComparisonRow(feature: "Custom Colors", free: "❌", pro: "✅")
                                }
                            }
                            
                            // Upgrade button at the bottom
                            Button(action: {
                                showSubscriptionView = true
                            }) {
                                Text("Upgrade to PRO")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color(red: 0.2, green: 0.4, blue: 0.8))
                                    .cornerRadius(10)
                            }
                            
                            // Restore Purchases, Terms, and Privacy (Paywall links)
                            VStack(spacing: 12) {
                                // Restore Purchases button
                                Button(action: {
                                    Task {
                                        await subscriptionManager.restorePurchases()
                                    }
                                }) {
                                    Text("Restore Purchases")
                                        .font(.system(size: 14))
                                        .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                                }
                                
                                // Terms and Privacy
                                HStack(spacing: 16) {
                                    Button(action: {
                                        if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        Text("Terms")
                                            .font(.system(size: 14))
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
                                            .font(.system(size: 14))
                                            .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                        .padding(.vertical, 12)
                    } header: {
                        Text("Premium")
                    }
                }
                
                Section {
                    HStack {
                        Image(systemName: "moon.fill")
                            .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                        Text("Appearance")
                        Spacer()
                        Picker("", selection: $colorScheme) {
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                            Text("System").tag("system")
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                Section {
                    if authManager.biometricType() != "None" {
                        Toggle(isOn: $authManager.isBiometricEnabled) {
                            HStack {
                                Image(systemName: authManager.biometricType() == "Face ID" ? "faceid" : "touchid")
                                    .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                                Text("Enable \(authManager.biometricType())")
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "faceid")
                                .foregroundColor(Color.secondary)
                            Text("Biometric authentication not available")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Security")
                } footer: {
                    if authManager.biometricType() != "None" {
                        Text("Use \(authManager.biometricType()) to quickly unlock protected folders")
                    }
                }
                
                Section {
                    Button(action: {
                        rateApp()
                    }) {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                            Text("Rate App")
                        }
                    }
                    
                    Button(action: {
                        shareApp()
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up.fill")
                                .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                            Text("Share App")
                        }
                    }
                } header: {
                    Text("App")
                }
                
                Section {
                    Button(action: {
                        if let url = URL(string: "https://gvpdf.com/saveurl") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                            Text("Privacy Policy")
                        }
                    }
                    
                    Button(action: {
                        if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                            Text("Terms and Conditions")
                        }
                    }
                    
                    Button(action: {
                        if let url = URL(string: "mailto:juanitovilleda502@gmail.com") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                            Text("Contact")
                            Spacer()
                            Text("juanitovilleda502@gmail.com")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSubscriptionView) {
                SubscriptionView()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                }
            }
            .task {
                await subscriptionManager.checkSubscriptionStatus()
                // Load products to show pricing in Settings
                if subscriptionManager.subscriptionStatus != .subscribed {
                    await subscriptionManager.loadProducts()
                }
            }
            .preferredColorScheme(colorSchemeMode)
        }
    }
    
    private func rateApp() {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
    
    private func shareApp() {
        let appStoreURL = "https://apps.apple.com/app/id6757314064"
        let activityVC = UIActivityViewController(
            activityItems: [appStoreURL],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            // For iPad
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = rootViewController.view
                popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            rootViewController.present(activityVC, animated: true)
        }
    }
}


struct PlanComparisonRow: View {
    let feature: String
    let free: String
    let pro: String
    
    var body: some View {
        HStack {
            Text(feature)
                .font(.system(size: 13))
                .frame(width: 120, alignment: .leading)
            
            Spacer()
            
            Text(free)
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .frame(width: 80, alignment: .center)
            
            Text(pro)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                .frame(width: 80, alignment: .center)
        }
    }
}

#Preview {
    SettingsView()
}


//
//  SubscriptionManager.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import Foundation
import StoreKit
import Combine

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    @Published var subscriptionStatus: SubscriptionStatus = .free
    
    #if DEBUG
    /// Development only: unlocks PRO without buying it, to test premium features in the
    /// simulator. This code isn't compiled into Release (App Store) builds.
    @Published var debugForcePro: Bool = UserDefaults.standard.bool(forKey: "debugForcePro") {
        didSet {
            UserDefaults.standard.set(debugForcePro, forKey: "debugForcePro")
            Task { await checkSubscriptionStatus() }
        }
    }
    #endif
    @Published var availableProducts: [Product] = []
    @Published var isLoading = false
    
    private let productIDs = [
        "gvwebsite.monthly",  // Monthly subscription
        "gvwebsite.year"      // Yearly subscription
    ]
    
    private var updateListenerTask: Task<Void, Error>?
    
    enum SubscriptionStatus {
        case free
        case subscribed
        case expired
    }
    
    private init() {
        // Start listening for transaction updates
        updateListenerTask = listenForTransactions()
        
        // Load initial subscription status
        Task {
            await checkSubscriptionStatus()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let products = try await Product.products(for: productIDs)
            availableProducts = products.sorted { $0.id < $1.id }
        } catch {
            print("Failed to load products: \(error)")
        }
    }
    
    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await checkSubscriptionStatus()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }
    
    func checkSubscriptionStatus() async {
        var isSubscribed = false
        
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                
                if productIDs.contains(transaction.productID) {
                    isSubscribed = true
                    break
                }
            } catch {
                print("Failed to verify transaction: \(error)")
            }
        }
        
        #if DEBUG
        if debugForcePro { isSubscribed = true }
        #endif
        subscriptionStatus = isSubscribed ? .subscribed : .free
        SharedStore.publish(isPro: isSubscribed)
    }
    
    func restorePurchases() async {
        try? await AppStore.sync()
        await checkSubscriptionStatus()
    }
    
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await transaction.finish()
                    await self.checkSubscriptionStatus()
                } catch {
                    print("Transaction verification failed: \(error)")
                }
            }
        }
    }
    
    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
    
    // Helper methods for checking features
    var canUseQRScanner: Bool {
        subscriptionStatus == .subscribed
    }
    
    var canUsePIN: Bool {
        subscriptionStatus == .subscribed
    }
    
    var canUseFaceID: Bool {
        subscriptionStatus == .subscribed
    }
    
    var canUseAI: Bool {
        subscriptionStatus == .subscribed
    }
    
    var canUseColors: Bool {
        subscriptionStatus == .subscribed
    }
    
    func canAddMoreLinks(currentCount: Int) -> Bool {
        if subscriptionStatus == .subscribed {
            return true // Unlimited for subscribers
        }
        return currentCount < 50 // Free plan limit
    }
}


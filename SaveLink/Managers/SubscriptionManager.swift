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
    }
    
    enum PurchaseResult {
        case purchased
        /// Waiting for approval (Ask to Buy) or extra bank verification.
        case pending
        case cancelled
    }
    
    enum RestoreResult {
        case restored
        case nothingToRestore
        case failed
    }
    
    private init() {
        // Start listening for transaction updates
        updateListenerTask = listenForTransactions()
        
        // Finish purchases interrupted last time (e.g. the app closed mid-purchase),
        // then load the current status.
        Task {
            await finishUnfinishedTransactions()
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
    
    func purchase(_ product: Product) async throws -> PurchaseResult {
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await checkSubscriptionStatus()
            return .purchased
        case .pending:
            // Transaction.updates delivers it once approved.
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }
    
    private func finishUnfinishedTransactions() async {
        for await result in Transaction.unfinished {
            if let transaction = try? checkVerified(result) {
                await transaction.finish()
            }
        }
    }
    
    func checkSubscriptionStatus() async {
        var isSubscribed = false
        
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                
                // Refunded or revoked subscriptions don't count.
                if productIDs.contains(transaction.productID), transaction.revocationDate == nil {
                    isSubscribed = true
                    break
                }
            } catch {
                print("Failed to verify transaction: \(error)")
            }
        }
        
        subscriptionStatus = isSubscribed ? .subscribed : .free
        SharedStore.publish(isPro: isSubscribed)
    }
    
    @discardableResult
    func restorePurchases() async -> RestoreResult {
        do {
            try await AppStore.sync()
        } catch {
            // Still check: entitlements already on the device may be valid.
            await checkSubscriptionStatus()
            return subscriptionStatus == .subscribed ? .restored : .failed
        }
        await checkSubscriptionStatus()
        return subscriptionStatus == .subscribed ? .restored : .nothingToRestore
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
    
    var isPro: Bool {
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


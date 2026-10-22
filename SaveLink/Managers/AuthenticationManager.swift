//
//  AuthenticationManager.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import Foundation
import LocalAuthentication
import Combine

class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var isBiometricEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isBiometricEnabled, forKey: "biometricEnabled")
        }
    }
    
    private init() {
        self.isBiometricEnabled = UserDefaults.standard.bool(forKey: "biometricEnabled")
    }
    
    func authenticate(completion: @escaping (Bool, String?) -> Void) {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            let errorMessage = error?.localizedDescription ?? "Biometric authentication is not available"
            completion(false, errorMessage)
            return
        }
        
        let reason = "Authenticate to access this folder"
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
            DispatchQueue.main.async {
                if success {
                    completion(true, nil)
                } else {
                    let errorMessage = authenticationError?.localizedDescription ?? "Authentication failed"
                    completion(false, errorMessage)
                }
            }
        }
    }
    
    func biometricType() -> String {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "None"
        }
        
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .none:
            return "None"
        @unknown default:
            return "None"
        }
    }
}


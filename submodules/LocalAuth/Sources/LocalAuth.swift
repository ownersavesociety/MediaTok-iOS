import Foundation
import LocalAuthentication
import SwiftSignalKit
import Security

public enum LocalAuthBiometricAuthentication {
    case touchId
    case faceId
}

public struct LocalAuth {
    private static let customKeyIdPrefix = "$#_".data(using: .utf8)!
    
    public enum DecryptionResult {
        public enum Error {
            case cancelled
            case generic
        }
        
        case result(Data)
        case error(Error)
    }
    
    #if targetEnvironment(simulator)
    public final class PrivateKey {
        public let publicKeyRepresentation: Data
        
        fileprivate init() {
            self.publicKeyRepresentation = Data(count: 32)
        }
        
        public func encrypt(data: Data) -> Data? {
            return data
        }
        
        public func decrypt(data: Data) -> DecryptionResult {
            return .result(data)
        }
    }
    #else
    public final class PrivateKey {
        private let privateKey: SecKey
        private let publicKey: SecKey
        public let publicKeyRepresentation: Data
        
        fileprivate init(privateKey: SecKey, publicKey: SecKey, publicKeyRepresentation: Data) {
            self.privateKey = privateKey
            self.publicKey = publicKey
            self.publicKeyRepresentation = publicKeyRepresentation
        }
        
        public func encrypt(data: Data) -> Data? {
            var error: Unmanaged<CFError>?
            let cipherText = SecKeyCreateEncryptedData(self.publicKey, .eciesEncryptionCofactorVariableIVX963SHA512AESGCM, data as CFData, &error)
            if let error {
                error.release()
            }
            guard let cipherText else {
                return nil
            }
            
            let result = cipherText as Data
            return result
        }
        
        public func decrypt(data: Data) -> DecryptionResult {
            var maybeError: Unmanaged<CFError>?
            let plainText = SecKeyCreateDecryptedData(self.privateKey, .eciesEncryptionCofactorVariableIVX963SHA512AESGCM, data as CFData, &maybeError)
            let error = maybeError?.takeRetainedValue()
            
            guard let plainText else {
                if let error {
                    if CFErrorGetCode(error) == -2 {
                        return .error(.cancelled)
                    }
                }
                return .error(.generic)
            }
            
            let result = plainText as Data
            return .result(result)
        }
    }
    #endif
    
    public static var biometricAuthentication: LocalAuthBiometricAuthentication? {
        let context = LAContext()
        if context.canEvaluatePolicy(LAPolicy(rawValue: Int(kLAPolicyDeviceOwnerAuthenticationWithBiometrics))!, error: nil) {
            switch context.biometryType {
            case .faceID, .opticID:
                return .faceId
            case .touchID:
                return .touchId
            case .none:
                return nil
            @unknown default:
                return nil
            }
        } else {
            return nil
        }
    }
    
    public static let evaluatedPolicyDomainState: Data? = {
        let context = LAContext()
        if context.canEvaluatePolicy(LAPolicy(rawValue: Int(kLAPolicyDeviceOwnerAuthenticationWithBiometrics))!, error: nil) {
            if #available(iOSApplicationExtension 9.0, iOS 9.0, *) {
                return context.evaluatedPolicyDomainState
            } else {
                return Data()
            }
        }
        return nil
    }()
    
    public static func auth(reason: String) -> Signal<(Bool, Data?), NoError> {
        return Signal { subscriber in
            let context = LAContext()
            
            if LAContext().canEvaluatePolicy(LAPolicy(rawValue: Int(kLAPolicyDeviceOwnerAuthenticationWithBiometrics))!, error: nil) {
                context.evaluatePolicy(LAPolicy(rawValue: Int(kLAPolicyDeviceOwnerAuthenticationWithBiometrics))!, localizedReason: reason, reply: { result, _ in
                    let evaluatedPolicyDomainState: Data?
                    if #available(iOSApplicationExtension 9.0, iOS 9.0, *) {
                        evaluatedPolicyDomainState = context.evaluatedPolicyDomainState
                    } else {
                        evaluatedPolicyDomainState = Data()
                    }
                    subscriber.putNext((result, evaluatedPolicyDomainState))
                    subscriber.putCompletion()
                })
            } else {
                subscriber.putNext((false, nil))
                subscriber.putCompletion()
            }
            
            return ActionDisposable {
                if #available(iOSApplicationExtension 9.0, iOS 9.0, *) {
                    context.invalidate()
                }
            }
        }
    }
    
    private static func bundleSeedId() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword as String,
            kSecAttrAccount as String: "bundleSeedID",
            kSecAttrService as String: "",
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            status = SecItemAdd(query as CFDictionary, &result)
        }
        if status != errSecSuccess {
            return nil
        }
        guard let result = result else {
            return nil
        }
        if CFGetTypeID(result) != CFDictionaryGetTypeID() {
            return nil
        }
        guard let resultDict = (result as! CFDictionary) as? [String: Any] else {
            return nil
        }
        guard let accessGroup = resultDict[kSecAttrAccessGroup as String] as? String else {
            return nil
        }
        let components = accessGroup.components(separatedBy: ".")
        guard let seedId = components.first else {
            return nil
        }
        return seedId;
    }
    
    public static func getOrCreatePrivateKey(baseAppBundleId: String, keyId: Data) -> PrivateKey? {
        if let key = self.getPrivateKey(baseAppBundleId: baseAppBundleId, keyId: keyId) {
            return key
        } else {
            return self.addPrivateKey(baseAppBundleId: baseAppBundleId, keyId: keyId)
        }
    }
    
    private static func getPrivateKey(baseAppBundleId: String, keyId: Data) -> PrivateKey? {
        #if targetEnvironment(simulator)
        return PrivateKey()
        #else
        let applicationTag = customKeyIdPrefix + keyId
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassKey as String,
            kSecAttrApplicationTag as String: applicationTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom as String,
            kSecReturnRef as String: true
        ]

        var maybePrivateKey: CFTypeRef?
        var status: OSStatus = errSecItemNotFound
        if let bundleSeedId = self.bundleSeedId() {
            var groupedQuery = baseQuery
            groupedQuery[kSecAttrAccessGroup as String] = "\(bundleSeedId).\(baseAppBundleId)"
            status = SecItemCopyMatching(groupedQuery as CFDictionary, &maybePrivateKey)
        }
        if status != errSecSuccess {
            maybePrivateKey = nil
            status = SecItemCopyMatching(baseQuery as CFDictionary, &maybePrivateKey)
        }
        if status != errSecSuccess {
            return nil
        }
        guard let maybePrivateKey else {
            return nil
        }
        if CFGetTypeID(maybePrivateKey) != SecKeyGetTypeID() {
            return nil
        }
        let privateKey = maybePrivateKey as! SecKey
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return nil
        }
        guard let publicKeyRepresentation = SecKeyCopyExternalRepresentation(publicKey, nil) else {
            return nil
        }
        
        let result = PrivateKey(privateKey: privateKey, publicKey: publicKey, publicKeyRepresentation: publicKeyRepresentation as Data)
        
        return result
        #endif
    }
    
    public static func removePrivateKey(baseAppBundleId: String, keyId: Data) -> Bool {
        let applicationTag = customKeyIdPrefix + keyId
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassKey as String,
            kSecAttrApplicationTag as String: applicationTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom as String,
            kSecAttrIsPermanent as String: true
        ]
        var deleted = false
        if let bundleSeedId = self.bundleSeedId() {
            var groupedQuery = baseQuery
            groupedQuery[kSecAttrAccessGroup as String] = "\(bundleSeedId).\(baseAppBundleId)"
            if SecItemDelete(groupedQuery as CFDictionary) == errSecSuccess {
                deleted = true
            }
        }
        if SecItemDelete(baseQuery as CFDictionary) == errSecSuccess {
            deleted = true
        }
        return deleted
    }
    
    private static func addPrivateKey(baseAppBundleId: String, keyId: Data) -> PrivateKey? {
        #if targetEnvironment(simulator)
        return PrivateKey()
        #else
        let applicationTag = customKeyIdPrefix + keyId
        
        guard let access = SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, [.userPresence, .privateKeyUsage], nil) else {
            return nil
        }

        func makeAttributes(accessGroup: String?) -> [String: Any] {
            var privAttrs: [String: Any] = [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: applicationTag,
                kSecAttrAccessControl as String: access
            ]
            if let accessGroup {
                privAttrs[kSecAttrAccessGroup as String] = accessGroup
            }
            return [
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom as String,
                kSecAttrKeySizeInBits as String: 256 as NSNumber,
                kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave as String,
                kSecPrivateKeyAttrs as String: privAttrs
            ]
        }

        var maybePrivateKey: SecKey?
        if let bundleSeedId = self.bundleSeedId() {
            var error: Unmanaged<CFError>?
            maybePrivateKey = SecKeyCreateRandomKey(makeAttributes(accessGroup: "\(bundleSeedId).\(baseAppBundleId)") as CFDictionary, &error)
            if let error {
                error.release()
            }
        }
        if maybePrivateKey == nil {
            var error: Unmanaged<CFError>?
            maybePrivateKey = SecKeyCreateRandomKey(makeAttributes(accessGroup: nil) as CFDictionary, &error)
            if let error {
                error.release()
            }
        }
        guard let privateKey = maybePrivateKey else {
            return nil
        }
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return nil
        }
        guard let publicKeyRepresentation = SecKeyCopyExternalRepresentation(publicKey, nil) else {
            return nil
        }
        
        let result = PrivateKey(privateKey: privateKey, publicKey: publicKey, publicKeyRepresentation: publicKeyRepresentation as Data)
        return result
        #endif
    }
}

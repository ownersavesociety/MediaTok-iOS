import Foundation
import MTCore

// Settings of «Приватность › Подмены»: the number and the profile substitutions, both per account
// and on this device only. Toggles default to off.

public enum MTNetworkSpoofSettings {
    // MARK: Phone number (this device only)
    public static let fakePhoneEnabled = MTAccountSetting<Bool>("networkSpoof.fakePhoneEnabled", default: false)
    /// Digits only, up to 15.
    public static let fakePhone = MTAccountSetting<String>("networkSpoof.fakePhone", default: "")

    // MARK: Profile substitution (this device only)
    public static let profileRedirectEnabled = MTAccountSetting<Bool>("networkSpoof.profileRedirectEnabled", default: false)
    /// Source peer (`MTPeerKey.stringValue`) → the peer whose profile opens instead.
    public static let profileRedirects = MTAccountSetting<[String: MTPeerKey]>("networkSpoof.profileRedirects", default: [:])

    static func declare() {
        let _ = MTNetworkSpoofSettings.fakePhoneEnabled
        let _ = MTNetworkSpoofSettings.fakePhone
        let _ = MTNetworkSpoofSettings.profileRedirectEnabled
        let _ = MTNetworkSpoofSettings.profileRedirects
    }
}

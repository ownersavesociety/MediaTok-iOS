import Foundation
import TelegramCore

public extension EngineRawMessage {
    func isRestricted(platform: String, contentSettings: ContentSettings) -> Bool {
        return self.restrictionReason(platform: platform, contentSettings: contentSettings) != nil
    }
    
    func restrictionReason(platform: String, contentSettings: ContentSettings) -> String? {
        // MEDIATOK: features may ignore message restrictions (MTRestrictionHooks.messageRestriction)
        if !MTRestrictionHooks.messageRestrictionApplies(self) { return nil }
        if let attribute = self.restrictedContentAttribute {
            if let value = attribute.platformText(platform: platform, contentSettings: contentSettings) {
                return value
            }
        }
        return nil
    }
}

public extension RestrictedContentMessageAttribute {
    func platformText(platform: String, contentSettings: ContentSettings) -> String? {
        // MEDIATOK: features may ignore message restrictions for every reader of the text — bubble, copy, previews (MTRestrictionHooks.messageRestriction)
        if !MTRestrictionHooks.messageRestrictionApplies(nil) { return nil }
        for rule in self.rules {
            if rule.reason == "sensitive" {
                continue
            }
            if rule.platform == "all" || rule.platform == "ios" || contentSettings.addContentRestrictionReasons.contains(rule.platform) {
                if !contentSettings.ignoreContentRestrictionReasons.contains(rule.reason) {
                    return mtExtrasRestrictionText(rule.text, reason: rule.reason, platform: rule.platform) // MEDIATOK: «Код ограничения» (MTExtrasCoreHooks.restrictionText)
                }
            }
        }
        return nil
    }
}

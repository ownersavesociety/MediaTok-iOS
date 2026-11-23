import Foundation
import TelegramCore
import MTCore
import MTFeaturesShared

// Settings of «VPN по подписке». Global: Telegram's proxy is shared by every account of the app.
// The loopback port is in MTFeaturesShared (the extensions must recognise the loopback entry).

public struct MTVlessSavedProxy: Codable, Equatable, MTSettingValue {
    public var enabled: Bool
    public var activeServer: ProxyServerSettings?

    public init(enabled: Bool, activeServer: ProxyServerSettings?) {
        self.enabled = enabled
        self.activeServer = activeServer
    }
}

public enum MTVlessSettings {
    public static let enabled = MTSetting<Bool>("vless.enabled", default: false)
    /// Identity of the chosen server (`MTVlessServer.id`), "" = none.
    public static let selectedServer = MTSetting<String>("vless.selectedServer", default: "")
    /// Send a random installation id (`x-hwid`) with subscription requests. Off: panels that limit
    /// devices by it will refuse; the user decides.
    public static let sendHwid = MTSetting<Bool>("vless.sendHwid", default: false)
    /// The random id itself, created on first use. Never derived from the device.
    public static let hwid = MTSetting<String>("vless.hwid", default: "", flags: [.noExport])
    /// Telegram's proxy state before the VPN took it over, restored when the VPN is switched off.
    public static let previousProxy = MTSetting<MTVlessSavedProxy?>("vless.previousProxy", default: nil, flags: [.noExport])
    /// Credentials of the loopback SOCKS5 listener (the same pair is in Telegram's proxy entry).
    public static let inboundUser = MTSetting<String>("vless.inboundUser", default: "", flags: [.noExport])
    public static let inboundPassword = MTSetting<String>("vless.inboundPassword", default: "", flags: [.noExport])

    static func declare() {
        let _ = MTVlessSettings.enabled
        let _ = MTVlessSettings.selectedServer
        let _ = MTVlessSettings.sendHwid
        let _ = MTVlessSettings.hwid
        let _ = MTVlessSettings.previousProxy
        let _ = MTVlessSettings.inboundUser
        let _ = MTVlessSettings.inboundPassword
    }

    /// The installation id for `x-hwid`, created when first needed.
    static func installationId() -> String {
        let current = MTVlessSettings.hwid.value
        if !current.isEmpty {
            return current
        }
        let value = UUID().uuidString
        MTVlessSettings.hwid.set(value)
        return value
    }
}

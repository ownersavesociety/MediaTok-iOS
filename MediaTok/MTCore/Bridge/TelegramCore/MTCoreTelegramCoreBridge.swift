// Compiled into TelegramCore (filegroup //MediaTok/MTCore:TelegramCoreBridgeSources): the parts of
// MTCore that need TelegramCore / Postbox types. MTCore itself can not see them, since
// TelegramCore depends on MTCore.

import Foundation
import Postbox
import SwiftSignalKit
import MTCore

// MARK: - Canonical keys

public extension AccountRecordId {
    /// The account's MediaTok key (same raw value).
    var mt: MTAccountID {
        return MTAccountID(rawValue: self.int64)
    }

    init(mt: MTAccountID) {
        self.init(rawValue: mt.rawValue)
    }
}

public extension PeerId {
    /// The whole PeerId, namespace included. Use this, never `toInt64()`, as a stored key.
    var mtKey: MTPeerKey {
        guard let key = MTPeerKey(namespace: self.namespace._internalGetInt32Value(), id: self.id._internalGetInt64Value()) else {
            preconditionFailure("PeerId namespace out of range")
        }
        return key
    }

    init(mtKey: MTPeerKey) {
        self.init(namespace: PeerId.Namespace._internalFromInt32Value(mtKey.namespace), id: PeerId.Id._internalFromInt64Value(mtKey.id))
    }
}

public extension MessageId {
    /// Peer, message namespace and id.
    var mtKey: MTMessageKey {
        return MTMessageKey(peer: self.peerId.mtKey, namespace: self.namespace, id: self.id)
    }

    init(mtKey: MTMessageKey) {
        self.init(peerId: PeerId(mtKey: mtKey.peer), namespace: mtKey.namespace, id: mtKey.id)
    }
}

// MARK: - Account lifecycle

/// MediaTok hook target: call from `Account.init`, before the account's network starts. Loads the
/// account's MediaTok settings (`<basePath>/mediatok/settings.json`) and runs its migrations.
public func mtCoreAccountDidLoad(id: AccountRecordId, basePath: String) {
    #if DEBUG
    mtCoreBridgeSelfCheckOnce()
    #endif
    MTSettingsStore.shared.registerAccount(id.mt, basePath: basePath)
}

/// MediaTok hook target: call right after `mtCoreAccountDidLoad`, once the account's own peer is known
/// (`Account.init`, the notification service's standalone state manager). Runs the account's
/// migrations of old data keyed by that peer (`MTMigrations.registerAccountPeer`, app only).
public func mtCoreAccountPeerDidLoad(id: AccountRecordId, peerId: PeerId) {
    MTMigrations.accountPeerDidLoad(id.mt, peer: peerId.mtKey)
}

/// MediaTok hook target: call when the account is logged out / removed.
public func mtCoreAccountWillBeRemoved(id: AccountRecordId) {
    MTSettingsStore.shared.unregisterAccount(id.mt)
}

// MARK: - Proxy for MTNetwork

/// The SOCKS5 proxy for MediaTok's own requests, or nil (MTProxy and WEB proxies can not carry
/// a `URLSession` request).
public func mtProxy(from server: ProxyServerSettings?) -> MTProxy? {
    guard let server = server else {
        return nil
    }
    switch server.connection {
    case let .socks5(username, password):
        return .socks5(host: server.host, port: Int(server.port), username: username, password: password)
    case .mtp, .web:
        return nil
    }
}

private struct MTProxyBridgeState {
    let proxy: MTProxy?
    let isDirectConnectionAllowed: Bool
}

private let mtProxyBridgeState = Atomic<MTProxyBridgeState>(value: MTProxyBridgeState(proxy: nil, isDirectConnectionAllowed: true))
private let mtProxyBridgeAttached = Atomic<Bool>(value: false)
private let mtProxyBridgeDisposable = MetaDisposable()

/// MediaTok hook target: call once after the `AccountManager` is created (app and extensions).
/// Keeps `MTNetwork.shared` on the user's active proxy: SOCKS5 is used, any other active proxy
/// blocks direct requests. Later calls do nothing.
public func mtCoreAttachProxySettings(accountManager: AccountManager<TelegramAccountManagerTypes>) {
    if mtProxyBridgeAttached.swap(true) {
        return
    }
    MTNetwork.shared.proxyProvider = {
        return mtProxyBridgeState.with { state in
            return state.proxy
        }
    }
    MTNetwork.shared.isDirectConnectionAllowedProvider = {
        return mtProxyBridgeState.with { state in
            return state.isDirectConnectionAllowed
        }
    }
    mtProxyBridgeDisposable.set((accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
    |> map { sharedData -> ProxyServerSettings? in
        return sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self)?.effectiveActiveServer
    }
    |> distinctUntilChanged).start(next: { server in
        let state = MTProxyBridgeState(proxy: mtProxy(from: server), isDirectConnectionAllowed: server == nil)
        let _ = mtProxyBridgeState.swap(state)
    }))
}

// MARK: - Debug self-check

#if DEBUG
private let mtCoreBridgeSelfChecked = Atomic<Bool>(value: false)

/// MTLegacyKeys mirrors the bit layout of `PeerId(Int64)`; make sure it still does.
private func mtCoreBridgeSelfCheckOnce() {
    if mtCoreBridgeSelfChecked.swap(true) {
        return
    }
    let samples: [PeerId] = [
        PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(777000)),
        PeerId(namespace: Namespaces.Peer.CloudGroup, id: PeerId.Id._internalFromInt64Value(123456789)),
        PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(1234567890123)),
        PeerId(namespace: Namespaces.Peer.SecretChat, id: PeerId.Id._internalFromInt64Value(-5)),
        PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(5000000000))
    ]
    for peerId in samples {
        assert(MTLegacyKeys.peerKey(fromLegacyInt64: peerId.toInt64()) == peerId.mtKey, "MTLegacyKeys diverged from PeerId(Int64)")
        assert(MTLegacyKeys.legacyInt64(of: peerId.mtKey) == peerId.toInt64(), "MTLegacyKeys diverged from PeerId.toInt64()")
        assert(PeerId(mtKey: peerId.mtKey) == peerId, "PeerId(mtKey:) does not round-trip")
    }
}
#endif

import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import PeerAvatarGalleryUI

/// A dated trace of an account: it certainly existed at `timestamp`.
struct MTRegDateTraceFound: Equatable {
    let timestamp: Int32
    let trace: MTRegDateTrace
}

/// Everything the device knows about when an account was created, besides its ID. Each source costs
/// no extra traffic (or one request ever, for the own account's sessions) and nothing runs on the
/// main thread but the cheap synchronous reads of the profile's own data.
enum MTRegDateEvidenceCollector {
    /// Telegram's account (777000): its chat starts when the own account does.
    static let serviceUserId: Int64 = 777000
    /// Messages read from the start of a chat: enough to step over a short imported history.
    static let earliestMessagesLimit = 50
    static let photosTimeout: Double = 20.0
    static let sessionsTimeout: Double = 20.0

    // MARK: Synchronous: the profile's own data

    /// `peerSettings.registration_month` as Telegram sent it ("MM.YYYY"). The server fills it in
    /// `userFull.settings` (`users.getFullUser`), `messages.getPeerSettings` and `updatePeerSettings`
    /// for people outside the contacts — the case where Telegram's new-chat card shows
    /// «Регистрация: <месяц>» (`ChatUserInfoItem`).
    static func telegramMonth(_ cachedData: CachedPeerData?) -> String? {
        guard let cachedData = cachedData as? CachedUserData, let month = cachedData.peerStatusSettings?.registrationDate, !month.isEmpty else {
            return nil
        }
        return month
    }

    /// The last name / photo change the same settings carry: the account existed then.
    static func statusTraces(_ cachedData: CachedPeerData?) -> [MTRegDateTraceFound] {
        guard let cachedData = cachedData as? CachedUserData, let settings = cachedData.peerStatusSettings else {
            return []
        }
        var result: [MTRegDateTraceFound] = []
        if let date = settings.nameChangeDate, date > 0 {
            result.append(MTRegDateTraceFound(timestamp: date, trace: .nameChange))
        }
        if let date = settings.photoChangeDate, date > 0 {
            result.append(MTRegDateTraceFound(timestamp: date, trace: .photoChange))
        }
        return result
    }

    // MARK: Local database (one read transaction)

    /// The earliest traces in the database of this account: the private chat (its first message and
    /// «… joined Telegram»), the message the profile was opened from, the basic group it was opened
    /// from; for the own account Telegram's service chat and Saved Messages.
    static func localTraces(context: AccountContext, peerId: EnginePeer.Id, sourceMessageId: EngineMessage.Id?, sourceChatPeerId: EnginePeer.Id?) -> Signal<[MTRegDateTraceFound], NoError> {
        let isOwn = peerId == context.account.peerId
        return context.account.postbox.transaction { transaction -> [MTRegDateTraceFound] in
            var result: [MTRegDateTraceFound] = []

            // The private chat (for the own account it is Saved Messages).
            let chat = MTRegDateEvidenceCollector.earliestMessage(transaction, peerId: peerId)
            if let timestamp = chat.timestamp {
                result.append(MTRegDateTraceFound(timestamp: timestamp, trace: isOwn ? .savedMessages : .privateChat))
            }
            if let joined = chat.joined {
                result.append(MTRegDateTraceFound(timestamp: joined, trace: .joinedTelegram))
            }

            if isOwn {
                let servicePeerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(MTRegDateEvidenceCollector.serviceUserId))
                if let timestamp = MTRegDateEvidenceCollector.earliestMessage(transaction, peerId: servicePeerId).timestamp {
                    result.append(MTRegDateTraceFound(timestamp: timestamp, trace: .serviceMessages))
                }
            }

            // The message the profile was opened from, when this account wrote it (or its forward
            // names this account as the author: then the original date).
            if let sourceMessageId, let message = transaction.getMessage(sourceMessageId), !MTRegDateEvidenceCollector.isImported(message) {
                let trace: MTRegDateTrace = sourceMessageId.peerId == peerId ? .privateChat : .chatMessage
                if message.author?.id == peerId, message.timestamp > 0 {
                    result.append(MTRegDateTraceFound(timestamp: message.timestamp, trace: trace))
                } else if let forwardInfo = message.forwardInfo, forwardInfo.author?.id == peerId, forwardInfo.date > 0 {
                    result.append(MTRegDateTraceFound(timestamp: forwardInfo.date, trace: trace))
                }
            }

            // The basic group the profile was opened from: when the person joined it, or created it
            // (a basic group can not change its creator). A supergroup keeps no member list here.
            if let sourceChatPeerId, sourceChatPeerId.namespace == Namespaces.Peer.CloudGroup, let cachedGroup = transaction.getPeerCachedData(peerId: sourceChatPeerId) as? CachedGroupData, let participants = cachedGroup.participants {
                for participant in participants.participants where participant.peerId == peerId {
                    switch participant {
                    case let .member(_, _, invitedAt, _), let .admin(_, _, invitedAt, _):
                        if invitedAt > 0 {
                            result.append(MTRegDateTraceFound(timestamp: invitedAt, trace: .groupJoin))
                        }
                    case .creator:
                        if let group = transaction.getPeer(sourceChatPeerId) as? TelegramGroup, group.creationDate > 0 {
                            result.append(MTRegDateTraceFound(timestamp: group.creationDate, trace: .groupCreated))
                        }
                    }
                }
            }
            return result
        }
    }

    /// The first stored messages of a chat, oldest first. Imported history carries the dates of
    /// another messenger and proves nothing about the Telegram account: skipped.
    private static func earliestMessage(_ transaction: Transaction, peerId: PeerId) -> (timestamp: Int32?, joined: Int32?) {
        let namespace = Namespaces.Message.Cloud
        let messages = transaction.getMessages(peerId: peerId, namespace: namespace, from: MessageIndex.lowerBound(peerId: peerId, namespace: namespace), includeFrom: true, to: MessageIndex.upperBound(peerId: peerId, namespace: namespace), limit: MTRegDateEvidenceCollector.earliestMessagesLimit)
        var earliest: Int32?
        var joined: Int32?
        for message in messages {
            if message.timestamp <= 0 || MTRegDateEvidenceCollector.isImported(message) {
                continue
            }
            if earliest.map({ message.timestamp < $0 }) ?? true {
                earliest = message.timestamp
            }
            if joined == nil, MTRegDateEvidenceCollector.isPeerJoined(message) {
                joined = message.timestamp
            }
        }
        return (earliest, joined)
    }

    private static func isImported(_ message: Message) -> Bool {
        return message.forwardInfo?.flags.contains(.isImported) == true
    }

    private static func isPeerJoined(_ message: Message) -> Bool {
        for media in message.media {
            if let action = media as? TelegramMediaAction, case .peerJoined = action.action {
                return true
            }
        }
        return false
    }

    // MARK: Profile photos

    /// The oldest dated profile photo, from the cache the profile header fills
    /// (`peerInfoProfilePhotosWithCache`): while the profile is open its `photos.getUserPhotos` is
    /// already made, this only reads the shared result. Nil if no dated photo arrives in time.
    static func profilePhotoTrace(context: AccountContext, peerId: EnginePeer.Id) -> Signal<MTRegDateTraceFound?, NoError> {
        return peerInfoProfilePhotosWithCache(context: context, peerId: peerId)
        |> mapToSignal { complete, entries -> Signal<MTRegDateTraceFound?, NoError> in
            // The cache first answers «complete, empty» before anything is loaded: wait for dates.
            guard complete, let earliest = MTRegDateEvidenceCollector.earliestPhotoDate(entries) else {
                return .complete()
            }
            return .single(MTRegDateTraceFound(timestamp: earliest, trace: .profilePhoto))
        }
        |> take(1)
        |> timeout(MTRegDateEvidenceCollector.photosTimeout, queue: Queue.mainQueue(), alternate: .single(nil))
    }

    static func earliestPhotoDate(_ entries: [AvatarGalleryEntry]) -> Int32? {
        var earliest: Int32?
        for entry in entries {
            // A personal photo (set by the viewer) comes with date 0.
            if case let .image(_, _, _, _, _, date, _, _, _, _, _, _) = entry, let date, date > 0 {
                if earliest.map({ date < $0 }) ?? true {
                    earliest = date
                }
            }
        }
        return earliest
    }

    // MARK: Own account

    /// The oldest active session's creation (`account.getAuthorizations`). One request to Telegram,
    /// asked once per account: the answer is kept. Nil when the list could not be loaded in time.
    static func sessionTrace(context: AccountContext) -> Signal<MTRegDateTraceFound?, NoError> {
        return Signal { subscriber in
            let sessions = context.engine.privacy.activeSessions()
            let disposable = (sessions.state
            |> filter { state in
                return !state.isLoadingMore && !state.sessions.isEmpty
            }
            |> take(1)).start(next: { state in
                var earliest: Int32?
                for session in state.sessions where session.creationDate > 0 {
                    if earliest.map({ session.creationDate < $0 }) ?? true {
                        earliest = session.creationDate
                    }
                }
                subscriber.putNext(earliest.map { MTRegDateTraceFound(timestamp: $0, trace: .session) })
                subscriber.putCompletion()
            })
            return ActionDisposable {
                disposable.dispose()
                withExtendedLifetime(sessions) {
                }
            }
        }
        |> timeout(MTRegDateEvidenceCollector.sessionsTimeout, queue: Queue.mainQueue(), alternate: .single(nil))
    }
}

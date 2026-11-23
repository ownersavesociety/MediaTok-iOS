import Foundation
import UIKit
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import PresentationDataUtils
import OverlayStatusController
import TextFormat
import MTCore
import MTHooks
import MTFeaturesShared

/// «Переводить перед отправкой»: a UI step before the message is enqueued (the core text stages run
/// afterwards on the translated text). One implementation for both old variants: the language set
/// for this chat in the send menu wins, otherwise the general language of the setting.
/// Secret chats are never sent to a translation service.
enum MTTranslateBeforeSending {
    static func register() {
        MTChatScreenHooks.willSendText.register({ request, proceed in
            return MTTranslateBeforeSending.intercept(request, proceed: proceed)
        })
    }

    static func targetLanguage(context: AccountContext, peerId: PeerId) -> String {
        if let language = MTMessagesPolicy.outgoingLanguage(accountId: context.account.id, peerId: peerId) {
            return language
        }
        return MTMessagesSettings.translateBeforeSendingLanguage.value
    }

    /// A translation is on its way (main thread): Return / Enter pressed again meanwhile would start a
    /// second one, which puts the translation back after the first one was sent and sends it again.
    private static var isTranslating = false

    /// The entities the services must leave as they are: the composer's formatting plus what the send
    /// path detects itself — links, `/commands`, `#hashtags`, `@mentions`, phone numbers.
    static func protectedEntities(_ inputText: NSAttributedString) -> [MessageTextEntity] {
        return generateTextEntities(inputText.string, enabledTypes: .all, currentEntities: generateChatInputTextEntities(inputText))
    }

    private static func intercept(_ request: MTComposedTextRequest, proceed: @escaping () -> Void) -> Bool {
        guard MTMessagesSettings.translateBeforeSending.value else {
            return false
        }
        guard let peerId = request.chatLocation.peerId, peerId.namespace != Namespaces.Peer.SecretChat else {
            return false
        }
        let inputText = request.state.inputText
        let text = inputText.string
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        // Structured composer content (headings, lists, media blocks) can not be rebuilt from
        // translated plain text without losing its structure: such messages are sent as typed.
        if chatInputContent(from: inputText) != request.state.content {
            return false
        }
        if MTTranslateBeforeSending.isTranslating {
            // The first press is being translated and will send; this one changes nothing.
            return true
        }
        let context = request.context
        let toLang = MTTranslateBeforeSending.targetLanguage(context: context, peerId: peerId)
        let entities = MTTranslateBeforeSending.protectedEntities(inputText)
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }

        MTTranslateBeforeSending.isTranslating = true
        let disposable = MetaDisposable()
        let progress = OverlayStatusController(style: presentationData.theme.overallDarkAppearance ? .dark : .light, type: .loading(cancelled: {
            MTTranslateBeforeSending.isTranslating = false
            disposable.dispose()
        }))
        context.sharedContext.mainWindow?.present(progress, on: .root)

        let translateSignal: Signal<(String, [MessageTextEntity])?, TranslationError> = context.engine.messages.translate(text: text, toLang: toLang, entities: entities)
        |> `catch` { _ -> Signal<(String, [MessageTextEntity])?, TranslationError> in
            return MTTranslationEngine.translate([(text, entities)], toLang: toLang, service: .google)
            |> map { items in
                return items.first
            }
        }

        disposable.set((translateSignal
        |> deliverOnMainQueue).start(next: { [weak progress] result in
            MTTranslateBeforeSending.isTranslating = false
            progress?.dismiss()
            if let result, !result.0.isEmpty {
                request.replace(ChatTextInputState(inputText: chatInputStateStringWithAppliedEntities(result.0, entities: result.1)))
            }
            proceed()
        }, error: { [weak progress] _ in
            MTTranslateBeforeSending.isTranslating = false
            progress?.dismiss()
            let alert = textAlertController(context: context, title: MTStrings.Translation.Error.title, text: text, actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .defaultAction, title: MTStrings.Translation.Error.sendOriginal, action: {
                    proceed()
                })
            ])
            context.sharedContext.mainWindow?.present(alert, on: .root)
        }, completed: { [weak progress] in
            // Completion without an answer: never leave the composer blocked.
            if MTTranslateBeforeSending.isTranslating {
                MTTranslateBeforeSending.isTranslating = false
                progress?.dismiss()
            }
        }))
        return true
    }
}

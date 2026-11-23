import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import AccountContext
import Pasteboard
import MTCore
import MTFeaturesShared

/// «История правок» of one message: the current text and every saved version with its server
/// date. A long tap copies a version. No alert with an unbounded text: a list.
func mtMakeEditVersionsController(context: AccountContext, messageId: MessageId) -> ViewController {
    weak var weakController: ViewController?
    let message = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Messages.Message(id: messageId))

    let model = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, message)
    |> map { presentationData, message -> MTADScreenModel in
        var model = MTADScreenModel(title: .text(MTStrings.AntiDelete.Versions.title), sections: [])
        guard let message = message?._asMessage() else {
            model.sections.append(MTADSection(id: "empty", rows: [MTADRow(id: "empty", kind: .footer(MTStrings.AntiDelete.Versions.gone))]))
            return model
        }
        let state = MTAntiDeleteMessageState(attributes: message.attributes)
        let current = message.mtEffectiveText
        var currentText = current.text
        if currentText.isEmpty, let token = mtAntiDeleteMediaToken(message.media) {
            currentText = mtAntiDeleteMediaTitle(token)
        }
        model.sections.append(MTADSection(id: "current", rows: [
            MTADRow(id: "current.header", kind: .header(MTStrings.AntiDelete.Versions.current)),
            MTADRow(id: "current", kind: .text(currentText))
        ]))
        model.tap["current"] = {
            storeMessageTextInPasteboard(current.text, entities: current.entities)
        }

        let versions = state.history?.versions ?? []
        if versions.isEmpty {
            model.sections.append(MTADSection(id: "none", rows: [MTADRow(id: "none", kind: .footer(MTStrings.AntiDelete.Versions.none))]))
        } else {
            var rows: [MTADRow] = []
            for (index, version) in versions.enumerated().reversed() {
                let date = stringForMediumDate(timestamp: version.date, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat)
                var text = version.text
                if let media = version.mediaDescription {
                    let mediaTitle = mtAntiDeleteMediaTitle(media)
                    text = text.isEmpty ? mediaTitle : mediaTitle + "\n" + text
                }
                rows.append(MTADRow(id: "version.\(index).header", kind: .header(date)))
                rows.append(MTADRow(id: "version.\(index)", kind: .text(text)))
                model.tap["version.\(index)"] = {
                    storeMessageTextInPasteboard(version.text, entities: version.entities)
                }
            }
            rows.append(MTADRow(id: "versions.footer", kind: .footer(MTStrings.AntiDelete.Versions.copyHint)))
            model.sections.append(MTADSection(id: "versions", rows: rows))
        }

        var actions: [MTADRow] = [MTADRow(id: "open", kind: .action(title: MTStrings.AntiDelete.History.openInChat, destructive: false))]
        model.tap["open"] = {
            if let navigationController = weakController?.navigationController as? NavigationController {
                mtOpenMessage(context: context, navigationController: navigationController, messageId: messageId, threadId: message.threadId)
            }
        }
        if !versions.isEmpty {
            actions.append(MTADRow(id: "clear", kind: .action(title: MTStrings.AntiDelete.History.clearVersions, destructive: true)))
            model.tap["clear"] = {
                let _ = MTAntiDeleteOperations.removeEditHistory(postbox: context.account.postbox, accountId: context.account.id, messageIds: [messageId]).start()
            }
        }
        model.sections.append(MTADSection(id: "actions", rows: actions))
        return model
    }

    let controller = mtMakeADListController(context: context, model: model)
    weakController = controller
    return controller
}

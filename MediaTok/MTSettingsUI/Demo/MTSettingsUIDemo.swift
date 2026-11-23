import Foundation
import UIKit
import Display
import TelegramPresentationData
import ItemListUI
import MTCore
import MTSettingsUI

// Demo registration of the menu skeleton. NOT part of the normal launch: it exists so the
// orchestrator can check every row type and every preview in the simulator before wave 2.
// Enable it by adding `//MediaTok/MTSettingsUI:MTSettingsUIDemo` to the deps of MTFeatures and
// calling `MTSettingsUIDemo.register()` right after `MTSettingsUI.register()` (see USAGE.md).

enum MTSettingsUIDemoSettings {
    static let toggle = MTSetting<Bool>("menuDemo.toggle", default: false)
    static let choice = MTSetting<String>("menuDemo.choice", default: "a")
    static let longChoice = MTSetting<String>("menuDemo.longChoice", default: "1")
    static let slider = MTSetting<Double>("menuDemo.slider", default: 50.0)
    static let discrete = MTSetting<String>("menuDemo.discrete", default: "medium")
    static let cards = MTSetting<String>("menuDemo.cards", default: "round")
    static let group = MTSetting<Bool>("menuDemo.group", default: false)
    static let groupFirst = MTSetting<Bool>("menuDemo.groupFirst", default: true)
    static let groupSecond = MTSetting<Bool>("menuDemo.groupSecond", default: false)
    static let groupThird = MTSetting<Bool>("menuDemo.groupThird", default: false)
    static let listFirst = MTSetting<Bool>("menuDemo.listFirst", default: true)
    static let listSecond = MTSetting<Bool>("menuDemo.listSecond", default: false)
    static let listThird = MTSetting<Bool>("menuDemo.listThird", default: false)
    static let restart = MTSetting<Bool>("menuDemo.restart", default: false, flags: [.requiresRestart])
    static let accountToggle = MTAccountSetting<Bool>("menuDemo.accountToggle", default: false)
    static let transparency = MTSetting<Double>("menuDemo.transparency", default: 50.0)
    static let segmentToggle = MTSetting<Bool>("menuDemo.segmentToggle", default: false)

    static func touchAll() {
        let _ = toggle
        let _ = choice
        let _ = longChoice
        let _ = slider
        let _ = discrete
        let _ = cards
        let _ = group
        let _ = groupFirst
        let _ = groupSecond
        let _ = groupThird
        let _ = listFirst
        let _ = listSecond
        let _ = listThird
        let _ = restart
        let _ = accountToggle
        let _ = transparency
        let _ = segmentToggle
    }
}

/// A custom preview: a rounded square whose corner radius follows the demo slider while it is
/// dragged (draft), then the stored value.
private final class MTDemoPreviewView: UIView, MTMenuPreviewView {
    private let shapeView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.addSubview(self.shapeView)
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    func update(context: MTMenuContext) {
        let theme = context.presentationData.theme
        self.backgroundColor = mtPreviewBackgroundColor(theme: theme)
        self.shapeView.backgroundColor = theme.list.itemAccentColor
        let value = context.displayValue(.global(MTSettingsUIDemoSettings.slider))
        self.shapeView.layer.cornerRadius = CGFloat(value) / 100.0 * 30.0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 60.0
        self.shapeView.frame = CGRect(x: floor((self.bounds.width - side) / 2.0), y: floor((self.bounds.height - side) / 2.0), width: side, height: side)
    }
}

private func mtDemoCardImage(_ kind: String, theme: PresentationTheme) -> UIImage? {
    let size = CGSize(width: 40.0, height: 40.0)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
        theme.list.itemAccentColor.setFill()
        let rect = CGRect(origin: CGPoint(), size: size)
        switch kind {
        case "round":
            UIBezierPath(ovalIn: rect).fill()
        case "squircle":
            UIBezierPath(roundedRect: rect, cornerRadius: 12.0).fill()
        default:
            UIBezierPath(rect: rect).fill()
        }
    }
}

public enum MTSettingsUIDemo {
    public static let tabId = MTMenuTabID("menuDemo.tab")

    public static func register() {
        assert(Thread.isMainThread)
        MTSettingsUIDemoSettings.touchAll()
        MTSettingsUI.showsEmptyScreens = true

        let tabId = MTSettingsUIDemo.tabId
        MTMenuRegistry.register(
            tab: MTMenuTabDescriptor(
                id: tabId,
                parent: .category(.more),
                title: { MTStrings.Menu.Demo.title },
                topView: MTMenuTopView(content: .animation("ChatListFolders"), text: { MTStrings.Menu.Demo.topText }),
                segments: [
                    MTMenuSegment(id: "first", title: { MTStrings.Menu.Demo.segmentFirst }),
                    MTMenuSegment(id: "second", title: { MTStrings.Menu.Demo.segmentSecond })
                ]
            ),
            linkIn: .moreTabs,
            order: 900,
            subtitle: { MTStrings.Menu.Demo.subtitle },
            icon: .system("hammer"),
            label: { _ in
                return MTSettingsUIDemoSettings.toggle.value ? MTStrings.Menu.Demo.on : nil
            }
        )

        let previews = MTMenuSectionID("menuDemo.previews")
        let rows = MTMenuSectionID("menuDemo.rows")
        let more = MTMenuSectionID("menuDemo.more")
        let second = MTMenuSectionID("menuDemo.second")
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: previews, screen: .tab(tabId), order: 100, segment: "first", header: { MTStrings.Menu.Demo.previewsHeader }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: rows, screen: .tab(tabId), order: 200, segment: "first", header: { MTStrings.Menu.Demo.rowsHeader }, footer: { _ in MTStrings.Menu.Demo.rowsFooter }))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: more, screen: .tab(tabId), order: 300, segment: "first"))
        MTMenuRegistry.register(section: MTMenuSectionDescriptor(id: second, screen: .tab(tabId), order: 400, segment: "second", header: { MTStrings.Menu.Demo.secondHeader }))

        // Previews.
        MTMenuRegistry.register(MTMenuRow(id: "menuDemo.miniChat", section: previews, order: 100, title: { "" }, kind: .preview(.miniChat(MTMiniChatConfiguration(scope: "menuDemo", height: 236.0, content: { _ in
            var content = MTMiniChatContent.sample(header: MTMiniChatContent.sampleHeader())
            content.messages.append(MTPreviewMessage(id: 3, isOutgoing: true, text: MTStrings.Menu.Preview.pendingText, isPending: true, ageSeconds: 60))
            return content
        })))))
        MTMenuRegistry.register(MTMenuRow(id: "menuDemo.transparency", section: previews, order: 200, title: { MTStrings.Menu.Demo.transparency }, kind: .slider(.global(MTSettingsUIDemoSettings.transparency), range: 0.0 ... 100.0, step: 5.0, format: { value in
            return "\(Int(value)) %"
        })))
        MTMenuRegistry.register(MTMenuRow(id: "menuDemo.miniChatList", section: previews, order: 300, title: { "" }, kind: .preview(.miniChatList(MTMiniChatListConfiguration(scope: "menuDemo", height: 228.0, rows: { _ in
            return MTPreviewChatListRow.samples()
        })))))
        MTMenuRegistry.register(MTMenuRow(id: "menuDemo.customPreview", section: previews, order: 400, title: { "" }, kind: .preview(.custom(height: 120.0, make: { _ in
            return MTDemoPreviewView(frame: CGRect())
        }))))

        // Modifiers: the second demo message follows the transparency slider (draft while dragging)
        // and is marked «edited»; the first chat row gets typing while the demo toggle is on.
        MTPreviewModifiers.registerChatModifier(id: "menuDemo.transparency", order: 100) { messages, context in
            guard context.previewScope == "menuDemo" else {
                return
            }
            let transparency = context.displayValue(.global(MTSettingsUIDemoSettings.transparency))
            for i in 0 ..< messages.count where messages[i].id == 2 {
                messages[i].alpha = CGFloat(max(0.15, 1.0 - transparency / 100.0))
                messages[i].isEdited = true
                messages[i].mark = MTPreviewMark(icon: .bundle("Chat/Context Menu/Delete"))
            }
        }
        MTPreviewModifiers.registerChatListModifier(id: "menuDemo.typing", order: 100) { rows, context in
            guard context.previewScope == "menuDemo", MTSettingsUIDemoSettings.toggle.value, !rows.isEmpty else {
                return
            }
            rows[0].isTyping = true
        }

        // One row of every kind.
        MTMenuRegistry.register(MTMenuRow(id: "menuDemo.toggle", section: rows, order: 100, title: { MTStrings.Menu.Demo.toggle }, subtitle: { MTStrings.Menu.Demo.toggleExample }, kind: .toggle(.global(MTSettingsUIDemoSettings.toggle)), searchKeywords: { [MTStrings.Menu.Demo.keywords] }))
        MTMenuRegistry.register(MTMenuRow(id: "menuDemo.choice", section: rows, order: 200, title: { MTStrings.Menu.Demo.choice }, icon: .bundle("Chat/Context Menu/Customize"), kind: .choice(.global(MTSettingsUIDemoSettings.choice), options: [
            MTMenuChoiceOption(value: "a", title: { MTStrings.Menu.Demo.optionA }),
            MTMenuChoiceOption(value: "b", title: { MTStrings.Menu.Demo.optionB }),
            MTMenuChoiceOption(value: "c", title: { MTStrings.Menu.Demo.optionC })
        ])))
        var longOptions: [MTMenuChoiceOption] = []
        for index in 1 ... 9 {
            longOptions.append(MTMenuChoiceOption(value: "\(index)", title: { MTStrings.Menu.Demo.optionNumber(number: "\(index)") }))
        }
        MTMenuRegistry.register(MTMenuRow(id: "menuDemo.longChoice", section: rows, order: 300, title: { MTStrings.Menu.Demo.longChoice }, icon: .bundle("Chat/Context Menu/List"), kind: .choice(.global(MTSettingsUIDemoSettings.longChoice), options: longOptions)))
        MTMenuRegistry.register(MTMenuRow(id: "menuDemo.slider", section: rows, order: 400, title: { MTStrings.Menu.Demo.slider }, kind: .slider(.global(MTSettingsUIDemoSettings.slider), range: 0.0 ... 100.0, step: 1.0, format: { value in
            return "\(Int(value))"
        })))
        MTMenuRegistry.register(MTMenuRow(id: "menuDemo.discrete", section: rows, order: 500, title: { MTStrings.Menu.Demo.discrete }, kind: .discreteChoice(.global(MTSettingsUIDemoSettings.discrete), options: [
            MTMenuChoiceOption(value: "off", title: { MTStrings.Menu.Demo.levelOff }),
            MTMenuChoiceOption(value: "medium", title: { MTStrings.Menu.Demo.levelMedium }),
            MTMenuChoiceOption(value: "high", title: { MTStrings.Menu.Demo.levelHigh })
        ])))
        MTMenuRegistry.register(MTMenuRow(id: "menuDemo.cards", section: rows, order: 600, title: { MTStrings.Menu.Demo.cards }, kind: .cards(.global(MTSettingsUIDemoSettings.cards), options: [
            MTMenuCardOption(value: "round", title: { MTStrings.Menu.Demo.shapeRound }, image: { theme in mtDemoCardImage("round", theme: theme) }),
            MTMenuCardOption(value: "squircle", title: { MTStrings.Menu.Demo.shapeSquircle }, image: { theme in mtDemoCardImage("squircle", theme: theme) }),
            MTMenuCardOption(value: "square", title: { MTStrings.Menu.Demo.shapeSquare }, image: { theme in mtDemoCardImage("square", theme: theme) })
        ])))
        MTMenuRegistry.register(MTMenuRow(id: "menuDemo.group", section: rows, order: 700, title: { MTStrings.Menu.Demo.group }, kind: .expandableGroup(master: .global(MTSettingsUIDemoSettings.group), children: [
            MTMenuRow(id: "menuDemo.groupFirst", section: rows, order: 100, title: { MTStrings.Menu.Demo.groupFirst }, kind: .toggle(.global(MTSettingsUIDemoSettings.groupFirst))),
            MTMenuRow(id: "menuDemo.groupSecond", section: rows, order: 200, title: { MTStrings.Menu.Demo.groupSecond }, kind: .toggle(.global(MTSettingsUIDemoSettings.groupSecond))),
            MTMenuRow(id: "menuDemo.groupThird", section: rows, order: 300, title: { MTStrings.Menu.Demo.groupThird }, kind: .toggle(.global(MTSettingsUIDemoSettings.groupThird)))
        ])))
        MTMenuRegistry.register(MTMenuRow(id: "menuDemo.list", section: rows, order: 750, title: { MTStrings.Menu.Demo.list }, kind: .expandableList(children: [
            MTMenuRow(id: "menuDemo.listFirst", section: rows, order: 100, title: { MTStrings.Menu.Demo.groupFirst }, kind: .toggle(.global(MTSettingsUIDemoSettings.listFirst))),
            MTMenuRow(id: "menuDemo.listSecond", section: rows, order: 200, title: { MTStrings.Menu.Demo.groupSecond }, kind: .toggle(.global(MTSettingsUIDemoSettings.listSecond))),
            MTMenuRow(id: "menuDemo.listThird", section: rows, order: 300, title: { MTStrings.Menu.Demo.groupThird }, kind: .toggle(.global(MTSettingsUIDemoSettings.listThird)))
        ], summary: { count in
            return MTStrings.Menu.Demo.listCount(selected: "\(count.selected)", total: "\(count.total)")
        })))
        MTMenuRegistry.register(MTMenuRow(id: "menuDemo.action", section: rows, order: 800, title: { MTStrings.Menu.Demo.action }, icon: .bundle("Chat/Context Menu/Info"), kind: .action({ context in
            context.presentToast(MTStrings.Menu.Demo.actionDone)
        })))

        MTMenuRegistry.register(MTMenuRow(id: "menuDemo.restart", section: more, order: 100, title: { MTStrings.Menu.Demo.restart }, kind: .toggle(.global(MTSettingsUIDemoSettings.restart))))
        MTMenuRegistry.register(MTMenuRow(id: "menuDemo.accountToggle", section: more, order: 200, title: { MTStrings.Menu.Demo.accountToggle }, subtitle: { MTStrings.Menu.Demo.accountToggleInfo }, kind: .toggle(.account(MTSettingsUIDemoSettings.accountToggle))))
        MTMenuRegistry.register(MTMenuRow(id: "menuDemo.dependent", section: more, order: 300, title: { MTStrings.Menu.Demo.dependent }, kind: .action({ context in
            context.presentToast(MTStrings.Menu.Demo.actionDone)
        }), isVisible: { _ in
            return MTSettingsUIDemoSettings.toggle.value
        }))
        MTMenuRegistry.register(MTMenuRow(id: "menuDemo.custom", section: more, order: 400, title: { MTStrings.Menu.Demo.custom }, kind: .custom({ context in
            return ItemListTextItem(presentationData: context.itemListPresentationData, text: .plain(MTStrings.Menu.Demo.custom), sectionId: context.sectionId)
        })))

        MTMenuRegistry.register(MTMenuRow(id: "menuDemo.segmentToggle", section: second, order: 100, title: { MTStrings.Menu.Demo.segmentToggle }, kind: .toggle(.global(MTSettingsUIDemoSettings.segmentToggle))))
    }
}

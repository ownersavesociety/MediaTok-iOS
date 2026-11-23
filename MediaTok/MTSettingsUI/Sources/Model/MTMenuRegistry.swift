import Foundation
import UIKit
import Display
import SwiftSignalKit

/// Registration API for features. Called on the main thread from the feature's `register()`,
/// i.e. once at launch (see MediaTok spec). Reading happens only while menu screens are built.
public enum MTMenuRegistry {
    public static func register(_ row: MTMenuRow) {
        MTMenuStorage.shared.add(row: row)
    }

    /// Segments («Чаты / Папки / Типы») for a tab someone else created — usually a tab of the
    /// skeleton. Sections pick their segment with `MTMenuSectionDescriptor.segment`.
    public static func register(segments: [MTMenuSegment], for tab: MTMenuTabID) {
        MTMenuStorage.shared.setSegments(segments, for: tab)
    }

    /// Rows a section gets at runtime from data the registry can not know at launch (the chats of
    /// a list, the user's folders). `rows` is called once per opening of the screen; its signal lives
    /// as long as the screen and re-emits the whole list. The rows are shown after the section's
    /// registered rows (by `order`), take part neither in the search nor in the navbar reset, and
    /// their ids must not clash with registered ones (prefix them with the setting's key).
    /// The context passed in can push and present; for row titles use the context of the row
    /// (`.custom` builders get it on every rebuild).
    public static func register(dynamicRowsIn section: MTMenuSectionID, _ rows: @escaping (MTMenuContext) -> Signal<[MTMenuRow], NoError>) {
        MTMenuStorage.shared.addDynamicRows(section: section, provider: rows)
    }

    /// A third-party component on «О приложении › Сторонние компоненты» (a bundled library).
    public static func register(license: MTMenuLicense) {
        mtRegisterLicense(license)
    }

    /// Feature-owned deeper tabs (e.g. «История» inside «Удалённые и изменённые»). The row that
    /// opens the tab is registered separately as a `.tab(id)` row in a section of the parent screen.
    public static func register(tab: MTMenuTabDescriptor) {
        MTMenuStorage.shared.add(tab: tab)
    }

    public static func register(section: MTMenuSectionDescriptor) {
        MTMenuStorage.shared.add(section: section)
    }

    /// Convenience for the most common case: a tab plus its «кнопка с подписью» in the parent section.
    public static func register(tab: MTMenuTabDescriptor, linkIn section: MTMenuSectionID, order: Int, subtitle: (() -> String)? = nil, icon: MTMenuIcon? = nil, label: ((MTMenuContext) -> String?)? = nil) {
        MTMenuStorage.shared.add(tab: tab)
        MTMenuStorage.shared.add(row: MTMenuRow(
            id: "menu.link.\(tab.id.rawValue)",
            section: section,
            order: order,
            title: tab.title,
            subtitle: subtitle,
            icon: icon,
            kind: .tab(tab.id),
            searchKeywords: tab.searchKeywords,
            label: label
        ))
    }
}

/// Main-thread storage behind `MTMenuRegistry`. Sorted views are cached and dropped on every change.
final class MTMenuStorage {
    struct ChatModifier {
        let id: String
        let order: Int
        let modify: (inout [MTPreviewMessage], MTMenuContext) -> Void
    }

    struct ChatListModifier {
        let id: String
        let order: Int
        let modify: (inout [MTPreviewChatListRow], MTMenuContext) -> Void
    }

    static let shared = MTMenuStorage()

    private(set) var rowsById: [String: MTMenuRow] = [:]
    private var rowsBySection: [MTMenuSectionID: [MTMenuRow]] = [:]
    private(set) var tabs: [MTMenuTabID: MTMenuTabDescriptor] = [:]
    private(set) var sectionsById: [MTMenuSectionID: MTMenuSectionDescriptor] = [:]
    private var sectionsByScreen: [MTMenuScreenID: [MTMenuSectionDescriptor]] = [:]
    /// Setting key → row id: every setting has exactly one place in the menu.
    private var rowIdBySettingKey: [String: String] = [:]
    /// Group child row id → group row id.
    private(set) var groupByChildId: [String: String] = [:]
    /// Demo registration only: show tabs and categories that have no rows yet.
    var showsEmptyTabs = false
    private(set) var chatModifiers: [ChatModifier] = []
    private(set) var chatListModifiers: [ChatListModifier] = []
    private var modifierIds = Set<String>()
    /// Section → runtime row providers (`register(dynamicRowsIn:)`).
    private(set) var dynamicRowProviders: [MTMenuSectionID: [(MTMenuContext) -> Signal<[MTMenuRow], NoError>]] = [:]

    private var sortedSectionsCache: [MTMenuScreenID: [MTMenuSectionDescriptor]] = [:]
    private var sortedRowsCache: [MTMenuSectionID: [MTMenuRow]] = [:]

    private init() {
    }

    private func invalidate() {
        self.sortedSectionsCache.removeAll()
        self.sortedRowsCache.removeAll()
    }

    func add(row: MTMenuRow) {
        assert(Thread.isMainThread)
        if self.rowsById[row.id] != nil {
            assertionFailure("MTMenu: duplicate row id \(row.id)")
            return
        }
        var bindingOwners: [(key: String, rowId: String)] = []
        if let children = row.groupChildren {
            if case let .expandableGroup(master, _) = row.kind {
                bindingOwners.append((key: master.key, rowId: row.id))
            }
            for child in children {
                for binding in child.anyBindings {
                    bindingOwners.append((key: binding.key, rowId: child.id))
                }
            }
        } else {
            for binding in row.anyBindings {
                bindingOwners.append((key: binding.key, rowId: row.id))
            }
        }
        for owner in bindingOwners {
            if let existing = self.rowIdBySettingKey[owner.key] {
                assertionFailure("MTMenu: setting \(owner.key) is bound by both \(existing) and \(owner.rowId)")
            } else {
                self.rowIdBySettingKey[owner.key] = owner.rowId
            }
        }
        self.rowsById[row.id] = row
        if let children = row.groupChildren {
            for child in children {
                if self.rowsById[child.id] != nil {
                    assertionFailure("MTMenu: duplicate row id \(child.id)")
                    continue
                }
                if !child.isToggle {
                    assertionFailure("MTMenu: group \(row.id) child \(child.id) must be a toggle")
                }
                self.rowsById[child.id] = child
                self.groupByChildId[child.id] = row.id
            }
        }
        self.rowsBySection[row.section, default: []].append(row)
        self.invalidate()
    }

    func add(tab: MTMenuTabDescriptor) {
        assert(Thread.isMainThread)
        if self.tabs[tab.id] != nil {
            assertionFailure("MTMenu: duplicate tab id \(tab.id.rawValue)")
            return
        }
        self.tabs[tab.id] = tab
        self.invalidate()
    }

    /// Replaces the tab's segments, keeping everything else of its descriptor.
    func setSegments(_ segments: [MTMenuSegment], for tabId: MTMenuTabID) {
        assert(Thread.isMainThread)
        guard let tab = self.tabs[tabId] else {
            assertionFailure("MTMenu: segments for an unknown tab \(tabId.rawValue)")
            return
        }
        if !tab.segments.isEmpty {
            assertionFailure("MTMenu: tab \(tabId.rawValue) already has segments")
        }
        self.tabs[tabId] = MTMenuTabDescriptor(id: tab.id, parent: tab.parent, title: tab.title, topView: tab.topView, segments: segments, makeScreen: tab.makeScreen, searchKeywords: tab.searchKeywords)
        self.invalidate()
    }

    func addDynamicRows(section: MTMenuSectionID, provider: @escaping (MTMenuContext) -> Signal<[MTMenuRow], NoError>) {
        assert(Thread.isMainThread)
        self.dynamicRowProviders[section, default: []].append(provider)
        self.invalidate()
    }

    func hasDynamicRows(in section: MTMenuSectionID) -> Bool {
        return self.dynamicRowProviders[section] != nil
    }

    func add(section: MTMenuSectionDescriptor) {
        assert(Thread.isMainThread)
        if self.sectionsById[section.id] != nil {
            assertionFailure("MTMenu: duplicate section id \(section.id.rawValue)")
            return
        }
        if let existing = self.sectionsByScreen[section.screen]?.first(where: { $0.order == section.order }) {
            assertionFailure("MTMenu: sections \(existing.id.rawValue) and \(section.id.rawValue) share order \(section.order)")
        }
        self.sectionsById[section.id] = section
        self.sectionsByScreen[section.screen, default: []].append(section)
        self.invalidate()
    }

    func addChatModifier(_ modifier: ChatModifier) {
        assert(Thread.isMainThread)
        if !self.modifierIds.insert("chat." + modifier.id).inserted {
            assertionFailure("MTMenu: duplicate chat preview modifier \(modifier.id)")
            return
        }
        self.chatModifiers.append(modifier)
        self.chatModifiers.sort(by: { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.id < rhs.id
        })
    }

    func addChatListModifier(_ modifier: ChatListModifier) {
        assert(Thread.isMainThread)
        if !self.modifierIds.insert("chatList." + modifier.id).inserted {
            assertionFailure("MTMenu: duplicate chat list preview modifier \(modifier.id)")
            return
        }
        self.chatListModifiers.append(modifier)
        self.chatListModifiers.sort(by: { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.id < rhs.id
        })
    }

    func sections(for screen: MTMenuScreenID) -> [MTMenuSectionDescriptor] {
        if let cached = self.sortedSectionsCache[screen] {
            return cached
        }
        let sorted = (self.sectionsByScreen[screen] ?? []).sorted(by: { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.id.rawValue < rhs.id.rawValue
        })
        self.sortedSectionsCache[screen] = sorted
        return sorted
    }

    func rows(in section: MTMenuSectionID) -> [MTMenuRow] {
        if let cached = self.sortedRowsCache[section] {
            return cached
        }
        let sorted = (self.rowsBySection[section] ?? []).sorted(by: { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.id < rhs.id
        })
        self.sortedRowsCache[section] = sorted
        return sorted
    }

    /// The row a setting is bound to (its one place in the menu).
    func row(forSettingKey key: String) -> MTMenuRow? {
        guard let rowId = self.rowIdBySettingKey[key] else {
            return nil
        }
        return self.rowsById[rowId]
    }
}

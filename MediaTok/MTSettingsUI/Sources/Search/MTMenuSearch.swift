import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import MTCore

/// One searchable place in the menu: a category, a tab or a row.
struct MTMenuSearchEntry {
    let id: String
    let title: String
    /// «Категория › Вкладка» (without «MediaTok» and without the title itself).
    let path: [String]
    let keywords: [String]
    let icon: MTMenuIcon?
    let target: MTMenuScreenID
    let focusRowId: String?
}

/// For Telegram's own settings search (`SettingsUI/Sources/Search`): the same places as the
/// MediaTok search, with breadcrumbs that start at «MediaTok».
public struct MTMenuSearchItem {
    public let id: String
    public let title: String
    public let breadcrumbs: [String]
    public let keywords: [String]
    /// Opens the screen (it scrolls to the row and highlights it) through the access gates
    /// (`MTMenuAccessGates`): `push` may be called later, after the code was entered, or never.
    public let open: (AccountContext, @escaping (ViewController) -> Void) -> Void
}

public func mtSettingsSearchItems(context: AccountContext) -> [MTMenuSearchItem] {
    assert(Thread.isMainThread)
    let menuContext = mtDetachedMenuContext(context: context)
    let appName = MTStrings.Menu.title
    return mtMenuSearchIndex(menuContext: menuContext).map { entry in
        let target = entry.target
        let focusRowId = entry.focusRowId
        return MTMenuSearchItem(
            id: "mediatok." + entry.id,
            title: entry.title,
            breadcrumbs: [appName] + entry.path,
            keywords: entry.keywords,
            open: { context, push in
                mtMenuWithAccess(.screen(target), path: mtMenuScreenPathIds(target), context: context, perform: {
                    guard let controller = mtMakeMenuScreen(context: context, screen: target, focusRowId: focusRowId) else {
                        return nil
                    }
                    push(controller)
                    return controller
                })
            }
        )
    }
}

/// A context for code that runs outside a menu screen (search from Telegram's settings).
func mtDetachedMenuContext(context: AccountContext) -> MTMenuContext {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    return MTMenuContext(context: context, presentationData: presentationData, accountPeer: nil, drafts: [:], handle: MTMenuScreenHandle(context: context))
}

private func mtMenuScreenPath(_ screen: MTMenuScreenID, depth: Int = 0) -> [String] {
    if depth > 8 {
        return []
    }
    switch screen {
    case .root:
        return []
    case let .category(category):
        return [category.title]
    case let .tab(tabId):
        guard let tab = MTMenuStorage.shared.tabs[tabId] else {
            return []
        }
        return mtMenuScreenPath(tab.parent, depth: depth + 1) + [tab.title()]
    }
}

/// Every visible place, in menu order. Rows hidden by their own condition (or living on a screen
/// that is not reachable) are left out: a result must open something that is really there.
func mtMenuSearchIndex(menuContext: MTMenuContext) -> [MTMenuSearchEntry] {
    let storage = MTMenuStorage.shared
    var result: [MTMenuSearchEntry] = []
    var visitedScreens = Set<MTMenuScreenID>()

    func visit(screen: MTMenuScreenID, depth: Int) {
        if depth > 8 || visitedScreens.contains(screen) {
            return
        }
        visitedScreens.insert(screen)
        let screenPath = mtMenuScreenPath(screen)
        var segments: [MTMenuSegment] = []
        if case let .tab(tabId) = screen, let tab = storage.tabs[tabId] {
            segments = tab.segments
        }
        for section in storage.sections(for: screen) {
            if let isVisible = section.isVisible, !isVisible(menuContext) {
                continue
            }
            // A row of a segmented tab shows its segment in the path («Исключения › Типы»).
            var path = screenPath
            if let segmentId = section.segment, let segment = segments.first(where: { $0.id == segmentId }) {
                path.append(segment.title())
            }
            for row in storage.rows(in: section.id) {
                if !mtMenuRowIsVisible(row, menuContext: menuContext) {
                    continue
                }
                switch row.kind {
                case let .tab(tabId):
                    guard let tab = storage.tabs[tabId] else {
                        continue
                    }
                    var keywords = row.searchKeywords()
                    keywords.append(contentsOf: tab.searchKeywords())
                    if let subtitle = row.subtitle?() {
                        keywords.append(subtitle)
                    }
                    result.append(MTMenuSearchEntry(id: "tab." + tabId.rawValue, title: tab.title(), path: path, keywords: keywords, icon: row.icon, target: .tab(tabId), focusRowId: nil))
                    visit(screen: .tab(tabId), depth: depth + 1)
                case .preview:
                    continue
                case let .expandableGroup(_, children), let .expandableList(children, _):
                    let title = row.title()
                    result.append(MTMenuSearchEntry(id: row.id, title: title, path: path, keywords: mtRowKeywords(row), icon: row.icon, target: screen, focusRowId: row.id))
                    for child in children {
                        if let isVisible = child.isVisible, !isVisible(menuContext) {
                            continue
                        }
                        result.append(MTMenuSearchEntry(id: child.id, title: child.title(), path: path + [title], keywords: mtRowKeywords(child), icon: row.icon, target: screen, focusRowId: child.id))
                    }
                default:
                    let title = row.title()
                    if title.isEmpty {
                        continue
                    }
                    result.append(MTMenuSearchEntry(id: row.id, title: title, path: path, keywords: mtRowKeywords(row), icon: row.icon, target: screen, focusRowId: row.id))
                }
            }
        }
    }

    for category in MTMenuCategory.allCases {
        if !mtMenuScreenHasContent(.category(category), menuContext: menuContext) {
            continue
        }
        result.append(MTMenuSearchEntry(id: "category." + category.rawValue, title: category.title, path: [], keywords: [category.subtitle], icon: category.icon, target: .category(category), focusRowId: nil))
        visit(screen: .category(category), depth: 0)
    }
    return result
}

private func mtRowKeywords(_ row: MTMenuRow) -> [String] {
    var keywords = row.searchKeywords()
    if let subtitle = row.subtitle?() {
        keywords.append(subtitle)
    }
    return keywords
}

/// Case- and diacritic-insensitive («черный» finds «Чёрный»); every word of the query must match
/// somewhere (title, keywords, path). Ranking: title prefix → title contains all → anything else.
func mtMenuSearch(query: String, menuContext: MTMenuContext) -> [MTMenuSearchEntry] {
    let words = mtFoldForSearch(query).split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
    if words.isEmpty {
        return []
    }
    var ranked: [(rank: Int, index: Int, entry: MTMenuSearchEntry)] = []
    for (index, entry) in mtMenuSearchIndex(menuContext: menuContext).enumerated() {
        let title = mtFoldForSearch(entry.title)
        let haystack = ([title] + entry.keywords.map(mtFoldForSearch) + entry.path.map(mtFoldForSearch)).joined(separator: " ")
        if !words.allSatisfy({ haystack.contains($0) }) {
            continue
        }
        let rank: Int
        if title.hasPrefix(words[0]) || title.contains(" " + words[0]) {
            rank = 0
        } else if words.allSatisfy({ title.contains($0) }) {
            rank = 1
        } else {
            rank = 2
        }
        ranked.append((rank: rank, index: index, entry: entry))
    }
    ranked.sort(by: { lhs, rhs in
        if lhs.rank != rhs.rank {
            return lhs.rank < rhs.rank
        }
        return lhs.index < rhs.index
    })
    return ranked.map { $0.entry }
}

func mtFoldForSearch(_ string: String) -> String {
    return string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
}

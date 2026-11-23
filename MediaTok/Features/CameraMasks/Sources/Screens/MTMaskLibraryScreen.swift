import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import ItemListUI
import PresentationDataUtils
import MTCore
import MTSettingsUI
import MTFeaturesShared

enum MTMaskLibraryTarget {
    /// The user's own choice for round videos and calls.
    case current
    /// The anonymous mode's mask.
    case anonymous
}

/// What the library screen shows: refreshed by the stores' signals, read by the content closure.
private final class MTMaskLibraryState {
    var userEntries: [MTMaskStoreEntry] = []
    var catalogEntries: [MTMaskCatalogEntry] = []
    var cacheSize: Int64?
}

/// «Маски»: pick a mask (built-in, own, from the catalog) and manage the catalog cache. Opening it
/// refreshes the catalog if it is stale (only while masks are in use); nothing else touches the
/// network, and the cache size is computed once in the background, not on every update.
func mtMakeMaskLibraryScreen(context: AccountContext, target: MTMaskLibraryTarget) -> ViewController {
    let state = MTMaskLibraryState()
    let accountId = context.account.id.mt
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var refreshValue = 0
    let bump = {
        refreshValue += 1
        refresh.set(refreshValue)
    }
    let extra: Signal<Void, NoError> = combineLatest(
        MTMaskStore.shared.entries,
        MTMaskCatalog.shared.entries,
        MTMaskEngine.shared.changes.get(),
        refresh.get()
    )
    |> deliverOnMainQueue
    |> map { userEntries, catalogEntries, _, _ -> Void in
        state.userEntries = userEntries
        state.catalogEntries = catalogEntries
        return Void()
    }

    weak var controllerRef: ViewController?
    let languageCode = { MTLocalization.shared.languageCode }

    let currentSelection: () -> MTMaskSelection = {
        switch target {
        case .current:
            return MTMaskSelection(storage: MTMaskSettings.selection.value)
        case .anonymous:
            return MTMaskSelection(storage: MTAnonymousMode.mask.value)
        }
    }
    let select: (MTMaskSelection) -> Void = { selection in
        switch target {
        case .current:
            MTMaskEngine.shared.select(selection, account: accountId)
        case .anonymous:
            MTAnonymousMode.mask.set(selection.storage)
            MTMaskEngine.shared.retry(selection)
        }
    }

    let controller = mtMakeListScreen(context: context, extra: extra, content: {
        let selected = currentSelection()
        var rows: [MTListRow] = []

        rows.append(MTListRow(id: "builtin.header", section: 0, kind: .header(MTStrings.CameraMasks.Masks.builtInSection)))
        if case .current = target {
            rows.append(MTListRow(id: "none", section: 0, kind: .checkbox(title: MTStrings.CameraMasks.Masks.none, subtitle: nil, checked: selected == .none, enabled: true), action: {
                select(.none)
            }))
        }
        for id in MTBuiltInMasks.ids {
            let selection = MTMaskSelection.builtIn(id)
            rows.append(MTListRow(id: "builtin." + id, section: 0, kind: .checkbox(title: MTBuiltInMasks.glyph(id: id) + "  " + MTBuiltInMasks.title(id: id), subtitle: nil, checked: selected == selection, enabled: true), action: {
                select(selection)
            }))
        }

        rows.append(MTListRow(id: "user.header", section: 1, kind: .header(MTStrings.CameraMasks.Masks.ownSection)))
        for entry in state.userEntries {
            let selection = MTMaskSelection.user(entry.id)
            rows.append(MTListRow(id: "user." + entry.id, section: 1, kind: .checkbox(title: entry.manifest.displayName(languageCode: languageCode()), subtitle: MTStrings.CameraMasks.Studio.layers(count: entry.manifest.effects.count), checked: selected == selection, enabled: true), action: {
                select(selection)
            }))
        }
        rows.append(MTListRow(id: "user.create", section: 1, kind: .action(title: MTStrings.CameraMasks.Studio.create, destructive: false, enabled: true), action: {
            controllerRef?.push(mtMakeMaskStudioHome(context: context))
        }))

        rows.append(MTListRow(id: "catalog.header", section: 2, kind: .header(MTStrings.CameraMasks.Masks.catalogSection)))
        if !MTMaskCatalog.isAvailable {
            rows.append(MTListRow(id: "catalog.unavailable", section: 2, kind: .footer(MTStrings.CameraMasks.Masks.catalogUnavailable)))
        } else if state.catalogEntries.isEmpty {
            rows.append(MTListRow(id: "catalog.empty", section: 2, kind: .footer(MTStrings.CameraMasks.Masks.catalogEmpty)))
        } else {
            for entry in state.catalogEntries {
                let selection = MTMaskSelection.catalog(entry.id)
                rows.append(MTListRow(id: "catalog." + entry.id, section: 2, kind: .checkbox(title: entry.displayName(languageCode: languageCode()), subtitle: nil, checked: selected == selection, enabled: true), action: {
                    select(selection)
                }))
            }
        }

        if case .current = target, MTMaskCatalog.isAvailable {
            let fetchedAt = MTMaskSettings.catalogFetchedAt.value
            let fetchedLabel: String
            if fetchedAt > 0.0 {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                fetchedLabel = formatter.string(from: Date(timeIntervalSince1970: fetchedAt))
            } else {
                fetchedLabel = MTStrings.CameraMasks.Masks.never
            }
            rows.append(MTListRow(id: "cache.header", section: 3, kind: .header(MTStrings.CameraMasks.Masks.cacheSection)))
            rows.append(MTListRow(id: "cache.refresh", section: 3, kind: .disclosure(title: MTStrings.CameraMasks.Masks.refreshCatalog, label: fetchedLabel, icon: nil, enabled: true), action: {
                MTMaskCatalog.shared.refreshIfNeeded(force: true)
            }))
            let sizeLabel = state.cacheSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…"
            rows.append(MTListRow(id: "cache.size", section: 3, kind: .disclosure(title: MTStrings.CameraMasks.Masks.cacheSize, label: sizeLabel, icon: nil, enabled: true), action: {
                guard let controller = controllerRef else {
                    return
                }
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                controller.present(textAlertController(context: context, title: MTStrings.CameraMasks.Masks.clearCacheTitle, text: MTStrings.CameraMasks.Masks.clearCacheText, actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: MTStrings.CameraMasks.Masks.clearCacheConfirm, action: {
                        MTMaskCatalog.shared.clearCache(completion: {
                            state.cacheSize = 0
                            bump()
                        })
                    })
                ]), in: .window(.root))
            }))
            rows.append(MTListRow(id: "cache.limit", section: 3, kind: .disclosure(title: MTStrings.CameraMasks.Masks.cacheLimit, label: MTStrings.CameraMasks.Masks.megabytes(value: MTMaskSettings.cacheLimit.value), icon: nil, enabled: true), action: {
                mtPresentMenuActionSheet(
                    context: context,
                    from: controllerRef,
                    title: MTStrings.CameraMasks.Masks.cacheLimit,
                    buttons: ["50", "100", "200", "400", "800", "1024"].map { value in
                        let prefix = value == MTMaskSettings.cacheLimit.value ? "✓ " : ""
                        return (prefix + MTStrings.CameraMasks.Masks.megabytes(value: value), false, {
                            MTMaskSettings.cacheLimit.set(value)
                        })
                    }
                )
            }))
        }
        rows.append(MTListRow(id: "footer", section: 4, kind: .footer(MTStrings.CameraMasks.Masks.footer)))

        let title: String
        switch target {
        case .current:
            title = MTStrings.CameraMasks.Masks.title
        case .anonymous:
            title = MTStrings.CameraMasks.Anonymous.mask
        }
        return MTListScreenContent(title: title, rows: rows)
    })
    controllerRef = controller

    if MTMaskEngine.isActive(for: accountId) || target == .anonymous {
        MTMaskCatalog.shared.refreshIfNeeded()
    }
    if case .current = target {
        MTMaskCatalog.shared.cacheSize(completion: { size in
            state.cacheSize = size
            bump()
        })
    }
    return controller
}

extension MTMaskLibraryTarget: Equatable {}

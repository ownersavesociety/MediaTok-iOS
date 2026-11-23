import Foundation
import MTCore

// The studio's composed labels. The per-item names (filters, parameters, anchors…) are generated
// into MTMaskStudioNamesGenerated.swift.

extension MTMaskStudioNames {
    static func layerTitle(_ effect: MTMaskEffect) -> String {
        if effect.type == .filter, let id = effect.filterId, MTFilterCatalog.descriptor(id) != nil {
            return MTMaskStudioNames.filterTitle(id)
        }
        return MTMaskStudioNames.effectType(effect.type)
    }

    static func layerSubtitle(_ effect: MTMaskEffect) -> String {
        var parts: [String] = []
        if effect.type == .filter, let id = effect.filterId, let descriptor = MTFilterCatalog.descriptor(id) {
            parts.append(MTMaskStudioNames.category(descriptor.category))
            if descriptor.param("anchor") != nil, let anchor = effect.effectiveAnchor {
                parts.append(MTMaskStudioNames.anchor(anchor))
            }
        } else if let anchor = effect.anchor {
            parts.append(MTMaskStudioNames.anchor(anchor))
        }
        if !effect.isEnabled {
            parts.append(MTStrings.CameraMasks.Studio.layerOff)
        }
        return parts.joined(separator: " · ")
    }

    static func filterSubtitle(_ descriptor: MTFilterDescriptor) -> String {
        var text = MTStrings.CameraMasks.Studio.layerCost(units: "\(descriptor.cost)")
        if descriptor.isHeavy {
            text += " · " + MTStrings.CameraMasks.Studio.heavy
        }
        return text + MTMaskStudioNames.needsSuffix(descriptor.needs)
    }

    /// « · needs a face» and the like; empty when the layer needs nothing from Vision.
    static func needsSuffix(_ needs: MTVisionNeeds) -> String {
        if needs.contains(.segmentation) {
            return " · " + MTStrings.CameraMasks.Studio.needsSegmentation
        }
        if needs.contains(.landmarks) {
            return " · " + MTStrings.CameraMasks.Studio.needsLandmarks
        }
        if needs.contains(.face) {
            return " · " + MTStrings.CameraMasks.Studio.needsFace
        }
        return ""
    }

    static func violation(_ violation: MTMaskBudget.Violation) -> String {
        switch violation {
        case let .tooManyEffects(limit):
            return MTStrings.CameraMasks.Studio.Violation.tooManyEffects(count: limit)
        case .tooManyHeavy:
            return MTStrings.CameraMasks.Studio.Violation.tooManyHeavy
        case .tooManySegmentation:
            return MTStrings.CameraMasks.Studio.Violation.tooManySegmentation
        case .tooManyFaceWarps:
            return MTStrings.CameraMasks.Studio.Violation.tooManyFaceWarps
        case .tooManyAnimated:
            return MTStrings.CameraMasks.Studio.Violation.tooManyAnimated
        case .overBudget:
            return MTStrings.CameraMasks.Studio.Violation.overBudget
        }
    }
}

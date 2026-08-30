import SwiftUI

/// Visual identity of the hotkey HUD per workflow: how the capsule enters
/// and how the icon moves while the workflow runs. Every workflow gets a
/// unique combination of card tint, entrance, and icon motion so it is
/// recognizable at a glance.
struct HUDAnimationStyle {
    enum Entrance {
        case riseUp         // offset y +18 -> 0
        case dropDown       // offset y -18 -> 0
        case slideLeading   // offset x -24 -> 0
        case slideTrailing  // offset x +24 -> 0

        var startOffset: CGSize {
            switch self {
            case .riseUp: return CGSize(width: 0, height: 18)
            case .dropDown: return CGSize(width: 0, height: -18)
            case .slideLeading: return CGSize(width: -24, height: 0)
            case .slideTrailing: return CGSize(width: 24, height: 0)
            }
        }

        /// Every remaining entrance is a pure translation.
        var startScale: CGFloat { 1.0 }

        var spring: Animation {
            .spring(response: 0.38, dampingFraction: 0.8)
        }
    }

    enum IconMotion {
        case variableColorIterative   // symbol effect, macOS 14
        case pulse                    // symbol effect, macOS 14
        case breathe                  // hand-rolled: scale 1.0 <-> 1.1
    }

    let entrance: Entrance
    let iconMotion: IconMotion
}

extension WorkflowType {
    var hudAnimationStyle: HUDAnimationStyle {
        switch self {
        case .transcription:
            return HUDAnimationStyle(entrance: .riseUp, iconMotion: .variableColorIterative)
        case .textImprover:
            return HUDAnimationStyle(entrance: .slideLeading, iconMotion: .pulse)
        case .braindump:
            return HUDAnimationStyle(entrance: .dropDown, iconMotion: .breathe)
        case .selectionEdit:
            return HUDAnimationStyle(entrance: .slideTrailing, iconMotion: .variableColorIterative)
        }
    }
}

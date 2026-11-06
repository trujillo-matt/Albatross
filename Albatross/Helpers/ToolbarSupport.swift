import SwiftUI

// iPhone Duo's vertical bar only keeps toolbar items that have both a title and an
// SF Symbol, so toolbar buttons use `Label` instead of bare images or text.
// The two helpers below isolate the iOS 27 APIs so call sites stay free of
// availability checks. Both fall back to ordinary behaviour on earlier systems.

extension ToolbarItemPlacement {
    /// Placement for a sheet's main confirm or save action.
    /// Pinned in the vertical bar on iOS 27; the standard confirmation slot otherwise.
    static var albatrossConfirm: ToolbarItemPlacement {
        if #available(iOS 27.0, *) {
            return .topBarPinnedTrailing
        }
        return .confirmationAction
    }
}

/// Scroll views draw under the vertical bar on the sides of the screen.
/// This keeps scrolling content out of that strip by clipping it to the safe area.
private struct HorizontalSafeAreaClip: ViewModifier {
    func body(content: Content) -> some View {
        // A mask is laid out inside the safe area even when the scroll view draws beyond it,
        // so a plain rectangle is exactly the safe area on every side.
        content.mask(Rectangle())
    }
}

extension View {
    func clippedToHorizontalSafeArea() -> some View {
        modifier(HorizontalSafeAreaClip())
    }
}

extension ToolbarContent {
    /// Marks a frequently used action so it is the last to collapse into the overflow menu.
    @ToolbarContentBuilder
    func frequentAction() -> some ToolbarContent {
        if #available(iOS 27.0, *) {
            self.visibilityPriority(.high)
        } else {
            self
        }
    }
}

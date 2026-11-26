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
        content.mask { Rectangle().ignoresSafeArea(.container, edges: .vertical) }
    }
}

extension View {
    func clippedToHorizontalSafeArea() -> some View {
        modifier(HorizontalSafeAreaClip())
    }

    /// Keeps the toolbar in a bar along the top, with the clock and status beside the camera, instead of in the
    /// vertical bar down the side (iOS 27.1). Used while scoring, where the paper needs the full width.
    /// Earlier systems already have a top bar.
    @ViewBuilder
    func horizontalToolbarWhereAvailable() -> some View {
        if #available(iOS 27.1, *) {
            self.toolbarVerticalBehavior(.disabled)
        } else {
            self
        }
    }

    /// Presents a sheet from the trailing side when there is room (iOS 27), and as usual otherwise.
    @ViewBuilder
    func sidePlacementWhenWide(_ isWide: Bool) -> some View {
        if #available(iOS 27.0, *) {
            self.presentationPlacement(isWide ? .trailing : .automatic)
        } else {
            self
        }
    }

    /// Keeps a column of content at a comfortable reading width and centres it,
    /// so cards and text don't stretch across a wide screen.
    func readableContentWidth(_ maxWidth: CGFloat = 680) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
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

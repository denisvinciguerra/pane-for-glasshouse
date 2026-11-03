import PaneKit
import SwiftUI
import UIKit

extension View {
    /// The action editor while `model.editingAction` is set: full screen on iPhone, a form sheet
    /// on iPad. Hung above the layouts, so that a rotation, a Split View or a fold that swaps them
    /// keeps it open, and its draft (the editor's state) with it. `onDismiss` is told once it has
    /// closed.
    func actionEditor(_ model: AppModel, onDismiss: @escaping () -> Void = {}) -> some View {
        modifier(ActionEditorPresentation(model: model, onDismiss: onDismiss))
    }
}

private struct ActionEditorPresentation: ViewModifier {
    let model: AppModel
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        let editing = Bindable(model).editingAction
        // The device does not change while the app runs: one presentation only.
        if UIDevice.current.userInterfaceIdiom == .pad {
            content.sheet(item: editing, onDismiss: onDismiss) { ActionEditorSheet(model: model, draft: $0) }
        } else {
            content.fullScreenCover(item: editing, onDismiss: onDismiss) { ActionEditorSheet(model: model, draft: $0) }
        }
    }
}

/// The editor in its navigation bar, in the palette and the theme. Only Cancel and Save close it:
/// a swipe would lose the draft.
private struct ActionEditorSheet: View {
    let model: AppModel
    let draft: CustomAction
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Palette.of(colorScheme)
        NavigationStack {
            ActionEditorView(model: model, draft: draft) { model.editingAction = nil }
                .background(palette.bg)
        }
        .font(.manrope(11))
        .foregroundStyle(palette.fg)
        .tint(palette.fg)
        .environment(\.palette, palette)
        .environment(\.appModel, model)
        .presentationBackground(palette.bg)
        .interactiveDismissDisabled()
        // A sheet is its own presentation: it takes the theme again.
        .preferredColorScheme(model.theme.colorScheme)
    }
}

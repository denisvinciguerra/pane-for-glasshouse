import PaneKit
import SwiftUI

/// "Drag | ⌥ held" and an (i) that explains them, on the right of the Pointer section's title
/// (mockups/2026-11-20-geste-pointeur/geste.html, A). A click on a word only changes the gesture.
struct PointerGesturePicker: View {
    @Binding var selection: PointerMoveGesture
    @State private var showsHelp = false
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            word(.drag, spoken: "Drag") { Text("Drag") }
            word(.option, spoken: "Option held") { Text("⌥ held") }
            Button { showsHelp.toggle() } label: {
                Text(verbatim: "i")
                    .font(.system(size: 9.5, weight: .semibold, design: .serif).italic())
                    .tracking(0)
                    .textCase(nil)
                    .foregroundStyle(showsHelp ? palette.fg : palette.fg.opacity(0.8))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(showsHelp ? palette.fg : palette.line, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About the gestures")
            .popover(isPresented: $showsHelp, arrowEdge: .bottom) { help }
        }
    }

    private func word(_ gesture: PointerMoveGesture, spoken: LocalizedStringKey,
                      @ViewBuilder label: () -> some View) -> some View {
        let chosen = selection == gesture
        return Button { selection = gesture } label: {
            label()
                .sectionLabelStyle()
                .foregroundStyle(chosen ? palette.fg : palette.label)
                .padding(.bottom, 2)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(chosen ? palette.fg : .clear).frame(height: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// Inside the section title, whose style reaches the popover: put back to plain text here.
    private var help: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("**Moving the TV pointer**")
            Text("**⌥ held**: hold ⌥ and move the mouse or a finger on the trackpad, without clicking. Click whenever you like: the click goes to the TV. The Mac cursor stays on the pad.")
            Text("**Drag**: hold the click and move. Release, then click to select.")
            Text("In both: right-click goes back, the wheel or two fingers scroll, and what you type goes to the TV.")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .tracking(0)
        .textCase(nil)
        .lineLimit(nil)
        .foregroundStyle(palette.fg)
        .fixedSize(horizontal: false, vertical: true)
        // 268 pt in all, as in the mockup.
        .frame(width: 240, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

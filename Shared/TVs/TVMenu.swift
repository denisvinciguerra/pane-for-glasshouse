import PaneKit
import SwiftUI

/// The header's label « LG OLED TV · <name> ⌄ » and its menu: one entry per TV (the active one
/// ticked), then « Add a TV… ». Like the footer's chevron menu, it does not close the popover.
struct TVMenu: View {
    let model: AppModel
    var body: some View {
        Menu {
            Picker(selection: Binding(get: { model.activeID },
                                      set: { if let id = $0 { model.activate(id) } })) {
                ForEach(model.store.tvs) { tv in
                    Text(verbatim: tv.name).tag(Optional(tv.id))
                }
            } label: { EmptyView() }
            .pickerStyle(.inline)
            .labelsHidden()
            #if os(macOS)
            Divider()
            Button("Add a TV…") { model.openPreferences(.tv) }
            #endif
        } label: {
            HStack(spacing: 4) {
                Text("LG OLED TV · \(model.activeTV?.name ?? "")")
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
            }
            .sectionLabelStyle()
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(TVMenuButtonStyle())
        .fixedSize()
        .accessibilityLabel(Text("TV: \(model.activeTV?.name ?? "")"))
    }
}

/// The label in its colour, full strength while pressed.
private struct TVMenuButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(configuration.isPressed ? palette.fg : palette.label)
    }
}

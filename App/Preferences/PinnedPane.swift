import PaneKit
import SwiftUI

/// Preferences › Pinned: the active TV's pins in Remote's order, each moved up or down, or unpinned.
struct PinnedPane: View {
    let model: AppModel

    var body: some View {
        PreferencesScroll {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Pinned", trailing: model.store.active?.name)
                if let tv = model.store.activeID {
                    let pinned = model.actions.pinned(for: tv)
                    if pinned.isEmpty {
                        PreferencesNote("Nothing pinned yet. Use PIN on a setting, or + under Pinned on Remote.")
                    }
                    ForEach(Array(pinned.enumerated()), id: \.element.id) { index, action in
                        PreferencesRow {
                            HStack(spacing: 12) {
                                Text(verbatim: action.title)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button { model.actions.movePin(for: tv, from: [index], to: index - 1) } label: {
                                    Text(verbatim: "↑").frame(width: 16)
                                }
                                .disabled(index == 0)
                                .accessibilityLabel(Text("Move up"))
                                Button { model.actions.movePin(for: tv, from: [index], to: index + 2) } label: {
                                    Text(verbatim: "↓").frame(width: 16)
                                }
                                .disabled(index == pinned.count - 1)
                                .accessibilityLabel(Text("Move down"))
                                Button("Unpin") { model.unpin(action.id) }
                            }
                            .buttonStyle(TextButtonStyle())
                            .frame(minHeight: 34)
                        }
                    }
                } else {
                    PreferencesNote("Connect a TV first")
                }
            }
        }
    }
}

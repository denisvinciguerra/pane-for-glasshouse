import PaneKit
import SwiftUI

/// The thin amber bar under the footer while keys are being set: what to do now, then Done to
/// leave (Esc too), or, when the key is taken, the offer to swap, or, when the change would replace the
/// Custom profile, the question.
struct EditBar: View {
    let keyboard: KeyboardController
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: message)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if keyboard.state.replacing != nil {
                Button("Replace") { keyboard.resolveReplacement(replace: true) }
                    .fontWeight(.semibold)
                Button("Cancel") { keyboard.resolveReplacement(replace: false) }
            } else if keyboard.state.conflict != nil {
                Button("Swap") { keyboard.resolveConflict(swap: true) }
                    .fontWeight(.semibold)
                Button("Cancel") { keyboard.resolveConflict(swap: false) }
            } else {
                Button("Done") { keyboard.done() }
                    .fontWeight(.semibold)
            }
        }
        .buttonStyle(.plain)
        .font(.manrope(10))
        .foregroundStyle(palette.accent)
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(palette.accent.opacity(0.08))
        .overlay(alignment: .top) { Rectangle().fill(palette.accent.opacity(0.25)).frame(height: 1) }
    }

    private var message: String {
        if keyboard.state.replacing != nil {
            return String(localized: "Replace your Custom profile?")
        }
        if let conflict = keyboard.state.conflict {
            let key = KeyLabel.text(conflict.binding, layout: keyboard.layout)
            return String(localized: "\(key) is \(keyboard.title(of: conflict.owner))'s key")
        }
        if let id = keyboard.awaitingKey {
            return String(localized: "\(keyboard.title(of: id)): press a key")
        }
        return String(localized: "Click a button, then press its key")
    }
}

/// The quiet bar under the footer while the keys show: the way into the edit mode, and out.
struct ShowBar: View {
    let keyboard: KeyboardController
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Text("Keys shown")
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Edit Keys") { keyboard.editAll() }
                .fontWeight(.semibold)
                .foregroundStyle(palette.fg)
            Button("Hide") { keyboard.iconClicked() }
        }
        .buttonStyle(.plain)
        .font(.manrope(10))
        .foregroundStyle(palette.label)
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) { Hairline() }
    }
}

extension KeyModeState {
    /// Keys are being set: the edit mode, or one button after "Set Key…".
    var setsKeys: Bool {
        switch mode {
        case .editing, .capturing: true
        case .normal, .showing: false
        }
    }

    /// The amber bar shows: keys are being set, or a change asks to replace the Custom profile.
    var showsEditBar: Bool { setsKeys || replacing != nil }
}

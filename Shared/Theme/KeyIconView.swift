import PaneKit
import SwiftUI

/// A key's fine-line icon: the `KeyIcon`'s path on its 24 grid, scaled to `size`, stroked (never
/// filled: some paths are open lines) in the button's own colour. The foreground style is what
/// turns amber on a key waiting for its keyboard key, and grey on an inactive one.
struct KeyIconView: View {
    let icon: KeyIcon
    let size: CGFloat

    init(_ icon: KeyIcon, size: CGFloat = Metrics.keyIcon) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        let scale = size / KeyIcon.grid
        Path(icon.path)
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .stroke(.foreground, style: StrokeStyle(lineWidth: KeyIcon.strokeWidth * scale,
                                                    lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension View {
    /// The key's name: VoiceOver's label and the hover help, in place of a word on the key.
    func keyName(_ name: LocalizedStringKey) -> some View {
        accessibilityLabel(Text(name)).help(Text(name)).accessibilityHint(Text(verbatim: ""))
    }
}

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Opens a link outside Pane: the browser, or the system's settings.
@MainActor func openExternal(_ url: URL) {
    #if os(macOS)
    NSWorkspace.shared.open(url)
    #else
    UIApplication.shared.open(url)
    #endif
}

extension Image {
    /// An image from PNG or other image data; nil when the data is not one.
    init?(data: Data) {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        self.init(nsImage: image)
        #else
        guard let image = UIImage(data: data) else { return nil }
        self.init(uiImage: image)
        #endif
    }
}

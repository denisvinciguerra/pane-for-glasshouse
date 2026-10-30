import Foundation
@testable import PaneKit

/// A language's own bundle, so the texts are asserted in that language whatever the Mac's is.
func lproj(_ code: String) -> Bundle {
    guard let path = PaneKitResources.bundle.path(forResource: code, ofType: "lproj"), let b = Bundle(path: path)
    else { fatalError("Missing \(code).lproj") }
    return b
}

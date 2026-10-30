import Foundation

enum Fixture {
    /// A name without extension loads `<name>.json`; with an extension it loads as-is.
    static func data(_ name: String) -> Data {
        let file = name.contains(".") ? name : name + ".json"
        guard let url = Bundle.module.url(forResource: file, withExtension: nil, subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url)
        else { fatalError("Missing fixture \(file)") }
        return data
    }
}

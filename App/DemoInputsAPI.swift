#if DEBUG
import Foundation
import PaneKit

/// For -PaneDemoInputs (screenshots): the TV's HDMI inputs named PC, Xbox, Shield and PS5 in every
/// JSON answer, wherever their own names show (the inputs, the current app, the HDMI ports).
struct DemoInputsAPI: GlasshouseAPI {
    let base: GlasshouseClient
    private let labels = Labels()

    private static let names = ["hdmi1": "PC", "hdmi2": "Xbox", "hdmi3": "Shield", "hdmi4": "PS5"]

    init(base: GlasshouseClient) { self.base = base }

    /// The TV's own name of each input, as the stats last gave them.
    private actor Labels {
        var renames: [String: String] = [:]
        func learn(_ inputs: [String: String]) {
            for (id, label) in inputs { if let name = DemoInputsAPI.names[id] { renames[label] = name } }
        }
    }

    func get<T: Decodable & Sendable>(_ path: String, as: T.Type) async throws(APIError) -> T {
        let data = try await base.getData(path)
        guard let object = try? JSONSerialization.jsonObject(with: data) else { throw .decoding("not JSON") }
        if path == "/api/stats", let inputs = (object as? [String: Any])?["inputs"] as? [String: String] {
            await labels.learn(inputs)
        }
        let renamed = Self.rename(object, await labels.renames)
        do {
            return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: renamed))
        } catch {
            throw .decoding(String(describing: error))
        }
    }

    func getText(_ path: String) async throws(APIError) -> String { try await base.getText(path) }
    func getData(_ path: String) async throws(APIError) -> Data { try await base.getData(path) }
    func send(_ command: Command) async throws(APIError) { try await base.send(command) }

    /// A string equal to an input's name becomes the demo name; a longer one that contains a
    /// name of the TV's own ("PS5 Console de jeu (HDMI4)") has it replaced, but not "HDMI 1".
    private static func rename(_ value: Any, _ renames: [String: String]) -> Any {
        switch value {
        case let s as String:
            if let exact = renames[s] { return exact }
            return renames.reduce(s) { text, pair in
                pair.key.range(of: #"^HDMI ?\d$"#, options: .regularExpression) == nil
                    ? text.replacingOccurrences(of: pair.key, with: pair.value) : text
            }
        case let array as [Any]: return array.map { rename($0, renames) }
        case let object as [String: Any]: return object.mapValues { rename($0, renames) }
        default: return value
        }
    }
}
#endif

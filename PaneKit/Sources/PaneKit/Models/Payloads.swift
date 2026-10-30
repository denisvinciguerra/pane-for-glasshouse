import Foundation

/// Decodes an array element by element, skipping the elements that fail to decode.
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    private struct Skip: Decodable {}

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                result.append(element)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
        elements = result
    }
}

public struct PicturePayload: Decodable, Sendable {
    public let available: Bool
    public let writable: Bool?
    public internal(set) var rows: [SettingRow]
    public let dimension: Dimension?
    public let inputs: [String: String]?

    public struct Dimension: Decodable, Sendable {
        public let pictureMode: String?
        public let dynamicRange: String?
        public let input: String?
    }

    private enum CodingKeys: String, CodingKey { case available, writable, rows, dimension, inputs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        available = try c.decode(Bool.self, forKey: .available)
        writable = try c.decodeIfPresent(Bool.self, forKey: .writable)
        rows = try c.decodeIfPresent(LossyArray<SettingRow>.self, forKey: .rows)?.elements ?? []
        dimension = try? c.decodeIfPresent(Dimension.self, forKey: .dimension)
        inputs = try? c.decodeIfPresent([String: String].self, forKey: .inputs)
    }
}

public struct GamePayload: Decodable, Sendable {
    public let available: Bool
    public internal(set) var rows: [SettingRow]?
    public let input: String?
    public let pictureMode: String?

    private enum CodingKeys: String, CodingKey { case available, rows, input, pictureMode }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        available = try c.decode(Bool.self, forKey: .available)
        rows = try c.decodeIfPresent(LossyArray<SettingRow>.self, forKey: .rows)?.elements
        input = try? c.decodeIfPresent(String.self, forKey: .input)
        pictureMode = try? c.decodeIfPresent(String.self, forKey: .pictureMode)
    }
}

public struct AudioPayload: Decodable, Sendable {
    public let writable: Bool?
    public internal(set) var lgSettings: [SettingRow]?
    public let receiver: Receiver?

    public struct Receiver: Decodable, Sendable {
        public let name: String?
        public let connected: Bool?
        public let link: String?
        public let port: Int?
    }

    private enum CodingKeys: String, CodingKey { case writable, lgSettings, receiver }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        writable = try? c.decodeIfPresent(Bool.self, forKey: .writable)
        lgSettings = try c.decodeIfPresent(LossyArray<SettingRow>.self, forKey: .lgSettings)?.elements
        receiver = try? c.decodeIfPresent(Receiver.self, forKey: .receiver)
    }
}

public struct LGSettingsPayload: Decodable, Sendable {
    public let rows: [SettingRow]

    private enum CodingKeys: String, CodingKey { case rows }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rows = try c.decodeIfPresent(LossyArray<SettingRow>.self, forKey: .rows)?.elements ?? []
    }
}

public struct HDMIPayload: Decodable, Sendable {
    public struct Input: Decodable, Sendable {
        public let id: String
        public let port: Int
        public let label: String
        public let active: Bool
        public let deviceSeen: Bool?
    }
    public let inputs: [Input]

    private enum CodingKeys: String, CodingKey { case inputs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputs = try c.decodeIfPresent(LossyArray<Input>.self, forKey: .inputs)?.elements ?? []
    }
}

/// A Glasshouse server version ("0.132.0"), ordered numerically.
public struct ServerVersion: Comparable, Sendable {
    private let parts: [Int]

    /// "0.132.0", "0.126" or "v0.126.1": one to three integers (digits only) separated by dots,
    /// padded with zeros. Surrounding spaces and a pre-release or build suffix ("-rc1", "+abc")
    /// are ignored. `nil` for anything else.
    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let core = trimmed.prefix { $0 != "-" && $0 != "+" }
        let body = core.hasPrefix("v") ? core.dropFirst() : core
        let numbers = body.split(separator: ".", omittingEmptySubsequences: false).map { part in
            part.allSatisfy(\.isASCII) && part.allSatisfy(\.isNumber) ? Int(part) : nil
        }
        guard (1...3).contains(numbers.count), numbers.allSatisfy({ $0 != nil }) else { return nil }
        parts = numbers.map { $0! } + Array(repeating: 0, count: 3 - numbers.count)
    }

    /// The first version that has the Picture tab (#1038).
    public static let pictureTab = ServerVersion("0.126.0")!

    public static func < (a: ServerVersion, b: ServerVersion) -> Bool { a.parts.lexicographicallyPrecedes(b.parts) }
}

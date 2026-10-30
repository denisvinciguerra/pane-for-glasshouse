import Foundation

public struct Source: Equatable, Sendable, Identifiable { public let id: String; public let label: String; public let isActive: Bool }

/// Live TV first, then the HDMI inputs in numeric order (then any other input by key), named as the TV names them.
public func sources(from stats: Stats) -> [Source] {
    let inputs = stats.inputs ?? [:]
    func number(_ key: String) -> Int? { key.hasPrefix("hdmi") ? Int(key.dropFirst(4)) : nil }
    let others = inputs.keys.filter { $0 != "livetv" }.sorted { a, b in
        switch (number(a), number(b)) {
        case let (x?, y?): x < y
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): a < b
        }
    }
    let live = Source(id: "livetv", label: String(localized: "TV", bundle: .module), isActive: stats.app == "livetv")
    return [live] + others.map { Source(id: $0, label: inputs[$0] ?? $0, isActive: stats.app == $0) }
}

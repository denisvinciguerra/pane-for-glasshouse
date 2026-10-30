import Foundation
import Observation

/// The icons of the apps the pinned actions launch, by app ID, shared by every TV, with the colour
/// of their edge. Each one is kept in `directory`, so a tile shows it with the TV off, and asked
/// of the TV again once per launch, for an app that changed its icon.
@MainActor @Observable public final class AppIconStore {
    private var icons: [String: Data]
    private var edges: [String: IconColor]

    @ObservationIgnored private let directory: URL?
    /// The apps a TV gave an icon for since launch, and those being asked for.
    @ObservationIgnored private var fetched: Set<String> = []
    @ObservationIgnored private var asking: Set<String> = []

    /// `directory`: where the icons are kept; `nil` keeps them in memory only.
    public init(directory: URL?) {
        self.directory = directory
        var icons: [String: Data] = [:], edges: [String: IconColor] = [:]
        if let directory, let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in files {
                guard let id = file.lastPathComponent.removingPercentEncoding,
                      let data = try? Data(contentsOf: file), !data.isEmpty else { continue }
                icons[id] = data
                edges[id] = IconColor(edgeOf: data)
            }
        }
        self.icons = icons
        self.edges = edges
    }

    public func icon(for appID: String) -> Data? { icons[appID] }

    /// The colour of the icon's edge; `nil` without an icon, or for an icon with a transparent edge.
    public func edge(for appID: String) -> IconColor? { edges[appID] }

    /// Asks `fetch` for each app not fetched since launch, one at a time, until the task is
    /// cancelled. An app without an answer keeps the icon it had, and is asked again on the next call.
    public func refresh(_ appIDs: [String], fetch: @Sendable (String) async -> Data?) async {
        for id in appIDs where !fetched.contains(id) && !asking.contains(id) {
            if Task.isCancelled { return }
            asking.insert(id)
            let data = await fetch(id)
            asking.remove(id)
            guard let data, !data.isEmpty else { continue }
            fetched.insert(id)
            if icons[id] != data {
                icons[id] = data
                edges[id] = IconColor(edgeOf: data)
                write(data, for: id)
            }
        }
    }

    /// One file per app, named by its ID with every character but letters, digits, "-" and "_"
    /// escaped, so no ID reaches outside `directory`.
    private func write(_ data: Data, for appID: String) {
        guard let directory,
              let name = appID.addingPercentEncoding(withAllowedCharacters: Self.fileNameCharacters) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    private static let fileNameCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
}

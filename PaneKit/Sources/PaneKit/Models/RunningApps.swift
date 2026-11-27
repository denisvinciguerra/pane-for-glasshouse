import Foundation

public struct AppsOverview: Decodable, Sendable {
    public let writable: Bool?
    /// Missing on servers that do not report apps in memory.
    public let running: [RunningApp]?
}

public struct RunningApp: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let mb: Double?
    public let foreground: Bool?
}

public struct RecentAppsPayload: Decodable, Sendable {
    public let ok: Bool
    public let error: String?
    public let apps: [RecentApp]?
}

public struct RecentApp: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
}

public struct AppActivity: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let onScreen: Bool
    public let recent: Bool
    public let running: RunningApp?
}

/// Keeps the TV's recent order, then separates running apps without a recent card.
public struct AppActivityList: Sendable {
    public let recents: [AppActivity]
    public let background: [AppActivity]

    public init(recents: [RecentApp], running: [RunningApp], foregroundID: String? = nil, transition: RecentApp? = nil) {
        var live: [String: RunningApp] = [:]
        for app in running where live[app.id] == nil { live[app.id] = app }
        var seen = Set<String>()
        var cards = recents
        if let transition, live[transition.id] != nil, !cards.contains(where: { $0.id == transition.id }) {
            cards.insert(transition, at: 0)
        }
        if let current = running.first(where: { $0.id == foregroundID }), !cards.contains(where: { $0.id == current.id }) {
            cards.insert(RecentApp(id: current.id, title: current.title), at: 0)
        }
        self.recents = cards.compactMap { app in
            guard seen.insert(app.id).inserted else { return nil }
            return AppActivity(id: app.id, title: app.title, onScreen: app.id == foregroundID, recent: true, running: live[app.id])
        }
        self.background = running.compactMap { app in
            guard seen.insert(app.id).inserted else { return nil }
            return AppActivity(id: app.id, title: app.title, onScreen: false, recent: false, running: app)
        }
    }
}

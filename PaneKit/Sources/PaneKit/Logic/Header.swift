import Foundation

public struct Header: Equatable, Sendable {
    public let model: String        // "OLED65G45LW" (suffix after the dot removed)
    public let state: PowerState
    public let nowShowing: String?  // appName, else displayTitle, else the TV's name for the current input
    public let signal: String?      // "3840×2160 @ 120 Hz"
    public let rangeBadge: String?  // "HDR10", "SDR"…

    public init(stats: Stats?) {
        model = stats?.device?.model?.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
        state = PowerState.from(stats)
        nowShowing = Self.nonEmpty(stats?.appName) ?? Self.nonEmpty(stats?.displayTitle)
            ?? stats?.app.flatMap { stats?.inputs?[$0] }.flatMap(Self.nonEmpty)
        signal = Self.nonEmpty(stats?.signal).map(Self.formatSignal)
        rangeBadge = Self.nonEmpty(stats?.signalFormat?.typeDisplay)
    }

    private static func nonEmpty(_ s: String?) -> String? { (s?.isEmpty ?? true) ? nil : s }

    /// "3840x2160 @ 60Hz" -> "3840×2160 @ 60 Hz"
    static func formatSignal(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"(\d)\s*[xX]\s*(\d)"#, with: "$1×$2", options: .regularExpression)
            .replacingOccurrences(of: #"(\d)\s*Hz"#, with: "$1 Hz", options: .regularExpression)
    }
}

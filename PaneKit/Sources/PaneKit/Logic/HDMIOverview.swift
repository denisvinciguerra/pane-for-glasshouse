import Foundation

public struct HDMIPort: Equatable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let isActive: Bool
    public let deviceSeen: Bool
    public let signal: String?      // active port only: "3840×2160 @ 60 Hz · FRL 32 Gbps · RGB 4:4:4 · HDCP 2.3"
    public let flags: [String]      // active port only: "ALLM", "VRR" when true
    public let isARC: Bool          // the port the receiver is on
}

/// The HDMI tab: the ports, the receiver on the eARC port, and the HDMI and device settings.
public struct HDMIOverview: Equatable, Sendable {
    public let ports: [HDMIPort]
    public let receiver: String?    // "AVR-X4500H · eARC"
    public internal(set) var settings: [SettingRow]

    public init(hdmi: HDMIPayload, stats: Stats?, audio: AudioPayload?, lgSettings: LGSettingsPayload?) {
        let rx = audio?.receiver
        let receiverName = (rx?.name?.isEmpty ?? true) || rx?.connected == false ? nil : rx?.name
        receiver = receiverName.map { name in
            [name, rx?.link].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        let arcPort = receiverName == nil ? nil : rx?.port

        // As the web does (renderHdmiPort), the diagnostics belong to the active input. The
        // diagnostics' own port number is 0-based and is not used to place them.
        ports = hdmi.inputs.map { input in
            HDMIPort(id: input.port,
                     name: input.label.isEmpty ? "HDMI \(input.port)" : input.label,
                     isActive: input.active,
                     deviceSeen: input.deviceSeen ?? false,
                     signal: input.active ? Self.signal(stats) : nil,
                     flags: input.active ? Self.flags(stats) : [],
                     isARC: arcPort == input.port)
        }

        let source = lgSettings?.rows ?? audio?.lgSettings ?? []
        var seen = Set<String>()
        settings = source.filter { row in
            guard row.section == "hdmi" || row.section == "devices" else { return false }
            if case .unsupported = row.kind { return false }
            return seen.insert(row.id).inserted
        }
    }

    private static func signal(_ stats: Stats?) -> String? {
        guard let stats else { return nil }
        var parts: [String] = []
        if let s = stats.signal, !s.isEmpty { parts.append(Header.formatSignal(s)) }
        let diag = stats.hdmiDiag
        for text in [diag?.phyMode, diag?.chroma] { if let text, !text.isEmpty { parts.append(text) } }
        if let hdcp = diag?.hdcp, !hdcp.isEmpty, hdcp != "None" {
            parts.append("HDCP " + hdcp.replacingOccurrences(of: #"^HDCP\s*"#, with: "", options: [.regularExpression, .caseInsensitive]))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func flags(_ stats: Stats?) -> [String] {
        var flags: [String] = []
        if stats?.hdmiDiag?.allm == true { flags.append("ALLM") }
        if stats?.hdmiDiag?.vrr == true { flags.append("VRR") }
        return flags
    }
}

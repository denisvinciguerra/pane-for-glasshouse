import Foundation

/// The Mac's ARP table, which knows the MAC of a host that answered it, token or not.
public enum ARPTable {
    private static let timeout: TimeInterval = 2

    /// The normalized MAC on the line "? (<host>) at <mac> on …" of `arp -n` for exactly `host`;
    /// nil when there is no such line or the entry is incomplete.
    static func parse(_ output: String, host: String) -> String? {
        let marker = "(\(host)) at "
        for line in output.split(whereSeparator: \.isNewline) {
            guard let range = line.range(of: marker) else { continue }
            let mac = line[range.upperBound...].prefix { !$0.isWhitespace }
            if let normalized = WakeOnLAN.normalized(mac: String(mac)) { return normalized }
        }
        return nil
    }

    /// The MAC the ARP table gives for `host` (`/usr/sbin/arp -n`, 2 s at most); nil on any failure.
    public static func mac(of host: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: run(host: host)) }
        }
    }

    /// Blocks its (non-cooperative) thread until `arp` ends or is terminated at the timeout.
    private static func run(host: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-n", host]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if process.isRunning { process.terminate() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parse(String(decoding: data, as: UTF8.self), host: host)
    }
}

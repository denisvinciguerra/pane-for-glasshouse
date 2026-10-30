import Darwin
import Foundation

public enum WakeOnLANError: Error, Equatable, Sendable {
    case invalidMAC
    case timedOut
}

public enum WakeOnLAN {
    /// The magic packet: 6 × 0xFF, then the MAC 16 times. `nil` when the MAC is not 6 groups of 1 or 2
    /// hex digits, all separated by the same ":" or "-".
    public static func packet(mac: String) -> Data? {
        guard let bytes = macBytes(mac) else { return nil }
        return Data(repeating: 0xFF, count: 6) + Data((0..<16).flatMap { _ in bytes })
    }

    /// The MAC as "aa:bb:cc:dd:ee:ff"; `nil` when `packet(mac:)` would refuse it.
    public static func normalized(mac: String) -> String? {
        macBytes(mac)?.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    private static func macBytes(_ mac: String) -> [UInt8]? {
        guard let separator = mac.first(where: { $0 == ":" || $0 == "-" }) else { return nil }
        let parts = mac.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count == 6 else { return nil }
        let bytes = parts.compactMap { part in
            (1...2).contains(part.count) && part.allSatisfy(\.isHexDigit) ? UInt8(part, radix: 16) : nil
        }
        return bytes.count == 6 ? bytes : nil
    }

    /// Broadcasts the packet over UDP port 9, to 255.255.255.255 and to the broadcast address of
    /// each active IPv4 interface. Throws on an invalid MAC, when no copy could be sent, or after
    /// `timeout` seconds.
    public static func send(mac: String) async throws { try await send(mac: mac, timeout: 4) }

    static func send(mac: String, timeout: TimeInterval) async throws {
        guard let data = packet(mac: mac) else { throw WakeOnLANError.invalidMAC }
        let queue = DispatchQueue(label: "fr.synlink.pane.wol")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = Gate(continuation)
            queue.async { gate.finish(broadcast(data, timeout: timeout)) }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { gate.finish(WakeOnLANError.timedOut) }
        }
    }

    /// `address | ~netmask`, both in network byte order.
    static func directedBroadcast(address: in_addr_t, netmask: in_addr_t) -> in_addr_t {
        address | ~netmask
    }

    /// Sends one copy to each target; `nil` when at least one left. Network.framework's
    /// NWConnection does not set SO_BROADCAST, hence a BSD socket.
    private static func broadcast(_ data: Data, timeout: TimeInterval) -> Error? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return posixError() }
        defer { close(fd) }
        var on: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            return posixError()
        }
        var limit = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        var failure: Error?
        var sent = false
        for target in targets() {
            var to = sockaddr_in()
            to.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            to.sin_family = sa_family_t(AF_INET)
            to.sin_port = in_port_t(9).bigEndian
            to.sin_addr.s_addr = target
            let count = data.withUnsafeBytes { bytes in
                withUnsafePointer(to: &to) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if count == data.count { sent = true } else { failure = posixError() }
        }
        return sent ? nil : failure
    }

    /// 255.255.255.255, then each up, non-loopback IPv4 interface's broadcast address, once each.
    private static func targets() -> [in_addr_t] {
        var out: [in_addr_t] = [INADDR_BROADCAST]
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return out }
        defer { freeifaddrs(list) }
        for ifa in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ifa.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
                  let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
                  let mask = ifa.pointee.ifa_netmask else { continue }
            let a = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let m = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let b = directedBroadcast(address: a, netmask: m)
            if !out.contains(b) { out.append(b) }
        }
        return out
    }

    private static func posixError() -> Error {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    /// Resumes the continuation once: with the send's outcome or the timeout, whichever comes first.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?

        init(_ continuation: CheckedContinuation<Void, Error>) {
            self.continuation = continuation
        }

        func finish(_ error: Error?) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            guard let c else { return }
            if let error { c.resume(throwing: error) } else { c.resume() }
        }
    }
}

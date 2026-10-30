import Darwin
import Foundation

public struct SSDPResult: Equatable, Sendable {
    public var hosts: [String]
    public var denied: Bool

    public init(hosts: [String], denied: Bool) {
        self.hosts = hosts
        self.denied = denied
    }
}

public enum SSDP {
    static let targets = ["urn:dial-multiscreen-org:service:dial:1", "urn:lge-com:service:webos-second-screen:1"]

    static func searchMessage(target: String) -> String {
        "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: \(target)\r\n\r\n"
    }

    /// True when a `SERVER:` header line (any case) mentions webOS.
    static func isWebOSReply(_ reply: String) -> Bool {
        reply.split(whereSeparator: \.isNewline).contains {
            $0.lowercased().hasPrefix("server:") && $0.lowercased().contains("webos")
        }
    }

    /// Sends both searches, listens `listen` seconds and returns the source address of each webOS
    /// reply, once each. `denied`: every send failed with EHOSTUNREACH (local network access is off).
    public static func search(listen: TimeInterval = 3) async -> SSDPResult {
        let queue = DispatchQueue(label: "fr.synlink.pane.ssdp")
        return await withCheckedContinuation { (continuation: CheckedContinuation<SSDPResult, Never>) in
            let gate = Gate(continuation)
            queue.async { gate.finish(run(listen: listen)) }
            DispatchQueue.global().asyncAfter(deadline: .now() + listen + 2) {
                gate.finish(SSDPResult(hosts: [], denied: false))
            }
        }
    }

    private static func run(listen: TimeInterval) -> SSDPResult {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return SSDPResult(hosts: [], denied: false) }
        defer { close(fd) }
        var slice = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &slice, socklen_t(MemoryLayout<timeval>.size))

        var to = sockaddr_in()
        to.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        to.sin_family = sa_family_t(AF_INET)
        to.sin_port = in_port_t(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &to.sin_addr)
        var sent = 0
        var unreachable = 0
        for target in targets {
            let data = Array(searchMessage(target: target).utf8)
            let count = withUnsafePointer(to: &to) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, data, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if count == data.count { sent += 1 } else if errno == EHOSTUNREACH { unreachable += 1 }
        }
        if sent == 0, unreachable == targets.count { return SSDPResult(hosts: [], denied: true) }

        var hosts: [String] = []
        var buffer = [UInt8](repeating: 0, count: 2048)
        let end = Date().addingTimeInterval(listen)
        while Date() < end {
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buffer, buffer.count, 0, $0, &length)
                }
            }
            guard count > 0 else { continue } // receive timeout: look at the clock again
            guard isWebOSReply(String(decoding: buffer[0..<count], as: UTF8.self)) else { continue }
            var name = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var address = from.sin_addr
            guard inet_ntop(AF_INET, &address, &name, socklen_t(name.count)) != nil else { continue }
            let host = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if !hosts.contains(host) { hosts.append(host) }
        }
        return SSDPResult(hosts: hosts, denied: false)
    }

    /// Resumes the continuation once: with the search's result or the safety timeout's.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<SSDPResult, Never>?

        init(_ continuation: CheckedContinuation<SSDPResult, Never>) {
            self.continuation = continuation
        }

        func finish(_ result: SSDPResult) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: result)
        }
    }
}

import Darwin
import Foundation

public enum Subnet {
    /// An IPv4 interface of the Mac, in host order.
    public struct Interface: Equatable, Sendable {
        public let address: UInt32
        public let netmask: UInt32

        public init(address: UInt32, netmask: UInt32) {
            self.address = address
            self.netmask = netmask
        }
    }

    /// The addresses of the subnet around `address`, in host order, without the network address, the
    /// broadcast address or `address` itself. A prefix shorter than 24 is narrowed to 24, a longer one
    /// than 30 to 30.
    static func hostsAround(_ address: UInt32, prefixLength: Int) -> [UInt32] {
        let prefix = min(max(prefixLength, 24), 30)
        let mask = UInt32.max << UInt32(32 - prefix)
        let network = address & mask
        let broadcast = network | ~mask
        return (network + 1..<broadcast).filter { $0 != address }
    }

    static func dotted(_ address: UInt32) -> String {
        [24, 16, 8, 0].map { String((address >> UInt32($0)) & 0xFF) }.joined(separator: ".")
    }

    /// Whether the sweep visits `address`: not in 169.254.0.0/16 (link-local, no router, no TV).
    static func isSwept(_ address: UInt32) -> Bool { address >> 16 != 0xA9FE }

    /// Whether `host` is an IPv4 address the sweep of one of `interfaces` visits. A host name, or an
    /// address of another network, is not.
    public static func isLocal(_ host: String, interfaces: [Interface]) -> Bool {
        var parsed = in_addr()
        guard inet_pton(AF_INET, host, &parsed) == 1 else { return false }
        let address = UInt32(bigEndian: parsed.s_addr)
        return interfaces.contains { interface in
            isSwept(interface.address)
                && hostsAround(interface.address, prefixLength: interface.netmask.nonzeroBitCount).contains(address)
        }
    }

    /// The up, non-loopback IPv4 interfaces with broadcast.
    public static func interfaces() -> [Interface] {
        var out: [Interface] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return out }
        defer { freeifaddrs(list) }
        for ifa in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ifa.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
                  let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
                  let mask = ifa.pointee.ifa_netmask else { continue }
            let a = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let m = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            out.append(Interface(address: a, netmask: m))
        }
        return out
    }

    /// For each of `interfaces()` that is swept: `hostsAround`, once each.
    public static func localHosts() -> [String] {
        var out: [String] = []
        var seen = Set<UInt32>()
        for interface in interfaces() where isSwept(interface.address) {
            for host in hostsAround(interface.address, prefixLength: interface.netmask.nonzeroBitCount)
            where seen.insert(host).inserted {
                out.append(dotted(host))
            }
        }
        return out
    }
}

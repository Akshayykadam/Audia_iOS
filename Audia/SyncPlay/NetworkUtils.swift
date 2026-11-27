//
//  NetworkUtils.swift
//  Audia
//

import Foundation
import Darwin

enum NetworkUtils {
    static func getLocalIpAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var fallbackIp: String?
        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                let flags = Int32(interface.ifa_flags)
                let isUp = (flags & IFF_UP) != 0
                let isLoopback = (flags & IFF_LOOPBACK) != 0
                if isUp && !isLoopback {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        socklen_t(0),
                        NI_NUMERICHOST
                    ) == 0 {
                        let ip = String(cString: hostname)
                        if name == "en0" {
                            return ip
                        } else if fallbackIp == nil && (name.hasPrefix("en") || name.hasPrefix("bridge")) {
                            fallbackIp = ip
                        }
                    }
                }
            }
            if let next = interface.ifa_next {
                ptr = next
            } else {
                break
            }
        }
        return fallbackIp
    }
}

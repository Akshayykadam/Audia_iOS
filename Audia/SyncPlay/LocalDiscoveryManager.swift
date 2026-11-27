//
//  LocalDiscoveryManager.swift
//  Audia
//

import Foundation
import Network
import Observation

@Observable
@MainActor
final class LocalDiscoveryManager: NSObject {
    static let serviceType = "_audiasync._tcp"

    private(set) var discoveredSessions: [DiscoveredSession] = []

    private var browser: NWBrowser?
    private var advertiser: NetService?
    private var resolveConnections: [String: NWConnection] = [:]

    // MARK: - Host Advertising (Bonjour / mDNS)

    func advertiseSession(roomCode: String, hostName: String, port: Int, ipAddress: String) {
        stopAdvertising()
        let service = NetService(domain: "local.", type: "\(Self.serviceType).", name: "Audia-\(roomCode)", port: Int32(port))
        let txtDict: [String: Data] = [
            "code": Data(roomCode.utf8),
            "host": Data(hostName.utf8),
            "ip": Data(ipAddress.utf8)
        ]
        service.setTXTRecord(NetService.data(fromTXTRecord: txtDict))
        service.publish()
        advertiser = service
    }

    func stopAdvertising() {
        advertiser?.stop()
        advertiser = nil
    }

    // MARK: - Guest Discovery

    func startDiscovery() {
        guard browser == nil else { return }
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let newBrowser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: params)

        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                self?.handleBrowseResults(results)
            }
        }

        newBrowser.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                Log.player.error("SyncPlay Bonjour browser failed: \(error.localizedDescription)")
            }
        }

        browser = newBrowser
        newBrowser.start(queue: .main)
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        resolveConnections.values.forEach { $0.cancel() }
        resolveConnections.removeAll()
        discoveredSessions.removeAll()
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        var activeKeys = Set<String>()
        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            activeKeys.insert(name)

            var codeFromTxt: String?
            var hostFromTxt: String?
            var ipFromTxt: String?

            if case .bonjour(let txtRecord) = result.metadata {
                let dict = txtRecord.dictionary
                codeFromTxt = dict["code"]
                hostFromTxt = dict["host"]
                ipFromTxt = dict["ip"]
            }

            if let ip = ipFromTxt, !ip.hasPrefix("127."), ip != "localhost",
               let code = codeFromTxt, !code.isEmpty {
                // We can still resolve port via NWConnection, or default 8088 and verify /info
                resolveEndpoint(result.endpoint, serviceName: name, fallbackCode: code, fallbackHost: hostFromTxt, fallbackIp: ip)
            } else {
                resolveEndpoint(result.endpoint, serviceName: name, fallbackCode: codeFromTxt, fallbackHost: hostFromTxt, fallbackIp: nil)
            }
        }

        discoveredSessions.removeAll { session in
            !activeKeys.contains("Audia-\(session.roomCode)")
        }
    }

    private func resolveEndpoint(
        _ endpoint: NWEndpoint,
        serviceName: String,
        fallbackCode: String?,
        fallbackHost: String?,
        fallbackIp: String?
    ) {
        if resolveConnections[serviceName] != nil { return }
        let conn = NWConnection(to: endpoint, using: .tcp)
        resolveConnections[serviceName] = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                let remoteEndpoint = conn.currentPath?.remoteEndpoint
                var resolvedIp = fallbackIp
                var resolvedPort = 8088

                if case .hostPort(let host, let port) = remoteEndpoint {
                    resolvedPort = Int(port.rawValue)
                    switch host {
                    case .ipv4(let addr):
                        resolvedIp = addr.debugDescription.components(separatedBy: "%").first
                    case .name(let hostname, _):
                        if resolvedIp == nil { resolvedIp = hostname }
                    default:
                        break
                    }
                }
                conn.cancel()
                Task { @MainActor [weak self] in
                    self?.resolveConnections.removeValue(forKey: serviceName)
                    guard let ip = resolvedIp, !ip.isEmpty else { return }
                    let roomCode = (fallbackCode?.isEmpty == false ? fallbackCode : nil)
                        ?? (serviceName.hasPrefix("Audia-") ? String(serviceName.dropFirst("Audia-".count)) : serviceName)
                    let hostName = fallbackHost ?? "Host"
                    await self?.fetchInfoAndStore(ip: ip, port: resolvedPort, fallbackCode: roomCode, fallbackHost: hostName)
                }
            } else if case .failed = state {
                conn.cancel()
                Task { @MainActor [weak self] in
                    self?.resolveConnections.removeValue(forKey: serviceName)
                }
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
    }

    private func fetchInfoAndStore(ip: String, port: Int, fallbackCode: String, fallbackHost: String) async {
        var finalCode = fallbackCode
        var finalHost = fallbackHost

        if let url = URL(string: "http://\(ip):\(port)/info") {
            var request = URLRequest(url: url, timeoutInterval: 2.0)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            if let (data, _) = try? await URLSession.shared.data(for: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let code = json["roomCode"] as? String, !code.isEmpty {
                    finalCode = code
                }
                if let host = json["hostName"] as? String, !host.isEmpty {
                    finalHost = host
                }
            }
        }

        let session = DiscoveredSession(
            roomCode: finalCode,
            hostName: finalHost,
            ipAddress: ip,
            port: port,
            discoveredAtMs: TimeSyncEngine.currentEpochMs()
        )
        if let idx = discoveredSessions.firstIndex(where: { $0.roomCode == session.roomCode }) {
            discoveredSessions[idx] = session
        } else {
            discoveredSessions.append(session)
        }
    }
}

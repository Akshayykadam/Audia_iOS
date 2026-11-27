//
//  LocalSyncPlayServer.swift
//  Audia
//

import CryptoKit
import Foundation
import Network

struct LocalAudioStream {
    let fileURL: URL
    let mimeType: String
}

final class LocalSyncPlayServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.akshayysk.Audia.LocalSyncPlayServer")
    private let roomManager = LocalRoomManager()
    private var listener: NWListener?
    private var connections: [String: LocalSocketConnection] = [:]

    private(set) var boundPort: Int = 0
    var audioStreamProvider: ((_ mediaId: String) -> LocalAudioStream?)?

    var isRunning: Bool {
        queue.sync { listener != nil }
    }

    func start(preferredPort: Int = 8088, completion: @escaping @Sendable (Int) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.listener != nil {
                self.roomManager.clearAll()
                let port = self.boundPort
                DispatchQueue.main.async { completion(port) }
                return
            }

            self.tryStart(port: UInt16(preferredPort), attemptsLeft: 10, completion: completion)
        }
    }

    private func tryStart(port: UInt16, attemptsLeft: Int, completion: @escaping @Sendable (Int) -> Void) {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            if let ipOptions = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ipOptions.version = .v4
            }
            let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
            let newListener = try NWListener(using: params, on: nwPort)

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    let actualPort = Int(newListener.port?.rawValue ?? port)
                    self.boundPort = actualPort
                    DispatchQueue.main.async { completion(actualPort) }
                case .failed:
                    newListener.cancel()
                    if self.listener === newListener {
                        self.listener = nil
                    }
                    if attemptsLeft > 0 {
                        self.tryStart(port: port + 1, attemptsLeft: attemptsLeft - 1, completion: completion)
                    } else {
                        DispatchQueue.main.async { completion(0) }
                    }
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] nwConn in
                self?.handleNewConnection(nwConn)
            }

            self.listener = newListener
            newListener.start(queue: queue)
        } catch {
            if attemptsLeft > 0 {
                tryStart(port: port + 1, attemptsLeft: attemptsLeft - 1, completion: completion)
            } else {
                DispatchQueue.main.async { completion(0) }
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            self.connections.values.forEach { $0.close() }
            self.connections.removeAll()
            self.roomManager.clearAll()
            self.boundPort = 0
        }
    }

    private func handleNewConnection(_ nwConn: NWConnection) {
        let connId = UUID().uuidString
        let conn = LocalSocketConnection(
            connectionId: connId,
            connection: nwConn,
            queue: queue,
            roomManager: roomManager,
            audioStreamProvider: { [weak self] mediaId in self?.audioStreamProvider?(mediaId) },
            onClose: { [weak self] in
                self?.connections.removeValue(forKey: connId)
            }
        )
        connections[connId] = conn
        conn.start()
    }
}

private final class LocalSocketConnection: LocalClientConnection, @unchecked Sendable {
    let connectionId: String
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let roomManager: LocalRoomManager
    private let audioStreamProvider: (String) -> LocalAudioStream?
    private let onClose: () -> Void

    private var buffer = Data()
    private var handshakeComplete = false
    private var isClosed = false
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        connectionId: String,
        connection: NWConnection,
        queue: DispatchQueue,
        roomManager: LocalRoomManager,
        audioStreamProvider: @escaping (String) -> LocalAudioStream?,
        onClose: @escaping () -> Void
    ) {
        self.connectionId = connectionId
        self.connection = connection
        self.queue = queue
        self.roomManager = roomManager
        self.audioStreamProvider = audioStreamProvider
        self.onClose = onClose
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.handleDisconnect()
            } else if case .cancelled = state {
                self?.handleDisconnect()
            }
        }
        connection.start(queue: queue)
        receiveNext()
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, !self.isClosed else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.processBuffer()
            }
            if isComplete || error != nil {
                self.handleDisconnect()
            } else {
                self.receiveNext()
            }
        }
    }

    private func processBuffer() {
        if !handshakeComplete {
            guard let headerEndRange = buffer.range(of: Data("\r\n\r\n".utf8)) else { return }
            let headerData = buffer.subdata(in: 0..<headerEndRange.lowerBound)
            buffer.removeSubrange(0..<headerEndRange.upperBound)

            guard let headerString = String(data: headerData, encoding: .utf8) else {
                close()
                return
            }
            let lines = headerString.components(separatedBy: "\r\n")
            guard let reqLine = lines.first else {
                close()
                return
            }
            let parts = reqLine.split(separator: " ")
            if parts.count >= 2 && parts[0].uppercased() == "GET" {
                let path = String(parts[1])
                if path == "/info" || path.hasPrefix("/info?") {
                    sendInfoResponse()
                    return
                }
                if path.hasPrefix("/audio/") {
                    let mediaId = String(path.dropFirst("/audio/".count).prefix(while: { $0 != "?" && $0 != "#" }))
                    sendAudioResponse(mediaId: mediaId, headers: lines)
                    return
                }
            }

            guard let keyLine = lines.first(where: { $0.lowercased().hasPrefix("sec-websocket-key:") }) else {
                close()
                return
            }
            let key = keyLine.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? ""
            let acceptKey = computeWebSocketAccept(key: key)
            let response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(acceptKey)\r\n\r\n"
            sendRaw(Data(response.utf8))
            handshakeComplete = true
        }

        while handshakeComplete && !isClosed {
            guard buffer.count >= 2 else { return }
            let b0 = buffer[0]
            let b1 = buffer[1]
            let opcode = b0 & 0x0F
            let isMasked = (b1 & 0x80) != 0
            var payloadLen = UInt64(b1 & 0x7F)
            var offset = 2

            if payloadLen == 126 {
                guard buffer.count >= offset + 2 else { return }
                payloadLen = (UInt64(buffer[offset]) << 8) | UInt64(buffer[offset + 1])
                offset += 2
            } else if payloadLen == 127 {
                guard buffer.count >= offset + 8 else { return }
                var len: UInt64 = 0
                for i in 0..<8 {
                    len = (len << 8) | UInt64(buffer[offset + i])
                }
                payloadLen = len
                offset += 8
            }

            let maskLen = isMasked ? 4 : 0
            let totalLen = offset + maskLen + Int(payloadLen)
            guard buffer.count >= totalLen else { return }

            var payload = buffer.subdata(in: (offset + maskLen)..<totalLen)
            if isMasked {
                let mask = Array(buffer[offset..<(offset + 4)])
                for i in 0..<payload.count {
                    payload[i] ^= mask[i % 4]
                }
            }
            buffer.removeSubrange(0..<totalLen)

            switch opcode {
            case 0x01:
                if let msg = try? decoder.decode(ClientSyncMessage.self, from: payload) {
                    roomManager.handleClientMessage(conn: self, message: msg)
                }
            case 0x08:
                handleDisconnect()
                return
            case 0x09:
                sendFrame(opcode: 0x0A, payload: payload)
            default:
                break
            }
        }
    }

    private func sendInfoResponse() {
        let body: String
        if let info = roomManager.activeRoomInfo {
            let escapedHost = info.hostName.replacingOccurrences(of: "\"", with: "\\\"")
            body = "{\"roomCode\":\"\(info.code)\",\"hostName\":\"\(escapedHost)\"}"
        } else {
            body = "{\"status\":\"idle\"}"
        }
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        var full = Data(header.utf8)
        full.append(bodyData)
        sendRaw(full, closeAfter: true)
    }

    private func sendAudioResponse(mediaId: String, headers: [String]) {
        guard let stream = audioStreamProvider(mediaId),
              let handle = try? FileHandle(forReadingFrom: stream.fileURL),
              let attrs = try? FileManager.default.attributesOfItem(atPath: stream.fileURL.path),
              let totalSize = attrs[.size] as? Int64, totalSize > 0 else {
            let notFound = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            sendRaw(Data(notFound.utf8), closeAfter: true)
            return
        }
        defer { try? handle.close() }

        var start: Int64 = 0
        var end: Int64 = totalSize - 1
        var isRange = false

        if let rangeLine = headers.first(where: { $0.lowercased().hasPrefix("range:") }) {
            let val = rangeLine.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? ""
            if val.hasPrefix("bytes=") {
                isRange = true
                let parts = val.dropFirst("bytes=".count).split(separator: "-", omittingEmptySubsequences: false)
                if let s = parts.first, let parsedStart = Int64(s) {
                    start = parsedStart
                }
                if parts.count > 1, let parsedEnd = Int64(parts[1]), parsedEnd < totalSize {
                    end = parsedEnd
                }
            }
        }

        let contentLength = max(0, end - start + 1)
        let status = isRange ? "206 Partial Content" : "200 OK"
        var header = "HTTP/1.1 \(status)\r\nContent-Type: \(stream.mimeType)\r\nAccept-Ranges: bytes\r\nContent-Length: \(contentLength)\r\n"
        if isRange {
            header += "Content-Range: bytes \(start)-\(end)/\(totalSize)\r\n"
        }
        header += "Connection: close\r\n\r\n"
        sendRaw(Data(header.utf8))

        try? handle.seek(toOffset: UInt64(start))
        var remaining = contentLength
        while remaining > 0 {
            let chunkSize = Int(min(remaining, 32768))
            guard let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            sendRaw(chunk)
            remaining -= Int64(chunk.count)
        }
        close()
    }

    @discardableResult
    func send(_ message: ServerSyncMessage) -> Bool {
        guard !isClosed, handshakeComplete,
              let data = try? encoder.encode(message) else { return false }
        queue.async { [weak self] in
            self?.sendFrame(opcode: 0x01, payload: data)
        }
        return true
    }

    private func sendFrame(opcode: UInt8, payload: Data) {
        guard !isClosed else { return }
        var frame = Data()
        frame.append(0x80 | opcode)
        let len = payload.count
        if len <= 125 {
            frame.append(UInt8(len))
        } else if len <= 65535 {
            frame.append(126)
            frame.append(UInt8((len >> 8) & 0xFF))
            frame.append(UInt8(len & 0xFF))
        } else {
            frame.append(127)
            let len64 = UInt64(len)
            for i in (0..<8).reversed() {
                frame.append(UInt8((len64 >> (i * 8)) & 0xFF))
            }
        }
        frame.append(payload)
        sendRaw(frame)
    }

    private func sendRaw(_ data: Data, closeAfter: Bool = false) {
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            if closeAfter {
                self?.close()
            }
        })
    }

    private func computeWebSocketAccept(key: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(data: Data((key + magic).utf8))
        return Data(digest).base64EncodedString()
    }

    private func handleDisconnect() {
        guard !isClosed else { return }
        roomManager.handleDisconnect(conn: self)
        close()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        connection.cancel()
        onClose()
    }
}

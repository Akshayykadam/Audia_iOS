//
//  SyncPlayWebSocketClient.swift
//  Audia
//

import Foundation
import Observation

enum SyncConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(reason: String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

@Observable
@MainActor
final class SyncPlayWebSocketClient: NSObject {
    static let defaultServerUrl = "wss://audia-syncplay.onrender.com"

    private(set) var connectionState: SyncConnectionState = .disconnected
    var onMessage: ((ServerSyncMessage) -> Void)?
    var onConnectionStateChanged: ((SyncConnectionState) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var currentUrl: String?
    private var reconnectTask: Task<Void, Never>?
    private var timePingTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var isIntentionallyClosed = false
    private var reconnectAttempts = 0

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    override init() {
        super.init()
    }

    func connect(url: String) {
        isIntentionallyClosed = false
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUrl: String
        if trimmed.lowercased().hasPrefix("https://") {
            normalizedUrl = "wss://" + trimmed.dropFirst("https://".count)
        } else if trimmed.lowercased().hasPrefix("http://") {
            normalizedUrl = "ws://" + trimmed.dropFirst("http://".count)
        } else if !trimmed.lowercased().hasPrefix("ws://") && !trimmed.lowercased().hasPrefix("wss://") {
            normalizedUrl = "wss://\(trimmed)"
        } else {
            normalizedUrl = trimmed
        }

        currentUrl = normalizedUrl
        reconnectAttempts = 0
        reconnectTask?.cancel()
        timePingTask?.cancel()
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        updateState(.connecting)
        openSocket(urlString: normalizedUrl)
    }

    func resetConnectionState() {
        if case .failed = connectionState {
            updateState(.disconnected)
        }
    }

    func failConnection(reason: String) {
        isIntentionallyClosed = true
        reconnectTask?.cancel()
        timePingTask?.cancel()
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: String(reason.prefix(50)).data(using: .utf8))
        webSocketTask = nil
        updateState(.failed(reason: reason))
    }

    func disconnect() {
        isIntentionallyClosed = true
        reconnectTask?.cancel()
        timePingTask?.cancel()
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: "User disconnected".data(using: .utf8))
        webSocketTask = nil
        updateState(.disconnected)
    }

    @discardableResult
    func send(_ message: ClientSyncMessage) -> Bool {
        guard let task = webSocketTask else { return false }
        do {
            let data = try encoder.encode(message)
            guard let text = String(data: data, encoding: .utf8) else { return false }
            task.send(.string(text)) { error in
                if let error {
                    Log.player.error("SyncPlay: WebSocket send error: \(error.localizedDescription)")
                }
            }
            return true
        } catch {
            Log.player.error("SyncPlay: Failed to encode message: \(error.localizedDescription)")
            return false
        }
    }

    func triggerImmediateReconnect() {
        guard let url = currentUrl, !isIntentionallyClosed, !connectionState.isConnected else { return }
        reconnectTask?.cancel()
        reconnectAttempts = 0
        updateState(.reconnecting(attempt: 1))
        openSocket(urlString: url)
    }

    func triggerPingBurst() {
        Task { @MainActor [weak self] in
            for _ in 0..<5 {
                guard let self, self.connectionState.isConnected else { return }
                self.send(.timePing(clientTimeMs: TimeSyncEngine.currentEpochMs()))
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    private func openSocket(urlString: String) {
        guard let url = URL(string: urlString) else {
            updateState(.failed(reason: "Invalid server URL"))
            return
        }

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        urlSession?.invalidateAndCancel()
        urlSession = session

        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        startReceiveLoop(for: task)
    }

    private func startReceiveLoop(for task: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    guard let self else { return }
                    switch message {
                    case .string(let text):
                        if let data = text.data(using: .utf8),
                           let decoded = try? self.decoder.decode(ServerSyncMessage.self, from: data) {
                            await MainActor.run {
                                self.onMessage?(decoded)
                            }
                        }
                    case .data(let data):
                        if let decoded = try? self.decoder.decode(ServerSyncMessage.self, from: data) {
                            await MainActor.run {
                                self.onMessage?(decoded)
                            }
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    guard let self else { return }
                    await MainActor.run {
                        guard self.webSocketTask === task else { return }
                        self.handleSocketClosedOrFailed(error: error)
                    }
                    break
                }
            }
        }
    }

    private func handleSocketClosedOrFailed(error: Error?) {
        timePingTask?.cancel()
        receiveTask?.cancel()
        if isIntentionallyClosed {
            if case .failed = connectionState {
                return
            }
            updateState(.disconnected)
        } else {
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard let url = currentUrl else { return }
        if reconnectAttempts >= 15 {
            updateState(.failed(reason: "Connection lost. Session ended or timed out."))
            return
        }
        reconnectAttempts += 1
        let shift = min(reconnectAttempts - 1, 4)
        let baseBackoffMs = min(6000, 500 * (1 << shift))
        let jitterMs = Int.random(in: -200...200)
        let backoffMs = max(400, baseBackoffMs + jitterMs)

        updateState(.reconnecting(attempt: reconnectAttempts))
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(backoffMs))
            guard let self, !Task.isCancelled, !self.isIntentionallyClosed else { return }
            self.openSocket(urlString: url)
        }
    }

    private func startTimePingLoop() {
        timePingTask?.cancel()
        timePingTask = Task { @MainActor [weak self] in
            for _ in 0..<5 {
                guard let self, !Task.isCancelled else { return }
                self.send(.timePing(clientTimeMs: TimeSyncEngine.currentEpochMs()))
                try? await Task.sleep(for: .milliseconds(80))
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(2500))
                guard let self, !Task.isCancelled else { return }
                self.send(.timePing(clientTimeMs: TimeSyncEngine.currentEpochMs()))
            }
        }
    }

    private func updateState(_ newState: SyncConnectionState) {
        connectionState = newState
        onConnectionStateChanged?(newState)
    }
}

extension SyncPlayWebSocketClient: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.webSocketTask === webSocketTask else { return }
            self.reconnectAttempts = 0
            self.updateState(.connected)
            self.startTimePingLoop()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.webSocketTask === webSocketTask else { return }
            self.handleSocketClosedOrFailed(error: nil)
        }
    }
}

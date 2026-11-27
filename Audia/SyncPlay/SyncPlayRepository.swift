//
//  SyncPlayRepository.swift
//  Audia
//

import Foundation
import Observation

enum SyncEvent: Sendable {
    case playbackCommandReceived(command: String, positionMs: Int64?, scheduledAtMs: Int64?, executedBy: String)
    case sessionTerminated(reason: String, wasHost: Bool)
    case errorOccurred(code: String, message: String)
}

@Observable
@MainActor
final class SyncPlayRepository {
    let timeSyncEngine: TimeSyncEngine
    private let client: SyncPlayWebSocketClient

    private(set) var currentSession: SyncRoomSnapshot?
    private(set) var myParticipantId: String?
    var connectionState: SyncConnectionState { client.connectionState }

    var onEvent: ((SyncEvent) -> Void)?
    var onSessionChanged: ((SyncRoomSnapshot?) -> Void)?
    var onConnectionStateChanged: ((SyncConnectionState) -> Void)?

    private var pendingJoinAction: (() -> Void)?
    private var sessionToken: String?
    private var wasHostSession = false
    private var userInitiatedEnd = false

    init(
        timeSyncEngine: TimeSyncEngine? = nil,
        client: SyncPlayWebSocketClient? = nil
    ) {
        let resolvedEngine = timeSyncEngine ?? TimeSyncEngine()
        let resolvedClient = client ?? SyncPlayWebSocketClient()
        self.timeSyncEngine = resolvedEngine
        self.client = resolvedClient

        resolvedClient.onMessage = { [weak self] msg in
            self?.handleServerMessage(msg)
        }
        resolvedClient.onConnectionStateChanged = { [weak self] state in
            self?.handleConnectionStateChange(state)
        }
    }

    func triggerPingBurst() {
        client.triggerPingBurst()
    }

    func triggerImmediateReconnect() {
        client.triggerImmediateReconnect()
    }

    func resetConnectionState() {
        client.resetConnectionState()
    }

    func failLocalStart(reason: String) {
        client.failConnection(reason: reason)
    }

    func isHost() -> Bool {
        if let session = currentSession, let myId = myParticipantId {
            let currentHost = session.hostId == myId
            if currentHost { wasHostSession = true }
            return currentHost
        }
        return wasHostSession
    }

    func createRoom(
        serverUrl: String,
        hostName: String,
        settings: SyncRoomSettings = SyncRoomSettings()
    ) {
        disconnectSession()
        wasHostSession = true
        userInitiatedEnd = false
        pendingJoinAction = { [weak self] in
            self?.client.send(.createRoom(hostName: hostName, settings: settings))
        }
        client.connect(url: serverUrl)
    }

    func joinRoom(
        serverUrl: String,
        roomCode: String,
        participantName: String
    ) {
        disconnectSession()
        wasHostSession = false
        userInitiatedEnd = false
        pendingJoinAction = { [weak self] in
            self?.client.send(.joinRoom(roomCode: roomCode, participantName: participantName))
        }
        client.connect(url: serverUrl)
    }

    func leaveRoom() {
        userInitiatedEnd = true
        client.send(.leaveRoom)
        disconnectSession()
    }

    func endSession() {
        userInitiatedEnd = true
        wasHostSession = true
        if isHost() {
            client.send(.endSession)
        }
        disconnectSession()
    }

    func broadcastSyncState(
        currentTrack: SyncTrack?,
        isPlaying: Bool,
        positionMs: Int64,
        speed: Float = 1.0
    ) {
        client.send(.syncState(currentTrack: currentTrack, isPlaying: isPlaying, positionMs: positionMs, speed: speed))
    }

    func broadcastPlaybackCommand(
        command: String,
        positionMs: Int64? = nil,
        scheduledAtMs: Int64? = nil
    ) {
        client.send(.playbackCommand(command: command, positionMs: positionMs, scheduledAtMs: scheduledAtMs))
    }

    func broadcastQueue(_ queue: [SyncTrack]) {
        client.send(.queueUpdate(queue: queue))
    }

    func updateSettings(_ settings: SyncRoomSettings) {
        client.send(.settingsUpdate(settings: settings))
    }

    func kickParticipant(_ participantId: String) {
        client.send(.kickParticipant(participantId: participantId))
    }

    func reportSync(isSynced: Bool, latencyMs: Int64? = nil) {
        client.send(.reportSync(isSynced: isSynced, latencyMs: latencyMs))
    }

    private func disconnectSession() {
        pendingJoinAction = nil
        sessionToken = nil
        wasHostSession = false
        currentSession = nil
        myParticipantId = nil
        timeSyncEngine.reset()
        client.disconnect()
        onSessionChanged?(nil)
    }

    private func handleConnectionStateChange(_ state: SyncConnectionState) {
        onConnectionStateChanged?(state)
        switch state {
        case .connected:
            client.triggerPingBurst()
            if let action = pendingJoinAction {
                action()
                pendingJoinAction = nil
            } else if let active = currentSession, let myId = myParticipantId {
                if let token = sessionToken {
                    client.send(.reconnect(roomCode: active.code, participantId: myId, sessionToken: token))
                } else if let myName = active.participants.first(where: { $0.id == myId })?.name {
                    client.send(.joinRoom(roomCode: active.code, participantName: myName))
                }
            }
        case .failed(let reason):
            if currentSession != nil {
                onEvent?(.errorOccurred(code: "CONNECTION_LOST", message: reason))
                let isHostUser = isHost() || wasHostSession || userInitiatedEnd
                if !isHostUser {
                    onEvent?(.sessionTerminated(reason: "Connection to host was lost.", wasHost: false))
                    disconnectSession()
                }
            }
        default:
            break
        }
    }

    private func handleServerMessage(_ msg: ServerSyncMessage) {
        switch msg {
        case .timePong(let clientTimeMs, let serverReceiveTimeMs, let serverSendTimeMs):
            timeSyncEngine.onTimePongReceived(
                clientTimeMs: clientTimeMs,
                serverReceiveTimeMs: serverReceiveTimeMs,
                serverSendTimeMs: serverSendTimeMs
            )

        case .roomCreated(_, let participantId, let token, let room):
            wasHostSession = true
            userInitiatedEnd = false
            myParticipantId = participantId
            sessionToken = token
            currentSession = room
            onSessionChanged?(room)

        case .roomJoined(_, let participantId, let token, let room):
            wasHostSession = (room.hostId == participantId)
            userInitiatedEnd = false
            myParticipantId = participantId
            sessionToken = token
            currentSession = room
            onSessionChanged?(room)

        case .reconnected(_, let participantId, _, let room):
            wasHostSession = (room.hostId == participantId)
            userInitiatedEnd = false
            myParticipantId = participantId
            currentSession = room
            onSessionChanged?(room)

        case .participantJoined(let participant):
            guard var current = currentSession else { return }
            current.participants = current.participants.filter { $0.id != participant.id } + [participant]
            currentSession = current
            onSessionChanged?(current)

        case .participantOffline(let participantId):
            guard var current = currentSession else { return }
            current.participants = current.participants.map {
                var p = $0
                if p.id == participantId { p.isOffline = true }
                return p
            }
            currentSession = current
            onSessionChanged?(current)

        case .participantLeft(let participantId, _, let newHostId):
            guard var current = currentSession else { return }
            let resolvedHostId = newHostId ?? current.hostId
            if resolvedHostId == myParticipantId && myParticipantId != nil {
                wasHostSession = true
            }
            current.hostId = resolvedHostId
            current.participants = current.participants
                .filter { $0.id != participantId }
                .map {
                    var p = $0
                    if p.id == resolvedHostId { p.isHost = true }
                    return p
                }
            currentSession = current
            onSessionChanged?(current)

        case .participantKicked(let reason):
            onEvent?(.sessionTerminated(reason: reason, wasHost: false))
            disconnectSession()

        case .participantSyncUpdate(let participantId, let isSynced, let latencyMs):
            guard var current = currentSession else { return }
            current.participants = current.participants.map {
                var p = $0
                if p.id == participantId {
                    p.isSynced = isSynced
                    p.latencyMs = latencyMs ?? p.latencyMs
                }
                return p
            }
            currentSession = current
            onSessionChanged?(current)

        case .syncState(let currentTrack, let isPlaying, let positionMs, let serverTimestampMs, let speed):
            guard var current = currentSession else { return }
            current.playbackState = SyncPlaybackState(
                currentTrack: currentTrack,
                isPlaying: isPlaying,
                positionMs: positionMs,
                speed: speed,
                serverTimestampMs: serverTimestampMs
            )
            currentSession = current
            onSessionChanged?(current)

        case .playbackCommand(let command, let positionMs, let scheduledAtMs, let executedBy):
            onEvent?(.playbackCommandReceived(command: command, positionMs: positionMs, scheduledAtMs: scheduledAtMs, executedBy: executedBy))

        case .queueUpdate(let queue, _):
            guard var current = currentSession else { return }
            current.queue = queue
            currentSession = current
            onSessionChanged?(current)

        case .settingsUpdated(let settings):
            guard var current = currentSession else { return }
            current.settings = settings
            currentSession = current
            onSessionChanged?(current)

        case .sessionEnded(let reason):
            let wasHost = isHost() || wasHostSession
            onEvent?(.sessionTerminated(reason: reason, wasHost: wasHost))
            disconnectSession()

        case .error(let code, let message):
            onEvent?(.errorOccurred(code: code, message: message))
            if currentSession == nil {
                pendingJoinAction = nil
                client.failConnection(reason: message)
            }
        }
    }
}

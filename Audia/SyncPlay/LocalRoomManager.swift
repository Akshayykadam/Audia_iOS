//
//  LocalRoomManager.swift
//  Audia
//

import Foundation

protocol LocalClientConnection: AnyObject, Sendable {
    var connectionId: String { get }
    @discardableResult
    func send(_ message: ServerSyncMessage) -> Bool
    func close()
}

final class LocalParticipantRecord {
    var participant: SyncParticipant
    weak var connection: (any LocalClientConnection)?
    let sessionToken: String
    var disconnectWorkItem: DispatchWorkItem?

    init(participant: SyncParticipant, connection: (any LocalClientConnection)?, sessionToken: String) {
        self.participant = participant
        self.connection = connection
        self.sessionToken = sessionToken
    }
}

final class LocalRoom {
    let code: String
    var hostId: String
    var settings: SyncRoomSettings
    var playbackState: SyncPlaybackState
    var queue: [SyncTrack]
    var participants: [String: LocalParticipantRecord] = [:]
    let createdAt: Int64

    init(
        code: String,
        hostId: String,
        settings: SyncRoomSettings = SyncRoomSettings(),
        playbackState: SyncPlaybackState = SyncPlaybackState(),
        queue: [SyncTrack] = []
    ) {
        self.code = code
        self.hostId = hostId
        self.settings = settings
        self.playbackState = playbackState
        self.queue = queue
        self.createdAt = TimeSyncEngine.currentEpochMs()
    }

    func toSnapshot() -> SyncRoomSnapshot {
        SyncRoomSnapshot(
            code: code,
            hostId: hostId,
            settings: settings,
            playbackState: playbackState,
            queue: queue,
            participants: participants.values.map(\.participant)
        )
    }

    func broadcast(_ message: ServerSyncMessage, excludeConnectionId: String? = nil) {
        for record in participants.values {
            if let conn = record.connection, conn.connectionId != excludeConnectionId {
                conn.send(message)
            }
        }
    }
}

final class LocalRoomManager: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.akshayysk.Audia.LocalRoomManager")
    private var rooms: [String: LocalRoom] = [:]
    private var connectionToRoomMap: [String: (roomCode: String, participantId: String)] = [:]
    private let codeChars = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")

    var activeRoomInfo: (code: String, hostName: String)? {
        queue.sync {
            guard let room = rooms.values.first else { return nil }
            let hostName = room.participants[room.hostId]?.participant.name ?? "Host"
            return (room.code, hostName)
        }
    }

    private func generateRoomCodeLocked() -> String {
        for _ in 0..<100 {
            let code = String((0..<6).map { _ in codeChars.randomElement()! })
            if rooms[code] == nil {
                return code
            }
        }
        return "AU" + String(TimeSyncEngine.currentEpochMs() % 10000)
    }

    func handleClientMessage(conn: any LocalClientConnection, message: ClientSyncMessage) {
        queue.async { [weak self] in
            self?.handleClientMessageLocked(conn: conn, message: message)
        }
    }

    private func handleClientMessageLocked(conn: any LocalClientConnection, message: ClientSyncMessage) {
        let receiveTime = TimeSyncEngine.currentEpochMs()

        switch message {
        case .timePing(let clientTimeMs):
            let sendTime = TimeSyncEngine.currentEpochMs()
            conn.send(.timePong(
                clientTimeMs: clientTimeMs,
                serverReceiveTimeMs: receiveTime,
                serverSendTimeMs: sendTime
            ))

        case .createRoom(let hostName, let settings):
            clearAllLocked()
            let code = generateRoomCodeLocked()
            let participantId = "p_" + String(UUID().uuidString.prefix(8))
            let sessionToken = UUID().uuidString
            let now = TimeSyncEngine.currentEpochMs()

            let trimmedName = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
            let hostParticipant = SyncParticipant(
                id: participantId,
                name: trimmedName.isEmpty ? "Host" : trimmedName,
                isHost: true,
                isSynced: true,
                joinedAt: now,
                latencyMs: 0
            )

            let room = LocalRoom(
                code: code,
                hostId: participantId,
                settings: settings ?? SyncRoomSettings(),
                playbackState: SyncPlaybackState(serverTimestampMs: now)
            )
            room.participants[participantId] = LocalParticipantRecord(
                participant: hostParticipant,
                connection: conn,
                sessionToken: sessionToken
            )
            rooms[code] = room
            connectionToRoomMap[conn.connectionId] = (code, participantId)

            conn.send(.roomCreated(
                roomCode: code,
                participantId: participantId,
                sessionToken: sessionToken,
                room: room.toSnapshot()
            ))

        case .joinRoom(let roomCode, let participantName):
            leaveCurrentRoomLocked(conn: conn)
            let code = roomCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard let room = rooms[code] else {
                conn.send(.error(code: "ROOM_NOT_FOUND", message: "Local session \(code) does not exist."))
                return
            }
            if room.participants.count >= room.settings.maxParticipants {
                conn.send(.error(code: "ROOM_FULL", message: "Session has reached max participant capacity."))
                return
            }

            let participantId = "p_" + String(UUID().uuidString.prefix(8))
            let sessionToken = UUID().uuidString
            let trimmedName = participantName.trimmingCharacters(in: .whitespacesAndNewlines)
            let participant = SyncParticipant(
                id: participantId,
                name: trimmedName.isEmpty ? "Guest" : trimmedName,
                isHost: false,
                isSynced: true,
                joinedAt: TimeSyncEngine.currentEpochMs(),
                latencyMs: 0
            )

            room.participants[participantId] = LocalParticipantRecord(
                participant: participant,
                connection: conn,
                sessionToken: sessionToken
            )
            connectionToRoomMap[conn.connectionId] = (code, participantId)

            conn.send(.roomJoined(
                roomCode: code,
                participantId: participantId,
                sessionToken: sessionToken,
                room: room.toSnapshot()
            ))
            room.broadcast(.participantJoined(participant: participant), excludeConnectionId: conn.connectionId)

        case .reconnect(let roomCode, let participantId, let sessionToken):
            let code = roomCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard let room = rooms[code] else {
                conn.send(.error(code: "ROOM_NOT_FOUND", message: "Session \(code) does not exist."))
                return
            }
            guard let record = room.participants[participantId], record.sessionToken == sessionToken else {
                conn.send(.error(code: "SESSION_INVALID", message: "Invalid or expired session token."))
                return
            }

            record.disconnectWorkItem?.cancel()
            record.disconnectWorkItem = nil
            record.connection = conn
            record.participant.isOffline = false
            connectionToRoomMap[conn.connectionId] = (code, participantId)

            conn.send(.reconnected(
                roomCode: code,
                participantId: participantId,
                sessionToken: sessionToken,
                room: room.toSnapshot()
            ))
            room.broadcast(.participantJoined(participant: record.participant), excludeConnectionId: conn.connectionId)

        case .syncState(let currentTrack, let isPlaying, let positionMs, let speed):
            guard let (room, participantId) = getRoomAndParticipantLocked(conn: conn),
                  room.hostId == participantId else { return }
            let now = TimeSyncEngine.currentEpochMs()
            room.playbackState = SyncPlaybackState(
                currentTrack: currentTrack,
                isPlaying: isPlaying,
                positionMs: positionMs,
                speed: speed,
                serverTimestampMs: now
            )
            room.broadcast(
                .syncState(
                    currentTrack: currentTrack,
                    isPlaying: isPlaying,
                    positionMs: positionMs,
                    serverTimestampMs: now,
                    speed: speed
                ),
                excludeConnectionId: conn.connectionId
            )

        case .playbackCommand(let command, let positionMs, let scheduledAtMs):
            guard let (room, participantId) = getRoomAndParticipantLocked(conn: conn) else { return }
            let isHost = room.hostId == participantId
            guard isHost || room.settings.guestControlAllowed else { return }
            let pName = room.participants[participantId]?.participant.name ?? ""
            let now = TimeSyncEngine.currentEpochMs()
            switch command {
            case "PLAY":
                room.playbackState.isPlaying = true
                room.playbackState.positionMs = positionMs ?? room.playbackState.positionMs
                room.playbackState.serverTimestampMs = now
            case "PAUSE":
                room.playbackState.isPlaying = false
                room.playbackState.positionMs = positionMs ?? room.playbackState.positionMs
                room.playbackState.serverTimestampMs = now
            case "SEEK":
                if let positionMs {
                    room.playbackState.positionMs = positionMs
                    room.playbackState.serverTimestampMs = now
                }
            default:
                break
            }
            room.broadcast(
                .playbackCommand(
                    command: command,
                    positionMs: positionMs,
                    scheduledAtMs: scheduledAtMs,
                    executedBy: pName
                ),
                excludeConnectionId: conn.connectionId
            )

        case .queueUpdate(let newQueue):
            guard let (room, participantId) = getRoomAndParticipantLocked(conn: conn) else { return }
            let isHost = room.hostId == participantId
            guard isHost || room.settings.guestQueueAllowed else { return }
            room.queue = newQueue
            let pName = room.participants[participantId]?.participant.name ?? ""
            room.broadcast(.queueUpdate(queue: room.queue, updatedBy: pName), excludeConnectionId: conn.connectionId)

        case .settingsUpdate(let settings):
            guard let (room, participantId) = getRoomAndParticipantLocked(conn: conn),
                  room.hostId == participantId else { return }
            room.settings = settings
            room.broadcast(.settingsUpdated(settings: settings))

        case .kickParticipant(let targetId):
            guard let (room, participantId) = getRoomAndParticipantLocked(conn: conn),
                  room.hostId == participantId,
                  let target = room.participants[targetId] else { return }
            target.disconnectWorkItem?.cancel()
            target.connection?.send(.participantKicked(reason: "Host removed you from session."))
            target.connection?.close()
            room.participants.removeValue(forKey: targetId)
            if let connId = target.connection?.connectionId {
                connectionToRoomMap.removeValue(forKey: connId)
            }
            room.broadcast(.participantLeft(
                participantId: targetId,
                participantName: target.participant.name,
                newHostId: nil
            ))

        case .reportSync(let isSynced, let latencyMs):
            guard let (room, participantId) = getRoomAndParticipantLocked(conn: conn),
                  let existing = room.participants[participantId] else { return }
            existing.participant.isSynced = isSynced
            existing.participant.latencyMs = latencyMs
            room.broadcast(.participantSyncUpdate(
                participantId: participantId,
                isSynced: isSynced,
                latencyMs: latencyMs
            ))

        case .leaveRoom:
            leaveCurrentRoomLocked(conn: conn)

        case .endSession:
            guard let (room, participantId) = getRoomAndParticipantLocked(conn: conn),
                  room.hostId == participantId else { return }
            endRoomLocked(roomCode: room.code, reason: "Host ended the session.")
        }
    }

    func handleDisconnect(conn: any LocalClientConnection) {
        queue.async { [weak self] in
            self?.handleDisconnectLocked(conn: conn)
        }
    }

    private func handleDisconnectLocked(conn: any LocalClientConnection) {
        guard let mapping = connectionToRoomMap.removeValue(forKey: conn.connectionId),
              let room = rooms[mapping.roomCode],
              let record = room.participants[mapping.participantId] else { return }

        record.connection = nil
        record.participant.isOffline = true
        room.broadcast(.participantOffline(participantId: mapping.participantId))

        record.disconnectWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let currentRoom = self.rooms[mapping.roomCode],
                  let currentRecord = currentRoom.participants[mapping.participantId],
                  currentRecord.participant.isOffline else { return }
            currentRoom.participants.removeValue(forKey: mapping.participantId)
            if currentRoom.hostId == mapping.participantId {
                self.endRoomLocked(roomCode: currentRoom.code, reason: "Host disconnected.")
            } else {
                currentRoom.broadcast(.participantLeft(
                    participantId: mapping.participantId,
                    participantName: currentRecord.participant.name,
                    newHostId: nil
                ))
            }
        }
        record.disconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 45, execute: workItem)
    }

    private func leaveCurrentRoomLocked(conn: any LocalClientConnection) {
        guard let mapping = connectionToRoomMap.removeValue(forKey: conn.connectionId),
              let room = rooms[mapping.roomCode],
              let record = room.participants.removeValue(forKey: mapping.participantId) else { return }
        record.disconnectWorkItem?.cancel()

        if room.participants.isEmpty {
            rooms.removeValue(forKey: room.code)
            return
        }
        if room.hostId == mapping.participantId {
            endRoomLocked(roomCode: room.code, reason: "Host ended the session.")
            return
        }
        room.broadcast(.participantLeft(
            participantId: mapping.participantId,
            participantName: record.participant.name,
            newHostId: nil
        ))
    }

    private func endRoomLocked(roomCode: String, reason: String) {
        guard let room = rooms.removeValue(forKey: roomCode) else { return }
        room.participants.values.forEach { $0.disconnectWorkItem?.cancel() }
        room.broadcast(.sessionEnded(reason: reason))
        for record in room.participants.values {
            if let connId = record.connection?.connectionId {
                connectionToRoomMap.removeValue(forKey: connId)
            }
        }
        let connections = room.participants.values.compactMap(\.connection)
        queue.asyncAfter(deadline: .now() + 0.25) {
            connections.forEach { $0.close() }
        }
    }

    func clearAll() {
        queue.async { [weak self] in
            self?.clearAllLocked()
        }
    }

    private func clearAllLocked() {
        for code in Array(rooms.keys) {
            endRoomLocked(roomCode: code, reason: "Host ended the session.")
        }
        rooms.removeAll()
        connectionToRoomMap.removeAll()
    }

    private func getRoomAndParticipantLocked(conn: any LocalClientConnection) -> (LocalRoom, String)? {
        guard let mapping = connectionToRoomMap[conn.connectionId],
              let room = rooms[mapping.roomCode] else { return nil }
        return (room, mapping.participantId)
    }
}

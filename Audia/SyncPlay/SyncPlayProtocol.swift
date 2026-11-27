//
//  SyncPlayProtocol.swift
//  Audia
//

import Foundation

enum ClientSyncMessage: Sendable {
    case timePing(clientTimeMs: Int64)
    case createRoom(hostName: String, settings: SyncRoomSettings?)
    case joinRoom(roomCode: String, participantName: String)
    case reconnect(roomCode: String, participantId: String, sessionToken: String)
    case leaveRoom
    case endSession
    case syncState(currentTrack: SyncTrack?, isPlaying: Bool, positionMs: Int64, speed: Float)
    case playbackCommand(command: String, positionMs: Int64?, scheduledAtMs: Int64?)
    case queueUpdate(queue: [SyncTrack])
    case settingsUpdate(settings: SyncRoomSettings)
    case kickParticipant(participantId: String)
    case reportSync(isSynced: Bool, latencyMs: Int64?)
}

extension ClientSyncMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case clientTimeMs
        case hostName
        case settings
        case roomCode
        case participantName
        case participantId
        case sessionToken
        case currentTrack
        case isPlaying
        case positionMs
        case speed
        case command
        case scheduledAtMs
        case queue
        case isSynced
        case latencyMs
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .timePing(let clientTimeMs):
            try container.encode("TIME_PING", forKey: .type)
            try container.encode(clientTimeMs, forKey: .clientTimeMs)
        case .createRoom(let hostName, let settings):
            try container.encode("CREATE_ROOM", forKey: .type)
            try container.encode(hostName, forKey: .hostName)
            try container.encodeIfPresent(settings, forKey: .settings)
        case .joinRoom(let roomCode, let participantName):
            try container.encode("JOIN_ROOM", forKey: .type)
            try container.encode(roomCode, forKey: .roomCode)
            try container.encode(participantName, forKey: .participantName)
        case .reconnect(let roomCode, let participantId, let sessionToken):
            try container.encode("RECONNECT", forKey: .type)
            try container.encode(roomCode, forKey: .roomCode)
            try container.encode(participantId, forKey: .participantId)
            try container.encode(sessionToken, forKey: .sessionToken)
        case .leaveRoom:
            try container.encode("LEAVE_ROOM", forKey: .type)
        case .endSession:
            try container.encode("END_SESSION", forKey: .type)
        case .syncState(let currentTrack, let isPlaying, let positionMs, let speed):
            try container.encode("SYNC_STATE", forKey: .type)
            try container.encodeIfPresent(currentTrack, forKey: .currentTrack)
            try container.encode(isPlaying, forKey: .isPlaying)
            try container.encode(positionMs, forKey: .positionMs)
            try container.encode(speed, forKey: .speed)
        case .playbackCommand(let command, let positionMs, let scheduledAtMs):
            try container.encode("PLAYBACK_COMMAND", forKey: .type)
            try container.encode(command, forKey: .command)
            try container.encodeIfPresent(positionMs, forKey: .positionMs)
            try container.encodeIfPresent(scheduledAtMs, forKey: .scheduledAtMs)
        case .queueUpdate(let queue):
            try container.encode("QUEUE_UPDATE", forKey: .type)
            try container.encode(queue, forKey: .queue)
        case .settingsUpdate(let settings):
            try container.encode("SETTINGS_UPDATE", forKey: .type)
            try container.encode(settings, forKey: .settings)
        case .kickParticipant(let participantId):
            try container.encode("KICK_PARTICIPANT", forKey: .type)
            try container.encode(participantId, forKey: .participantId)
        case .reportSync(let isSynced, let latencyMs):
            try container.encode("REPORT_SYNC", forKey: .type)
            try container.encode(isSynced, forKey: .isSynced)
            try container.encodeIfPresent(latencyMs, forKey: .latencyMs)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "TIME_PING":
            self = .timePing(clientTimeMs: try container.decode(Int64.self, forKey: .clientTimeMs))
        case "CREATE_ROOM":
            self = .createRoom(
                hostName: try container.decode(String.self, forKey: .hostName),
                settings: try container.decodeIfPresent(SyncRoomSettings.self, forKey: .settings)
            )
        case "JOIN_ROOM":
            self = .joinRoom(
                roomCode: try container.decode(String.self, forKey: .roomCode),
                participantName: try container.decode(String.self, forKey: .participantName)
            )
        case "RECONNECT":
            self = .reconnect(
                roomCode: try container.decode(String.self, forKey: .roomCode),
                participantId: try container.decode(String.self, forKey: .participantId),
                sessionToken: try container.decode(String.self, forKey: .sessionToken)
            )
        case "LEAVE_ROOM":
            self = .leaveRoom
        case "END_SESSION":
            self = .endSession
        case "SYNC_STATE":
            self = .syncState(
                currentTrack: try container.decodeIfPresent(SyncTrack.self, forKey: .currentTrack),
                isPlaying: try container.decode(Bool.self, forKey: .isPlaying),
                positionMs: try container.decode(Int64.self, forKey: .positionMs),
                speed: try container.decodeIfPresent(Float.self, forKey: .speed) ?? 1.0
            )
        case "PLAYBACK_COMMAND":
            self = .playbackCommand(
                command: try container.decode(String.self, forKey: .command),
                positionMs: try container.decodeIfPresent(Int64.self, forKey: .positionMs),
                scheduledAtMs: try container.decodeIfPresent(Int64.self, forKey: .scheduledAtMs)
            )
        case "QUEUE_UPDATE":
            self = .queueUpdate(queue: try container.decode([SyncTrack].self, forKey: .queue))
        case "SETTINGS_UPDATE":
            self = .settingsUpdate(settings: try container.decode(SyncRoomSettings.self, forKey: .settings))
        case "KICK_PARTICIPANT":
            self = .kickParticipant(participantId: try container.decode(String.self, forKey: .participantId))
        case "REPORT_SYNC":
            self = .reportSync(
                isSynced: try container.decode(Bool.self, forKey: .isSynced),
                latencyMs: try container.decodeIfPresent(Int64.self, forKey: .latencyMs)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown ClientSyncMessage type: \(type)")
        }
    }
}

enum ServerSyncMessage: Sendable {
    case timePong(clientTimeMs: Int64, serverReceiveTimeMs: Int64, serverSendTimeMs: Int64)
    case roomCreated(roomCode: String, participantId: String, sessionToken: String?, room: SyncRoomSnapshot)
    case roomJoined(roomCode: String, participantId: String, sessionToken: String?, room: SyncRoomSnapshot)
    case reconnected(roomCode: String, participantId: String, sessionToken: String?, room: SyncRoomSnapshot)
    case participantJoined(participant: SyncParticipant)
    case participantOffline(participantId: String)
    case participantLeft(participantId: String, participantName: String, newHostId: String?)
    case participantKicked(reason: String)
    case participantSyncUpdate(participantId: String, isSynced: Bool, latencyMs: Int64?)
    case syncState(currentTrack: SyncTrack?, isPlaying: Bool, positionMs: Int64, serverTimestampMs: Int64, speed: Float)
    case playbackCommand(command: String, positionMs: Int64?, scheduledAtMs: Int64?, executedBy: String)
    case queueUpdate(queue: [SyncTrack], updatedBy: String)
    case settingsUpdated(settings: SyncRoomSettings)
    case sessionEnded(reason: String)
    case error(code: String, message: String)
}

extension ServerSyncMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case clientTimeMs
        case serverReceiveTimeMs
        case serverSendTimeMs
        case roomCode
        case participantId
        case sessionToken
        case room
        case participant
        case participantName
        case newHostId
        case reason
        case isSynced
        case latencyMs
        case currentTrack
        case isPlaying
        case positionMs
        case serverTimestampMs
        case speed
        case command
        case scheduledAtMs
        case executedBy
        case queue
        case updatedBy
        case settings
        case code
        case message
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .timePong(let clientTimeMs, let serverReceiveTimeMs, let serverSendTimeMs):
            try container.encode("TIME_PONG", forKey: .type)
            try container.encode(clientTimeMs, forKey: .clientTimeMs)
            try container.encode(serverReceiveTimeMs, forKey: .serverReceiveTimeMs)
            try container.encode(serverSendTimeMs, forKey: .serverSendTimeMs)
        case .roomCreated(let roomCode, let participantId, let sessionToken, let room):
            try container.encode("ROOM_CREATED", forKey: .type)
            try container.encode(roomCode, forKey: .roomCode)
            try container.encode(participantId, forKey: .participantId)
            try container.encodeIfPresent(sessionToken, forKey: .sessionToken)
            try container.encode(room, forKey: .room)
        case .roomJoined(let roomCode, let participantId, let sessionToken, let room):
            try container.encode("ROOM_JOINED", forKey: .type)
            try container.encode(roomCode, forKey: .roomCode)
            try container.encode(participantId, forKey: .participantId)
            try container.encodeIfPresent(sessionToken, forKey: .sessionToken)
            try container.encode(room, forKey: .room)
        case .reconnected(let roomCode, let participantId, let sessionToken, let room):
            try container.encode("RECONNECTED", forKey: .type)
            try container.encode(roomCode, forKey: .roomCode)
            try container.encode(participantId, forKey: .participantId)
            try container.encodeIfPresent(sessionToken, forKey: .sessionToken)
            try container.encode(room, forKey: .room)
        case .participantJoined(let participant):
            try container.encode("PARTICIPANT_JOINED", forKey: .type)
            try container.encode(participant, forKey: .participant)
        case .participantOffline(let participantId):
            try container.encode("PARTICIPANT_OFFLINE", forKey: .type)
            try container.encode(participantId, forKey: .participantId)
        case .participantLeft(let participantId, let participantName, let newHostId):
            try container.encode("PARTICIPANT_LEFT", forKey: .type)
            try container.encode(participantId, forKey: .participantId)
            try container.encode(participantName, forKey: .participantName)
            try container.encodeIfPresent(newHostId, forKey: .newHostId)
        case .participantKicked(let reason):
            try container.encode("PARTICIPANT_KICKED", forKey: .type)
            try container.encode(reason, forKey: .reason)
        case .participantSyncUpdate(let participantId, let isSynced, let latencyMs):
            try container.encode("PARTICIPANT_SYNC_UPDATE", forKey: .type)
            try container.encode(participantId, forKey: .participantId)
            try container.encode(isSynced, forKey: .isSynced)
            try container.encodeIfPresent(latencyMs, forKey: .latencyMs)
        case .syncState(let currentTrack, let isPlaying, let positionMs, let serverTimestampMs, let speed):
            try container.encode("SYNC_STATE", forKey: .type)
            try container.encodeIfPresent(currentTrack, forKey: .currentTrack)
            try container.encode(isPlaying, forKey: .isPlaying)
            try container.encode(positionMs, forKey: .positionMs)
            try container.encode(serverTimestampMs, forKey: .serverTimestampMs)
            try container.encode(speed, forKey: .speed)
        case .playbackCommand(let command, let positionMs, let scheduledAtMs, let executedBy):
            try container.encode("PLAYBACK_COMMAND", forKey: .type)
            try container.encode(command, forKey: .command)
            try container.encodeIfPresent(positionMs, forKey: .positionMs)
            try container.encodeIfPresent(scheduledAtMs, forKey: .scheduledAtMs)
            try container.encode(executedBy, forKey: .executedBy)
        case .queueUpdate(let queue, let updatedBy):
            try container.encode("QUEUE_UPDATE", forKey: .type)
            try container.encode(queue, forKey: .queue)
            try container.encode(updatedBy, forKey: .updatedBy)
        case .settingsUpdated(let settings):
            try container.encode("SETTINGS_UPDATED", forKey: .type)
            try container.encode(settings, forKey: .settings)
        case .sessionEnded(let reason):
            try container.encode("SESSION_ENDED", forKey: .type)
            try container.encode(reason, forKey: .reason)
        case .error(let code, let message):
            try container.encode("ERROR", forKey: .type)
            try container.encode(code, forKey: .code)
            try container.encode(message, forKey: .message)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "TIME_PONG":
            self = .timePong(
                clientTimeMs: try container.decode(Int64.self, forKey: .clientTimeMs),
                serverReceiveTimeMs: try container.decode(Int64.self, forKey: .serverReceiveTimeMs),
                serverSendTimeMs: try container.decode(Int64.self, forKey: .serverSendTimeMs)
            )
        case "ROOM_CREATED":
            self = .roomCreated(
                roomCode: try container.decode(String.self, forKey: .roomCode),
                participantId: try container.decode(String.self, forKey: .participantId),
                sessionToken: try container.decodeIfPresent(String.self, forKey: .sessionToken),
                room: try container.decode(SyncRoomSnapshot.self, forKey: .room)
            )
        case "ROOM_JOINED":
            self = .roomJoined(
                roomCode: try container.decode(String.self, forKey: .roomCode),
                participantId: try container.decode(String.self, forKey: .participantId),
                sessionToken: try container.decodeIfPresent(String.self, forKey: .sessionToken),
                room: try container.decode(SyncRoomSnapshot.self, forKey: .room)
            )
        case "RECONNECTED":
            self = .reconnected(
                roomCode: try container.decode(String.self, forKey: .roomCode),
                participantId: try container.decode(String.self, forKey: .participantId),
                sessionToken: try container.decodeIfPresent(String.self, forKey: .sessionToken),
                room: try container.decode(SyncRoomSnapshot.self, forKey: .room)
            )
        case "PARTICIPANT_JOINED":
            self = .participantJoined(participant: try container.decode(SyncParticipant.self, forKey: .participant))
        case "PARTICIPANT_OFFLINE":
            self = .participantOffline(participantId: try container.decode(String.self, forKey: .participantId))
        case "PARTICIPANT_LEFT":
            self = .participantLeft(
                participantId: try container.decode(String.self, forKey: .participantId),
                participantName: try container.decode(String.self, forKey: .participantName),
                newHostId: try container.decodeIfPresent(String.self, forKey: .newHostId)
            )
        case "PARTICIPANT_KICKED":
            self = .participantKicked(reason: try container.decode(String.self, forKey: .reason))
        case "PARTICIPANT_SYNC_UPDATE":
            self = .participantSyncUpdate(
                participantId: try container.decode(String.self, forKey: .participantId),
                isSynced: try container.decode(Bool.self, forKey: .isSynced),
                latencyMs: try container.decodeIfPresent(Int64.self, forKey: .latencyMs)
            )
        case "SYNC_STATE":
            self = .syncState(
                currentTrack: try container.decodeIfPresent(SyncTrack.self, forKey: .currentTrack),
                isPlaying: try container.decode(Bool.self, forKey: .isPlaying),
                positionMs: try container.decode(Int64.self, forKey: .positionMs),
                serverTimestampMs: try container.decode(Int64.self, forKey: .serverTimestampMs),
                speed: try container.decodeIfPresent(Float.self, forKey: .speed) ?? 1.0
            )
        case "PLAYBACK_COMMAND":
            self = .playbackCommand(
                command: try container.decode(String.self, forKey: .command),
                positionMs: try container.decodeIfPresent(Int64.self, forKey: .positionMs),
                scheduledAtMs: try container.decodeIfPresent(Int64.self, forKey: .scheduledAtMs),
                executedBy: try container.decodeIfPresent(String.self, forKey: .executedBy) ?? ""
            )
        case "QUEUE_UPDATE":
            self = .queueUpdate(
                queue: try container.decode([SyncTrack].self, forKey: .queue),
                updatedBy: try container.decodeIfPresent(String.self, forKey: .updatedBy) ?? ""
            )
        case "SETTINGS_UPDATED":
            self = .settingsUpdated(settings: try container.decode(SyncRoomSettings.self, forKey: .settings))
        case "SESSION_ENDED":
            self = .sessionEnded(reason: try container.decode(String.self, forKey: .reason))
        case "ERROR":
            self = .error(
                code: try container.decode(String.self, forKey: .code),
                message: try container.decode(String.self, forKey: .message)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown ServerSyncMessage type: \(type)")
        }
    }
}

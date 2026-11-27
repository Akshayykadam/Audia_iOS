//
//  SyncPlayModels.swift
//  Audia
//

import Foundation

struct SyncTrack: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let durationMs: Int64
    let thumbnailUrl: String?
    let streamUrl: String?

    init(
        id: String,
        title: String,
        artist: String,
        album: String? = nil,
        durationMs: Int64 = 0,
        thumbnailUrl: String? = nil,
        streamUrl: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
        self.thumbnailUrl = thumbnailUrl
        self.streamUrl = streamUrl
    }

    @MainActor
    static func fromNowPlaying(_ np: NowPlaying) -> SyncTrack? {
        guard let videoId = np.videoId, !videoId.isEmpty else { return nil }
        let artistStr = np.displayArtist
        return SyncTrack(
            id: videoId,
            title: np.title,
            artist: artistStr,
            album: np.albumTitle.isEmpty ? nil : np.albumTitle,
            durationMs: Int64(max(0, np.duration) * 1000.0),
            thumbnailUrl: ArtworkURLs.fallback(for: videoId),
            streamUrl: nil
        )
    }

    func toSongItem() -> SongItem {
        let parsedArtists = artist
            .split(separator: ",")
            .map { YTArtist(name: $0.trimmingCharacters(in: .whitespaces), id: nil) }
            .filter { !$0.name.isEmpty }
        return SongItem(
            videoId: id,
            title: title,
            artists: parsedArtists.isEmpty ? [YTArtist(name: artist, id: nil)] : parsedArtists,
            album: album,
            albumId: nil,
            duration: Int(durationMs / 1000),
            thumbnailUrl: thumbnailUrl ?? ArtworkURLs.fallback(for: id),
            isExplicit: false,
            playlistId: nil,
            likeStatus: nil
        )
    }
}

struct SyncRoomSettings: Codable, Equatable, Sendable {
    var guestControlAllowed: Bool = false
    var guestQueueAllowed: Bool = true
    var maxParticipants: Int = 50

    init(
        guestControlAllowed: Bool = false,
        guestQueueAllowed: Bool = true,
        maxParticipants: Int = 50
    ) {
        self.guestControlAllowed = guestControlAllowed
        self.guestQueueAllowed = guestQueueAllowed
        self.maxParticipants = maxParticipants
    }
}

struct SyncPlaybackState: Codable, Equatable, Sendable {
    var currentTrack: SyncTrack?
    var isPlaying: Bool
    var positionMs: Int64
    var speed: Float
    var serverTimestampMs: Int64

    init(
        currentTrack: SyncTrack? = nil,
        isPlaying: Bool = false,
        positionMs: Int64 = 0,
        speed: Float = 1.0,
        serverTimestampMs: Int64 = 0
    ) {
        self.currentTrack = currentTrack
        self.isPlaying = isPlaying
        self.positionMs = positionMs
        self.speed = speed
        self.serverTimestampMs = serverTimestampMs
    }
}

struct SyncParticipant: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    var isHost: Bool
    var isSynced: Bool
    var joinedAt: Int64
    var latencyMs: Int64?
    var isOffline: Bool

    init(
        id: String,
        name: String,
        isHost: Bool = false,
        isSynced: Bool = true,
        joinedAt: Int64 = 0,
        latencyMs: Int64? = nil,
        isOffline: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isHost = isHost
        self.isSynced = isSynced
        self.joinedAt = joinedAt
        self.latencyMs = latencyMs
        self.isOffline = isOffline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isHost = try container.decodeIfPresent(Bool.self, forKey: .isHost) ?? false
        isSynced = try container.decodeIfPresent(Bool.self, forKey: .isSynced) ?? true
        joinedAt = try container.decodeIfPresent(Int64.self, forKey: .joinedAt) ?? 0
        latencyMs = try container.decodeIfPresent(Int64.self, forKey: .latencyMs)
        isOffline = try container.decodeIfPresent(Bool.self, forKey: .isOffline) ?? false
    }
}

struct SyncRoomSnapshot: Codable, Equatable, Sendable {
    let code: String
    var hostId: String
    var settings: SyncRoomSettings
    var playbackState: SyncPlaybackState
    var queue: [SyncTrack]
    var participants: [SyncParticipant]

    init(
        code: String,
        hostId: String,
        settings: SyncRoomSettings = SyncRoomSettings(),
        playbackState: SyncPlaybackState = SyncPlaybackState(),
        queue: [SyncTrack] = [],
        participants: [SyncParticipant] = []
    ) {
        self.code = code
        self.hostId = hostId
        self.settings = settings
        self.playbackState = playbackState
        self.queue = queue
        self.participants = participants
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        hostId = try container.decode(String.self, forKey: .hostId)
        settings = try container.decodeIfPresent(SyncRoomSettings.self, forKey: .settings) ?? SyncRoomSettings()
        playbackState = try container.decodeIfPresent(SyncPlaybackState.self, forKey: .playbackState) ?? SyncPlaybackState()
        queue = try container.decodeIfPresent([SyncTrack].self, forKey: .queue) ?? []
        participants = try container.decodeIfPresent([SyncParticipant].self, forKey: .participants) ?? []
    }
}

struct DiscoveredSession: Identifiable, Equatable, Sendable {
    var id: String { "\(roomCode)-\(ipAddress):\(port)" }
    let roomCode: String
    let hostName: String
    let ipAddress: String
    let port: Int
    let discoveredAtMs: Int64

    var serverUrl: String {
        "ws://\(ipAddress):\(port)/ws"
    }
}

//
//  PlaylistImportService.swift
//  Audia
//

import Foundation
import GRDB

struct PlaylistPreviewInfo: Sendable {
    let linkType: PlaylistLinkType
    let title: String
    let author: String?
    let artworkUrl: String?
    let trackCount: Int
    let descriptionText: String?
}

enum PlaylistImportError: LocalizedError {
    case unsupportedLink
    case playlistNotFound
    case emptyPlaylist
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedLink:
            return "Please provide a valid YouTube Music or Spotify playlist link."
        case .playlistNotFound:
            return "Could not find or access the playlist."
        case .emptyPlaylist:
            return "The playlist contains no playable tracks."
        case .importFailed(let msg):
            return "Import failed: \(msg)"
        }
    }
}

actor PlaylistImportService {
    static let shared = PlaylistImportService()

    private init() {}

    // MARK: - Preview

    /// Quick metadata preview without downloading/matching all tracks.
    func previewPlaylist(from linkOrId: String) async throws -> PlaylistPreviewInfo {
        guard let linkType = PlaylistLinkParser.parse(linkOrId) else {
            throw PlaylistImportError.unsupportedLink
        }

        switch linkType {
        case .youTube(let playlistId):
            let (firstPage, rows) = try await SyncBridge.playlistDetail.fetchPlaylistRows(playlistId: playlistId)
            let parsed = await MainActor.run {
                PlaylistDetailViewModel.parsePlaylistDetail(firstPage: firstPage, rows: rows, playlistId: playlistId)
            }
            return PlaylistPreviewInfo(
                linkType: linkType,
                title: parsed.title,
                author: parsed.authorName,
                artworkUrl: parsed.thumbnailUrl,
                trackCount: parsed.songs.count,
                descriptionText: parsed.descriptionText
            )

        case .spotify(let playlistId):
            let info = try await SpotifyService.shared.fetchPlaylist(id: playlistId)
            return PlaylistPreviewInfo(
                linkType: linkType,
                title: info.title,
                author: info.author,
                artworkUrl: info.artworkUrl,
                trackCount: info.totalTracks,
                descriptionText: info.descriptionText
            )
        }
    }

    // MARK: - Import Orchestration

    /// Imports a playlist from either a YouTube Music or Spotify link.
    func importPlaylist(
        from linkOrId: String,
        customName: String? = nil,
        onProgress: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> PlaylistEntity {
        guard let linkType = PlaylistLinkParser.parse(linkOrId) else {
            throw PlaylistImportError.unsupportedLink
        }

        switch linkType {
        case .youTube(let playlistId):
            return try await importYouTubePlaylist(
                playlistId: playlistId,
                customName: customName,
                onProgress: onProgress
            )
        case .spotify(let playlistId):
            return try await importSpotifyPlaylist(
                playlistId: playlistId,
                customName: customName,
                onProgress: onProgress
            )
        }
    }

    // MARK: - YouTube Import

    func importYouTubePlaylist(
        playlistId: String,
        customName: String? = nil,
        onProgress: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> PlaylistEntity {
        onProgress?(0.1, "Connecting to YouTube Music...")

        let (firstPage, rows) = try await SyncBridge.playlistDetail.fetchPlaylistRows(playlistId: playlistId)

        onProgress?(0.5, "Parsing playlist tracks...")
        let parsed = await MainActor.run {
            PlaylistDetailViewModel.parsePlaylistDetail(firstPage: firstPage, rows: rows, playlistId: playlistId)
        }

        guard !parsed.songs.isEmpty else {
            throw PlaylistImportError.emptyPlaylist
        }

        onProgress?(0.8, "Saving \(parsed.songs.count) songs to your library...")

        let pid = playlistId
        let browseId = pid.hasPrefix("VL") ? pid : "VL\(pid)"
        let playlistTitle = (customName?.isEmpty == false ? customName : nil) ?? parsed.title
        let songs = parsed.songs

        let entity = PlaylistEntity(
            id: pid,
            browseId: browseId,
            name: playlistTitle,
            thumbnailUrl: parsed.thumbnailUrl,
            isEditable: true,
            bookmarkedAt: Date(), // Bookmarked so it immediately appears in Library
            remoteSongCount: songs.count,
            isAutoSync: false
        )

        try await DatabaseService.shared.write { db in
            try entity.save(db)
            try db.execute(sql: "DELETE FROM playlist_song_map WHERE playlist_id = ?", arguments: [pid])

            for (index, song) in songs.enumerated() {
                let existingSong = try SongEntity.fetchOne(db, key: song.videoId)
                let songEntity = SongEntity.merging(
                    existing: existingSong,
                    id: song.videoId,
                    title: song.title,
                    artistName: song.artists.first?.name,
                    albumName: song.album,
                    duration: song.duration,
                    thumbnailUrl: song.thumbnailUrl
                )
                try songEntity.save(db)

                let map = PlaylistSongMap(
                    id: nil,
                    playlistId: pid,
                    songId: song.videoId,
                    position: index,
                    setVideoId: nil
                )
                try map.insert(db, onConflict: .ignore)
            }
        }

        onProgress?(1.0, "Import completed!")
        return entity
    }

    // MARK: - Spotify Import

    func importSpotifyPlaylist(
        playlistId: String,
        customName: String? = nil,
        onProgress: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> PlaylistEntity {
        onProgress?(0.05, "Connecting to Spotify...")

        let info = try await SpotifyService.shared.fetchPlaylist(id: playlistId)
        guard !info.tracks.isEmpty else {
            throw PlaylistImportError.emptyPlaylist
        }

        let total = info.tracks.count
        onProgress?(0.1, "Found \(total) tracks. Matching with YouTube Music...")

        // Match tracks with controlled concurrency (3 parallel workers)
        var matchedSongs: [(index: Int, song: SongItem)] = []
        let tracksWithIndex = Array(info.tracks.enumerated())

        let batchSize = 3
        var processedCount = 0

        for chunkStart in stride(from: 0, to: tracksWithIndex.count, by: batchSize) {
            let chunkEnd = min(chunkStart + batchSize, tracksWithIndex.count)
            let chunk = tracksWithIndex[chunkStart..<chunkEnd]

            let results: [(Int, SongItem?)] = await withTaskGroup(of: (Int, SongItem?).self) { group in
                for (idx, track) in chunk {
                    group.addTask {
                        let matched = await TrackMatchingService.shared.matchTrack(track)
                        return (idx, matched)
                    }
                }

                var batchResults: [(Int, SongItem?)] = []
                for await res in group {
                    batchResults.append(res)
                }
                return batchResults
            }

            for (idx, song) in results {
                processedCount += 1
                if let song {
                    matchedSongs.append((index: idx, song: song))
                }
            }

            let progressFraction = 0.1 + (Double(processedCount) / Double(total)) * 0.75
            let currentTrack = chunk.last?.element.title ?? ""
            onProgress?(progressFraction, "Matching (\(processedCount)/\(total)): \(currentTrack)")
        }

        // Sort matched songs back into their original playlist order
        matchedSongs.sort { $0.index < $1.index }
        let finalSongs = matchedSongs.map(\.song)

        guard !finalSongs.isEmpty else {
            throw PlaylistImportError.importFailed("Unable to match any tracks from this Spotify playlist.")
        }

        onProgress?(0.9, "Saving \(finalSongs.count) matched songs to your library...")

        let localPlaylistId = UUID().uuidString
        let playlistTitle = (customName?.isEmpty == false ? customName : nil) ?? info.title
        let artworkUrl = info.artworkUrl ?? finalSongs.first?.thumbnailUrl

        let entity = PlaylistEntity(
            id: localPlaylistId,
            browseId: nil, // Local playlist
            name: playlistTitle,
            thumbnailUrl: artworkUrl,
            isEditable: true,
            bookmarkedAt: Date(), // Bookmarked so it appears in Library
            remoteSongCount: finalSongs.count,
            isAutoSync: false
        )

        try await DatabaseService.shared.write { db in
            try entity.save(db)

            for (index, song) in finalSongs.enumerated() {
                let existingSong = try SongEntity.fetchOne(db, key: song.videoId)
                let songEntity = SongEntity.merging(
                    existing: existingSong,
                    id: song.videoId,
                    title: song.title,
                    artistName: song.artists.first?.name,
                    albumName: song.album,
                    duration: song.duration,
                    thumbnailUrl: song.thumbnailUrl
                )
                try songEntity.save(db)

                let map = PlaylistSongMap(
                    id: nil,
                    playlistId: localPlaylistId,
                    songId: song.videoId,
                    position: index,
                    setVideoId: nil
                )
                try map.insert(db, onConflict: .ignore)
            }
        }

        onProgress?(1.0, "Imported \(finalSongs.count) of \(total) songs!")
        return entity
    }
}

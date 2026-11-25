//
//  DeepLinkHandler.swift
//  Audia
//

import Foundation
import UIKit

@MainActor
enum DeepLinkHandler {

    /// Handle incoming deep links (e.g. from Safari Web Extension, custom schemes, or clipboard).
    static func handle(url: URL) {
        let scheme = url.scheme?.lowercased()

        // 1. If scheme is audia or youtubemusic
        if scheme == "audia" || scheme == "youtubemusic" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                // Format: audia://open?url=https%3A%2F%2Fmusic.youtube.com%2F...
                if components.host == "open",
                   let targetUrlString = components.queryItems?.first(where: { $0.name == "url" })?.value,
                   let targetUrl = URL(string: targetUrlString) {
                    handleWebURL(targetUrl)
                    return
                }

                // Internal route: tab, player, settings, artist, playlist, watch, etc.
                if handleInternalRoute(components: components, url: url) {
                    return
                }
            }
        }

        // 2. Direct web URL or passed URL
        handleWebURL(url)
    }

    private static func handleInternalRoute(components: URLComponents, url: URL) -> Bool {
        guard let host = components.host?.lowercased() else { return false }

        switch host {
        case "tab":
            if let index = Int(url.lastPathComponent) {
                AppRouter.shared.selectedTabIndex = index
                return true
            }
        case "player":
            if NowPlaying.shared.isBarPresented {
                AppRouter.shared.expandPlayer()
            }
            return true
        case "play", "track":
            let videoId = components.queryItems?.first(where: { $0.name == "id" })?.value
                ?? components.queryItems?.first(where: { $0.name == "v" })?.value
                ?? url.lastPathComponent
            if !videoId.isEmpty {
                playVideo(id: videoId)
                return true
            }
        case "settings":
            let section = components.queryItems?.first(where: { $0.name == "section" })?.value
            AppRouter.shared.settingsTargetSection = section
            AppRouter.shared.open(.settings)
            return true
        case "downloads":
            AppRouter.shared.open(.downloads)
            return true
        case "artist":
            let artistId = url.lastPathComponent
            if !artistId.isEmpty {
                AppRouter.shared.open(.artist(browseId: artistId))
                return true
            }
        case "album":
            let albumId = url.lastPathComponent
            if !albumId.isEmpty {
                AppRouter.shared.open(.album(browseId: albumId))
                return true
            }
        case "playlist":
            let listId = components.queryItems?.first(where: { $0.name == "list" })?.value ?? url.lastPathComponent
            if !listId.isEmpty {
                AppRouter.shared.open(.playlist(playlistId: listId))
                return true
            }
        case "watch":
            if let videoId = components.queryItems?.first(where: { $0.name == "v" })?.value ?? components.queryItems?.first(where: { $0.name == "videoId" })?.value {
                playVideo(id: videoId)
                return true
            }
        case "testplay":
            let song = SongItem(
                videoId: "9Nq_sD8V7_I",
                title: "Tum Se Tum Tak",
                artists: [YTArtist(name: "Niyam", id: "")],
                duration: 163,
                isExplicit: false
            )
            NowPlaying.shared.setQueue([song], startIndex: 0)
            NowPlaying.shared.playCurrentSong(logContext: "testplay")
            return true
        case "testlike":
            if let song = NowPlaying.shared.queueSongs.first {
                Task { await LikeStore.shared.toggle(song: song) }
            }
            return true
        default:
            break
        }

        return false
    }

    /// Handles music.youtube.com, youtube.com, youtu.be web URLs
    static func handleWebURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let host = components.host?.lowercased() ?? ""
        let path = components.path

        // Check if host is YouTube / YouTube Music
        let isYouTube = host.contains("youtube.com") || host.contains("youtu.be")
        guard isYouTube else {
            // Fallback to PlaylistLinkParser (e.g. Spotify playlist)
            if let parsed = PlaylistLinkParser.parse(url.absoluteString) {
                if case .youTube(let pid) = parsed {
                    AppRouter.shared.open(.playlist(playlistId: pid))
                }
            }
            return
        }

        // 1. Check for single song (watch?v=...)
        if let videoId = components.queryItems?.first(where: { $0.name == "v" })?.value, !videoId.isEmpty {
            playVideo(id: videoId)
            return
        }

        // 2. Check for youtu.be/VIDEO_ID
        if host.contains("youtu.be") {
            let videoId = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !videoId.isEmpty && videoId != "/" {
                playVideo(id: videoId)
                return
            }
        }

        // 3. Check for playlist (playlist?list=... or query param list=...)
        if let playlistId = components.queryItems?.first(where: { $0.name == "list" })?.value, !playlistId.isEmpty {
            let cleanId = playlistId.replacingOccurrences(of: "^(VL|RDAMPL)", with: "", options: .regularExpression)
            if cleanId.hasPrefix("OLAK5uy_") {
                // Album playlist
                AppRouter.shared.open(.album(browseId: cleanId))
            } else {
                AppRouter.shared.open(.playlist(playlistId: cleanId))
            }
            return
        }

        // 4. Check for Album / Browse (/browse/MPREb_... or /album/...)
        if path.contains("/browse/") || path.contains("/album/") {
            let browseId = url.lastPathComponent
            if browseId.hasPrefix("MPREb_") || browseId.hasPrefix("OLAK") {
                AppRouter.shared.open(.album(browseId: browseId))
                return
            } else if browseId.hasPrefix("UC") {
                AppRouter.shared.open(.artist(browseId: browseId))
                return
            }
        }

        // 5. Check for Artist / Channel (/channel/UC... or /browse/UC...)
        if path.contains("/channel/") {
            let artistId = url.lastPathComponent
            if !artistId.isEmpty {
                AppRouter.shared.open(.artist(browseId: artistId))
                return
            }
        }

        // Fallback: Check PlaylistLinkParser
        if let parsed = PlaylistLinkParser.parse(url.absoluteString) {
            if case .youTube(let pid) = parsed {
                AppRouter.shared.open(.playlist(playlistId: pid))
            }
        }
    }

    private static func playVideo(id: String) {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { return }

        let placeholder = SongItem(
            videoId: cleanId,
            title: "Loading...",
            artists: [],
            duration: 0,
            isExplicit: false
        )
        PlaybackQueue.playSingleWithRadio(placeholder, log: Log.nowPlaying)
        AppRouter.shared.expandPlayer()
    }
}

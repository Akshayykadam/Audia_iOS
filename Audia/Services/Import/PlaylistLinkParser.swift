//
//  PlaylistLinkParser.swift
//  Audia
//

import Foundation

enum PlaylistLinkType: Equatable, Sendable {
    case youTube(playlistId: String)
    case spotify(playlistId: String)

    var serviceName: String {
        switch self {
        case .youTube: return "YouTube Music"
        case .spotify: return "Spotify"
        }
    }

    var systemIcon: String {
        switch self {
        case .youTube: return "play.rectangle.fill"
        case .spotify: return "waveform.circle.fill"
        }
    }

    var playlistId: String {
        switch self {
        case .youTube(let id): return id
        case .spotify(let id): return id
        }
    }
}

struct PlaylistLinkParser {

    /// Parses a URL or plain string into a typed playlist identifier.
    static func parse(_ input: String) -> PlaylistLinkType? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Try Spotify first
        if let spotifyId = extractSpotifyPlaylistId(from: trimmed) {
            return .spotify(playlistId: spotifyId)
        }

        // 2. Try YouTube / YouTube Music
        if let ytId = extractYouTubePlaylistId(from: trimmed) {
            return .youTube(playlistId: ytId)
        }

        return nil
    }

    // MARK: - Spotify Extraction

    private static func extractSpotifyPlaylistId(from text: String) -> String? {
        // Form: spotify:playlist:37i9dQZF1DXcBWIGoYBM5M
        if text.hasPrefix("spotify:playlist:") {
            let id = String(text.dropFirst("spotify:playlist:".count))
            if isValidSpotifyId(id) { return id }
        }

        // Form: https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=...
        if let url = URL(string: text),
           let host = url.host?.lowercased(),
           host.contains("spotify.com") {
            let components = url.pathComponents
            if let index = components.firstIndex(of: "playlist"),
               index + 1 < components.count {
                let id = components[index + 1]
                if isValidSpotifyId(id) { return id }
            }
        }

        // Regex scan for open.spotify.com/playlist/{22-chars}
        let pattern = #"spotify\.com\/playlist\/([a-zA-Z0-9]{22})"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range),
               let matchRange = Range(match.range(at: 1), in: text) {
                let id = String(text[matchRange])
                if isValidSpotifyId(id) { return id }
            }
        }

        // If string itself is just a 22-char alphanumeric ID (not a URL)
        if isValidSpotifyId(text) && !text.hasPrefix("PL") && !text.hasPrefix("OL") {
            return text
        }

        return nil
    }

    private static func isValidSpotifyId(_ id: String) -> Bool {
        id.count == 22 && id.allSatisfy { $0.isLetter || $0.isNumber }
    }

    // MARK: - YouTube Extraction

    private static func extractYouTubePlaylistId(from text: String) -> String? {
        // Form: URL with query parameters (music.youtube.com, youtube.com, youtu.be)
        if let url = URL(string: text),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let host = components.host?.lowercased() ?? ""
            if host.contains("youtube.com") || host.contains("youtu.be") {
                if let list = components.queryItems?.first(where: { $0.name == "list" })?.value,
                   !list.isEmpty {
                    return cleanYouTubePlaylistId(list)
                }
            }
        }

        // Regex scan for ?list=... or &list=...
        let pattern = #"[?&]list=([a-zA-Z0-9_\-]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range),
               let matchRange = Range(match.range(at: 1), in: text) {
                return cleanYouTubePlaylistId(String(text[matchRange]))
            }
        }

        // Raw YouTube playlist IDs
        if (text.hasPrefix("PL") && text.count >= 16) ||
           (text.hasPrefix("OLAK5uy_") && text.count >= 24) ||
           (text.hasPrefix("RDCLAK5uy_") && text.count >= 26) ||
           (text.hasPrefix("VL") && text.count >= 18) {
            return cleanYouTubePlaylistId(text)
        }

        return nil
    }

    private static func cleanYouTubePlaylistId(_ id: String) -> String {
        if id.hasPrefix("VL") {
            return String(id.dropFirst(2))
        }
        return id
    }
}

//
//  SpotifyService.swift
//  Audia
//

import Foundation

struct SpotifyTrackItem: Sendable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let duration: Int // In seconds
    let isrc: String?
    let artworkUrl: String?

    init(
        id: String,
        title: String,
        artist: String,
        album: String? = nil,
        duration: Int,
        isrc: String? = nil,
        artworkUrl: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.isrc = isrc
        self.artworkUrl = artworkUrl
    }
}

struct SpotifyPlaylistInfo: Sendable {
    let id: String
    let title: String
    let author: String?
    let descriptionText: String?
    let artworkUrl: String?
    let totalTracks: Int
    let tracks: [SpotifyTrackItem]

    init(
        id: String,
        title: String,
        author: String? = nil,
        descriptionText: String? = nil,
        artworkUrl: String? = nil,
        totalTracks: Int,
        tracks: [SpotifyTrackItem]
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.descriptionText = descriptionText
        self.artworkUrl = artworkUrl
        self.totalTracks = totalTracks
        self.tracks = tracks
    }
}

enum SpotifyServiceError: LocalizedError {
    case invalidPlaylistId
    case networkError(String)
    case parsingError(String)
    case authenticationFailed
    case emptyPlaylist

    var errorDescription: String? {
        switch self {
        case .invalidPlaylistId:
            return "Invalid Spotify playlist link or ID."
        case .networkError(let msg):
            return "Network error while reaching Spotify: \(msg)"
        case .parsingError(let msg):
            return "Failed to parse Spotify playlist: \(msg)"
        case .authenticationFailed:
            return "Spotify API authentication failed. Please check your credentials."
        case .emptyPlaylist:
            return "The Spotify playlist is empty or inaccessible."
        }
    }
}

actor SpotifyService {
    static let shared = SpotifyService()

    private var cachedToken: String?
    private var tokenExpiry: Date?

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    /// Fetches playlist metadata and tracks. Uses official API if credentials exist, otherwise falls back to the embed scraper.
    func fetchPlaylist(id: String) async throws -> SpotifyPlaylistInfo {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { throw SpotifyServiceError.invalidPlaylistId }

        let clientId = SettingsStore.shared.spotifyClientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = SettingsStore.shared.spotifyClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)

        if !clientId.isEmpty && !clientSecret.isEmpty {
            do {
                return try await fetchViaWebAPI(id: trimmedId, clientId: clientId, clientSecret: clientSecret)
            } catch {
                Log.search.warning("Spotify Web API failed, falling back to embed scraper: \(error.localizedDescription)")
            }
        }

        // Fallback: Embed scraper (zero credentials required)
        return try await fetchViaEmbed(id: trimmedId)
    }

    // MARK: - Embed Scraper (Zero Keys Required)

    func fetchViaEmbed(id: String) async throws -> SpotifyPlaylistInfo {
        guard let url = URL(string: "https://open.spotify.com/embed/playlist/\(id)") else {
            throw SpotifyServiceError.invalidPlaylistId
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw SpotifyServiceError.networkError("HTTP status \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw SpotifyServiceError.parsingError("Unable to decode HTML string")
        }

        return try parseEmbedHTML(html, id: id)
    }

    private func parseEmbedHTML(_ html: String, id: String) throws -> SpotifyPlaylistInfo {
        let pattern = #"<script id="__NEXT_DATA__"[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            throw SpotifyServiceError.parsingError("Regex initialization failed")
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              let jsonRange = Range(match.range(at: 1), in: html) else {
            throw SpotifyServiceError.parsingError("No JSON data block found in Spotify embed page")
        }

        let jsonString = String(html[jsonRange])
        guard let jsonData = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let props = root["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any],
              let state = pageProps["state"] as? [String: Any],
              let data = state["data"] as? [String: Any],
              let entity = data["entity"] as? [String: Any] else {
            throw SpotifyServiceError.parsingError("Failed to parse Spotify JSON payload structure")
        }

        let name = entity["name"] as? String ?? entity["title"] as? String ?? "Spotify Playlist"
        let subtitle = entity["subtitle"] as? String

        // Extract artwork
        var artworkUrl: String?
        if let coverArt = entity["coverArt"] as? [String: Any],
           let sources = coverArt["sources"] as? [[String: Any]],
           let first = sources.first,
           let urlStr = first["url"] as? String {
            artworkUrl = urlStr
        } else if let visual = entity["visualIdentity"] as? [String: Any],
                  let images = visual["image"] as? [[String: Any]],
                  let first = images.first,
                  let urlStr = first["url"] as? String {
            artworkUrl = urlStr
        }

        // Extract track list
        guard let trackList = entity["trackList"] as? [[String: Any]], !trackList.isEmpty else {
            throw SpotifyServiceError.emptyPlaylist
        }

        var tracks: [SpotifyTrackItem] = []
        for (index, item) in trackList.enumerated() {
            let trackTitle = item["title"] as? String ?? "Unknown Track"
            var artistName = item["subtitle"] as? String ?? "Unknown Artist"
            // Clean up non-breaking spaces (\u{00A0}) in artist names
            artistName = artistName.replacingOccurrences(of: "\u{00A0}", with: " ")

            let durationMs = item["duration"] as? Int ?? 0
            let durationSec = durationMs > 0 ? durationMs / 1000 : 0

            let uri = item["uri"] as? String ?? "track_\(index)"
            let trackId = uri.replacingOccurrences(of: "spotify:track:", with: "")

            tracks.append(SpotifyTrackItem(
                id: trackId,
                title: trackTitle,
                artist: artistName,
                album: nil,
                duration: durationSec,
                isrc: nil,
                artworkUrl: nil
            ))
        }

        return SpotifyPlaylistInfo(
            id: id,
            title: name,
            author: subtitle,
            descriptionText: subtitle,
            artworkUrl: artworkUrl,
            totalTracks: tracks.count,
            tracks: tracks
        )
    }

    // MARK: - Official Web API (Client Credentials Flow)

    private func getAccessToken(clientId: String, clientSecret: String) async throws -> String {
        if let token = cachedToken, let expiry = tokenExpiry, expiry > Date().addingTimeInterval(60) {
            return token
        }

        guard let tokenUrl = URL(string: "https://accounts.spotify.com/api/token") else {
            throw SpotifyServiceError.networkError("Invalid token URL")
        }

        var request = URLRequest(url: tokenUrl)
        request.httpMethod = "POST"
        let authString = "\(clientId):\(clientSecret)"
        guard let authData = authString.data(using: .utf8) else {
            throw SpotifyServiceError.authenticationFailed
        }
        request.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=client_credentials".data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SpotifyServiceError.authenticationFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? TimeInterval else {
            throw SpotifyServiceError.authenticationFailed
        }

        cachedToken = accessToken
        tokenExpiry = Date().addingTimeInterval(expiresIn)
        return accessToken
    }

    private func fetchViaWebAPI(id: String, clientId: String, clientSecret: String) async throws -> SpotifyPlaylistInfo {
        let token = try await getAccessToken(clientId: clientId, clientSecret: clientSecret)

        guard let playlistUrl = URL(string: "https://api.spotify.com/v1/playlists/\(id)") else {
            throw SpotifyServiceError.invalidPlaylistId
        }

        var request = URLRequest(url: playlistUrl)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw SpotifyServiceError.networkError("HTTP status \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SpotifyServiceError.parsingError("Unable to decode playlist response")
        }

        let name = json["name"] as? String ?? "Spotify Playlist"
        let description = json["description"] as? String
        let owner = (json["owner"] as? [String: Any])?["display_name"] as? String

        var artworkUrl: String?
        if let images = json["images"] as? [[String: Any]], let first = images.first {
            artworkUrl = first["url"] as? String
        }

        var allTracks: [SpotifyTrackItem] = []
        if let tracksObj = json["tracks"] as? [String: Any] {
            let items = tracksObj["items"] as? [[String: Any]] ?? []
            allTracks.append(contentsOf: parseTrackItems(items))

            var nextUrlStr = tracksObj["next"] as? String
            while let currentNext = nextUrlStr, let nextUrl = URL(string: currentNext), allTracks.count < 500 {
                var nextReq = URLRequest(url: nextUrl)
                nextReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                guard let (nextData, nextResp) = try? await session.data(for: nextReq),
                      let nextHttp = nextResp as? HTTPURLResponse, (200...299).contains(nextHttp.statusCode),
                      let nextJson = try? JSONSerialization.jsonObject(with: nextData) as? [String: Any] else {
                    break
                }
                let nextItems = nextJson["items"] as? [[String: Any]] ?? []
                allTracks.append(contentsOf: parseTrackItems(nextItems))
                nextUrlStr = nextJson["next"] as? String
            }
        }

        return SpotifyPlaylistInfo(
            id: id,
            title: name,
            author: owner,
            descriptionText: description,
            artworkUrl: artworkUrl,
            totalTracks: allTracks.count,
            tracks: allTracks
        )
    }

    private func parseTrackItems(_ items: [[String: Any]]) -> [SpotifyTrackItem] {
        var results: [SpotifyTrackItem] = []
        for item in items {
            guard let track = item["track"] as? [String: Any] else { continue }
            let id = track["id"] as? String ?? UUID().uuidString
            let title = track["name"] as? String ?? "Unknown Title"

            let artistsList = track["artists"] as? [[String: Any]] ?? []
            let artistNames = artistsList.compactMap { $0["name"] as? String }
            let artist = artistNames.joined(separator: ", ")

            let albumObj = track["album"] as? [String: Any]
            let album = albumObj?["name"] as? String
            let images = albumObj?["images"] as? [[String: Any]]
            let artworkUrl = images?.first?["url"] as? String

            let durationMs = track["duration_ms"] as? Int ?? 0
            let durationSec = durationMs > 0 ? durationMs / 1000 : 0

            let externalIds = track["external_ids"] as? [String: Any]
            let isrc = externalIds?["isrc"] as? String

            results.append(SpotifyTrackItem(
                id: id,
                title: title,
                artist: artist,
                album: album,
                duration: durationSec,
                isrc: isrc,
                artworkUrl: artworkUrl
            ))
        }
        return results
    }
}

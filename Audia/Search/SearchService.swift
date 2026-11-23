//
// SearchService.swift
// Audia
//

import Foundation
import GRDB

actor SearchService {
    nonisolated static let shared = SearchService()
    private let innerTube = InnerTubeClient.audiaShared
    private let db = DatabaseService.shared
    private var searchTask: Task<[String: Any], Error>?
    private var searchGeneration = 0
    private var suggestionsTask: Task<SearchSuggestionsResult, Never>?
    private var suggestionsGeneration = 0

    func search(query: String, params: String? = nil, client: YouTubeClient = .webRemix) async throws -> [String: Any] {
        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        let task = Task { () -> [String: Any] in
            try await innerTube.search(query: query, params: params, client: client)
        }
        searchTask = task
        let result = try await task.value
        guard generation == searchGeneration else { throw CancellationError() }
        return result
    }

    struct LocalSearchResults {
        var songs: [SongEntity] = []
        var artists: [ArtistEntity] = []
        var albums: [AlbumEntity] = []
        var playlists: [PlaylistEntity] = []
    }

    func localSearch(query: String) async throws -> LocalSearchResults {
        let pattern = "%\(query)%"
        async let songs = db.fetchAll(
            SongEntity.self,
            sql: "SELECT * FROM song WHERE title LIKE ? OR artist_name LIKE ? ORDER BY total_play_time DESC LIMIT 50",
            arguments: [pattern, pattern]
        )
        async let artists = db.fetchAll(ArtistEntity.self, sql: "SELECT * FROM artist WHERE name LIKE ? LIMIT 20", arguments: [pattern])
        async let albums = db.fetchAll(AlbumEntity.self, sql: "SELECT * FROM album WHERE title LIKE ? LIMIT 20", arguments: [pattern])
        async let playlists = db.fetchAll(PlaylistEntity.self, sql: "SELECT * FROM playlist WHERE name LIKE ? LIMIT 20", arguments: [pattern])
        let results = try await LocalSearchResults(songs: songs, artists: artists, albums: albums, playlists: playlists)
        return results
    }

    // MARK: - Search Suggestions

    func suggestions(query: String) async throws -> SearchSuggestionsResult {
        suggestionsTask?.cancel()
        suggestionsGeneration += 1
        let generation = suggestionsGeneration

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SearchSuggestionsResult() }

        let task = Task { () -> SearchSuggestionsResult in
            // 1. Try YouTube Music music/get_search_suggestions (returns text queries and artist/song entities)
            if let result = try? await fetchMusicSuggestions(query: trimmed),
               (!result.queries.isEmpty || !result.entities.isEmpty) {
                return result
            }

            // 2. Fallback to Google YouTube suggestions
            let fallbackQueries = (try? await fetchGoogleSuggestions(query: trimmed)) ?? []
            return SearchSuggestionsResult(queries: fallbackQueries, entities: [])
        }
        suggestionsTask = task
        let result = await task.value
        guard generation == suggestionsGeneration else { throw CancellationError() }
        return result
    }

    private func fetchMusicSuggestions(query: String) async throws -> SearchSuggestionsResult {
        guard let url = URL(string: "https://music.youtube.com/youtubei/v1/music/get_search_suggestions") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let country = SettingsStore.shared.contentCountry
        let gl = country.isEmpty ? "US" : country

        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20230515.01.00",
                    "hl": "en",
                    "gl": gl
                ]
            ],
            "input": query
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.badServerResponse)
        }
        return SearchParser.parseSuggestions(from: json)
    }

    private func fetchGoogleSuggestions(query: String) async throws -> [String] {
        guard var components = URLComponents(string: "https://suggestqueries.google.com/complete/search") else {
            return []
        }
        let country = SettingsStore.shared.contentCountry
        let gl = country.isEmpty ? "US" : country
        components.queryItems = [
            URLQueryItem(name: "client", value: "firefox"),
            URLQueryItem(name: "ds", value: "yt"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "hl", value: "en"),
            URLQueryItem(name: "gl", value: gl)
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }
        return SearchParser.parseGoogleSuggest(from: data)
    }
}

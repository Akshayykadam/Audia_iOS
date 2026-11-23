//
//  TrackMatchingService.swift
//  Audia
//

import Foundation
import GRDB

actor TrackMatchingService {
    static let shared = TrackMatchingService()

    private init() {}

    /// Matches a Spotify track to a playable YouTube Music SongItem.
    func matchTrack(_ track: SpotifyTrackItem) async -> SongItem? {
        // 1. Check local SQLite database for already cached/known matching song
        if let local = await checkLocalDatabase(for: track) {
            return local
        }

        // 2. Try ISRC matching if available (100% exact match)
        if let isrc = track.isrc, !isrc.isEmpty {
            if let matched = await searchByQuery(isrc, targetTrack: track) {
                return matched
            }
        }

        // 3. Fallback to title + artist search on YouTube Music
        let cleanTitle = sanitizeTitle(track.title)
        let primaryArtist = extractPrimaryArtist(from: track.artist)
        let query = "\(cleanTitle) \(primaryArtist)"

        if let matched = await searchByQuery(query, targetTrack: track) {
            return matched
        }

        // 4. Last attempt: search with title only
        if let matched = await searchByQuery(cleanTitle, targetTrack: track) {
            return matched
        }

        return nil
    }

    // MARK: - Local Database Lookup

    private func checkLocalDatabase(for track: SpotifyTrackItem) async -> SongItem? {
        let pattern = "%\(track.title)%"
        let targetDuration = track.duration

        let matchingEntities: [SongEntity]? = try? await DatabaseService.shared.read { db in
            try SongEntity
                .filter(Column("title").like(pattern))
                .fetchAll(db)
        }

        guard let entities = matchingEntities, !entities.isEmpty else { return nil }

        // Find best local match by duration and artist
        for entity in entities {
            let durationMatch = targetDuration <= 0 || abs(entity.duration - targetDuration) <= 6
            let artistMatch = entity.artistName?.lowercased().contains(track.artist.lowercased()) == true ||
                              track.artist.lowercased().contains(entity.artistName?.lowercased() ?? "")

            if durationMatch && artistMatch {
                return SongItem(
                    videoId: entity.id,
                    title: entity.title,
                    artists: [YTArtist(name: entity.artistName ?? track.artist, id: nil)],
                    album: entity.albumName,
                    albumId: nil,
                    duration: entity.duration,
                    thumbnailUrl: entity.thumbnailUrl,
                    isExplicit: false,
                    playlistId: nil
                )
            }
        }

        return nil
    }

    // MARK: - InnerTube Search & Scoring

    private func searchByQuery(_ query: String, targetTrack: SpotifyTrackItem) async -> SongItem? {
        do {
            let rawResult = try await SearchService.shared.search(query: query)
            let sections = SearchParser.parseSearchResults(from: rawResult)

            var candidateSongs: [SongItem] = []

            for section in sections {
                let sectionTitle = section.title.lowercased()
                if sectionTitle == "top result" || sectionTitle == "songs" {
                    for item in section.items {
                        if case .song(let s) = item {
                            candidateSongs.append(s)
                        }
                    }
                }
            }

            guard !candidateSongs.isEmpty else { return nil }

            return findBestCandidate(among: candidateSongs, for: targetTrack)
        } catch {
            Log.search.error("Search query failed for matching: '\(query)': \(error.localizedDescription)")
            return nil
        }
    }

    private func findBestCandidate(among candidates: [SongItem], for track: SpotifyTrackItem) -> SongItem? {
        let cleanTargetTitle = sanitizeTitle(track.title).lowercased()
        let targetArtist = track.artist.lowercased()
        let targetDuration = track.duration

        var bestCandidate: SongItem?
        var highestScore = -999

        for candidate in candidates {
            var score = 100
            let candidateTitle = candidate.title.lowercased()
            let candidateArtists = candidate.artists.map { $0.name.lowercased() }.joined(separator: " ")

            // 1. Duration scoring
            if targetDuration > 0 && candidate.duration > 0 {
                let delta = abs(candidate.duration - targetDuration)
                if delta <= 4 {
                    score += 40
                } else if delta <= 8 {
                    score += 20
                } else if delta <= 15 {
                    score -= 10
                } else {
                    score -= (delta * 3)
                }
            }

            // 2. Title matching
            if candidateTitle == cleanTargetTitle {
                score += 50
            } else if candidateTitle.contains(cleanTargetTitle) {
                score += 25
            }

            // 3. Artist matching
            if candidateArtists.contains(targetArtist) || targetArtist.contains(candidateArtists) {
                score += 30
            }

            // 4. Penalties for covers, karaoke, instrumental, live unless specified in Spotify track
            let isKaraoke = candidateTitle.contains("karaoke") && !cleanTargetTitle.contains("karaoke")
            let isCover = (candidateTitle.contains("cover") || candidateTitle.contains("tribute")) &&
                          !cleanTargetTitle.contains("cover") && !cleanTargetTitle.contains("tribute")
            let isInstrumental = candidateTitle.contains("instrumental") && !cleanTargetTitle.contains("instrumental")

            if isKaraoke || isCover || isInstrumental {
                score -= 150
            }

            // Avoid pure music videos if they have extended intro/outro
            if candidate.isMusicVideo && (targetDuration > 0 && abs(candidate.duration - targetDuration) > 10) {
                score -= 40
            }

            if score > highestScore {
                highestScore = score
                bestCandidate = candidate
            }
        }

        // Only return if it meets minimum confidence threshold
        if highestScore >= 30 {
            return bestCandidate
        }

        // If confidence was too low but we have at least one candidate, return the first one as last resort
        return candidates.first
    }

    // MARK: - String Sanitization

    private func sanitizeTitle(_ title: String) -> String {
        var clean = title

        // Strip parenthetical/bracketed extras like (feat. ...), [Official Video], etc.
        let patterns = [
            #"\((feat\.|ft\.|with).*?\)"#,
            #"\[(feat\.|ft\.|with).*?\]"#,
            #"\((official|audio|lyric|video).*?\)"#,
            #"\[(official|audio|lyric|video).*?\]"#,
            #"\((from|soundtrack|ost).*?\)"#,
            #"\[(from|soundtrack|ost).*?\]"#,
            #"\((remastered|bonus track).*?\)"#,
            #"\[(remastered|bonus track).*?\]"#,
            #"- .*?remaster.*?"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(clean.startIndex..<clean.endIndex, in: clean)
                clean = regex.stringByReplacingMatches(in: clean, options: [], range: range, withTemplate: "")
            }
        }

        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractPrimaryArtist(from artistText: String) -> String {
        // Return first artist before comma, &, or feat
        let separators = [",", "&", "feat.", "ft.", "/"]
        var primary = artistText
        for sep in separators {
            if let idx = primary.range(of: sep, options: .caseInsensitive)?.lowerBound {
                primary = String(primary[..<idx])
            }
        }
        return primary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

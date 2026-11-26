//
//  PersonalizationService.swift
//  Audia
//

import Foundation

actor PersonalizationService {
    nonisolated static let shared = PersonalizationService()
    private let db = DatabaseService.shared
    private let innerTube = InnerTubeClient.audiaShared

    private var enrichmentTasks: [Task<Void, Never>] = []

    // MARK: - Phase 1: Local sections (fast, load immediately)

    func buildQuickPicks(limit: Int = 16) async -> HomeSection {
        let target = max(limit, 16)
        var pickedItems: [YTItem] = []
        var seenIds = Set<String>()

        // 1. Gather all user listening data from local database
        let likedSongs = (try? await db.fetchAllLikedSongs(sort: .mostPlayed)) ?? []
        let topSongs = (try? await db.fetchTopSongs(limit: 50)) ?? []
        let recentSongs = (try? await db.fetchRecentSongs(days: 30, limit: 30)) ?? []
        let librarySongs = (try? await db.fetchLibrarySongs(limit: 100)) ?? []
        let historySongs = ((try? await db.fetchHistory(limit: 50)) ?? []).compactMap(\.song)

        // Deduplicate into allUserSongs while preserving prioritization
        var allUserSongs: [SongEntity] = []
        var userSongIds = Set<String>()
        for song in likedSongs + topSongs + recentSongs + historySongs + librarySongs {
            if userSongIds.insert(song.id).inserted {
                allUserSongs.append(song)
            }
        }

        guard !allUserSongs.isEmpty else {
            return .quickPicks(items: [])
        }

        // Check if user is in "first launch" mode (sparse history with fewer than 4 songs)
        let isFirstLaunch = allUserSongs.count < 4

        if isFirstLaunch {
            // First Launch Experience:
            // 1. Add user's 1-3 seed songs first
            for song in allUserSongs {
                if seenIds.insert(song.id).inserted {
                    pickedItems.append(.song(SongItem(entity: song)))
                }
            }

            // 2. Fetch radio recommendations distributed evenly across all available seed songs
            let needed = target - pickedItems.count
            if needed > 0 {
                let slotsPerSeed = max(1, (needed + allUserSongs.count - 1) / allUserSongs.count)
                var perSeedRadios: [[SongItem]] = []

                for seed in allUserSongs {
                    if let radio = try? await fetchRadio(videoId: seed.id), !radio.songs.isEmpty {
                        perSeedRadios.append(radio.songs)
                    }
                }

                // Interleave recommendations from seeds so no single seed dominates
                for slot in 0..<slotsPerSeed {
                    for radioSongs in perSeedRadios {
                        guard pickedItems.count < target else { break }
                        if slot < radioSongs.count {
                            let song = radioSongs[slot]
                            if seenIds.insert(song.videoId).inserted {
                                pickedItems.append(.song(song))
                            }
                        }
                    }
                    if pickedItems.count >= target { break }
                }

                // Fallback fill if still below target
                if pickedItems.count < target {
                    for radioSongs in perSeedRadios {
                        for song in radioSongs {
                            guard pickedItems.count < target else { break }
                            if seenIds.insert(song.videoId).inserted {
                                pickedItems.append(.song(song))
                            }
                        }
                        if pickedItems.count >= target { break }
                    }
                }
            }
        } else {
            // Established User Experience (YouTube Music algorithm):
            // Quick Picks reflects the user's broad taste across all their favorite artists/genres.
            // Listening to 1 song of a different language NEVER replaces all other languages.

            // A. Score each song based on user affinity signals
            var songScores: [String: Double] = [:]
            let recentIds = recentSongs.map(\.id)

            for song in allUserSongs {
                var score: Double = 0
                if song.liked { score += 50.0 }
                let playMinutes = Double(song.totalPlayTime) / 60_000.0
                score += min(playMinutes * 2.0, 50.0)
                if song.inLibrary != nil { score += 15.0 }
                if let recentIdx = recentIds.firstIndex(of: song.id) {
                    score += max(0.0, 20.0 - Double(recentIdx))
                }
                songScores[song.id] = score
            }

            // B. Group songs by artist
            var artistGroups: [String: [SongEntity]] = [:]
            for song in allUserSongs {
                let raw = song.artistName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let artistKey = raw.isEmpty ? "Various Artists" : raw
                artistGroups[artistKey, default: []].append(song)
            }

            // Sort each artist's songs by score descending
            for (artist, songs) in artistGroups {
                artistGroups[artist] = songs.sorted {
                    (songScores[$0.id] ?? 0) > (songScores[$1.id] ?? 0)
                }
            }

            // C. Rank artists by total affinity score
            struct ArtistAffinity {
                let name: String
                let score: Double
                let songs: [SongEntity]
            }

            var artistAffinities: [ArtistAffinity] = artistGroups.map { name, songs in
                let totalScore = songs.reduce(0.0) { $0 + (songScores[$1.id] ?? 0) }
                return ArtistAffinity(name: name, score: totalScore, songs: songs)
            }
            artistAffinities.sort { $0.score > $1.score }

            // D. Round-robin selection across artists to enforce diversity
            // Round 1: Top 1 song from each artist (sorted by artist affinity)
            // Round 2: Top 2 song from each artist
            // Round 3: Top 3 song from each artist
            var selectedSongs: [SongEntity] = []
            var selectedIds = Set<String>()

            // Offer variety on pull-to-refresh while preserving artist diversity
            for round in 0..<4 {
                for artist in artistAffinities {
                    guard selectedSongs.count < target else { break }
                    let available = artist.songs.filter { !selectedIds.contains($0.id) }
                    guard !available.isEmpty else { continue }
                    // Take from top available tracks (prefix 2 chosen with slight variety on refresh)
                    let candidatePool = Array(available.prefix(2))
                    let chosen = candidatePool.randomElement() ?? available[0]
                    if selectedIds.insert(chosen.id).inserted {
                        selectedSongs.append(chosen)
                    }
                }
                if selectedSongs.count >= target { break }
            }

            // Append selected songs
            for song in selectedSongs {
                if seenIds.insert(song.id).inserted {
                    pickedItems.append(.song(SongItem(entity: song)))
                }
            }

            // E. If we still need more songs to reach `target` (e.g. user has 6 songs total across 3 artists):
            // Pad with capped, interleaved radio discovery across multiple top artists!
            if pickedItems.count < target {
                let needed = target - pickedItems.count
                let seedCandidates = Array(artistAffinities.prefix(4).compactMap { $0.songs.first })
                if !seedCandidates.isEmpty {
                    let maxPerRadio = max(1, (needed + seedCandidates.count - 1) / seedCandidates.count)
                    var discoveryRadios: [[SongItem]] = []

                    for seed in seedCandidates {
                        if let radio = try? await fetchRadio(videoId: seed.id), !radio.songs.isEmpty {
                            discoveryRadios.append(radio.songs)
                        }
                    }

                    // Interleave discovery songs across the different artist radios
                    for slot in 0..<maxPerRadio {
                        for radioSongs in discoveryRadios {
                            guard pickedItems.count < target else { break }
                            if slot < radioSongs.count {
                                let song = radioSongs[slot]
                                if seenIds.insert(song.videoId).inserted {
                                    pickedItems.append(.song(song))
                                }
                            }
                        }
                        if pickedItems.count >= target { break }
                    }

                    // Fallback fill if still needed
                    if pickedItems.count < target {
                        for radioSongs in discoveryRadios {
                            for song in radioSongs {
                                guard pickedItems.count < target else { break }
                                if seenIds.insert(song.videoId).inserted {
                                    pickedItems.append(.song(song))
                                }
                            }
                            if pickedItems.count >= target { break }
                        }
                    }
                }
            }
        }

        guard !pickedItems.isEmpty else {
            return .quickPicks(items: [])
        }

        let chosen = Array(pickedItems.prefix(target))
        let section = HomeSection.quickPicks(items: chosen)
        let entitiesToEnrich = allUserSongs.prefix(target)
        let task = Task { [weak self] in
            guard let self else { return }
            await self.enrichLikedSongs(songs: Array(entitiesToEnrich))
        }
        recordEnrichment(task)
        return section
    }

    func buildKeepListening() async -> HomeSection {
        var items: [YTItem] = []
        var recentSongs: [SongEntity] = []

        if let fetched = try? await db.fetchRecentSongs(days: 30, limit: 8) {
            recentSongs = fetched
            for song in fetched where items.count < 8 {
                items.append(.song(SongItem(entity: song)))
            }
        }

        if let albums = try? await db.fetchAlbums(limit: 5) {
            for album in albums where items.count < 14 {
                items.append(.album(AlbumItem(entity: album)))
            }
        }

        if let artists = try? await db.fetchArtists(limit: 5) {
            for artist in artists where items.count < 20 {
                items.append(.artist(ArtistItem(entity: artist)))
            }
        }

        let section = HomeSection.keepListening(items: items)
        let task = Task { [weak self] in
            guard let self else { return }
            await self.enrichLikedSongs(songs: recentSongs)
        }
        recordEnrichment(task)
        return section
    }

    private func enrichLikedSongs(songs: [SongEntity]) async {
        for entity in songs where entity.title.isEmpty || entity.artistName == nil || entity.artistName?.isEmpty == true {
            guard let metadata = try? await fetchSongMetadata(videoId: entity.id),
                  !metadata.title.isEmpty else { continue }
            let enriched = SongEntity(sync: SyncSong.merging(entity.toSync(), with: metadata))
            try? await db.save(enriched)
        }
    }

    // MARK: - Phase 2: API-based sections (load in background)

    func buildAccountPlaylists() async -> HomeSection {
        guard await isLoggedIn() else { return .accountPlaylists(items: []) }
        do {
            let json = try await innerTube.browse(browseId: "FEmusic_liked_playlists")
            let playlists = LibraryBrowseParser.parsePlaylists(from: json)
            let items = playlists.map {
                YTItem.playlist(PlaylistItem(
                    id: $0.browseId, title: $0.title,
                    author: nil, thumbnailUrl: $0.thumbnailUrl,
                    songCount: $0.songCount
                ))
            }
            return .accountPlaylists(items: items)
        } catch {
            return .accountPlaylists(items: [])
        }
    }

    func buildDailyDiscover() async -> HomeSection {
        guard await isLoggedIn() else { return .dailyDiscover(items: []) }
        guard let likedSongs = try? await db.fetchLikedSongs(), !likedSongs.isEmpty else {
            return .dailyDiscover(items: [])
        }

        let seeds = likedSongs.shuffled().prefix(3)
        var seenIds = Set<String>()
        var discovered: [YTItem] = []

        for song in seeds {
            guard discovered.count < 10 else { break }
            guard let radio = try? await fetchRadio(videoId: song.id),
                  !radio.songs.isEmpty else { continue }
            let related = radio.songs.map { YTItem.song($0) }
            for item in related {
                if let videoId = item.videoId, !seenIds.contains(videoId) {
                    seenIds.insert(videoId)
                    discovered.append(item)
                }
                if discovered.count >= 10 { break }
            }
        }

        return .dailyDiscover(items: discovered)
    }

    func buildSimilarRecommendations() async -> [HomeSection] {
        guard await isLoggedIn() else { return [] }
        guard let topArtists = try? await db.fetchArtists(limit: 3), !topArtists.isEmpty else {
            return []
        }

        var sections: [HomeSection] = []
        for artist in topArtists.prefix(3) {
            guard sections.count < 3 else { break }
            guard let related = try? await innerTube.browse(browseId: artist.id),
                  let items = parseRelatedItems(from: related), !items.isEmpty else { continue }
            let title = String(
                format: NSLocalizedString("Similar to %@", comment: "Similar artist section title"),
                artist.name
            )
            sections.append(.similarRecommendation(items: items, title: title))
        }
        return sections
    }

    func buildFromTheCommunity() async -> HomeSection {
        guard await isLoggedIn() else { return .fromTheCommunity(items: []) }
        guard let topArtists = try? await db.fetchArtists(limit: 3), !topArtists.isEmpty else {
            return .fromTheCommunity(items: [])
        }

        var seenIds = Set<String>()
        var communityPlaylists: [YTItem] = []

        for artist in topArtists {
            guard communityPlaylists.count < 5 else { break }
            guard let json = try? await innerTube.browse(browseId: artist.id) else { continue }
            let playlists = LibraryBrowseParser.extractCommunityPlaylists(from: json)
            for playlist in playlists {
                let pid = LibraryBrowseParser.normalizePlaylistId(playlist.browseId)
                guard !seenIds.contains(pid) else { continue }
                seenIds.insert(pid)
                communityPlaylists.append(.playlist(PlaylistItem(
                    id: pid, title: playlist.title,
                    author: nil, thumbnailUrl: playlist.thumbnailUrl,
                    songCount: playlist.songCount
                )))
                if communityPlaylists.count >= 5 { break }
            }
        }

        return .fromTheCommunity(items: communityPlaylists)
    }

    // MARK: - Helpers

    /// Tracks a background enrichment task so `drainEnrichments()` can
    /// wait for it to complete.
    private func recordEnrichment(_ task: Task<Void, Never>) {
        enrichmentTasks.append(task)
        Task { [weak self] in
            await task.value
            await self?.removeEnrichment(task)
        }
    }

    private func removeEnrichment(_ task: Task<Void, Never>) {
        enrichmentTasks.removeAll { $0 == task }
    }

    /// Awaits all in-flight background enrichment tasks. Use this before
    /// re-reading derived state so the next query sees freshly-saved data.
    func drainEnrichments() async {
        let tasks = enrichmentTasks
        for task in tasks { await task.value }
    }

    private func fetchSongMetadata(videoId: String) async throws -> SongMetadata? {
        let json: [String: Any]
        do {
            json = try await innerTube.player(videoId: videoId)
        } catch {
            return nil
        }
        guard let videoDetails = json["videoDetails"] as? [String: Any] else { return nil }
        let title = videoDetails["title"] as? String ?? ""
        let author = videoDetails["author"] as? String
        let lengthSeconds = videoDetails["lengthSeconds"] as? String
        let duration = lengthSeconds.flatMap { Int($0) } ?? 0
        var thumbnailUrl: String?
        if let thumbs = videoDetails["thumbnail"] as? [String: Any],
           let list = thumbs["thumbnails"] as? [[String: Any]] {
            thumbnailUrl = list.last?["url"] as? String
        }
        guard !title.isEmpty else { return nil }
        return SongMetadata(title: title, artistName: author, thumbnailUrl: thumbnailUrl, duration: duration, albumName: nil)
    }

    private func isLoggedIn() async -> Bool {
        return false
    }

    func fetchRadio(videoId: String) async throws -> (songs: [SongItem], currentIndex: Int) {
        try await fetchRadio(videoId: videoId, options: .default)
    }

    func fetchRadio(videoId: String, options: RadioOptions) async throws -> (songs: [SongItem], currentIndex: Int) {
        let playlistId = "RDAMVM\(videoId)"
        let panel: PlaylistPanel
        if let json = try? await innerTube.nextRadio(videoId: videoId, playlistId: playlistId),
           let extracted = try? extractPlaylistPanel(from: json) {
            panel = extracted
        } else {
            // Fallback: ask `next` with just `videoId` and resolve its automix endpoint.
            let seedJson = try await innerTube.next(videoId: videoId)
            panel = try extractPlaylistPanel(from: seedJson)
        }
        var songs: [(SongItem, Bool)] = []
        for entry in panel.contents {
            guard songs.count < 50 else { break }
            if let renderer = entry["playlistPanelVideoRenderer"] as? [String: Any],
               let song = parsePlaylistPanelVideoRenderer(renderer) {
                songs.append((song, renderer["selected"] as? Bool ?? false))
            }
        }
        var resultSongs = songs.map(\.0)
        if let automixItems = await tryResolveAutomix(from: panel) {
            let deduped = automixItems.filter { a in !resultSongs.contains(where: { $0.videoId == a.videoId }) }
            resultSongs += deduped
        }
        guard !resultSongs.isEmpty else { throw NSError(domain: "fetchRadio", code: 1, userInfo: [:]) }
        let currentIndex = songs.firstIndex(where: { $0.1 }) ?? 0
        switch options.style {
        case .similar:
            break
        case .variety:
            if resultSongs.count > 2 {
                let head = Array(resultSongs.prefix(2))
                let tail = Array(resultSongs.dropFirst(2)).shuffled()
                resultSongs = head + tail
            }
        case .deepCuts:
            if resultSongs.count > 5 {
                resultSongs = Array(resultSongs.dropFirst(3))
            }
        }
        if !options.allowExplicit {
            resultSongs = resultSongs.filter { !$0.isExplicit }
        }
        resultSongs = Array(resultSongs.prefix(max(1, options.limit)))
        guard !resultSongs.isEmpty else { throw NSError(domain: "fetchRadio", code: 1, userInfo: [:]) }
        let clampedIndex = min(currentIndex, resultSongs.count - 1)
        return (resultSongs, clampedIndex)
    }

    private struct PlaylistPanel { let contents: [[String: Any]] }

    private func extractPlaylistPanel(from json: [String: Any]) throws -> PlaylistPanel {
        guard let contents = json["contents"] as? [String: Any],
              let singleColumn = contents["singleColumnMusicWatchNextResultsRenderer"] as? [String: Any],
              let tabbed = singleColumn["tabbedRenderer"] as? [String: Any],
              let watchNext = tabbed["watchNextTabbedResultsRenderer"] as? [String: Any],
              let tabs = watchNext["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let content = tabRenderer["content"] as? [String: Any],
              let queueRenderer = content["musicQueueRenderer"] as? [String: Any],
              let queueContent = queueRenderer["content"] as? [String: Any],
              let playlistPanel = queueContent["playlistPanelRenderer"] as? [String: Any],
              let panelContents = playlistPanel["contents"] as? [[String: Any]] else {
            throw NSError(domain: "fetchRadio", code: 2, userInfo: [:])
        }
        return PlaylistPanel(contents: panelContents)
    }

    private func tryResolveAutomix(from panel: PlaylistPanel) async -> [SongItem]? {
        guard let lastEntry = panel.contents.last,
              let automix = lastEntry["automixPreviewVideoRenderer"] as? [String: Any],
              let content = automix["content"] as? [String: Any],
              let autoRenderer = content["automixPlaylistVideoRenderer"] as? [String: Any],
              let navEndpoint = autoRenderer["navigationEndpoint"] as? [String: Any],
              let watchPlaylist = navEndpoint["watchPlaylistEndpoint"] as? [String: Any],
              let playlistId = watchPlaylist["playlistId"] as? String else { return nil }
        let autoVideoId = watchPlaylist["videoId"] as? String
        let params = watchPlaylist["params"] as? String
        guard let autoJson = try? await innerTube.nextRadio(videoId: autoVideoId, playlistId: playlistId, params: params),
              let autoPanel = try? extractPlaylistPanel(from: autoJson) else { return nil }
        var songs: [SongItem] = []
        for entry in autoPanel.contents {
            guard songs.count < 50 else { break }
            if let renderer = entry["playlistPanelVideoRenderer"] as? [String: Any],
               let song = parsePlaylistPanelVideoRenderer(renderer) { songs.append(song) }
        }
        return songs.isEmpty ? nil : songs
    }

    private func parsePlaylistPanelVideoRenderer(_ renderer: [String: Any]) -> SongItem? {
        guard let vid = renderer["videoId"] as? String else { return nil }
        let title = InnerTubeJSON.runsText(renderer["title"] as? [String: Any]) ?? "Unknown"
        let bylineRuns = InnerTubeJSON.rawRuns(renderer["longBylineText"] as? [String: Any] ?? renderer["shortBylineText"] as? [String: Any])
        let artists = parseArtists(from: bylineRuns)
        let thumbnail = InnerTubeJSON.nestedThumbnailURL(renderer)
        let duration = DurationFormat.parseRendererDuration(renderer)
        return SongItem(
            videoId: vid, title: title, artists: artists, duration: duration,
            thumbnailUrl: thumbnail, isExplicit: false, musicVideoType: VideoAvailability.rowMusicVideoType(renderer)
        )
    }

    private func parseArtists(from bylineRuns: [[String: Any]]) -> [YTArtist] {
        ArtistCredits.parse(runs: bylineRuns).map { YTArtist(name: $0.name, id: $0.browseId) }
    }

    private func parseRelatedItems(from json: [String: Any]) -> [YTItem]? {
        guard let sections = BrowseLens.browseSections(json) else { return nil }

        var items: [YTItem] = []
        for section in sections {
            guard let shelf = section["musicShelfRenderer"] as? [String: Any],
                  let contents = shelf["contents"] as? [[String: Any]] else { continue }
            for entry in contents {
                if items.count >= 10 { break }
                if let renderer = entry["musicResponsiveListItemRenderer"] as? [String: Any] {
                    if let song = SongItem.from(renderer) {
                        items.append(.song(song))
                    }
                }
            }
        }
        return items.isEmpty ? nil : items
    }
}

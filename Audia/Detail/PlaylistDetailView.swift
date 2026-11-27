//
//  PlaylistDetailView.swift
//  Audia
//

import SwiftUI
import PhotosUI
import GRDB

// MARK: - View Model

@MainActor
@Observable
final class PlaylistDetailViewModel {
    let playlistId: String
    var playlist: PlaylistDetailInfo?
    var isLoading = true
    var error: Error?

    let autoRoute: AutoPlaylistRoute?
    var autoSongSort: LibrarySongSort = .recentlyAdded
    var autoTopPeriod: TopPeriod = .allTime

    init(playlistId: String) {
        self.playlistId = playlistId
        self.autoRoute = nil
    }

    init(autoPlaylistRoute: AutoPlaylistRoute) {
        self.playlistId = ""
        self.autoRoute = autoPlaylistRoute
    }

    /// Fetches every playlist page from InnerTube and parses the response.
    /// Prependes "VL" to the playlistId if not already present (required by the browse endpoint).
    func load(silent: Bool = false) async {
        if let route = autoRoute {
            await loadAutoPlaylist(route: route, silent: silent)
            return
        }

        if !silent || playlist == nil {
            isLoading = true
        }
        error = nil

        // Check if this playlist already has local cached data in SQLite
        if let entity = try? await DatabaseService.shared.fetchOne(PlaylistEntity.self, key: playlistId) {
            await loadLocalPlaylist(entity: entity)
            if (entity.browseId == nil || !entity.isAutoSync) && (playlist?.songs.isEmpty == false) {
                return
            }
        }

        do {
            let browseId = playlistId.hasPrefix("VL") ? playlistId : "VL\(playlistId)"
            let (firstPage, rows) = try await SyncBridge.playlistDetail.fetchPlaylistRows(playlistId: playlistId)
            let parsed = Self.parsePlaylistDetail(firstPage: firstPage, rows: rows, playlistId: playlistId)

            // Persist songs to the song table so they become searchable in the library
            let pid = playlistId
            let songs = parsed.songs
            let title = parsed.title
            try await DatabaseService.shared.write { db in
                let existing = try PlaylistEntity.fetchOne(db, key: pid)
                let entity = PlaylistEntity.merging(
                    existing: existing,
                    id: pid,
                    browseId: browseId,
                    name: title,
                    remoteSongCount: songs.count,
                    thumbnailUrl: parsed.thumbnailUrl
                )
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

            playlist = parsed
            isLoading = false
        } catch {
            if (playlist?.songs.count ?? 0) > 0 {
                isLoading = false
                return
            }
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                isLoading = false
                return
            }
            if let entity = try? await DatabaseService.shared.fetchOne(PlaylistEntity.self, key: playlistId) {
                await loadLocalPlaylist(entity: entity)
                if (playlist?.songs.count ?? 0) > 0 {
                    isLoading = false
                    return
                }
            }
            self.error = error
            isLoading = false
        }
    }

    private func loadLocalPlaylist(entity: PlaylistEntity) async {
        do {
            // Fetch songs from playlist_song_map joined with song table
            let songs = try await DatabaseService.shared.fetchAll(
                SongEntity.self,
                sql: """
                    SELECT s.* FROM song s
                    INNER JOIN playlist_song_map m ON m.song_id = s.id
                    WHERE m.playlist_id = ?
                    ORDER BY m.position, m.id
                    """,
                arguments: [playlistId]
            )
            let songItems = songs.toSongItems()
            let totalDuration = songItems.reduce(0) { $0 + $1.duration }
            playlist = PlaylistDetailInfo(
                title: entity.name,
                authorName: nil,
                authorBrowseId: nil,
                authorAvatarUrl: nil,
                descriptionText: nil,
                songCount: songItems.count,
                duration: totalDuration,
                thumbnailUrl: entity.thumbnailUrl,
                playlistId: playlistId,
                songs: songItems
            )
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    private func loadAutoPlaylist(route: AutoPlaylistRoute, silent: Bool = false) async {
        if !silent || playlist == nil {
            isLoading = true
        }
        error = nil
        do {
            let entities: [SongEntity]
            let title: String
            switch route {
            case .likedSongs:
                title = "Liked Songs"
                entities = try await DatabaseService.shared.fetchAllLikedSongs(sort: autoSongSort)
            case .topSongs(let limit):
                title = "My Top \(limit)"
                await SyncBridge.mutations.repairOrphanSongs()
                if autoTopPeriod == .allTime {
                    entities = try await DatabaseService.shared.fetchTopSongs(limit: limit)
                } else {
                    entities = try await DatabaseService.shared.fetchTopSongs(limit: limit, from: autoTopPeriod.dateFrom, to: Date())
                }
            }
            var songs = entities.toSongItems()

            // Resolve missing durations in background
            let emptyDurationIds = songs.filter { $0.duration <= 0 }.map { $0.videoId }
            if !emptyDurationIds.isEmpty {
                await withTaskGroup(of: (String, Int).self) { group in
                    for videoId in emptyDurationIds {
                        guard !DurationCache.isPending(videoId) else { continue }
                        if let cached = DurationCache.get(videoId), cached > 0 { continue }
                        group.addTask {
                            let duration = await InnerTubeClient.audiaShared.resolveDuration(videoId: videoId) ?? 0
                            return (videoId, duration)
                        }
                    }
                }
                for i in songs.indices where songs[i].duration <= 0 {
                    if let cached = DurationCache.get(songs[i].videoId), cached > 0 {
                        songs[i].duration = cached
                    }
                }
            }

            let totalDuration = songs.reduce(0) { $0 + $1.duration }

            playlist = PlaylistDetailInfo(
                title: title,
                authorName: nil,
                authorBrowseId: nil,
                authorAvatarUrl: nil,
                descriptionText: nil,
                songCount: songs.count,
                duration: totalDuration,
                thumbnailUrl: nil,
                playlistId: "",
                songs: songs
            )
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }
}

// MARK: - Parser

extension PlaylistDetailViewModel {
    /// Parses InnerTube browse JSON into a PlaylistDetailInfo.
    /// Extracts header metadata (title, author, song count, duration, thumbnail, description)
    /// from musicDetailHeaderRenderer on the first page, and songs from the
    /// track rows collected across every continuation page.
    /// Branch count is inherent to tolerant InnerTube JSON parsing.
    static func parsePlaylistDetail(firstPage json: [String: Any], rows: [[String: Any]], playlistId: String) -> PlaylistDetailInfo {
        var title = "Unknown Playlist"
        var authorName: String?
        var authorBrowseId: String?
        var authorAvatarUrl: String?
        var descriptionText: String?
        var songCount = 0
        var duration = 0
        var thumbnailUrl: String?
        var songs: [SongItem] = []

        let firstTabSectionInner = BrowseLens.firstSectionItem(json)
        let firstTabSection = firstTabSectionInner
            .flatMap { $0["itemSectionRenderer"] as? [String: Any] }
            .flatMap { ($0["contents"] as? [[String: Any]])?.first }
            ?? firstTabSectionInner

        let headerRenderer: [String: Any]? =
            firstTabSection?["musicResponsiveHeaderRenderer"] as? [String: Any]
            ?? (firstTabSection?["musicEditablePlaylistDetailHeaderRenderer"] as? NSDictionary)
                .flatMap { ($0 as? [String: Any]) }
                .flatMap { ($0["header"] as? NSDictionary) as? [String: Any] }
                .flatMap {
                    ($0["musicDetailHeaderRenderer"] as? [String: Any])
                        ?? $0["musicResponsiveHeaderRenderer"] as? [String: Any]
                }
            ?? (json["header"] as? [String: Any]).flatMap {
                $0["musicDetailHeaderRenderer"] as? [String: Any]
                ?? $0["musicResponsiveHeaderRenderer"] as? [String: Any]
            }

        if let detailHeader = headerRenderer {
            title = InnerTubeJSON.runsText(detailHeader["title"] as? [String: Any]) ?? title
            thumbnailUrl = InnerTubeJSON.musicThumbnailURL(detailHeader)

            descriptionText = detailHeader["description"]
                .flatMap { $0 as? [String: Any] }
                .flatMap { InnerTubeJSON.runsText($0) }

            // Author from straplineTextOne
            if let strapline = detailHeader["straplineTextOne"] as? [String: Any],
               let runs = strapline["runs"] as? [[String: Any]],
               let firstRun = runs.first,
               let text = firstRun["text"] as? String {
                authorName = text
                authorBrowseId = (firstRun["navigationEndpoint"] as? [String: Any])
                    .flatMap { $0["browseEndpoint"] as? [String: Any] }
                    .flatMap { $0["browseId"] as? String }
            }

            // Author from facepile (editable/self-authored playlists)
            if authorName == nil,
               let facepile = detailHeader["facepile"] as? [String: Any],
               let stack = facepile["avatarStackViewModel"] as? [String: Any] {
                authorName = (stack["text"] as? [String: Any])?["content"] as? String
                authorBrowseId = (stack["rendererContext"] as? [String: Any])
                    .flatMap { $0["commandContext"] as? [String: Any] }
                    .flatMap { $0["onTap"] as? [String: Any] }
                    .flatMap { $0["innertubeCommand"] as? [String: Any] }
                    .flatMap { $0["browseEndpoint"] as? [String: Any] }
                    .flatMap { $0["browseId"] as? String }
                if let avatars = stack["avatars"] as? [[String: Any]],
                   let firstAvatar = avatars.first,
                   let vm = firstAvatar["avatarViewModel"] as? [String: Any],
                   let image = vm["image"] as? [String: Any],
                   let sources = image["sources"] as? [[String: Any]],
                   let firstSource = sources.first,
                   let url = firstSource["url"] as? String {
                    authorAvatarUrl = url
                } else {
                    Log.parser.debug("facepile found but failed to extract avatar URL")
                    Log.parser.debug("facepile stack keys: \(stack.keys)")
                    if let avatars = stack["avatars"] {
                        Log.parser.debug("avatars type: \(type(of: avatars))")
                    }
                }
            }

            // Author from subtitle runs (fallback)
            if authorName == nil,
               let subtitle = detailHeader["subtitle"] as? [String: Any],
               let runs = subtitle["runs"] as? [[String: Any]] {
                for run in runs {
                    guard let text = run["text"] as? String else { continue }
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || trimmed == "•" { continue }
                    if let navEndpoint = run["navigationEndpoint"] as? [String: Any],
                       let bind = navEndpoint["browseEndpoint"] as? [String: Any],
                       let bid = bind["browseId"] as? String {
                        authorName = trimmed; authorBrowseId = bid; break
                    } else if authorName == nil {
                        authorName = trimmed
                    }
                }
            }

            // Song count / duration from secondSubtitle
            if let secondSubtitle = detailHeader["secondSubtitle"] as? [String: Any],
               let runs = secondSubtitle["runs"] as? [[String: Any]] {
                for run in runs {
                    guard let text = run["text"] as? String else { continue }
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    if trimmed.contains("song") || trimmed.contains("Song") ||
                       trimmed.contains("track") || trimmed.contains("Track") ||
                       trimmed.contains("video") || trimmed.contains("Video") {
                        if let count = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init).first {
                            songCount = count
                        }
                    } else if trimmed.contains(":") {
                        duration = DurationFormat.parseClock(trimmed) ?? 0
                    } else {
                        let lower = trimmed.lowercased()
                        if lower.hasSuffix("min") || lower.hasSuffix("mins") || lower.hasSuffix("minute") || lower.hasSuffix("minutes") {
                            let nums = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
                            if let minutes = nums.first {
                                duration = minutes * 60
                            }
                        } else if lower.hasSuffix("hour") || lower.hasSuffix("hours") || lower.hasSuffix("hr") || lower.hasSuffix("hrs") {
                            let nums = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
                            if let hours = nums.first {
                                duration = hours * 3600
                            }
                        }
                    }
                }
            }
        }

        // --- Songs ---
        // Rows were collected across every continuation page by the caller;
        // continuation markers are already stripped.
        for itemDict in rows {
            if let renderer = itemDict["musicResponsiveListItemRenderer"] as? [String: Any],
               let song = SongItem.from(renderer) {
                songs.append(song)
            }
        }

        // Use actual song data for total duration (more precise than header)
        if songCount == 0 { songCount = songs.count }
        let songDuration = songs.reduce(0) { $0 + $1.duration }
        if songDuration > 0 {
            duration = songDuration
        }

        return PlaylistDetailInfo(
            title: title,
            authorName: authorName,
            authorBrowseId: authorBrowseId,
            authorAvatarUrl: authorAvatarUrl,
            descriptionText: descriptionText,
            songCount: songCount,
            duration: duration,
            thumbnailUrl: thumbnailUrl,
            playlistId: playlistId,
            songs: songs
        )
    }
}

// MARK: - View

struct PlaylistDetailView: View {
    let playlistId: String
    @State private var viewModel: PlaylistDetailViewModel
    @State private var playlistEntity: PlaylistEntity?
    @State private var showAddSongs = false
    @State private var showRenameAlert = false
    @State private var showDeleteAlert = false
    @State private var showCoverPicker = false
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var renameText = ""
    @State private var pendingRoute: DetailRoute?
    @ObservedObject private var likeStore = LikeStore.shared

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var barProgress: CGFloat = 0
    private static let barFadeStart: CGFloat = 160
    private static let barFadeDistance: CGFloat = 60
    private static let iPadBannerHeight: CGFloat = 400

    init(playlistId: String) {
        self.playlistId = playlistId
        _viewModel = State(initialValue: PlaylistDetailViewModel(playlistId: playlistId))
    }

    init(autoPlaylistRoute: AutoPlaylistRoute) {
        self.playlistId = ""
        _viewModel = State(initialValue: PlaylistDetailViewModel(autoPlaylistRoute: autoPlaylistRoute))
    }

    var isEditable: Bool {
        guard viewModel.autoRoute == nil, let entity = playlistEntity else { return false }
        return entity.isEditable || entity.bookmarkedAt != nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                DetailStateContainer(
                    isLoading: viewModel.isLoading,
                    error: viewModel.error,
                    data: viewModel.playlist,
                    noun: "playlist",
                    emptyIcon: "music.note.list"
                ) { playlist in
                    playlistContent(for: playlist)
                }
            }
            .refreshable {
                await viewModel.load()
            }
            .scrollDisabled(viewModel.isLoading || viewModel.error != nil || viewModel.playlist == nil)
            .miniPlayerTracksScroll()
            .onScrollGeometryChange(
                for: CGFloat.self,
                of: {
                    let raw = min(max(($0.contentOffset.y - Self.barFadeStart) / Self.barFadeDistance, 0), 1)
                    return (raw * 40).rounded() / 40
                },
                action: { _, newProgress in
                    if barProgress != newProgress {
                        barProgress = newProgress
                    }
                }
            )
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)

            customTopBar
        }
        .sheet(isPresented: $showAddSongs) {
            AddSongToPlaylistView(playlistId: playlistId) {
                await viewModel.load()
            }
        }
        .photosPicker(isPresented: $showCoverPicker, selection: $selectedCoverItem, matching: .images)
        .onChange(of: selectedCoverItem) { _, newItem in
            guard let newItem else { return }
            selectedCoverItem = nil
            Task { await applyCustomCover(from: newItem) }
        }
        .task {
            await fetchEntity()
            if viewModel.autoRoute != nil || viewModel.isLoading {
                await viewModel.load()
                await fetchEntity()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryPlaylistsUpdated)) { notification in
            if let updatedId = notification.object as? String, updatedId != playlistId {
                return
            }
            Task {
                await fetchEntity()
                await viewModel.load(silent: true)
            }
        }
        .onAppear {
            if viewModel.autoRoute == .likedSongs {
                Task { await viewModel.load(silent: true) }
            }
        }
        .onChange(of: likeStore.liked) { _, _ in
            if viewModel.autoRoute == .likedSongs {
                Task { await viewModel.load(silent: true) }
            }
        }
        .detailRouteSheet(item: $pendingRoute)
        .alert("Delete Playlist", isPresented: $showDeleteAlert) {
            Button("Delete") {
                let targetId = playlistId.isEmpty ? (viewModel.playlist?.playlistId ?? "") : playlistId
                let coverUrl = playlistEntity?.thumbnailUrl
                Task {
                    PlaylistCoverStorage.delete(urlString: coverUrl)
                    try? await DatabaseService.shared.deletePlaylist(id: targetId)
                    let auth = await InnerTubeClient.audiaShared.currentAuth()
                    if !auth.cookies.isEmpty {
                        try? await SyncBridge.mutations.deletePlaylist(playlistId: targetId)
                    }
                    NotificationCenter.default.post(name: .libraryPlaylistsUpdated, object: nil)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this playlist?")
        }
        .textPrompt(
            "Rename Playlist",
            isPresented: $showRenameAlert,
            placeholder: "Playlist name",
            text: $renameText,
            okTitle: "Rename"
        ) {
            let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != (viewModel.playlist?.title ?? "") else { return }
            Task {
                let pid = viewModel.playlist?.playlistId ?? playlistId
                try? await DatabaseService.shared.write { db in
                    try db.execute(sql: "UPDATE playlist SET name = ? WHERE id = ?", arguments: [name, pid])
                }
                try? await SyncBridge.mutations.renamePlaylist(
                    playlistId: pid,
                    newName: name
                )
                NotificationCenter.default.post(name: .libraryPlaylistsUpdated, object: pid)
                await viewModel.load(silent: true)
            }
        }
        .audiaScreenBackground()
    }

    private var customTopBar: some View {
        HStack(spacing: 8) {
            topBarBackButton

            Spacer(minLength: 0)

            if let playlist = viewModel.playlist {
                Text(playlist.title)
                    .font(.satoshi(.headline))
                    .foregroundStyle(AudiaTheme.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .audiaGlassCapsule(isInteractive: false)
                    .opacity(barProgress)
            }

            Spacer(minLength: 0)

            topBarOptionsMenu
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: AudiaTheme.background, location: 0.0),
                    .init(color: AudiaTheme.background.opacity(0.85), location: 0.55),
                    .init(color: AudiaTheme.background.opacity(0.0), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 110)
            .opacity(barProgress)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }

    private var topBarBackButton: some View {
        topBarCircleButton(
            systemName: "chevron.left",
            accessibilityLabel: "Back",
            action: { dismiss() }
        )
    }

    private var topBarOptionsMenu: some View {
        Group {
            if let playlist = viewModel.playlist {
                Menu {
                    PlaylistMenuActionsView(
                        playlist: playlist,
                        onEdit: {
                            renameText = playlist.title
                            showRenameAlert = true
                        },
                        onChangeCover: isEditable ? {
                            showCoverPicker = true
                        } : nil,
                        onDelete: viewModel.autoRoute == nil ? {
                            showDeleteAlert = true
                        } : nil,
                        onAddSongs: isEditable ? {
                            showAddSongs = true
                        } : nil
                    )
                } label: {
                    ZStack {
                        Image(systemName: "ellipsis")
                            .font(.satoshi(size: 16, weight: .semibold))
                            .foregroundStyle(AudiaTheme.textPrimary)
                    }
                    .frame(width: 40, height: 40)
                    .audiaGlassCircle(isActive: false)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
            }
        }
    }

    private func topBarCircleButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action, label: {
            ZStack {
                Image(systemName: systemName)
                    .font(.satoshi(size: 16, weight: .semibold))
                    .foregroundStyle(AudiaTheme.textPrimary)
            }
            .frame(width: 40, height: 40)
            .audiaGlassCircle(isActive: false)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        })
        .buttonStyle(BouncyScaleButtonStyle(scale: 0.92))
        .accessibilityLabel(accessibilityLabel)
    }

    private func fetchEntity() async {
        guard !playlistId.isEmpty else { return }
        playlistEntity = try? await DatabaseService.shared.fetchOne(PlaylistEntity.self, key: playlistId)
    }

    private func secondaryActionsView(for playlist: PlaylistDetailInfo) -> AnyView? {
        let showBookmark = viewModel.autoRoute == nil && !isEditable
        let showDownload = !playlist.songs.isEmpty
        guard showBookmark || showDownload else { return nil }

        let isSaved = playlistEntity?.bookmarkedAt != nil
        return AnyView(
            HStack(spacing: 10) {
                if showBookmark {
                    Button {
                        Haptics.light()
                        Task { await toggleBookmark(for: playlist) }
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.satoshi(size: 16, weight: .semibold))
                            .foregroundStyle(isSaved ? AudiaTheme.primary : AudiaTheme.textPrimary)
                            .frame(width: 40, height: 40)
                            .contentShape(Circle())
                            .audiaGlassCircle()
                    }
                    .buttonStyle(BouncyScaleButtonStyle(scale: 0.90))
                    .accessibilityLabel(isSaved ? "Remove from Library" : "Save to Library")
                }

                if showDownload {
                    PlaylistDownloadAllButton(songs: playlist.songs)
                }
            }
        )
    }

    private func toggleBookmark(for playlist: PlaylistDetailInfo) async {
        guard !playlistId.isEmpty else { return }
        let newDate: Date? = playlistEntity?.bookmarkedAt == nil ? Date() : nil
        let pid = playlistId
        let browseId = pid.hasPrefix("VL") ? pid : "VL\(pid)"
        try? await DatabaseService.shared.write { db in
            if var existing = try PlaylistEntity.fetchOne(db, key: pid) {
                existing.bookmarkedAt = newDate
                try existing.save(db)
            } else {
                let entity = PlaylistEntity(
                    id: pid,
                    browseId: browseId,
                    name: playlist.title,
                    thumbnailUrl: playlist.thumbnailUrl,
                    isEditable: false,
                    bookmarkedAt: newDate ?? Date(),
                    remoteSongCount: playlist.songs.count,
                    isAutoSync: false
                )
                try entity.save(db)
            }
        }
        await fetchEntity()
        NotificationCenter.default.post(name: .libraryPlaylistsUpdated, object: pid)
    }

    @ViewBuilder
    private func playlistContent(for playlist: PlaylistDetailInfo) -> some View {
        LazyVStack(spacing: 0) {
            header(for: playlist)

            VStack(alignment: .leading, spacing: 14) {
                // Author row & metadata
                HStack(spacing: 8) {
                    if let authorName = playlist.authorName {
                        if let authorId = playlist.authorBrowseId {
                            NavigationLink(value: DetailRoute.artist(browseId: authorId)) {
                                authorRow(name: authorName, avatarUrl: playlist.authorAvatarUrl)
                            }
                            .buttonStyle(.plain)
                        } else {
                            authorRow(name: authorName, avatarUrl: playlist.authorAvatarUrl)
                        }

                        Text("•")
                            .font(.satoshi(.subheadline, weight: .medium))
                            .foregroundStyle(AudiaTheme.textMuted)
                    }

                    let metaParts = metaStrings(for: playlist)
                    if !metaParts.isEmpty {
                        Text(metaParts.joined(separator: " • "))
                            .font(.satoshi(.subheadline, weight: .medium))
                            .foregroundStyle(AudiaTheme.textSecondary)
                    }
                }

                if let desc = playlist.descriptionText, !desc.isEmpty {
                    Text(desc)
                        .font(.satoshi(.subheadline))
                        .foregroundStyle(AudiaTheme.textSecondary)
                        .lineLimit(3)
                }

                HStack(alignment: .center, spacing: 8) {
                    PlaybackControlsView(
                        compactPlay: viewModel.autoRoute != nil,
                        horizontalPadding: 0,
                        onPlay: { playAll(playlist) },
                        onShuffle: { shufflePlay(playlist) },
                        secondaryActions: secondaryActionsView(for: playlist)
                    )

                    if viewModel.autoRoute != nil {
                        Spacer(minLength: 0)
                        sortControls
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontalSizeClass == .regular ? 32 : DesignTokens.screenHPadding)
            .padding(.top, 8)
            .padding(.bottom, 16)

            if playlist.songs.isEmpty {
                VStack(spacing: 8) {
                    Spacer().frame(height: 40)
                    Text("No songs found")
                        .font(.satoshi(.subheadline))
                        .foregroundColor(.secondary)
                }
            } else {
                songList(for: playlist)
            }
        }
        .appBottomClearance()
    }

    @ViewBuilder
    private func header(for playlist: PlaylistDetailInfo) -> some View {
        if horizontalSizeClass == .regular {
            GeometryReader { proxy in
                headerBanner(
                    for: playlist,
                    size: CGSize(width: proxy.size.width, height: Self.iPadBannerHeight)
                )
            }
            .frame(height: Self.iPadBannerHeight)
            .accessibilityElement(children: .contain)
        } else {
            // iPhone: full-width square banner.
            GeometryReader { proxy in
                headerBanner(for: playlist, size: proxy.size)
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityElement(children: .contain)
        }
    }

    private func headerBanner(for playlist: PlaylistDetailInfo, size: CGSize) -> some View {
        ZStack(alignment: .bottomLeading) {
            AudiaTheme.background

            bannerArtwork(for: playlist, size: size)
                .frame(width: size.width, height: size.height)
                .clipped()
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0.0),
                            .init(color: .white, location: 0.65),
                            .init(color: .white.opacity(0.4), location: 0.88),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.35),
                    .init(color: AudiaTheme.background.opacity(0.35), location: 0.60),
                    .init(color: AudiaTheme.background.opacity(0.85), location: 0.88),
                    .init(color: AudiaTheme.background, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.title)
                    .font(.satoshi(size: 38, weight: .bold))
                    .foregroundStyle(AudiaTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .shadow(color: AudiaTheme.background.opacity(0.4), radius: 6, y: 2)
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? 32 : DesignTokens.screenHPadding)
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private func bannerArtwork(for playlist: PlaylistDetailInfo, size: CGSize) -> some View {
        if let autoRoute = viewModel.autoRoute {
            let style: (colors: [Color], icon: String) = {
                switch autoRoute {
                case .likedSongs:
                    return (
                        [Color(red: 0.96, green: 0.24, blue: 0.45), Color(red: 0.56, green: 0.16, blue: 0.65), Color(red: 0.22, green: 0.12, blue: 0.45)],
                        "heart.fill"
                    )
                case .topSongs:
                    return (
                        [Color(red: 0.18, green: 0.45, blue: 0.96), Color(red: 0.42, green: 0.24, blue: 0.88), Color(red: 0.14, green: 0.12, blue: 0.42)],
                        "chart.line.uptrend.xyaxis"
                    )
                }
            }()

            ZStack {
                LinearGradient(
                    colors: style.colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color.white.opacity(0.22), Color.clear],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: size.width * 0.75
                )
                Image(systemName: style.icon)
                    .font(.system(size: min(size.width, size.height) * 0.28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                    .offset(y: -16)
            }
            .frame(width: size.width, height: size.height)
        } else {
            let artworkUrl: String? = {
                if let thumb = playlist.thumbnailUrl, !thumb.isEmpty {
                    return ArtworkURLs.sized(thumb, width: 1200, height: 1200) ?? thumb
                }
                if let first = playlist.songs.compactMap(\.thumbnailUrl).first(where: { !$0.isEmpty }) {
                    return ArtworkURLs.sized(first, width: 1200, height: 1200) ?? first
                }
                return nil
            }()

            if let artworkUrl {
                AsyncImageView(
                    url: artworkUrl,
                    contentMode: .fill
                )
                .frame(width: size.width, height: size.height)
                .clipped()
            } else {
                LinearGradient(
                    colors: [Color.orange.opacity(0.8), Color.purple.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: size.width, height: size.height)
                .overlay(
                    Image(systemName: "music.note.list")
                        .font(.satoshi(size: 64))
                        .foregroundStyle(.white.opacity(0.8))
                )
            }
        }
    }

    @ViewBuilder
    private func authorRow(name: String, avatarUrl: String?) -> some View {
        HStack(spacing: 8) {
            if let avatarUrl {
                AsyncImageView(url: avatarUrl)
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.satoshi(.caption))
                    .foregroundColor(AudiaTheme.textSecondary)
            }
            Text(name)
                .font(.satoshi(.subheadline))
                .fontWeight(.medium)
                .foregroundColor(AudiaTheme.textSecondary)
        }
    }

    @ViewBuilder
    private var sortControls: some View {
        switch viewModel.autoRoute {
        case .likedSongs:
            Picker("Sort", selection: Binding(
                get: { viewModel.autoSongSort },
                set: { viewModel.autoSongSort = $0 }
            )) {
                ForEach(LibrarySongSort.allCases) { sort in
                    Text(sort.displayName).tag(sort)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .onChange(of: viewModel.autoSongSort) {
                Task { await viewModel.load() }
            }
        case .topSongs:
            Picker("Period", selection: Binding(
                get: { viewModel.autoTopPeriod },
                set: { viewModel.autoTopPeriod = $0 }
            )) {
                ForEach(TopPeriod.allCases) { period in
                    Text(period.displayName).tag(period)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .onChange(of: viewModel.autoTopPeriod) {
                Task { await viewModel.load() }
            }
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func songList(for playlist: PlaylistDetailInfo) -> some View {
        ForEach(Array(playlist.songs.enumerated()), id: \.element.videoId) { index, song in
            SongRowView(
                song: song,
                showDownloadButton: true,
                onTap: { playSong(song, in: playlist) },
                onNavigate: { pendingRoute = $0 },
                onRemoveFromPlaylist: isEditable ? {
                    Task { await removeSong(song) }
                } : nil
            )

            if index < playlist.songs.count - 1 {
                Divider()
                    .padding(.leading, 84)
            }
        }
    }

    private func removeSong(_ song: SongItem) async {
        let maps = (try? await DatabaseService.shared.fetchAll(
            PlaylistSongMap.self,
            sql: "SELECT * FROM playlist_song_map WHERE playlist_id = ? AND song_id = ? LIMIT 1",
            arguments: [playlistId, song.videoId]
        )) ?? []
        let setVideoId = maps.first?.setVideoId ?? ""
        try? await SyncBridge.mutations.removeFromPlaylist(playlistId: playlistId, songId: song.videoId, setVideoId: setVideoId)
        try? await DatabaseService.shared.write { db in
            try db.execute(sql: "DELETE FROM playlist_song_map WHERE playlist_id = ? AND song_id = ?", arguments: [playlistId, song.videoId])
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM playlist_song_map WHERE playlist_id = ?", arguments: [playlistId]) ?? 0
            try db.execute(sql: "UPDATE playlist SET remote_song_count = ? WHERE id = ?", arguments: [count, playlistId])
            if let existing = try PlaylistEntity.fetchOne(db, key: playlistId),
               existing.browseId == nil,
               !(existing.thumbnailUrl ?? "").hasPrefix(PlaylistCoverStorage.scheme) {
                let nextThumb = try String.fetchOne(
                    db,
                    sql: """
                        SELECT s.thumbnail_url FROM song s
                        INNER JOIN playlist_song_map m ON m.song_id = s.id
                        WHERE m.playlist_id = ? AND s.thumbnail_url IS NOT NULL AND s.thumbnail_url != ''
                        ORDER BY m.position, m.id LIMIT 1
                        """,
                    arguments: [playlistId]
                )
                try db.execute(sql: "UPDATE playlist SET thumbnail_url = ? WHERE id = ?", arguments: [nextThumb, playlistId])
            }
        }
        NotificationCenter.default.post(name: .libraryPlaylistsUpdated, object: playlistId)
        await fetchEntity()
        await viewModel.load(silent: true)
    }

    private func applyCustomCover(from item: PhotosPickerItem) async {
        guard !playlistId.isEmpty,
              let data = try? await item.loadTransferable(type: Data.self),
              let coverUrl = PlaylistCoverStorage.save(
                  imageData: data,
                  playlistId: playlistId,
                  previousUrl: playlistEntity?.thumbnailUrl
              ) else { return }
        try? await DatabaseService.shared.write { db in
            try db.execute(
                sql: "UPDATE playlist SET thumbnail_url = ? WHERE id = ?",
                arguments: [coverUrl, playlistId]
            )
        }
        NotificationCenter.default.post(name: .libraryPlaylistsUpdated, object: playlistId)
        await fetchEntity()
        await viewModel.load(silent: true)
    }

    // MARK: - Actions

    private func playAll(_ playlist: PlaylistDetailInfo) {
        PlaybackQueue.play(playlist.songs, log: Log.playlistDetail, context: "playAll")
    }

    private func shufflePlay(_ playlist: PlaylistDetailInfo) {
        PlaybackQueue.playShuffled(playlist.songs, log: Log.playlistDetail, context: "shufflePlay")
    }

    private func playSong(_ song: SongItem, in playlist: PlaylistDetailInfo) {
        PlaybackQueue.play(song, in: playlist.songs, log: Log.playlistDetail, context: "playSong")
    }

    // MARK: - Helpers

    /// Builds metadata strings like "50 songs • 3:25:10"
    private func metaStrings(for playlist: PlaylistDetailInfo) -> [String] {
        var parts: [String] = []
        if playlist.songCount > 0 { parts.append("\(playlist.songCount) song\(playlist.songCount != 1 ? "s" : "")") }
        if playlist.duration > 0 { parts.append(playlist.duration.formattedDuration) }
        return parts
    }
}

// MARK: - Add Song to Playlist Sheet

struct AddSongToPlaylistView: View {
    let playlistId: String
    let onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var songs: [SongEntity] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var addingIds = Set<String>()

    private var filteredSongs: [SongEntity] {
        if searchText.isEmpty { return songs }
        let q = searchText.lowercased()
        return songs.filter {
            $0.title.lowercased().contains(q) ||
            ($0.artistName?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(LocalizedStringKey("Loading songs..."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if songs.isEmpty {
                    ContentUnavailableView(
                        "No songs found",
                        systemImage: "music.note",
                        description: Text("Songs you like will appear here")
                    )
                } else {
                    List {
                        ForEach(filteredSongs, id: \.id) { song in
                            HStack(spacing: 12) {
                                AsyncImageView(url: song.thumbnailUrl)
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title)
                                        .font(.satoshi(.subheadline))
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    if let artist = song.artistName {
                                        Text(artist)
                                            .font(.satoshi(.caption))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                if addingIds.contains(song.id) {
                                    ProgressView()
                                } else {
                                    Button("Add") {
                                        Task { await addSong(song) }
                                    }
                                    .font(.satoshi(.subheadline))
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search songs")
                }
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadSongs()
            }
        }
    }

    private func loadSongs() async {
        defer { isLoading = false }
        do {
            // Fetch songs that have actual titles
            songs = try await DatabaseService.shared.fetchAll(
                SongEntity.self,
                sql: "SELECT * FROM song WHERE title != '' ORDER BY create_date DESC LIMIT 200"
            )
        } catch {
            Log.addSong.error("Failed to load songs: \(error)")
        }
    }

    private func addSong(_ song: SongEntity) async {
        addingIds.insert(song.id)
        do {
            try await SyncBridge.mutations.addToPlaylist(playlistId: playlistId, songId: song.id)
            try? await DatabaseService.shared.write { db in
                try db.execute(
                    sql: "UPDATE playlist SET bookmarked_at = ? WHERE id = ?",
                    arguments: [Date(), playlistId]
                )
            }
            NotificationCenter.default.post(name: .libraryPlaylistsUpdated, object: playlistId)
            await onDone()
            dismiss()
        } catch {
            Log.addSong.error("Failed to add song: \(error)")
        }
        addingIds.remove(song.id)
    }
}

/// Liquid Glass download-all button for playlist headers with aggregate progress ring.
private struct PlaylistDownloadAllButton: View {
    let songs: [SongItem]
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var isBatchDownloading = false
    @State private var downloadTask: Task<Void, Never>?

    private var stats: (downloaded: Int, downloading: Bool, progress: Double) {
        guard !songs.isEmpty else { return (0, false, 0) }
        var downloaded = 0
        var active = false
        var totalProgress = 0.0

        for song in songs {
            switch downloadManager.state(for: song.videoId) {
            case .completed:
                downloaded += 1
                totalProgress += 1.0
            case .downloading(let fraction):
                active = true
                totalProgress += min(max(fraction, 0), 1)
            case .notStarted, .failed:
                break
            }
        }
        return (downloaded, active || isBatchDownloading, totalProgress / Double(songs.count))
    }

    var body: some View {
        let s = stats
        let allDownloaded = !songs.isEmpty && s.downloaded == songs.count

        Button {
            Haptics.light()
            if s.downloading {
                downloadTask?.cancel()
                downloadTask = nil
                isBatchDownloading = false
                for song in songs {
                    if case .downloading = downloadManager.state(for: song.videoId) {
                        downloadManager.cancel(videoId: song.videoId)
                    }
                }
                return
            }
            guard !allDownloaded else { return }
            isBatchDownloading = true
            let targets = songs
            downloadTask = Task {
                for song in targets {
                    if Task.isCancelled { break }
                    if !downloadManager.isDownloaded(videoId: song.videoId) {
                        await downloadManager.download(song: song)
                    }
                }
                await MainActor.run {
                    isBatchDownloading = false
                    downloadTask = nil
                }
            }
        } label: {
            ZStack {
                if allDownloaded {
                    Image(systemName: "arrow.down")
                        .font(.satoshi(size: 16, weight: .semibold))
                        .foregroundStyle(AudiaTheme.textSecondary.opacity(0.4))
                } else if s.downloading {
                    Circle()
                        .stroke(Color.primary.opacity(0.16), lineWidth: 2.5)
                        .padding(3)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(s.progress, 0.03), 1)))
                        .stroke(AudiaTheme.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(3)
                        .animation(.easeOut(duration: 0.25), value: s.progress)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AudiaTheme.textPrimary)
                } else {
                    Image(systemName: "arrow.down")
                        .font(.satoshi(size: 16, weight: .semibold))
                        .foregroundStyle(AudiaTheme.textPrimary)
                }
            }
            .frame(width: 40, height: 40)
            .contentShape(Circle())
            .audiaGlassCircle()
        }
        .buttonStyle(BouncyScaleButtonStyle(scale: 0.90))
        .disabled(allDownloaded)
        .accessibilityLabel(s.downloading ? "Stop downloading" : (allDownloaded ? "Playlist downloaded" : "Download all songs"))
    }
}

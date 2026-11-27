//
//  LibraryView.swift
//  Audia
//

import SwiftUI
import GRDB

struct LibraryView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var artists: [ArtistEntity] = []
    @State private var playlists: [PlaylistEntity] = []
    @State private var albums: [AlbumEntity] = []
    @State private var podcasts: [PodcastEntity] = []
    @State private var likedSongCount = 0
    @State private var isLoading = true
    @State private var selectedFilter: LibraryFilter?
    @State private var showCreateDialog = false
    @State private var playlistToDelete: PlaylistEntity?
    @State private var playlistSongCounts: [String: Int] = [:]
    @State private var nowPlaying = NowPlaying.shared

    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var likeStore = LikeStore.shared

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var gridColumns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: count)
    }
    private var autoPlaylists: [AutoPlaylistInfo] {
        [
            AutoPlaylistInfo(id: "liked", title: "Liked", icon: "heart.fill", subtitle: "Your favorite tracks", route: .likedSongs),
            AutoPlaylistInfo(id: "history", title: "History", icon: "clock.arrow.circlepath", subtitle: "Recently played tracks", route: nil, detailRoute: .history),
            AutoPlaylistInfo(id: "downloads", title: "Downloads", icon: "arrow.down.circle.fill",
                             subtitle: downloadsSubtitle, route: nil, detailRoute: .downloads),
            AutoPlaylistInfo(id: "top50", title: "My top 50", icon: "chart.line.uptrend.xyaxis", subtitle: "Your most played tracks", route: .topSongs(limit: 50))
        ]
    }

    private var downloadsSubtitle: String {
        downloadManager.persistedDownloadCount == 0
            ? "Offline songs and downloads"
            : "\(downloadManager.persistedDownloadCount) offline songs"
    }

    enum LibraryFilter: String, CaseIterable {
        case songs = "SONGS"
        case albums = "ALBUMS"
        case artists = "ARTISTS"
        case playlists = "PLAYLISTS"
        case podcasts = "PODCASTS"
    }

    var body: some View {
        NavigationStack(path: $router.libraryPath) {
            ZStack(alignment: .top) {
                Group {
                    if isLoading {
                        librarySkeleton
                            .padding(.top, 62)
                    } else {
                        feedContent
                    }
                }

                TabHeaderView(
                    title: "Library",
                    onAdd: { showCreateDialog = true },
                    onAccount: { router.libraryPath.append(DetailRoute.settings) }
                )
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .toolbar(.hidden, for: .navigationBar)
            .detailRouteDestinations()
            .overlay {
                if showCreateDialog {
                    CreatePlaylistDialog(
                        isPresented: $showCreateDialog,
                        onCreated: { await loadContent() }
                    )
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showCreateDialog)
            .onReceive(NotificationCenter.default.publisher(for: .libraryPlaylistsUpdated)) { _ in
                Task { await loadContent() }
            }
            .task {
                await loadContent()
                await SyncBridge.checkAndSyncIfStale()
                await loadContent()
            }
            .onChange(of: likeStore.liked) { _, _ in
                Task {
                    likedSongCount = (try? await DatabaseService.shared.fetchAllLikedSongCount()) ?? 0
                }
            }
            .task(id: isLoading) {
                guard !isLoading else { return }
                let urls = (playlists.map(\.thumbnailUrl) + albums.map(\.thumbnailUrl) + artists.map(\.thumbnailUrl) + podcasts.map(\.thumbnailUrl))
                    .compactMap { $0 }
                    .compactMap(URL.init)
                await ImagePreloader.shared.preload(urls)
            }
            .refreshable {
                await SyncBridge.forceFullSync()
                await loadContent()
            }
            .alert(
                "Delete Playlist",
                isPresented: .init(
                    get: { playlistToDelete != nil },
                    set: { if !$0 { playlistToDelete = nil } }
                )
            ) {
                Button("Delete") {
                    if let p = playlistToDelete {
                        Task { await deletePlaylist(p) }
                    }
                }
                Button("Cancel", role: .cancel) {
                    playlistToDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete \"\(playlistToDelete?.name ?? "")\"? This action cannot be undone.")
            }
        }
        .audiaScreenBackground()
    }

    // MARK: - Feed Content

    @ViewBuilder
    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Color.clear.frame(height: 62)
                autoPlaylistsList
                playlistsAndAlbumsSection
            }
            .appBottomClearance(isRootTab: true)
        }
        .scrollIndicators(.automatic)
        .miniPlayerTracksScroll()
    }

    // MARK: - Auto Playlists List (Audia style)

    private var autoPlaylistsList: some View {
        VStack(spacing: 2) {
            ForEach(autoPlaylists) { info in
                if let detailRoute = info.detailRoute {
                    NavigationLink(value: detailRoute) {
                        autoPlaylistRow(info: info)
                    }
                    .buttonStyle(.plain)
                } else if let route = info.route {
                    NavigationLink(value: DetailRoute.autoPlaylist(route)) {
                        autoPlaylistRow(info: info)
                    }
                    .buttonStyle(.plain)
                } else {
                    autoPlaylistRow(info: info)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func autoPlaylistRow(info: AutoPlaylistInfo) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AudiaTheme.surfaceVariant)
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(AudiaTheme.surfaceBorder, lineWidth: 1))
                Image(systemName: info.icon)
                    .font(.satoshi(size: 20))
                    .foregroundStyle(AudiaTheme.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(info.title))
                    .font(.satoshi(size: 16.5, weight: .semibold))
                    .foregroundStyle(AudiaTheme.textPrimary)
                if let subtitle = info.subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .font(.satoshi(size: 14))
                        .foregroundStyle(AudiaTheme.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Playlists & Albums Section (Audia style)

    private var playlistsAndAlbumsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Playlists & Albums")
                    .font(.satoshi(size: 26, weight: .bold))
                    .foregroundStyle(AudiaTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            ForEach(playlists, id: \.id) { playlist in
                playlistRow(playlist: playlist)
            }

            ForEach(albums, id: \.id) { album in
                albumRow(album: album)
            }
        }
    }

    private func playlistRow(playlist: PlaylistEntity) -> some View {
        HStack(spacing: 14) {
            NavigationLink(value: DetailRoute.playlist(playlistId: playlist.id)) {
                HStack(spacing: 14) {
                    AsyncImageView(url: playlist.thumbnailUrl)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(playlist.name)
                            .font(.satoshi(size: 16, weight: .semibold))
                            .foregroundStyle(AudiaTheme.textPrimary)
                            .lineLimit(1)
                        Text(playlistSongCounts[playlist.id].map { "\($0) songs" } ?? "Playlist")
                            .font(.satoshi(size: 14))
                            .foregroundStyle(AudiaTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            playlistMenu(playlist: playlist)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func albumRow(album: AlbumEntity) -> some View {
        HStack(spacing: 14) {
            NavigationLink(value: DetailRoute.album(browseId: album.id)) {
                HStack(spacing: 14) {
                    AsyncImageView(url: album.thumbnailUrl)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(album.title)
                            .font(.satoshi(size: 16, weight: .semibold))
                            .foregroundStyle(AudiaTheme.textPrimary)
                            .lineLimit(1)
                        Text(album.songCount > 0 ? "\(album.songCount) songs" : "Album")
                            .font(.satoshi(size: 14))
                            .foregroundStyle(AudiaTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            albumMenu(album: album)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func playlistMenu(playlist: PlaylistEntity) -> some View {
        Menu {
            Button {
                Task { await playPlaylist(playlist) }
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                Task { await addPlaylistToQueue(playlist) }
            } label: {
                Label("Add to Queue", systemImage: "text.badge.plus")
            }

            Button {
                if let shareUrl = URL.playlistShareURL(id: playlist.id) {
                    presentShareSheet(items: [shareUrl])
                } else {
                    presentShareSheet(items: [playlist.name])
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button {
                playlistToDelete = playlist
            } label: {
                Label("Delete Playlist", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.satoshi(size: 16, weight: .semibold))
                .foregroundStyle(AudiaTheme.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func albumMenu(album: AlbumEntity) -> some View {
        Menu {
            Button {
                if let shareUrl = URL.albumShareURL(id: album.id) {
                    presentShareSheet(items: [shareUrl])
                } else {
                    presentShareSheet(items: [album.title])
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button {
                Task {
                    try? await SyncBridge.mutations.unsaveAlbum(browseId: album.id)
                    await loadContent()
                }
            } label: {
                Label("Remove from Library", systemImage: "bookmark.slash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.satoshi(size: 16, weight: .semibold))
                .foregroundStyle(AudiaTheme.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Playlists (Auto + User)

    private var playlistsSection: some View {
        librarySection(title: "Playlists", count: playlists.count) {
            ForEach(autoPlaylists) { info in
                if let detailRoute = info.detailRoute {
                    NavigationLink(value: detailRoute) {
                        autoPlaylistCell(info: info)
                    }
                    .buttonStyle(.plain)
                } else if let route = info.route {
                    NavigationLink(value: DetailRoute.autoPlaylist(route)) {
                        autoPlaylistCell(info: info)
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(playlists, id: \.id) { playlist in
                NavigationLink(value: DetailRoute.playlist(playlistId: playlist.id)) {
                    itemCell(
                        url: playlist.thumbnailUrl,
                        title: playlist.name,
                        subtitle: playlistSongCounts[playlist.id].map { "\($0) songs" }
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if playlist.isEditable {
                        Button(role: .destructive) {
                            playlistToDelete = playlist
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Artists

    private var artistsSection: some View {
        librarySection(title: "Artists", count: artists.count) {
            ForEach(artists, id: \.id) { artist in
                NavigationLink(value: DetailRoute.artist(browseId: artist.id)) {
                    artistCell(
                        url: artist.thumbnailUrl,
                        name: artist.name
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Albums

    private var albumsSection: some View {
        librarySection(title: "Albums", count: albums.count) {
            ForEach(albums, id: \.id) { album in
                NavigationLink(value: DetailRoute.album(browseId: album.id)) {
                    itemCell(
                        url: album.thumbnailUrl,
                        title: album.title,
                        subtitle: album.songCount > 0 ? "\(album.songCount) songs" : nil
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Podcasts

    private var podcastsSection: some View {
        librarySection(title: "Podcasts", count: podcasts.count) {
            ForEach(podcasts, id: \.id) { podcast in
                NavigationLink(value: DetailRoute.podcast(browseId: podcast.id)) {
                    itemCell(
                        url: podcast.thumbnailUrl,
                        title: podcast.name,
                        subtitle: nil
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Components

    private func librarySection<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.sectionSpacing) {
            sectionTitle(title, count: count)

            LazyVGrid(columns: gridColumns, spacing: 16) {
                content()
            }
            .padding(.horizontal, DesignTokens.screenHPadding)
        }
        .padding(.bottom, 24)
    }

    private func sectionTitle(_ title: String, count: Int? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(title))
                .font(.satoshi(.title3))
                .fontWeight(.bold)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.satoshi(.callout))
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DesignTokens.screenHPadding)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func autoPlaylistCell(info: AutoPlaylistInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(autoPlaylistGradient())
                    .aspectRatio(1, contentMode: .fill)
                Image(systemName: info.icon)
                    .font(.satoshi(.largeTitle))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

            Text(LocalizedStringKey(info.title))
                .lineLimit(1)
                .font(.satoshi(.callout))
            if let subtitle = info.subtitle {
                Text(LocalizedStringKey(subtitle))
                    .font(.satoshi(.caption))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func autoPlaylistGradient() -> LinearGradient {
        let accent = settings.accentColor
        return LinearGradient(
            colors: [accent.opacity(0.55), accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func itemCell(url: String?, title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImageView(url: url)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(title).lineLimit(1).font(.satoshi(.callout))
            if let subtitle {
                Text(subtitle).font(.satoshi(.caption)).foregroundColor(.secondary)
            }
        }
    }

    private func artistCell(url: String?, name: String) -> some View {
        VStack(spacing: 8) {
            AsyncImageView(url: url)
                .frame(width: 120, height: 120)
                .clipShape(Circle())
            Text(name).lineLimit(1).font(.satoshi(.callout))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Loading Skeleton

    private var librarySkeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ShimmerChips(count: 4, width: 88)

                ForEach(0..<2, id: \.self) { _ in
                    ShimmerSectionTitle(width: 130)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(0..<6, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 6) {
                                ShimmerFill(radius: 12)
                                    .aspectRatio(1, contentMode: .fit)
                                ShimmerBlock(width: 110, height: 15, radius: 4)
                                ShimmerBlock(width: 70, height: 12, radius: 4)
                            }
                        }
                    }
                    .padding(.horizontal, DesignTokens.screenHPadding)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Data Loading

    private func loadContent() async {
        do {
            async let artistsFetch = DatabaseService.shared.fetchAll(
                ArtistEntity.self,
                sql: "SELECT * FROM artist WHERE bookmarked_at IS NOT NULL ORDER BY name LIMIT 50"
            )
            async let playlistsFetch = DatabaseService.shared.fetchAll(
                PlaylistEntity.self,
                sql: """
                    SELECT id, browse_id, name,
                           COALESCE(
                               NULLIF(thumbnail_url, ''),
                               (SELECT s.thumbnail_url FROM song s
                                INNER JOIN playlist_song_map m ON m.song_id = s.id
                                WHERE m.playlist_id = playlist.id
                                  AND s.thumbnail_url IS NOT NULL AND s.thumbnail_url != ''
                                ORDER BY m.position, m.id LIMIT 1)
                           ) AS thumbnail_url,
                           is_editable, bookmarked_at, remote_song_count, is_auto_sync
                    FROM playlist WHERE bookmarked_at IS NOT NULL ORDER BY name LIMIT 50
                    """
            )
            async let albumsFetch = DatabaseService.shared.fetchAllAlbums()
            async let podcastsFetch = DatabaseService.shared.fetchAllPodcasts()
            async let countFetch = DatabaseService.shared.fetchAllLikedSongCount()
            artists = try await artistsFetch
            playlists = try await playlistsFetch
            albums = try await albumsFetch
            podcasts = try await podcastsFetch
            likedSongCount = try await countFetch

            let rows: [(String, Int)] = try await DatabaseService.shared.read { db in
                try Row.fetchAll(
                    db,
                    sql: "SELECT playlist_id, COUNT(*) as cnt "
                        + "FROM playlist_song_map "
                        + "WHERE EXISTS (SELECT 1 FROM song WHERE id = song_id) "
                        + "GROUP BY playlist_id"
                )
                .map { ($0["playlist_id"] as String, $0["cnt"] as Int) }
            }
            playlistSongCounts = Dictionary(uniqueKeysWithValues: rows)

            isLoading = false
        } catch {
            Log.libraryView.error("Failed to load: \(error)")
            isLoading = false
        }
    }

    private func fetchPlaylistSongs(for playlist: PlaylistEntity) async -> [SongItem] {
        if let localSongs = try? await DatabaseService.shared.fetchAll(
            SongEntity.self,
            sql: """
                SELECT s.* FROM song s
                INNER JOIN playlist_song_map m ON m.song_id = s.id
                WHERE m.playlist_id = ?
                ORDER BY m.position, m.id
                """,
            arguments: [playlist.id]
        ), !localSongs.isEmpty {
            return localSongs.toSongItems()
        }

        do {
            let (firstPage, rows) = try await SyncBridge.playlistDetail.fetchPlaylistRows(playlistId: playlist.id)
            let parsed = PlaylistDetailViewModel.parsePlaylistDetail(firstPage: firstPage, rows: rows, playlistId: playlist.id)
            return parsed.songs
        } catch {
            Log.libraryView.error("Failed to fetch songs for playlist \(playlist.id): \(error)")
            return []
        }
    }

    private func playPlaylist(_ playlist: PlaylistEntity) async {
        let songs = await fetchPlaylistSongs(for: playlist)
        guard !songs.isEmpty else { return }
        PlaybackQueue.play(songs, log: Log.libraryView, context: "playPlaylist")
    }

    private func addPlaylistToQueue(_ playlist: PlaylistEntity) async {
        let songs = await fetchPlaylistSongs(for: playlist)
        guard !songs.isEmpty else { return }
        let np = NowPlaying.shared
        np.queueSongs.append(contentsOf: songs)
        np.persistQueueState()
    }

    private func deletePlaylist(_ playlist: PlaylistEntity) async {
        playlists.removeAll { $0.id == playlist.id }
        PlaylistCoverStorage.delete(urlString: playlist.thumbnailUrl)
        do {
            try await DatabaseService.shared.deletePlaylist(id: playlist.id)
            let auth = await InnerTubeClient.audiaShared.currentAuth()
            if !auth.cookies.isEmpty {
                try? await SyncBridge.mutations.deletePlaylist(playlistId: playlist.id)
            }
            NotificationCenter.default.post(name: .libraryPlaylistsUpdated, object: nil)
            await loadContent()
        } catch {
            Log.libraryView.error("Failed to delete playlist: \(error)")
            await loadContent()
        }
    }
}

// MARK: - Create Playlist Dialog

enum PlaylistDialogTab: String, CaseIterable {
    case create = "New Playlist"
    case importLink = "Import Link"
}

struct CreatePlaylistDialog: View {
    @Environment(SettingsStore.self) private var settings
    @Binding var isPresented: Bool
    var prefilledLink: String? = nil
    var initialTab: PlaylistDialogTab = .create
    let onCreated: () async -> Void

    @State private var selectedTab: PlaylistDialogTab = .create

    // Create state
    @State private var name = ""
    @State private var isCreating = false
    @FocusState private var isNameFocused: Bool

    // Import state
    @State private var linkText = ""
    @State private var detectedType: PlaylistLinkType?
    @State private var previewInfo: PlaylistPreviewInfo?
    @State private var isPreviewLoading = false
    @State private var isImporting = false
    @State private var importProgress: Double = 0
    @State private var importStatus: String = ""
    @State private var previewTask: Task<Void, Never>?
    @FocusState private var isLinkFocused: Bool

    @State private var error: Error?

    init(
        isPresented: Binding<Bool>,
        prefilledLink: String? = nil,
        initialTab: PlaylistDialogTab = .create,
        onCreated: @escaping () async -> Void
    ) {
        self._isPresented = isPresented
        self.prefilledLink = prefilledLink
        self.initialTab = initialTab
        self._selectedTab = State(initialValue: prefilledLink != nil ? .importLink : initialTab)
        self._linkText = State(initialValue: prefilledLink ?? "")
        self.onCreated = onCreated
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segmented Tab Picker
            tabPicker
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

            if selectedTab == .create {
                createContent
            } else {
                importContent
            }

            if let error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.satoshi(.caption))
                    Text(error.localizedDescription)
                        .font(.satoshi(.caption))
                        .lineLimit(2)
                }
                .foregroundColor(.red)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }

            Divider()
                .padding(.top, 8)
                .padding(.bottom, 4)

            actionButtons
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 20)
        }
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AudiaTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AudiaTheme.surfaceBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 30, y: 10)
        .onTapGesture { }
        .onAppear {
            if let prefilled = prefilledLink, !prefilled.isEmpty {
                handleLinkChange(prefilled)
            } else if selectedTab == .create {
                isNameFocused = true
            } else {
                isLinkFocused = true
            }
        }
    }

    // MARK: - Tab Picker

    private var accentTextColor: Color {
        if settings.accentName == "White" {
            return AudiaTheme.onPrimary
        }
        return .white
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(PlaylistDialogTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = tab
                        error = nil
                        if tab == .create {
                            isNameFocused = true
                        } else {
                            isLinkFocused = true
                        }
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.satoshi(.subheadline, weight: selectedTab == tab ? .bold : .medium))
                        .foregroundColor(selectedTab == tab ? accentTextColor : AudiaTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedTab == tab ? settings.accentColor : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AudiaTheme.surfaceVariant)
        )
    }

    // MARK: - Create Content

    @ViewBuilder
    private var createContent: some View {
        TextField("Playlist name", text: $name)
            .font(.satoshi(.body))
            .focused($isNameFocused)
            .padding(.horizontal, DesignTokens.screenHPadding)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AudiaTheme.surfaceVariant)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isNameFocused ? settings.accentColor : AudiaTheme.surfaceBorder, lineWidth: 1)
            )
            .autocorrectionDisabled()
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
    }

    // MARK: - Import Content

    @ViewBuilder
    private var importContent: some View {
        VStack(spacing: 12) {
            // Link input field with Paste button
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.satoshi(size: 14))
                    .foregroundColor(detectedType != nil ? settings.accentColor : AudiaTheme.textSecondary)

                TextField("YouTube or Spotify link", text: $linkText)
                    .font(.satoshi(.body))
                    .focused($isLinkFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: linkText) { _, newText in
                        handleLinkChange(newText)
                    }

                if !linkText.isEmpty {
                    Button {
                        linkText = ""
                        detectedType = nil
                        previewInfo = nil
                        previewTask?.cancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.satoshi(size: 14))
                            .foregroundColor(AudiaTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    if let clipboard = UIPasteboard.general.string {
                        linkText = clipboard
                        handleLinkChange(clipboard)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.satoshi(size: 14, weight: .semibold))
                        .foregroundColor(settings.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Paste from clipboard")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AudiaTheme.surfaceVariant)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isLinkFocused ? settings.accentColor : AudiaTheme.surfaceBorder, lineWidth: 1)
            )
            .padding(.horizontal, 24)

            // Detected Badge / Hint
            HStack(spacing: 6) {
                if let detected = detectedType {
                    Image(systemName: detected.systemIcon)
                        .font(.satoshi(size: 12, weight: .semibold))
                        .foregroundColor(detected.serviceName == "Spotify" ? .green : .red)
                    Text("\(detected.serviceName) Playlist")
                        .font(.satoshi(.caption, weight: .semibold))
                        .foregroundColor(detected.serviceName == "Spotify" ? .green : .red)
                } else {
                    Image(systemName: "info.circle")
                        .font(.satoshi(size: 12))
                        .foregroundColor(AudiaTheme.textSecondary)
                    Text("Paste link from YouTube Music or Spotify")
                        .font(.satoshi(.caption))
                        .foregroundColor(AudiaTheme.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 26)

            // Playlist preview card
            if isPreviewLoading {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(settings.accentColor)
                        .scaleEffect(0.8)
                    Text("Loading playlist details...")
                        .font(.satoshi(.caption))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AudiaTheme.surfaceVariant.opacity(0.6))
                )
                .padding(.horizontal, 24)
            } else if let preview = previewInfo {
                HStack(spacing: 12) {
                    if let artworkUrl = preview.artworkUrl {
                        AsyncImageView(url: artworkUrl)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AudiaTheme.surfaceVariant)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "music.note.list")
                                    .foregroundColor(AudiaTheme.textSecondary)
                            )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(preview.title)
                            .font(.satoshi(.subheadline, weight: .bold))
                            .lineLimit(1)
                        Text("\(preview.trackCount) track\(preview.trackCount != 1 ? "s" : "")\(preview.author != nil ? " • \(preview.author!)" : "")")
                            .font(.satoshi(.caption))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AudiaTheme.surfaceVariant)
                )
                .padding(.horizontal, 24)
            }

            // Progress indicator while importing
            if isImporting {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: importProgress, total: 1.0)
                        .tint(settings.accentColor)
                    Text(importStatus.isEmpty ? "Importing playlist..." : importStatus)
                        .font(.satoshi(.caption))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: { isPresented = false }, label: {
                Text("Cancel")
                    .font(.satoshi(.body, weight: .medium))
                    .foregroundColor(AudiaTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AudiaTheme.surfaceVariant)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AudiaTheme.surfaceBorder, lineWidth: 1)
                    )
            })
            .buttonStyle(.plain)
            .disabled(isCreating || isImporting)

            if selectedTab == .create {
                let canCreate = !name.trimmingCharacters(in: .whitespaces).isEmpty
                Button(action: {
                    guard canCreate else { return }
                    Task {
                        isCreating = true
                        do {
                            try await createPlaylist()
                            await onCreated()
                            isPresented = false
                        } catch {
                            self.error = error
                        }
                        isCreating = false
                    }
                }, label: {
                    HStack(spacing: 6) {
                        if isCreating {
                            ProgressView()
                                .tint(canCreate ? accentTextColor : AudiaTheme.textSecondary)
                                .scaleEffect(0.8)
                        }
                        Text("Create")
                            .font(.satoshi(.body, weight: .semibold))
                    }
                    .foregroundColor(canCreate ? accentTextColor : AudiaTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(canCreate ? settings.accentColor : AudiaTheme.surfaceVariant)
                    )
                })
                .buttonStyle(.plain)
                .disabled(!canCreate || isCreating)
            } else {
                let canImport = detectedType != nil && !isImporting
                Button(action: {
                    Task { await startImport() }
                }, label: {
                    HStack(spacing: 6) {
                        if isImporting {
                            ProgressView()
                                .tint(accentTextColor)
                                .scaleEffect(0.8)
                        }
                        Text(isImporting ? "Importing" : "Import")
                            .font(.satoshi(.body, weight: .semibold))
                    }
                    .foregroundColor(canImport ? accentTextColor : AudiaTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(canImport ? settings.accentColor : AudiaTheme.surfaceVariant)
                    )
                })
                .buttonStyle(.plain)
                .disabled(!canImport)
            }
        }
    }

    // MARK: - Logic

    private func handleLinkChange(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        error = nil
        guard !trimmed.isEmpty else {
            detectedType = nil
            previewInfo = nil
            previewTask?.cancel()
            return
        }

        if let detected = PlaylistLinkParser.parse(trimmed) {
            detectedType = detected
            previewTask?.cancel()
            previewTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await loadPreview(for: trimmed)
            }
        } else {
            detectedType = nil
            previewInfo = nil
            previewTask?.cancel()
        }
    }

    private func loadPreview(for link: String) async {
        isPreviewLoading = true
        defer { isPreviewLoading = false }
        do {
            let preview = try await PlaylistImportService.shared.previewPlaylist(from: link)
            previewInfo = preview
        } catch {
            Log.search.error("Playlist preview error: \(error.localizedDescription)")
        }
    }

    private func startImport() async {
        guard detectedType != nil else { return }
        isImporting = true
        error = nil
        importProgress = 0.05
        importStatus = "Starting import..."

        do {
            _ = try await PlaylistImportService.shared.importPlaylist(
                from: linkText,
                customName: name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name
            ) { progress, status in
                Task { @MainActor in
                    self.importProgress = progress
                    self.importStatus = status
                }
            }
            await onCreated()
            isPresented = false
        } catch {
            self.error = error
        }
        isImporting = false
    }

    private func createPlaylist() async throws {
        let title = name.trimmingCharacters(in: .whitespaces)
        let id = UUID().uuidString
        let entity = PlaylistEntity(
            id: id,
            browseId: nil,
            name: title,
            thumbnailUrl: nil,
            isEditable: true,
            bookmarkedAt: Date(),
            remoteSongCount: 0
        )
        try await DatabaseService.shared.insert(entity)
    }
}

// MARK: - AutoPlaylist Info

struct AutoPlaylistInfo: Identifiable {
    let id: String
    let title: String
    let icon: String
    let subtitle: String?
    let route: AutoPlaylistRoute?
    var detailRoute: DetailRoute?
}

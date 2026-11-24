//
//  SongRowView.swift
//  Audia
//

import SwiftUI

/// Trailing ⋮ button shared by every song row.
struct MoreButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action, label: {
            Image(systemName: "ellipsis")
                .font(.satoshi(size: 16, weight: .semibold))
                .foregroundStyle(AudiaTheme.textSecondary)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        })
        .buttonStyle(.plain)
        .accessibilityLabel("More")
    }
}

/// Unified song actions menu content for popup Menu and contextMenu.
struct SongMenuActionsView: View {
    let song: SongItem
    var pin: PinState = PinState()
    var onNavigate: ((DetailRoute) -> Void)?
    var onAddToPlaylist: () -> Void

    @ObservedObject private var likeStore = LikeStore.shared
    @ObservedObject private var downloadManager = DownloadManager.shared

    var body: some View {
        Group {
            Button {
                PlaybackQueue.startRadio(for: song)
            } label: {
                Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
            }

            Button {
                let np = NowPlaying.shared
                let insertIndex = min(np.queueIndex + 1, np.queueSongs.count)
                np.queueSongs.insert(song, at: insertIndex)
                np.repairQueueIndex()
                np.persistQueueState()
            } label: {
                Label("Play Next", systemImage: "text.insert")
            }

            Button {
                let np = NowPlaying.shared
                np.queueSongs.append(song)
                np.persistQueueState()
            } label: {
                Label("Add to Queue", systemImage: "text.badge.plus")
            }

            Divider()

            Button {
                Task { await likeStore.toggle(song: song) }
            } label: {
                if likeStore.isLiked(videoId: song.videoId) {
                    Label("Unlike", systemImage: "heart.slash")
                } else {
                    Label("Like", systemImage: "heart")
                }
            }

            Button {
                onAddToPlaylist()
            } label: {
                Label("Add to Playlist", systemImage: "plus.square.on.square")
            }

            downloadButton

            Divider()

            let namedArtists = song.artists.filter { !$0.name.isEmpty }
            if namedArtists.count > 1 {
                Menu {
                    ForEach(namedArtists, id: \.self) { artist in
                        Button(artist.name) {
                            openArtist(artist)
                        }
                    }
                } label: {
                    Label("View Artist", systemImage: "music.mic")
                }
            } else if let artist = namedArtists.first {
                Button {
                    openArtist(artist)
                } label: {
                    Label("View Artist", systemImage: "music.mic")
                }
            }

            if let albumId = song.firstAlbumBrowseId {
                Button {
                    onNavigate?(.album(browseId: albumId))
                } label: {
                    Label("View Album", systemImage: "record.circle")
                }
            }

            Divider()

            Button {
                UIPasteboard.general.string = song.webUrl
            } label: {
                Label("Copy Link", systemImage: "link")
            }

            Button {
                shareSong(song, downloadManager: downloadManager)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    @ViewBuilder
    private var downloadButton: some View {
        switch downloadManager.state(for: song.videoId) {
        case .completed:
            Button(role: .destructive) {
                Task { await downloadManager.delete(videoId: song.videoId) }
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        case .downloading:
            Button {} label: {
                Label("Downloading…", systemImage: "arrow.down.circle")
            }
            .disabled(true)
        case .notStarted, .failed:
            Button {
                Task { await downloadManager.download(song: song) }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }
    }

    @MainActor
    private func openArtist(_ artist: YTArtist) {
        if let id = artist.id {
            onNavigate?(.artist(browseId: id))
            return
        }
        let name = artist.name
        guard !name.isEmpty else { return }
        Task {
            let json = try? await SearchService.shared.search(query: name)
            guard let json else { return }
            let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let browseId = SearchParser.parseSearchResults(from: json)
                .flatMap(\.items)
                .compactMap { item -> (String, String)? in
                    if case .artist(let artist) = item { return (artist.name, artist.browseId) }
                    return nil
                }
                .first {
                    $0.0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted
                }?.1
            if let browseId {
                await MainActor.run {
                    onNavigate?(.artist(browseId: browseId))
                }
            }
        }
    }
}

/// Unified song row: artwork + title + artists • duration + overflow popup menu.
/// Replaces AlbumSongRow, PlaylistSongRow, PodcastEpisodeRow, DownloadedSongRow
/// and the song branch of YouTubeListItemView.
struct SongRowView: View {
    let song: SongItem
    var artSize: CGFloat = 54
    var artRadius: CGFloat = 12
    var onTap: () -> Void
    var onNavigate: ((DetailRoute) -> Void)?

    @State private var durations = DurationResolver()
    @State private var showPlaylistPicker = false
    @State private var pin = PinState()

    var body: some View {
        HStack(spacing: 14) {
            AsyncImageView(url: song.thumbnailUrl)
                .frame(width: artSize, height: artSize)
                .clipShape(RoundedRectangle(cornerRadius: artRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.satoshi(size: 16, weight: .semibold))
                    .foregroundColor(AudiaTheme.textPrimary)
                    .lineLimit(1)

                Text(song.subtitleLine(duration: durations.effectiveDuration(known: song.duration)))
                    .font(.satoshi(size: 14, weight: .medium))
                    .foregroundColor(AudiaTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                SongMenuActionsView(
                    song: song,
                    pin: pin,
                    onNavigate: onNavigate,
                    onAddToPlaylist: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            showPlaylistPicker = true
                        }
                    }
                )
            } label: {
                Image(systemName: "ellipsis")
                    .font(.satoshi(size: 16, weight: .semibold))
                    .foregroundStyle(AudiaTheme.textSecondary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More")
        }
        .background(DownloadCellProgressView(song: song))
        .padding(.horizontal, DesignTokens.screenHPadding)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.light()
            onTap()
        }
        .contextMenu {
            SongMenuActionsView(
                song: song,
                pin: pin,
                onNavigate: onNavigate,
                onAddToPlaylist: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        showPlaylistPicker = true
                    }
                }
            )
        }
        .sheet(isPresented: $showPlaylistPicker) {
            AddSongToPlaylistSheet(song: song)
        }
        .task {
            await durations.resolve(videoId: song.videoId, knownDuration: song.duration)
            await pin.load(videoId: song.videoId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .durationDidUpdate)) { notification in
            durations.handleUpdate(notification, videoId: song.videoId)
        }
    }
}

/// Full-cell progress background shown while a song is downloading.
struct DownloadCellProgressView: View {
    let song: SongItem
    @ObservedObject private var downloadManager = DownloadManager.shared

    var body: some View {
        let state = downloadManager.state(for: song.videoId)
        return GeometryReader { geo in
            if case .downloading(let fraction) = state {
                Color.accentColor.opacity(0.25)
                    .frame(
                        width: geo.size.width * CGFloat(min(max(fraction, 0), 1)),
                        height: geo.size.height
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: state)
    }
}

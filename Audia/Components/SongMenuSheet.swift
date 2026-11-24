//
//  SongMenuSheet.swift
//  Audia
//

import SwiftUI

struct SongMenuSheet: View {
    let song: SongItem
    var onNavigate: ((DetailRoute) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.settingsStore) private var settings
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var likeStore = LikeStore.shared

    @State private var pin = PinState()
    @State private var showPlaylistPicker = false
    @State private var showArtistPicker = false
    @State private var showShareDialog = false
    @State private var isResolvingArtist = false

    private var isLiked: Bool {
        likeStore.isLiked(videoId: song.videoId)
    }
    var body: some View {
        SheetChrome {
            Group {
                headerCard
                MenuCard {
                    MenuRow(
                        icon: isLiked ? "heart.slash" : "heart",
                        title: isLiked ? "Unlike" : "Like"
                    ) {
                        Task { await likeStore.toggle(song: song) }
                    }
                    Divider()
                    downloadRow
                }
                MenuCard {
                    MenuRow(
                        icon: "text.insert",
                        title: "Play Next",
                        subtitle: "Add to the queue, next in line"
                    ) { playNext() }
                    Divider()
                    MenuRow(
                        icon: "list.bullet",
                        title: "Add to Queue",
                        subtitle: "Add to the end of the queue"
                    ) { addToQueue() }
                    Divider()
                    MenuRow(
                        icon: "music.mic",
                        title: "View Artist",
                        subtitle: song.artistNamesDisplay
                    ) { handleViewArtist() }
                    if let albumId = song.firstAlbumBrowseId {
                        Divider()
                        MenuRow(
                            icon: "record.circle",
                            title: "View Album",
                            subtitle: song.album
                        ) { navigate(.album(browseId: albumId)) }
                    }
                }
            }
        }
        .confirmationDialog("View Artist", isPresented: $showArtistPicker, titleVisibility: .visible) {
            ForEach(song.artists.filter { !$0.name.isEmpty }, id: \.self) { artist in
                Button(artist.name) {
                    openArtist(artist)
                }
            }
        }
        .sheet(isPresented: $showPlaylistPicker) {
            AddSongToPlaylistSheet(song: song)
        }
        .confirmationDialog("Share", isPresented: $showShareDialog, titleVisibility: .visible) {
            Button("Copy Link") {
                UIPasteboard.general.string = song.webUrl
                dismiss()
            }
            Button("Share with Other Apps") {
                share()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(song.title)
        }
        .task { await pin.load(videoId: song.videoId) }
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(spacing: 12) {
            AsyncImageView(url: song.thumbnailUrl)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    text: song.title,
                    font: .headline,
                    frameHeight: 24,
                    textColor: AudiaTheme.textPrimary
                )
                Text(song.artistNamesDisplay)
                    .font(.satoshi(.subheadline))
                    .foregroundStyle(AudiaTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AudiaTheme.sheetSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AudiaTheme.sheetBorder, lineWidth: 1)
        )
    }


    private var downloadRow: some View {
        let state = downloadManager.state(for: song.videoId)
        return Group {
            switch state {
            case .completed:
                MenuRow(icon: "checkmark.circle.fill", title: "Remove Download", destructive: true) {
                    Task { await downloadManager.delete(videoId: song.videoId) }
                }
            case .downloading:
                MenuRow(icon: "arrow.down.circle", title: "Downloading…") {}
                    .disabled(true)
            case .notStarted, .failed:
                MenuRow(icon: "arrow.down.circle", title: "Download") {
                    Task { await downloadManager.download(song: song) }
                }
            }
        }
    }

    // MARK: - State

    // MARK: - Actions

    private func startRadio() {
        PlaybackQueue.startRadio(for: song)
        dismiss()
    }

    private func playNext() {
        let np = NowPlaying.shared
        let insertIndex = min(np.queueIndex + 1, np.queueSongs.count)
        np.queueSongs.insert(song, at: insertIndex)
        np.repairQueueIndex()
        np.persistQueueState()
        dismiss()
    }

    private func addToQueue() {
        let np = NowPlaying.shared
        np.queueSongs.append(song)
        np.persistQueueState()
        dismiss()
    }

    private func share() {
        shareSong(song, downloadManager: downloadManager, afterDismiss: { dismiss() })
    }

    private func navigate(_ route: DetailRoute) {
        dismiss()
        onNavigate?(route)
    }

    private func handleViewArtist() {
        guard !isResolvingArtist else { return }
        let namedArtists = song.artists.filter { !$0.name.isEmpty }
        if namedArtists.count > 1 {
            showArtistPicker = true
            return
        }
        guard let artist = namedArtists.first else { return }
        openArtist(artist)
    }

    private func openArtist(_ artist: YTArtist) {
        if let id = artist.id {
            navigate(.artist(browseId: id))
            return
        }
        resolveArtistByName(artist.name)
    }

    private func resolveArtistByName(_ name: String) {
        guard !name.isEmpty else { return }
        isResolvingArtist = true
        Task {
            defer { isResolvingArtist = false }
            var browseId: String?
            do {
                let json = try await SearchService.shared.search(query: name)
                let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                browseId = SearchParser.parseSearchResults(from: json)
                    .flatMap(\.items)
                    .compactMap { item -> (String, String)? in
                        if case .artist(let artist) = item { return (artist.name, artist.browseId) }
                        return nil
                    }
                    .first {
                        $0.0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted
                    }?.1
            } catch {
                browseId = nil
            }
            if let browseId {
                navigate(.artist(browseId: browseId))
            }
        }
    }
}

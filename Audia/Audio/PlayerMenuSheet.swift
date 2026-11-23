//
//  PlayerMenuSheet.swift
//  Audia
//

import SwiftUI
import Foundation
import Combine
import AVFoundation
import MediaPlayer

/// library/download/details rows.
struct PlayerMenuSheet: View {
    let song: SongItem
    /// Collapses the Big Player so the pushed page is visible underneath.
    var onCollapseRequest: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.settingsStore) private var settings

    enum Destination: Hashable {
        case equalizer
    }

    // Loaded state
    @State private var showPlaylistPicker = false
    @State private var showArtistPicker = false
    @State private var showShareDialog = false
    @State private var isResolvingArtist = false
    @State private var isResolvingAlbum = false
    @StateObject private var volumeObserver = SystemVolumeObserver()
    @ObservedObject private var downloadManager = DownloadManager.shared

    var body: some View {
        SheetChrome {
            Group {
                // Top 3 action boxes: Save, Download, Share
                topActionBoxes

                MenuCard {
                    // 1. View Artist
                    viewArtistRow

                    Divider()

                    // 2. View Album
                    viewAlbumRow

                    Divider()

                    // 3. Add to Queue
                    MenuRow(
                        icon: "list.bullet",
                        title: "Add to Queue",
                        subtitle: "Add to the end of the queue"
                    ) {
                        addToQueue()
                    }

                    Divider()

                    // 4. EQ
                    NavigationLink(value: Destination.equalizer) {
                        MenuRowLabel(
                            icon: "slider.horizontal.3",
                            title: "EQ",
                            subtitle: "Equalizer & audio effects"
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Music volume slider at the bottom
                volumeCard
            }
            .navigationDestination(for: Destination.self) { dest in
                switch dest {
                case .equalizer:
                    EqualizerView()
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
                shareSong(song, downloadManager: downloadManager, afterDismiss: { dismiss() })
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(song.title)
        }
    }

    // MARK: - App Volume Slider

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(AudiaTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AudiaTheme.surfaceBorder, lineWidth: 1)
            )
    }

    private var volumeCard: some View {
        HStack(spacing: 12) {
            Button {
                volumeObserver.toggleMute()
            } label: {
                Image(systemName: volumeIconName)
                    .font(.satoshi(.callout))
                    .foregroundStyle(settings.accentColor)
                    .frame(width: 24)
            }
            .buttonStyle(.plain)

            SystemVolumeSlider(volumeObserver: volumeObserver)
                .frame(height: 32)
                .accessibilityLabel("System volume")
        }
        .padding(16)
        .background(cardBackground)
    }

    private var volumeIconName: String {
        switch volumeObserver.volume {
        case ..<0.01: return "speaker.slash.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }


    // MARK: - Top Action Boxes (Save, Download, Share)

    private var topActionBoxes: some View {
        HStack(spacing: 10) {
            saveBox
            downloadBox
            shareBox
        }
    }

    private var saveBox: some View {
        Button {
            showPlaylistPicker = true
        } label: {
            topBoxContent(icon: "text.badge.plus", title: "Save")
        }
        .buttonStyle(.plain)
    }

    private var downloadBox: some View {
        let state = downloadManager.state(for: song.videoId)
        let icon: String
        let title: String
        let isLoading: Bool

        switch state {
        case .completed:
            icon = "checkmark.circle.fill"
            title = "Downloaded"
            isLoading = false
        case .downloading:
            icon = "arrow.down.circle"
            title = "Downloading"
            isLoading = true
        case .notStarted, .failed:
            icon = "arrow.down.circle"
            title = "Download"
            isLoading = false
        }

        return Button {
            switch state {
            case .completed:
                Task { await downloadManager.delete(videoId: song.videoId) }
            case .downloading:
                break
            case .notStarted, .failed:
                Task { await downloadManager.download(song: song) }
            }
        } label: {
            topBoxContent(icon: icon, title: title, isLoading: isLoading)
        }
        .buttonStyle(.plain)
    }

    private var shareBox: some View {
        Button {
            showShareDialog = true
        } label: {
            topBoxContent(icon: "arrowshape.turn.up.right", title: "Share")
        }
        .buttonStyle(.plain)
    }

    private func topBoxContent(icon: String, title: String, isLoading: Bool = false) -> some View {
        VStack(spacing: 6) {
            if isLoading {
                ProgressView()
                    .frame(height: 22)
            } else {
                Image(systemName: icon)
                    .font(.satoshi(size: 20, weight: .medium))
                    .foregroundStyle(settings.accentColor)
                    .frame(height: 22)
            }
            Text(title)
                .font(.satoshi(.footnote, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 66)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AudiaTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AudiaTheme.surfaceBorder, lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Library Rows

    private var viewArtistRow: some View {
        Button {
            handleViewArtist()
        } label: {
            HStack(spacing: DesignTokens.menuRowSpacing) {
                if isResolvingArtist {
                    ProgressView()
                        .frame(width: 26)
                } else {
                    Image(systemName: "music.mic")
                        .font(.satoshi(size: 18))
                        .foregroundStyle(settings.accentColor)
                        .frame(width: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("View Artist")
                        .font(.satoshi(.body))
                        .foregroundStyle(.primary)
                    Text(song.artistNamesDisplay.isEmpty ? "Artist details" : song.artistNamesDisplay)
                        .font(.satoshi(.footnote))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.satoshi(size: 14, weight: .semibold))
                    .foregroundStyle(AudiaTheme.textSecondary.opacity(0.4))
            }
            .padding(.horizontal, DesignTokens.screenHPadding)
            .frame(height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(song.artists.isEmpty || isResolvingArtist)
    }

    private var viewAlbumRow: some View {
        Button {
            handleViewAlbum()
        } label: {
            HStack(spacing: DesignTokens.menuRowSpacing) {
                if isResolvingAlbum {
                    ProgressView()
                        .frame(width: 26)
                } else {
                    Image(systemName: "record.circle")
                        .font(.satoshi(size: 18))
                        .foregroundStyle(settings.accentColor)
                        .frame(width: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("View Album")
                        .font(.satoshi(.body))
                        .foregroundStyle(.primary)
                    Text(song.album?.isEmpty == false ? song.album! : "Album details")
                        .font(.satoshi(.footnote))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.satoshi(size: 14, weight: .semibold))
                    .foregroundStyle(AudiaTheme.textSecondary.opacity(0.4))
            }
            .padding(.horizontal, DesignTokens.screenHPadding)
            .frame(height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled((song.firstAlbumBrowseId == nil && (song.album == nil || song.album!.isEmpty)) || isResolvingAlbum)
    }

    // MARK: - State

    private func addToQueue() {
        let np = NowPlaying.shared
        np.queueSongs.append(song)
        np.persistQueueState()
        dismiss()
    }

    private func startRadio() {
        PlaybackQueue.startRadio(for: song)
        dismiss()
    }

    private func navigate(_ route: DetailRoute) {
        dismiss()
        onCollapseRequest?()
        // Appends directly to the selected tab's NavigationPath — plain state
        // mutation, so it lands even while the player is tearing down.
        AppRouter.shared.open(route)
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
                browseId = SearchParser.parseSearchResults(from: json)
                    .flatMap(\.items)
                    .compactMap { item -> String? in
                        if case .artist(let artist) = item { return artist.browseId }
                        return nil
                    }
                    .first
            } catch {
                browseId = nil
            }
            if let browseId {
                navigate(.artist(browseId: browseId))
            }
        }
    }

    private func handleViewAlbum() {
        guard !isResolvingAlbum else { return }
        if let albumId = song.firstAlbumBrowseId, !albumId.isEmpty {
            navigate(.album(browseId: albumId))
            return
        }
        guard let albumTitle = song.album, !albumTitle.isEmpty else { return }
        resolveAlbumByName(albumTitle)
    }

    private func resolveAlbumByName(_ title: String) {
        isResolvingAlbum = true
        Task {
            defer { isResolvingAlbum = false }
            var browseId: String?
            do {
                let query = "\(title) \(song.artistNamesDisplay)"
                let json = try await SearchService.shared.search(query: query)
                browseId = SearchParser.parseSearchResults(from: json)
                    .flatMap(\.items)
                    .compactMap { item -> String? in
                        if case .album(let album) = item { return album.browseId }
                        return nil
                    }
                    .first
            } catch {
                browseId = nil
            }
            if let browseId {
                navigate(.album(browseId: browseId))
            }
        }
    }
}

// MARK: - Add to Playlist Picker

/// Lets the user pick which playlist to add `song` to, or create a new one.
struct AddSongToPlaylistSheet: View {
    let song: SongItem
    @Environment(\.dismiss) private var dismiss

    @State private var playlists: [PlaylistEntity] = []
    @State private var isLoading = true
    @State private var addedTo: Set<String> = []
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistTitle = ""
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if playlists.isEmpty {
                    ContentUnavailableView(
                        "No Playlists",
                        systemImage: "music.note.list",
                        description: Text("Create one below to start collecting songs.")
                    )
                } else {
                    List(playlists, id: \.id) { playlist in
                        Button {
                            addTo(playlist)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.name)
                                        .foregroundStyle(.primary)
                                    if let count = playlist.remoteSongCount {
                                        Text("\(count) songs")
                                            .font(.satoshi(.footnote))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if addedTo.contains(playlist.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newPlaylistTitle = ""
                        showNewPlaylistAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New playlist")
                }
            }
            .textPrompt(
                "New Playlist",
                isPresented: $showNewPlaylistAlert,
                placeholder: "Playlist name",
                text: $newPlaylistTitle,
                okTitle: "Create",
                message: Text("Adds “\(song.title)” once created.")
            ) {
                Task { await createAndAdd() }
            }
            .task { await loadPlaylists() }
        }
        .appSheetChrome()
    }

    private func loadPlaylists() async {
        playlists = (try? await DatabaseService.shared.fetchPlaylists(limit: 100)) ?? []
        isLoading = false
    }

    private func addTo(_ playlist: PlaylistEntity) {
        guard !addedTo.contains(playlist.id) else { return }
        Task {
            do {
                try await SyncBridge.mutations.addToPlaylist(playlistId: playlist.id, songId: song.videoId)
                addedTo.insert(playlist.id)
            } catch {
                addedTo.remove(playlist.id)
            }
        }
    }

    private func createAndAdd() async {
        let title = newPlaylistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isCreating else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            let playlistId = try await SyncBridge.mutations.createPlaylist(title: title)
            try await SyncBridge.mutations.addToPlaylist(playlistId: playlistId, songId: song.videoId)
            await loadPlaylists()
            addedTo.insert(playlistId)
        } catch {
            // Leave the sheet open so the user can retry.
        }
    }
}

// MARK: - Details (Nerdy Metadata)

struct SongDetailsView: View {
    let song: SongItem

    @State private var stream: PlaybackResult?
    @State private var formatEntity: FormatEntity?
    @State private var viewCountText: String?
    @State private var resolvedDuration: Int = 0

    private var effectiveDuration: Int {
        song.duration > 0 ? song.duration : resolvedDuration
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                trackSection
                streamSection
                statsSection
            }
            .padding(16)
        }
        .background(AudiaTheme.background)
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMetadata() }
    }

    // MARK: Sections

    private var trackSection: some View {
        section("Track") {
            row("Title", song.title)
            row("Artists", song.artistNamesDisplay)
            if let album = song.album {
                row("Album", album)
            }
            row("Duration", effectiveDuration.formattedDuration)
            row("Video ID", song.videoId, monospaced: true)
        }
    }

    @ViewBuilder
    private var streamSection: some View {
        section("Stream") {
            if let s = stream {
                row("Client", s.clientName)
                row("ITAG", "\(s.itag)", monospaced: true)
                row("Bitrate", "\(s.bitrate / 1000) kbps")
                row("Audio quality", s.audioQuality.replacingOccurrences(of: "AUDIO_QUALITY_", with: ""))
                if let loudness = s.loudnessDb {
                    row("Loudness", String(format: "%.1f dB", loudness))
                }
                row("Expires in", "\(s.expiresInSeconds)s")
            } else if let f = formatEntity {
                row("Source", "Cached format")
                row("ITAG", "\(f.itag)", monospaced: true)
                row("Bitrate", "\(f.bitrate / 1000) kbps")
                if f.contentLength > 0 {
                    row("Size", ByteCountFormatter.string(fromByteCount: f.contentLength, countStyle: .file))
                }
            } else {
                row("Status", "Not resolved yet")
            }
        }
    }

    private var statsSection: some View {
        section("Stats") {
            row("Views", viewCountText ?? "Loading…")
        }
    }

    // MARK: Building Blocks

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(LocalizedStringKey(title))
                .font(.satoshi(.footnote, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AudiaTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AudiaTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    private func row(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(LocalizedStringKey(label))
                .font(.satoshi(.callout))
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value.isEmpty ? "—" : value)
                .font(monospaced ? .satoshi(.footnote).monospaced() : .satoshi(.callout))
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    // MARK: Helpers

    private func loadMetadata() async {
        if song.duration <= 0 {
            if let duration = await InnerTubeClient.audiaShared.resolveDuration(videoId: song.videoId) {
                resolvedDuration = duration
            }
        }
        stream = await StreamCache.shared.get(videoId: song.videoId)
        formatEntity = try? await DatabaseService.shared.fetchOne(FormatEntity.self, key: song.videoId)
        if let response: PlayerResponse = try? await InnerTubeClient.audiaShared.playerResponse(videoId: song.videoId),
           let raw = response.videoDetails?.viewCount,
           let count = Int(raw) {
            viewCountText = count.formattedViews()
        } else {
            viewCountText = "Unavailable"
        }
    }
}

// MARK: - System Volume Controls

@MainActor
final class SystemVolumeObserver: ObservableObject {
    @Published var volume: Float = AVAudioSession.sharedInstance().outputVolume
    private var observation: NSKeyValueObservation?
    weak var activeSlider: UISlider?
    private var lastNonZeroVolume: Float = 0.5

    init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)
        self.volume = session.outputVolume
        self.observation = session.observe(\.outputVolume, options: [.new]) { [weak self] audioSession, _ in
            let newVolume = audioSession.outputVolume
            DispatchQueue.main.async {
                self?.volume = newVolume
            }
        }
    }

    deinit {
        observation?.invalidate()
    }

    func toggleMute() {
        guard let slider = activeSlider else { return }
        if slider.value > 0.01 {
            lastNonZeroVolume = slider.value
            slider.setValue(0, animated: false)
            slider.sendActions(for: .valueChanged)
        } else {
            let restoreVal = lastNonZeroVolume > 0.05 ? lastNonZeroVolume : 0.5
            slider.setValue(restoreVal, animated: false)
            slider.sendActions(for: .valueChanged)
        }
    }
}

private struct SystemVolumeSlider: UIViewRepresentable {
    @ObservedObject var volumeObserver: SystemVolumeObserver

    func makeUIView(context: Context) -> CustomMPVolumeView {
        let volumeView = CustomMPVolumeView(frame: .zero)
        volumeView.showsRouteButton = false
        volumeView.showsVolumeSlider = true

        let trackHeight: CGFloat = 6
        let thumbDiameter: CGFloat = 18

        let minTrack = makeCapsuleImage(color: .white, height: trackHeight)
        let maxTrack = makeCapsuleImage(color: UIColor(white: 0.22, alpha: 1.0), height: trackHeight)
        let thumb = makeCircleImage(color: .white, size: thumbDiameter)

        volumeView.setMinimumVolumeSliderImage(minTrack, for: .normal)
        volumeView.setMaximumVolumeSliderImage(maxTrack, for: .normal)
        volumeView.setVolumeThumbImage(thumb, for: .normal)
        volumeView.setVolumeThumbImage(thumb, for: .highlighted)

        volumeView.onSliderFound = { [weak volumeObserver] slider in
            volumeObserver?.activeSlider = slider
            slider.minimumTrackTintColor = .white
            slider.maximumTrackTintColor = UIColor(white: 0.22, alpha: 1.0)
            slider.thumbTintColor = .white
        }

        return volumeView
    }

    func updateUIView(_ uiView: CustomMPVolumeView, context: Context) {}

    private func makeCapsuleImage(color: UIColor, height: CGFloat) -> UIImage {
        let cornerRadius = height / 2.0
        let width = height * 2
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            color.setFill()
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius)
            path.fill()
        }
        return image.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: cornerRadius, bottom: 0, right: cornerRadius), resizingMode: .stretch)
    }

    private func makeCircleImage(color: UIColor, size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            color.setFill()
            let path = UIBezierPath(ovalIn: CGRect(origin: .zero, size: CGSize(width: size, height: size)))
            path.fill()
        }
    }
}

final class CustomMPVolumeView: MPVolumeView {
    var onSliderFound: ((UISlider) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        if let slider = subviews.first(where: { $0 is UISlider }) as? UISlider {
            onSliderFound?(slider)
        }
    }
}

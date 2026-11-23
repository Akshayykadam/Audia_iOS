//
//  FullPlayerView.swift
//  Audia
//

import SwiftUI

struct FullPlayerView: View {
    let onCollapse: () -> Void

    @Environment(SettingsStore.self) private var settings
    private let player = PlayerController.shared
    @Bindable private var np = NowPlaying.shared
    @State private var editingProgress: Float = 0
    @State private var isEditingSlider = false
    @State private var collapseOffset: CGFloat = 0

    @ObservedObject private var likeStore = LikeStore.shared
    private var isLiked: Bool {
        guard let vid = np.videoId, !vid.isEmpty else { return false }
        return likeStore.isLiked(videoId: vid)
    }

    private var currentSongItem: SongItem? {
        if np.queueSongs.indices.contains(np.queueIndex) {
            let s = np.queueSongs[np.queueIndex]
            if s.videoId == np.videoId { return s }
        }
        if let idx = np.queueSongs.firstIndex(where: { $0.videoId == np.videoId }) {
            return np.queueSongs[idx]
        }
        guard let vid = np.videoId, !vid.isEmpty else { return nil }
        return SongItem(
            videoId: vid,
            title: np.title,
            artists: np.artists.isEmpty ? [YTArtist(name: np.displayArtist, id: nil)] : np.artists,
            album: np.albumTitle.isEmpty ? nil : np.albumTitle,
            albumId: nil,
            duration: Int(np.duration),
            thumbnailUrl: ArtworkURLs.fallback(for: vid),
            isExplicit: false,
            playlistId: nil,
            likeStatus: nil
        )
    }
    @State private var showQueue = false
    @State private var pendingRoute: DetailRoute?
    @State private var showSongMenu = false
    @State private var showArtistPicker = false
    @State private var isResolvingArtist = false
    @State private var artworkEntryOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = geometry.size.width < 375 ? 24 : 32
            let isCompact = geometry.size.height < 700

            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if !settings.audioOnlyMode && np.isVideoMode && np.hasVideo {
                        musicVideoContent
                    } else if showQueue {
                        queueContent(horizontalPadding: horizontalPadding)
                    } else {
                        mainPlayerLayout(geometry: geometry, horizontalPadding: horizontalPadding, isCompact: isCompact)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                if CommandLine.arguments.contains("-openQueue") {
                    showQueue = true
                }
            }
            .offset(y: collapseOffset)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: collapseOffset)
            .animation(.easeInOut(duration: 0.35), value: showQueue)
            .simultaneousGesture(collapseDrag)
            .onChange(of: np.videoId) { _, _ in
                np.isVideoMode = false
                showQueue = false
            }
            .onChange(of: settings.audioOnlyMode) { _, newValue in
                if newValue {
                    np.isVideoMode = false
                }
            }
            .onChange(of: np.queueSongs.count) { _, _ in
                np.preloadNeighborArtwork()
            }
            .onChange(of: np.queueIndex) { _, _ in
                np.preloadNeighborArtwork()
            }
            .onChange(of: showQueue) { _, newValue in
                if newValue { np.preloadNeighborArtwork() }
            }
            .task { np.preloadNeighborArtwork() }
            .sheet(isPresented: $showSongMenu) {
                if let song = np.queueSongs.indices.contains(np.queueIndex) ? np.queueSongs[np.queueIndex] : nil {
                    PlayerMenuSheet(song: song, onCollapseRequest: { onCollapse() })
                }
            }
            .confirmationDialog("View Artist", isPresented: $showArtistPicker, titleVisibility: .visible) {
                ForEach(availableArtists, id: \.self) { artist in
                    Button(artist.name) {
                        openArtist(artist)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .background(
                Color.clear
                    .detailRouteSheet(item: $pendingRoute)
            )
        }
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack {
            Button(action: {
                Haptics.light()
                onCollapse()
            }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(BouncyScaleButtonStyle(scale: 0.88))

            Spacer()

            Text("Now Playing")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.85))

            Spacer()

            HStack(spacing: 6) {
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        showQueue = true
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(BouncyScaleButtonStyle(scale: 0.88))

                Button {
                    Haptics.light()
                    showSongMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(BouncyScaleButtonStyle(scale: 0.88))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func queueContent(horizontalPadding: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .contentShape(Rectangle().size(width: 60, height: 30))
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showQueue = false
                    }
                }
            QueueView(
                showQueue: $showQueue,
                isShuffleOn: $np.isShuffleOn,
                isRepeatOn: $np.isRepeatOn,
                editingProgress: $editingProgress,
                isEditingSlider: $isEditingSlider,
                pendingRoute: $pendingRoute,
                progressSlider: { progressSlider(horizontalPadding: horizontalPadding) }
            )
        }
    }

    @ViewBuilder
    private func mainPlayerLayout(geometry: GeometryProxy, horizontalPadding: CGFloat, isCompact: Bool) -> some View {
        topBar

        Spacer(minLength: 8)

        artwork
            .frame(
                width: min(geometry.size.width - 56, isCompact ? 280 : 340),
                height: min(geometry.size.width - 56, isCompact ? 280 : 340)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black, radius: 18, y: 8)

        Spacer(minLength: 16)

        titleAndActionsRow
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, isCompact ? 8 : 12)

        progressSlider(horizontalPadding: horizontalPadding)
            .padding(.bottom, isCompact ? 8 : 16)

        playbackControls(isCompact: isCompact)
    }

    private func playbackControls(isCompact: Bool) -> some View {
        PlaybackControlsRow(
            isPlaying: np.isPlaying,
            hasPrevious: np.hasPrevious,
            hasNext: np.hasNext,
            isShuffle: np.isShuffleOn,
            isLiked: isLiked,
            onPrevious: { np.playPrevious() },
            onPlayPause: { player.togglePlayPause() },
            onNext: { np.playNext() },
            onShuffle: { np.isShuffleOn.toggle() },
            onLike: {
                guard let song = currentSongItem else { return }
                Task { await likeStore.toggle(song: song) }
            }
        )
        .scaleEffect(isCompact ? 0.94 : 1)
        .padding(.bottom, isCompact ? 10 : 28)
    }

    // MARK: - Gestures

    /// Swipe left/right on the artwork to skip tracks (toggleable in Settings).
    /// Blocked at the queue's ends (no movement); on skip, the incoming
    /// artwork slides in from the swipe direction.
    private var artworkSwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard settings.artworkSwipeNavigation else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -60, np.hasNext {
                    np.playNext()
                    slideInArtwork(fromLeft: false)
                } else if value.translation.width > 60, np.hasPrevious {
                    np.playPrevious()
                    slideInArtwork(fromLeft: true)
                }
            }
    }

    private func slideInArtwork(fromLeft: Bool) {
        artworkEntryOffset = fromLeft ? -600 : 600
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            artworkEntryOffset = 0
        }
    }

    /// Swipe down anywhere to collapse. Vertical-dominant drags only.
    private var collapseDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard value.translation.height > 0,
                      value.translation.height > abs(value.translation.width) else { return }
                collapseOffset = value.translation.height
            }
            .onEnded { value in
                defer { collapseOffset = 0 }
                let isVertical = value.translation.height > abs(value.translation.width)
                if isVertical, value.translation.height > 140 {
                    onCollapse()
                }
            }
    }

    // MARK: - Player Content

    private var titleAndActionsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(np.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)

            Button(action: handleArtistTap) {
                Text(np.displayArtist)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(AudiaTheme.textSecondary)
                    .lineLimit(1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ArtistTapButtonStyle())
            .disabled(isResolvingArtist || np.displayArtist.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var musicVideoContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        np.isVideoMode = false
                        showQueue = false
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(AudiaTheme.surfaceVariant))
                        .overlay(Circle().stroke(AudiaTheme.surfaceBorder, lineWidth: 1))
                }
                .accessibilityLabel("Return to artwork player")

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            musicVideoStage

            QueueView(
                showQueue: $showQueue,
                isShuffleOn: $np.isShuffleOn,
                isRepeatOn: $np.isRepeatOn,
                editingProgress: $editingProgress,
                isEditingSlider: $isEditingSlider,
                pendingRoute: $pendingRoute,
                progressSlider: { progressSlider(horizontalPadding: 32) },
                isVideoMode: true
            )
            .frame(maxHeight: .infinity)
        }
    }

    private var musicVideoStage: some View {
        artwork
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if !settings.audioOnlyMode, np.isVideoMode, np.hasVideo {
                ZStack {
                    VideoPlayerView()
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .white, location: 0.12),
                                    .init(color: .white, location: 0.95),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                    if !np.isVideoReady {
                        artworkImage
                            .transition(.opacity)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .animation(.easeOut(duration: 0.2), value: np.isVideoReady)
            } else {
                artworkImage
                    .onTapGesture {
                        guard !settings.audioOnlyMode, np.hasVideo else { return }
                        showQueue = true
                        player.setVideoMode()
                    }
            }
        }
        .offset(x: artworkEntryOffset)
        .gesture(artworkSwipe)
    }

    /// Song artwork (or placeholder), filling its container.
    private var artworkImage: some View {
        ZStack {
            if let uiImage = np.thumbnailUIImage {
                let cropped = uiImage.centerCroppedSquare()
                GeometryReader { geo in
                    Image(uiImage: cropped)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note")
                        .font(.system(size: 64, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }

    private func progressSlider(horizontalPadding: CGFloat) -> some View {
        VStack(spacing: 6) {
            ProgressBar(
                progress: Binding(
                    get: { isEditingSlider ? editingProgress : np.progress },
                    set: { editingProgress = $0 }
                ),
                accentColor: np.dominantColors.first ?? .white,
                isPlaying: np.isPlaying,
                onEditingChanged: { editing in
                    if editing {
                        editingProgress = np.progress
                    } else {
                        let target = TimeInterval(editingProgress) * np.duration
                        player.seek(to: target)
                        np.currentTime = target
                        player.updateNowPlayingProgress()
                    }
                    isEditingSlider = editing
                }
            )

            HStack {
                Text(DurationFormat.playbackTime(isEditingSlider
                    ? TimeInterval(editingProgress) * np.duration
                    : np.currentTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()

                Text(DurationFormat.playbackTime(np.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, horizontalPadding)
    }

    // MARK: - Artist Navigation

    private var availableArtists: [YTArtist] {
        let currentSong = np.queueSongs.indices.contains(np.queueIndex) ? np.queueSongs[np.queueIndex] : nil
        if let songArtists = currentSong?.artists, !songArtists.isEmpty {
            let filtered = songArtists.filter { !$0.name.isEmpty }
            if !filtered.isEmpty { return filtered }
        }
        if !np.artists.isEmpty {
            let filtered = np.artists.filter { !$0.name.isEmpty }
            if !filtered.isEmpty { return filtered }
        }
        if !np.artist.isEmpty {
            return [YTArtist(name: np.artist, id: nil)]
        }
        if !np.displayArtist.isEmpty {
            return [YTArtist(name: np.displayArtist, id: nil)]
        }
        return []
    }

    private func handleArtistTap() {
        guard !isResolvingArtist else { return }
        Haptics.light()
        let artists = availableArtists
        if artists.count > 1 {
            showArtistPicker = true
            return
        }
        guard let artist = artists.first else { return }
        openArtist(artist)
    }

    private func openArtist(_ artist: YTArtist) {
        if let id = artist.id, !id.isEmpty {
            navigateToArtist(browseId: id)
            return
        }
        resolveArtistByName(artist.name)
    }

    private func resolveArtistByName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isResolvingArtist = true
        Task {
            defer { isResolvingArtist = false }
            var browseId: String?
            do {
                let json = try await SearchService.shared.search(query: trimmed)
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
                await MainActor.run {
                    navigateToArtist(browseId: browseId)
                }
            }
        }
    }

    private func navigateToArtist(browseId: String) {
        onCollapse()
        AppRouter.shared.open(.artist(browseId: browseId))
    }
}

private struct ArtistTapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1.0)
    }
}

//
//  FullPlayerView.swift
//  Audia
//

import SwiftUI

struct FullPlayerView: View {
    let onCollapse: () -> Void

    @Environment(\.colorScheme) private var colorScheme
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
    @State private var showLyrics = false
    @State private var showTranslation = false
    @State private var isTranslating = false
    @State private var hasLyrics = false
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
                AudiaTheme.background
                    .ignoresSafeArea()

                lyricsAmbientBackground(size: geometry.size)

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
            .animation(.spring(response: 0.5, dampingFraction: 0.86), value: showLyrics)
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
                if let song = currentSongItem {
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
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AudiaTheme.textPrimary)
                    .frame(width: 44, height: 44)
                    .audiaGlassCircle(isActive: false)
            }
            .buttonStyle(BouncyScaleButtonStyle(scale: 0.88))

            Spacer()

            Text("Now Playing")
                .font(.satoshi(size: 17, weight: .bold))
                .foregroundStyle(AudiaTheme.textPrimary)

            Spacer()

            HStack(spacing: 8) {
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                        showQueue = false
                        showLyrics = true
                    }
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(AudiaTheme.textPrimary)
                        .frame(width: 44, height: 44)
                        .audiaGlassCircle(isActive: false)
                }
                .buttonStyle(BouncyScaleButtonStyle(scale: 0.88))
                .accessibilityLabel("Lyrics")

                Button {
                    Haptics.light()
                    showSongMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(AudiaTheme.textPrimary)
                        .frame(width: 44, height: 44)
                        .audiaGlassCircle(isActive: false)
                }
                .buttonStyle(BouncyScaleButtonStyle(scale: 0.88))
                .accessibilityLabel("More options")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 5)
    }

    private func queueContent(horizontalPadding: CGFloat) -> some View {
        VStack(spacing: 0) {
            QueueView(
                showQueue: $showQueue,
                isShuffleOn: $np.isShuffleOn,
                isRepeatOn: $np.isRepeatOn,
                editingProgress: $editingProgress,
                isEditingSlider: $isEditingSlider,
                pendingRoute: $pendingRoute,
                progressSlider: { FullPlayerProgressSlider(horizontalPadding: horizontalPadding) }
            )
        }
    }

    @ViewBuilder
    private func mainPlayerLayout(geometry: GeometryProxy, horizontalPadding: CGFloat, isCompact: Bool) -> some View {
        let artSize = min(geometry.size.width - 56, isCompact ? 280 : 340)
        let heroLayout = showLyrics
            ? AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            : AnyLayout(VStackLayout(alignment: .center, spacing: 12))

        if !showLyrics {
            topBar
                .transition(.opacity)
        }

        heroLayout {
            artwork
                .frame(
                    width: showLyrics ? 54 : artSize,
                    height: showLyrics ? 54 : artSize
                )
                .clipShape(RoundedRectangle(cornerRadius: showLyrics ? 10 : 24, style: .continuous))
                .shadow(
                    color: Color.black.opacity(showLyrics ? 0.35 : (colorScheme == .dark ? 0.6 : 0.15)),
                    radius: showLyrics ? 8 : 18,
                    y: showLyrics ? 4 : 8
                )
                .frame(
                    maxWidth: showLyrics ? nil : .infinity,
                    maxHeight: showLyrics ? nil : .infinity,
                    alignment: .center
                )
                .onTapGesture {
                    if showLyrics {
                        Haptics.light()
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                            showLyrics = false
                        }
                    }
                }

            titleAndActionsRow
                .padding(.horizontal, showLyrics ? 0 : horizontalPadding)

            if showLyrics {
                lyricsHeaderButtons
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, showLyrics ? 16 : 0)
        .padding(.bottom, showLyrics ? 4 : (isCompact ? 12 : 20))

        if showLyrics {
            LyricsScrollSection(
                showTranslation: $showTranslation,
                isTranslating: $isTranslating,
                hasLyrics: $hasLyrics
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }

        FullPlayerProgressSlider(horizontalPadding: horizontalPadding)
            .padding(.bottom, isCompact ? 8 : 16)

        playbackControls(isCompact: isCompact)
    }

    private var lyricsHeaderButtons: some View {
        HStack(spacing: 8) {
            Button {
                Haptics.light()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                    showLyrics = false
                }
            } label: {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(AudiaTheme.textPrimary)
                    .frame(width: 44, height: 44)
                    .audiaGlassCircle(isActive: true)
            }
            .buttonStyle(BouncyScaleButtonStyle(scale: 0.88))
            .accessibilityLabel("Hide lyrics")

            Button {
                Haptics.toggle()
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTranslation.toggle()
                }
            } label: {
                ZStack {
                    if isTranslating {
                        ProgressView()
                            .tint(AudiaTheme.textPrimary)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "translate")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AudiaTheme.textPrimary)
                    }
                }
                .frame(width: 44, height: 44)
                .audiaGlassCircle(isActive: showTranslation)
            }
            .buttonStyle(BouncyScaleButtonStyle(scale: 0.88))
            .disabled(!hasLyrics)
            .opacity(hasLyrics ? 1 : 0.4)
            .accessibilityLabel("Translate lyrics")
        }
    }

    private func lyricsAmbientBackground(size: CGSize) -> some View {
        let isDark = colorScheme == .dark
        return ZStack {
            if let primary = np.dominantColors.first {
                let secondary = np.dominantColors.count > 1 ? np.dominantColors[1] : primary
                LinearGradient(
                    colors: isDark
                        ? [primary.opacity(0.75), secondary.opacity(0.45), Color.black.opacity(0.88)]
                        : [primary.opacity(0.28), secondary.opacity(0.18), Color.white.opacity(0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                AudiaTheme.background
            }

            if let uiImage = np.thumbnailUIImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .saturation(isDark ? 1.45 : 1.15)
                    .blur(radius: 85)
                    .scaleEffect(1.3)
                    .opacity(isDark ? 0.55 : 0.24)
            }

            LinearGradient(
                stops: isDark
                    ? [
                        .init(color: Color.black.opacity(0.28), location: 0.0),
                        .init(color: Color.black.opacity(0.15), location: 0.45),
                        .init(color: Color.black.opacity(0.52), location: 1.0)
                    ]
                    : [
                        .init(color: Color.white.opacity(0.55), location: 0.0),
                        .init(color: Color.white.opacity(0.38), location: 0.45),
                        .init(color: Color.white.opacity(0.65), location: 1.0)
                    ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.65), value: np.videoId)
    }

    private func playbackControls(isCompact: Bool) -> some View {
        PlaybackControlsRow(
            isPlaying: np.isPlaying,
            hasPrevious: np.hasPrevious,
            hasNext: np.hasNext,
            playbackMode: np.playbackMode,
            onPrevious: { np.playPrevious() },
            onPlayPause: { player.togglePlayPause() },
            onNext: { np.playNext() },
            onCyclePlaybackMode: { np.cyclePlaybackMode() },
            onQueue: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    showLyrics = false
                    showQueue = true
                }
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
                    Haptics.trackChanged()
                    np.playNext()
                    slideInArtwork(fromLeft: false)
                } else if value.translation.width > 60, np.hasPrevious {
                    Haptics.trackChanged()
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
                    Haptics.soft()
                    onCollapse()
                }
            }
    }

    // MARK: - Player Content

    private var titleAndActionsRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: showLyrics ? 2 : 4) {
                Text(np.title)
                    .font(.system(size: showLyrics ? 17.5 : 22, weight: .bold, design: .rounded))
                    .foregroundColor(AudiaTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Button(action: handleArtistTap) {
                    Text(np.displayArtist)
                        .font(.system(size: showLyrics ? 14.5 : 15, weight: .medium, design: .rounded))
                        .foregroundColor(AudiaTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ArtistTapButtonStyle())
                .disabled(isResolvingArtist || np.displayArtist.isEmpty)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if !showLyrics {
                Button {
                    Haptics.success()
                    guard let song = currentSongItem else { return }
                    Task { await likeStore.toggle(song: song) }
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.satoshi(size: 22, weight: .medium))
                        .foregroundStyle(isLiked ? AudiaTheme.primary : AudiaTheme.textSecondary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(BouncyScaleButtonStyle(scale: 0.82))
                .accessibilityLabel("Like")
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
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
                        .foregroundStyle(AudiaTheme.textPrimary)
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
                progressSlider: { FullPlayerProgressSlider(horizontalPadding: 32) },
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
                    AudiaTheme.surfaceVariant
                    Image(systemName: "music.note")
                        .font(.system(size: 64, design: .rounded))
                        .foregroundStyle(AudiaTheme.textMuted)
                }
            }
        }
    }

}

// MARK: - Progress Slider (Isolated from parent view re-evaluations)

private struct FullPlayerProgressSlider: View {
    let horizontalPadding: CGFloat
    @Bindable private var np = NowPlaying.shared
    private let player = PlayerController.shared
    @State private var editingProgress: Float = 0
    @State private var isEditingSlider = false

    var body: some View {
        VStack(spacing: 6) {
            ProgressBar(
                progress: Binding(
                    get: { isEditingSlider ? editingProgress : np.progress },
                    set: { editingProgress = $0 }
                ),
                accentColor: np.dominantColors.first ?? AudiaTheme.primary,
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
                    .foregroundStyle(AudiaTheme.textSecondary)

                Spacer()

                Text(DurationFormat.playbackTime(np.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AudiaTheme.textSecondary)
            }
        }
        .padding(.horizontal, horizontalPadding)
    }
}

extension FullPlayerView {

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

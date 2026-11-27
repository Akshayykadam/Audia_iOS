//
//  MiniPlayerBarView.swift
//  Audia
//

import SwiftUI
import Nuke

/// The mini player bar, hosted as the TabView's native bottom accessory.
/// Swiping left/right pages through the queue with the artwork and text sliding
/// together, exactly tracking the drag state. When the tab bar minimizes on
/// scroll the bar collapses into a compact inline form that merges with the
/// tab bar, matching the Apple Music behavior; otherwise it renders as the
/// 48pt floating glass capsule with a bottom progress line.
struct MiniPlayerBarView: View {
    var isAccessory: Bool = false
    var isCompactInline: Bool = false
    var overrideColorScheme: ColorScheme? = nil
    let onExpand: () -> Void

    @Environment(MiniPlayerScrollState.self) private var scrollState
    @Environment(\.colorScheme) private var colorScheme

    private var effectiveColorScheme: ColorScheme {
        overrideColorScheme ?? colorScheme
    }

    private let player = PlayerController.shared
    @Bindable private var np = NowPlaying.shared

    @State private var dragOffset: CGFloat = 0
    @State private var dragAxis: DragAxis?
    @State private var isCommitting = false

    private enum DragAxis {
        case horizontal
        case vertical
    }

    private var isInline: Bool {
        isCompactInline || scrollState.isInline
    }

    private var barHeight: CGFloat {
        if isCompactInline { return 48 }
        return isAccessory ? 52 : 58
    }

    private var artworkSize: CGFloat {
        if isCompactInline { return 34 }
        return isAccessory ? 38 : 42
    }

    private var titleColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var artistColor: Color {
        effectiveColorScheme == .dark ? Color.white.opacity(0.70) : Color.black.opacity(0.78)
    }

    var body: some View {
        let content = HStack(spacing: 0) {
            pagingArea
            HStack(spacing: isCompactInline ? 4 : 6) {
                playPauseButton
                if !isCompactInline {
                    nextButton
                }
            }
            .padding(.trailing, isCompactInline ? 10 : 12)
        }
        .frame(height: barHeight)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            if !isCompactInline {
                MiniPlayerProgressBar()
            }
        }

        Group {
            if isAccessory {
                content
            } else {
                content
                    .clipShape(Capsule())
                    .audiaGlassCapsule()
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.08), radius: 14, y: 5)
                    .padding(.horizontal, 16)
            }
        }
        .onChange(of: np.videoId) { _, _ in
            dragOffset = 0
        }
        .onChange(of: np.queueSongs.count) { _, _ in
            dragOffset = 0
            np.preloadNeighborArtwork()
        }
        .onChange(of: np.queueIndex) { _, _ in
            dragOffset = 0
            np.preloadNeighborArtwork()
        }
        .task { np.preloadNeighborArtwork() }
    }

    // MARK: - Paging area

    private var pagingArea: some View {
        GeometryReader { geo in
            let pageWidth = geo.size.width
            ZStack(alignment: .center) {
                if let prev = prevSong {
                    page(for: prev, width: pageWidth)
                        .offset(x: -pageWidth)
                }
                if let current = currentSong {
                    page(for: current, width: pageWidth)
                }
                if let next = nextSong {
                    page(for: next, width: pageWidth)
                        .offset(x: pageWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(x: dragOffset)
            .clipped()
            .contentShape(Rectangle())
            .gesture(dragGesture(pageWidth: pageWidth))
            .onTapGesture {
                Haptics.light()
                onExpand()
            }
        }
        .frame(height: barHeight)
    }

    private func page(for song: SongItem, width: CGFloat) -> some View {
        HStack(spacing: 10) {
            barArtwork(for: song.videoId, thumbnailUrl: song.thumbnailUrl)

            VStack(alignment: .leading, spacing: 1) {
                if isInline {
                    Text(song.title)
                        .font(.satoshi(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(titleColor)
                } else {
                    MarqueeText(
                        text: song.title,
                        font: .satoshi(size: 15, weight: .semibold),
                        frameHeight: 20,
                        textColor: titleColor
                    )
                }

                Text(artistLine(for: song))
                    .font(.satoshi(size: 13, weight: .medium))
                    .foregroundStyle(artistColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func barArtwork(for videoId: String, thumbnailUrl: String? = nil) -> some View {
        let isCurrent = videoId == np.videoId
        ZStack {
            if isCurrent, let uiImage = np.thumbnailUIImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                MiniArtworkView(videoId: videoId, thumbnailUrl: thumbnailUrl)
            }
        }
        .frame(width: artworkSize, height: artworkSize)
        .clipShape(Circle())
    }

    private var playPauseButton: some View {
        Button(action: {
            Haptics.medium()
            player.togglePlayPause()
        }) {
            Image(systemName: np.isPlaying ? "pause.fill" : "play.fill")
                .contentTransition(.symbolEffect(.replace))
                .font(.system(size: isCompactInline ? 15 : (isAccessory ? 17 : 20), weight: .semibold))
                .foregroundStyle(titleColor)
                .frame(width: isCompactInline ? 30 : 34, height: isCompactInline ? 30 : 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(BouncyScaleButtonStyle(scale: 0.86))
        .accessibilityLabel(np.isPlaying ? "Pause" : "Play")
    }

    private var nextButton: some View {
        Button(action: {
            Haptics.trackChanged()
            np.playNext()
        }) {
            Image(systemName: "forward.end.fill")
                .font(.system(size: isAccessory ? 15 : 17, weight: .semibold))
                .foregroundStyle(titleColor.opacity(0.85))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(BouncyScaleButtonStyle(scale: 0.86))
        .accessibilityLabel("Next song")
    }

    // MARK: - Data

    private var currentSong: SongItem? {
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
            thumbnailUrl: nil,
            isExplicit: false,
            playlistId: nil,
            likeStatus: nil
        )
    }

    private var prevSong: SongItem? {
        guard np.queueSongs.indices.contains(np.queueIndex - 1) else { return nil }
        return np.queueSongs[np.queueIndex - 1]
    }

    /// Artist line for a queued song, falling back to the resolved author
    /// (what the big player shows via `displayArtist`) when the queued item
    /// carries no artist runs — e.g. videos or cache-repaired songs.
    private func artistLine(for song: SongItem) -> String {
        let own = artistDisplayString(from: song.artists)
        if !own.isEmpty { return own }
        if song.videoId == np.videoId { return np.displayArtist }
        return own
    }

    private var nextSong: SongItem? {
        guard np.queueSongs.indices.contains(np.queueIndex + 1) else { return nil }
        return np.queueSongs[np.queueIndex + 1]
    }

    // MARK: - Gesture

    private func dragGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard !isCommitting else { return }
                if dragAxis == nil {
                    dragAxis = abs(value.translation.width) > abs(value.translation.height)
                        ? .horizontal
                        : .vertical
                }
                guard dragAxis == .horizontal else { return }

                let minOffset = nextSong != nil ? -pageWidth : 0
                let maxOffset = prevSong != nil ? pageWidth : 0
                dragOffset = min(max(value.translation.width, minOffset), maxOffset)
            }
            .onEnded { value in
                guard !isCommitting else { return }
                defer { dragAxis = nil }

                switch dragAxis {
                case .horizontal:
                    if dragOffset <= -pageWidth * 0.35, nextSong != nil {
                        commitSwipe(to: .next, pageWidth: pageWidth)
                    } else if dragOffset >= pageWidth * 0.35, prevSong != nil {
                        commitSwipe(to: .previous, pageWidth: pageWidth)
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            dragOffset = 0
                        }
                    }
                case .vertical:
                    if value.translation.height < -40 {
                        onExpand()
                    }
                case nil:
                    break
                }
            }
    }

    private enum SwipeDirection {
        case next
        case previous
    }

    private func commitSwipe(to direction: SwipeDirection, pageWidth: CGFloat) {
        isCommitting = true
        Haptics.trackChanged()
        let target: CGFloat = direction == .next ? -pageWidth : pageWidth
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            dragOffset = target
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            switch direction {
            case .next: np.playNext()
            case .previous: np.playPrevious()
            }
            withAnimation(nil) { dragOffset = 0 }
            isCommitting = false
        }
    }
}

// MARK: - Per-song artwork (memory-cache fast path)

@MainActor
private struct MiniArtworkView: View {
    let videoId: String
    var thumbnailUrl: String? = nil

    @State private var uiImage: UIImage?

    var body: some View {
        ZStack {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                AudiaTheme.surfaceVariant
                Image(systemName: "music.note")
                    .font(.satoshi(size: 20))
                    .foregroundStyle(AudiaTheme.textMuted)
            }
        }
        .onAppear { load() }
    }

    private func load() {
        let preferred = ArtworkURLs.highRes(thumbnailUrl)
            ?? ArtworkURLs.sdVariant(NowPlaying.artworkURL(for: videoId))
            ?? NowPlaying.artworkURL(for: videoId)
        if let url = URL(string: preferred), let cached = ArtworkLoader.cachedImage(for: url) {
            uiImage = cached.centerCroppedSquare()
            return
        }
        if let cached = cachedArtwork(for: videoId) {
            uiImage = cached
            return
        }
        guard let url = URL(string: preferred) else { return }
        loggedTask(Log.nowPlaying, "Mini artwork load failed") {
            let image = try await ArtworkLoader.image(for: url)
            let cropped = image.centerCroppedSquare()
            await MainActor.run { uiImage = cropped }
        }
    }
}

@MainActor
private func cachedArtwork(for videoId: String) -> UIImage? {
    guard let url = URL(string: NowPlaying.artworkURL(for: videoId)) else { return nil }
    return ArtworkLoader.cachedImage(for: url)?.centerCroppedSquare()
}

// MARK: - Isolated Progress Bar

private struct MiniPlayerProgressBar: View {
    @Bindable private var np = NowPlaying.shared

    var body: some View {
        GeometryReader { geo in
            let progressWidth = max(0, min(geo.size.width, geo.size.width * CGFloat(np.progress)))
            Capsule()
                .fill(AudiaTheme.primary)
                .frame(width: progressWidth, height: 3)
        }
        .frame(height: 3)
        .allowsHitTesting(false)
        .clipShape(Capsule())
    }
}

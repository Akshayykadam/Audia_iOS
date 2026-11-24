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
    let onExpand: () -> Void

    @Environment(MiniPlayerScrollState.self) private var scrollState
    @Environment(\.colorScheme) private var colorScheme

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
        scrollState.isInline
    }

    private var barHeight: CGFloat {
        72
    }

    private var artworkSize: CGFloat {
        54
    }

    private var titleColor: Color {
        AudiaTheme.textPrimary
    }

    private var artistColor: Color {
        AudiaTheme.textSecondary
    }

    var body: some View {
        HStack(spacing: 0) {
            pagingArea
            HStack(spacing: 14) {
                playPauseButton
                nextButton
            }
            .padding(.trailing, 16)
        }
        .frame(height: barHeight)
        .frame(maxWidth: .infinity)
        .background(
            Capsule()
                .fill(AudiaTheme.surface)
        )
        .overlay(alignment: .bottom) { MiniPlayerProgressBar() }
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AudiaTheme.surfaceBorder, lineWidth: 1.5))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.6 : 0.08), radius: 14, y: 5)
        .padding(.horizontal, 16)
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
        HStack(spacing: 12) {
            barArtwork(for: song.videoId)

            VStack(alignment: .leading, spacing: 3) {
                if isInline {
                    Text(song.title)
                        .font(.satoshi(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(titleColor)
                } else {
                    MarqueeText(
                        text: song.title,
                        font: .satoshi(size: 16, weight: .semibold),
                        frameHeight: 24,
                        textColor: titleColor
                    )
                }

                Text(artistLine(for: song))
                    .font(.satoshi(size: 14, weight: .medium))
                    .foregroundStyle(artistColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func barArtwork(for videoId: String) -> some View {
        let isCurrent = videoId == np.videoId
        ZStack {
            if isCurrent, let uiImage = np.thumbnailUIImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                MiniArtworkView(videoId: videoId)
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
            ZStack {
                Circle()
                    .fill(AudiaTheme.primaryLight)
                    .frame(width: 44, height: 44)
                Image(systemName: np.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .font(.satoshi(size: 18, weight: .bold))
                    .foregroundStyle(AudiaTheme.onPrimary)
            }
        }
        .buttonStyle(BouncyScaleButtonStyle(scale: 0.90))
        .accessibilityLabel(np.isPlaying ? "Pause" : "Play")
    }

    private var nextButton: some View {
        Button(action: {
            Haptics.light()
            np.playNext()
        }) {
            Image(systemName: "forward.end.fill")
                .font(.satoshi(size: 19, weight: .semibold))
                .foregroundStyle(AudiaTheme.textSecondary)
                .frame(width: 36, height: 36)
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
        Haptics.selection()
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
        if let cached = cachedArtwork(for: videoId) {
            uiImage = cached
            return
        }
        guard let url = URL(string: NowPlaying.artworkURL(for: videoId)) else { return }
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

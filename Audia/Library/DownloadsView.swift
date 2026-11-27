//
//  DownloadsView.swift
//  Audia
//

import SwiftUI

struct DownloadsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var pendingRoute: DetailRoute?
    @State private var showMoreSheet = false
    @State private var songs: [SongItem] = []
    @State private var barProgress: CGFloat = 0

    private static let barFadeStart: CGFloat = 160
    private static let barFadeDistance: CGFloat = 60
    private static let iPadBannerHeight: CGFloat = 400

    private var tracks: [DownloadedTrackEntity] { downloadManager.tracks }
    private var activeDownloads: [(videoId: String, progress: Double)] {
        downloadManager.activeDownloads
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if !downloadManager.isLoaded {
                    LoadingStateView("Loading downloads…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tracks.isEmpty && activeDownloads.isEmpty {
                    emptyView
                } else {
                    contentView
                }
            }

            customTopBar
        }
        .audiaScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showMoreSheet) {
            DownloadsMoreSheet(songs: songs)
        }
        .task {
            if !downloadManager.isLoaded {
                await downloadManager.reload()
            }
            songs = tracks.map { SongItem(entity: $0) }
        }
        .onChange(of: downloadManager.tracks) { _, newTracks in
            songs = newTracks.map { SongItem(entity: $0) }
        }
        .detailRouteSheet(item: $pendingRoute)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Downloads Yet", systemImage: "arrow.down.circle")
        } description: {
            Text("Save songs for offline listening from the player menu, or enable auto-download when you like a track.")
        }
        .miniPlayerTracksScroll()
    }

    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                headerBannerSection

                VStack(alignment: .leading, spacing: 14) {
                    let count = tracks.count
                    let totalDuration = tracks.reduce(0) { $0 + $1.duration }
                    if count > 0 {
                        let meta = totalDuration > 0
                            ? "\(count) \(count == 1 ? "song" : "songs") • \(totalDuration.formattedDuration)"
                            : "\(count) \(count == 1 ? "song" : "songs")"
                        Text(meta)
                            .font(.satoshi(.subheadline, weight: .medium))
                            .foregroundStyle(AudiaTheme.textSecondary)
                    }

                    if !songs.isEmpty {
                        PlaybackControlsView(
                            horizontalPadding: 0,
                            onPlay: playAll,
                            onShuffle: shufflePlay
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, horizontalSizeClass == .regular ? 32 : DesignTokens.screenHPadding)
                .padding(.top, 8)
                .padding(.bottom, 16)

                if !activeDownloads.isEmpty {
                    activeDownloadsSection
                }

                if !songs.isEmpty {
                    songList
                }
            }
            .appBottomClearance()
        }
        .refreshable { await downloadManager.reload() }
        .scrollDisabled(!downloadManager.isLoaded)
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
    }

    private var customTopBar: some View {
        HStack(spacing: 12) {
            Button(action: { dismiss() }) {
                ZStack {
                    Image(systemName: "chevron.left")
                        .font(.satoshi(size: 16, weight: .semibold))
                        .foregroundStyle(AudiaTheme.textPrimary)
                }
                .frame(width: 40, height: 40)
                .audiaGlassCircle(isActive: false)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text("Downloads")
                .font(.satoshi(size: 17, weight: .semibold))
                .foregroundStyle(AudiaTheme.textPrimary)
                .lineLimit(1)
                .opacity(barProgress)

            Spacer(minLength: 0)

            Button(action: { showMoreSheet = true }) {
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
            .buttonStyle(.plain)
            .accessibilityLabel("More options")
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

    @ViewBuilder
    private var headerBannerSection: some View {
        if horizontalSizeClass == .regular {
            GeometryReader { proxy in
                headerBanner(size: CGSize(width: proxy.size.width, height: Self.iPadBannerHeight))
            }
            .frame(height: Self.iPadBannerHeight)
        } else {
            GeometryReader { proxy in
                headerBanner(size: proxy.size)
            }
            .aspectRatio(1, contentMode: .fit)
        }
    }

    private func headerBanner(size: CGSize) -> some View {
        ZStack(alignment: .bottomLeading) {
            AudiaTheme.background

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.58, blue: 0.62),
                        Color(red: 0.12, green: 0.38, blue: 0.68),
                        Color(red: 0.08, green: 0.18, blue: 0.36)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color.white.opacity(0.22), Color.clear],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: size.width * 0.75
                )
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: min(size.width, size.height) * 0.28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                    .offset(y: -16)
            }
            .frame(width: size.width, height: size.height)
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

            Text("Downloads")
                .font(.satoshi(size: 38, weight: .bold))
                .foregroundStyle(AudiaTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .shadow(color: AudiaTheme.background.opacity(0.4), radius: 6, y: 2)
                .padding(.horizontal, horizontalSizeClass == .regular ? 32 : DesignTokens.screenHPadding)
                .padding(.bottom, 20)
        }
    }

    private var activeDownloadsSection: some View {
        VStack(spacing: 0) {
            SectionLabel(title: "Downloading", systemImage: "arrow.down.circle")
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            ForEach(activeDownloads, id: \.videoId) { item in
                ActiveDownloadRow(videoId: item.videoId, progress: item.progress)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
        }
        .padding(.bottom, 16)
    }

    private var songList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.videoId) { index, song in
                SongRowView(
                    song: song,
                    artSize: 48,
                    artRadius: 8,
                    onTap: { playSong(song) },
                    onNavigate: { pendingRoute = $0 }
                )

                if index < songs.count - 1 {
                    Divider()
                        .padding(.leading, 76)
                }
            }
        }
    }

    private func playAll() {
        let songs = songs
        guard !songs.isEmpty else { return }
        NowPlaying.shared.setQueue(songs, startIndex: 0)
        NowPlaying.shared.update(with: songs[0])
        Task { await playLocal(songs[0]) }
    }

    private func shufflePlay() {
        let songs = songs.shuffled()
        guard !songs.isEmpty else { return }
        NowPlaying.shared.setQueue(songs, startIndex: 0)
        NowPlaying.shared.update(with: songs[0])
        Task { await playLocal(songs[0]) }
    }

    private func playSong(_ song: SongItem) {
        let songs = songs
        if let index = songs.firstIndex(where: { $0.videoId == song.videoId }) {
            NowPlaying.shared.setQueue(songs, startIndex: index)
        } else {
            NowPlaying.shared.setQueue([song], startIndex: 0)
        }
        NowPlaying.shared.update(with: song)
        Task { await playLocal(song) }
    }

    private func playLocal(_ song: SongItem) async {
        guard let localURL = await downloadManager.localURL(for: song.videoId) else { return }
        let artists = song.artists
        let displayArtist = artists.map(\.name).joined(separator: ", ")
        await PlayerController.shared.play(
            url: localURL.absoluteString,
            title: song.title,
            artist: displayArtist,
            videoId: song.videoId,
            duration: TimeInterval(song.duration),
            artists: artists
        )
        await MainActor.run {
            NowPlaying.shared.updateVideoAvailability()
        }
    }
}

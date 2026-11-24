//
//  QueueView.swift
//  Audia
//

import SwiftUI

struct QueueView<ProgressSlider: View>: View {
    private let np = NowPlaying.shared
    private let player = PlayerController.shared
    @ObservedObject private var likeStore = LikeStore.shared

    @Binding var showQueue: Bool
    @Binding var isShuffleOn: Bool
    @Binding var isRepeatOn: Bool
    @Binding var editingProgress: Float
    @Binding var isEditingSlider: Bool
    let pendingRoute: Binding<DetailRoute?>
    @ViewBuilder var progressSlider: () -> ProgressSlider
    var isVideoMode: Bool = false

    var body: some View {
        queueContent
            .simultaneousGesture(backSwipeGesture)
    }

    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                guard value.startLocation.x <= 28,
                      isHorizontal,
                      value.translation.width > 80 else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    if isVideoMode {
                        np.isVideoMode = false
                    }
                    showQueue = false
                }
            }
    }

    // MARK: - Queue Content

    private var queueContent: some View {
        VStack(spacing: 0) {
            if !isVideoMode {
                navigationBar
            }

            ScrollViewReader { proxy in
                List {
                    // 1. Previously Played (if any)
                    if !playedSongs.isEmpty {
                        historyHeader
                            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 4, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                        ForEach(Array(playedSongs.enumerated()), id: \.element.videoId) { index, song in
                            playedRow(song: song, index: index)
                        }
                    }

                    // 2. Currently Playing
                    if currentSongItem != nil {
                        nowPlayingHeader
                            .listRowInsets(EdgeInsets(top: playedSongs.isEmpty ? 6 : 14, leading: 20, bottom: 4, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                        nowPlayingCard
                            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    // 3. Up Next
                    upNextHeader
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 4, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    if upcomingSongs.isEmpty {
                        emptyUpcomingView
                    } else {
                        ForEach(Array(upcomingSongs.enumerated()), id: \.element.videoId) { localIndex, song in
                            upcomingRow(song: song, localIndex: localIndex)
                        }
                        .onMove(perform: moveUpcomingSongs)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .layoutPriority(1)
                .onAppear {
                    if let song = currentSongItem {
                        proxy.scrollTo(song.videoId, anchor: .center)
                    }
                }
            }

            if isVideoMode {
                PlayerTransportAirPlayFooter(
                    isPlaying: np.isPlaying,
                    hasPrevious: np.hasPrevious,
                    hasNext: np.hasNext,
                    onPrevious: { np.playPrevious() },
                    onPlayPause: { player.togglePlayPause() },
                    onNext: { np.playNext() }
                )
            } else {
                VStack(spacing: 12) {
                    progressSlider()
                        .padding(.top, 8)

                    PlaybackControlsRow(
                        isPlaying: np.isPlaying,
                        hasPrevious: np.hasPrevious,
                        hasNext: np.hasNext,
                        onPrevious: { np.playPrevious() },
                        onPlayPause: { player.togglePlayPause() },
                        onNext: { np.playNext() }
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: np.isPlaying)
                }
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showQueue = false
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.satoshi(size: 14, weight: .bold))
                    .foregroundStyle(AudiaTheme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(AudiaTheme.surfaceVariant))
                    .overlay(Circle().stroke(AudiaTheme.surfaceBorder, lineWidth: 1))
            }

            Spacer()

            VStack(spacing: 2) {
                Text("Queue")
                    .font(.satoshi(size: 18, weight: .bold))
                    .foregroundStyle(AudiaTheme.textPrimary)
                if !np.queueSongs.isEmpty {
                    Text("\(np.queueSongs.count) \(np.queueSongs.count == 1 ? "track" : "tracks")")
                        .font(.satoshi(size: 13.5, weight: .medium))
                        .foregroundStyle(AudiaTheme.textMuted)
                }
            }

            Spacer()

            if upcomingSongsCount > 0 {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        clearUpcomingQueue()
                    }
                } label: {
                    Text("Clear")
                        .font(.satoshi(size: 13.5, weight: .semibold))
                        .foregroundStyle(AudiaTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(AudiaTheme.surfaceVariant))
                        .overlay(Capsule().stroke(AudiaTheme.surfaceBorder, lineWidth: 1))
                }
            } else {
                Color.clear.frame(width: 34, height: 34)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    // MARK: - Now Playing Card

    private var currentSongItem: SongItem? {
        if np.queueSongs.indices.contains(np.queueIndex) {
            return np.queueSongs[np.queueIndex]
        }
        return nil
    }

    private var nowPlayingHeader: some View {
        HStack {
            Text("Now Playing")
                .font(.satoshi(size: 13, weight: .bold))
                .foregroundStyle(AudiaTheme.textMuted)
                .textCase(.uppercase)
                .tracking(0.6)

            Spacer()
        }
    }

    private var nowPlayingCard: some View {
        Group {
            if let song = currentSongItem {
                HStack(spacing: 12) {
                    if let uiImage = np.thumbnailUIImage {
                        Image(uiImage: uiImage.centerCroppedSquare())
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        AsyncImageView(url: song.thumbnailUrl)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.title)
                            .font(.satoshi(size: 15, weight: .semibold))
                            .foregroundStyle(AudiaTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        let artistStr = song.artists.map(\.name).joined(separator: ", ")
                        if !artistStr.isEmpty {
                            Text(artistStr)
                                .font(.satoshi(size: 13))
                                .foregroundStyle(AudiaTheme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AudiaTheme.surfaceVariant)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AudiaTheme.surfaceBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        showQueue = false
                    }
                }
            }
        }
    }

    // MARK: - Up Next Header

    private var upcomingSongsCount: Int {
        guard np.queueSongs.indices.contains(np.queueIndex) else { return 0 }
        return max(0, np.queueSongs.count - np.queueIndex - 1)
    }

    private var upNextHeader: some View {
        HStack {
            HStack(spacing: 6) {
                Text("Up Next")
                    .font(.satoshi(size: 13, weight: .bold))
                    .foregroundStyle(AudiaTheme.textMuted)
                    .textCase(.uppercase)
                    .tracking(0.6)

                if upcomingSongsCount > 0 {
                    Text("(\(upcomingSongsCount))")
                        .font(.satoshi(size: 13, weight: .semibold))
                        .foregroundStyle(AudiaTheme.textMuted)
                }
            }

            Spacer()
        }
    }

    // MARK: - Queue Data & Actions

    private var upcomingSongs: [SongItem] {
        guard np.queueSongs.indices.contains(np.queueIndex + 1) else { return [] }
        return Array(np.queueSongs[(np.queueIndex + 1)...])
    }

    private var playedSongs: [SongItem] {
        guard np.queueIndex > 0, !np.queueSongs.isEmpty else { return [] }
        let end = min(np.queueIndex, np.queueSongs.count)
        return Array(np.queueSongs[0..<end])
    }

    private var historyHeader: some View {
        HStack {
            Text("Previously Played")
                .font(.satoshi(size: 13, weight: .bold))
                .foregroundStyle(AudiaTheme.textMuted)
                .textCase(.uppercase)
                .tracking(0.6)

            Spacer()
        }
    }

    private func upcomingRow(song: SongItem, localIndex: Int) -> some View {
        let actualIndex = np.queueIndex + 1 + localIndex
        return Button {
            playSong(at: actualIndex)
        } label: {
            QueueSongRow(
                song: song,
                isCurrent: false,
                isPlayed: false
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation(.spring(response: 0.3)) {
                    removeSong(at: actualIndex)
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func playedRow(song: SongItem, index: Int) -> some View {
        Button {
            playSong(at: index)
        } label: {
            QueueSongRow(
                song: song,
                isCurrent: false,
                isPlayed: true
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation(.spring(response: 0.3)) {
                    removeSong(at: index)
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private var emptyUpcomingView: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.satoshi(size: 26))
                .foregroundStyle(AudiaTheme.textMuted.opacity(0.4))
                .padding(.bottom, 2)
            Text("No upcoming tracks")
                .font(.satoshi(size: 16, weight: .semibold))
                .foregroundStyle(AudiaTheme.textMuted)
            Text("Queue is empty. Songs you add will appear here.")
                .font(.satoshi(size: 14))
                .foregroundStyle(AudiaTheme.textMuted.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func moveUpcomingSongs(from source: IndexSet, to destination: Int) {
        let offset = np.queueIndex + 1
        let mappedSource = IndexSet(source.map { $0 + offset })
        let mappedDestination = destination + offset
        np.moveQueueSongs(from: mappedSource, to: mappedDestination)
    }

    private func clearUpcomingQueue() {
        guard np.queueSongs.indices.contains(np.queueIndex) else { return }
        np.queueSongs = Array(np.queueSongs[0...np.queueIndex])
        np.persistQueueState()
    }

    private func playSong(at index: Int) {
        guard np.queueSongs.indices.contains(index) else { return }
        np.lastManualSkipTime = Date()
        np.queueIndex = index
        np.playCurrentSong(logContext: "resolveAndPlay", manageResolvingFlag: false)
    }

    private func removeSong(at index: Int) {
        guard np.queueSongs.indices.contains(index) else { return }
        let wasCurrent = index == np.queueIndex
        let removedVideoId = np.queueSongs[index].videoId
        np.queueSongs.remove(at: index)
        if wasCurrent {
            if np.queueSongs.isEmpty {
                np.queueIndex = 0
                np.isPlaying = false
                np.persistQueueState()
                Task { @MainActor in PlayerController.shared.setPaused(true) }
                return
            }
            let nextIndex = min(index, np.queueSongs.count - 1)
            np.queueIndex = nextIndex
            let song = np.queueSongs[nextIndex]
            np.update(with: song)
            loggedTask(Log.nowPlaying, "removeSong auto-play failed") {
                try await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId)
            }
        } else {
            np.repairQueueIndex()
        }
        np.persistQueueState()
        if !wasCurrent && removedVideoId == np.videoId {
            np.repairQueueIndex()
        }
    }
}

// MARK: - Queue Song Row

struct QueueSongRow: View {
    let song: SongItem
    var isCurrent = false
    var isPlayed = false

    var body: some View {
        HStack(spacing: 12) {
            AsyncImageView(url: song.thumbnailUrl)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(isPlayed ? 0.45 : 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.satoshi(size: 16, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                let artistStr = song.artists.map(\.name).joined(separator: ", ")
                if !artistStr.isEmpty {
                    Text(artistStr)
                        .font(.satoshi(size: 14))
                        .foregroundStyle(AudiaTheme.textSecondary.opacity(isPlayed ? 0.5 : 0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            Image(systemName: "line.3.horizontal")
                .font(.satoshi(size: 15, weight: .regular))
                .foregroundStyle(AudiaTheme.textMuted.opacity(0.4))
                .padding(.leading, 6)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.2), value: isCurrent)
    }

    private var titleColor: Color {
        isPlayed ? AudiaTheme.textMuted : AudiaTheme.textPrimary
    }
}

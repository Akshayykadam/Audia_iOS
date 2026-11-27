//
//  NowPlaying.swift
//  Audia
//

import AVFoundation
import Foundation
import MediaPlayer
import Observation
import Nuke
import SwiftUI

enum PlaybackMode: String, Codable, CaseIterable {
    case off
    case shuffle
    case repeatAll
    case repeatOne

    var iconName: String {
        switch self {
        case .off, .shuffle: return "shuffle"
        case .repeatAll: return "repeat"
        case .repeatOne: return "repeat.1"
        }
    }

    var isActive: Bool {
        self != .off
    }

    var accessibilityLabel: String {
        switch self {
        case .off: return "Shuffle off"
        case .shuffle: return "Shuffle on"
        case .repeatAll: return "Repeat all"
        case .repeatOne: return "Repeat one song"
        }
    }
}

@Observable
@MainActor
final class NowPlaying {
    static let shared = NowPlaying()

    var title = ""
    var artist = ""
    var albumTitle = ""
    var videoId: String?
    var artists: [YTArtist] = []
    var isPlaying = false {
        didSet {
            if isPlaying != oldValue {
                MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
                WidgetBridge.shared.syncPlayback(from: self)
            }
        }
    }
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var progress: Float {
        duration > 0 ? Float(currentTime / duration) : 0
    }
    var thumbnailImage: Image?
    var thumbnailUIImage: UIImage?
    var thumbnailVersion = 0
    var dominantColors: [Color] = [Color.black, Color.black]

    var accentColor: Color? {
        guard videoId != nil, let primary = dominantColors.first else { return nil }
        return primary
    }

    var queueSongs: [SongItem] = []
    var queueIndex = 0

    var playbackMode: PlaybackMode = .off

    var isShuffleOn: Bool {
        get { playbackMode == .shuffle }
        set {
            if newValue {
                if playbackMode != .shuffle {
                    shuffleQueue()
                }
            } else if playbackMode == .shuffle {
                disableShuffle()
            }
        }
    }

    var isRepeatOn: Bool {
        get { playbackMode == .repeatOne }
        set {
            if newValue {
                if playbackMode == .shuffle { disableShuffle() }
                playbackMode = .repeatOne
            } else if playbackMode == .repeatOne {
                playbackMode = .off
            }
            persistQueueState()
        }
    }

    var hasVideo: Bool = false
    var isVideoMode: Bool = false
    var isVideoReady: Bool = false
    var musicVideoType: String?

    private var originalQueue: [SongItem]?

    var hasNext: Bool {
        queueIndex + 1 < queueSongs.count || (playbackMode == .repeatAll && !queueSongs.isEmpty)
    }

    var hasPrevious: Bool {
        queueIndex > 0
    }

    var isBarPresented: Bool {
        videoId != nil
    }

    private var timer: Timer?
    var lastManualSkipTime: Date?
    private var isResolvingNext = false
    /// Timestamps of the last mid-play failure per videoId, to bound retries.
    private var lastFailureAt: [String: Date] = [:]

    private static let queueKey = "nowPlaying.queue"
    private static let queueIndexKey = "nowPlaying.queueIndex"
    private static let shuffleKey = "nowPlaying.shuffle"
    private static let repeatKey = "nowPlaying.repeat"
    private static let playbackModeKey = "nowPlaying.playbackMode"

    private init() {
        Task { @MainActor in
            self.restoreQueueIfNeeded()
        }
    }

    deinit {
        Task { @MainActor [weak self] in self?.stopTimer() }
    }

    // MARK: - Persistent queue

    private func restoreQueueIfNeeded() {
        guard SettingsStore.shared.persistQueue,
              let data = UserDefaults.standard.data(forKey: Self.queueKey),
              let songs = try? JSONDecoder().decode([SongItem].self, from: data),
              !songs.isEmpty else { return }
        queueSongs = songs
        // integer(forKey:) returns 0 even when key missing – distinguish via object(forKey:)
        let storedIndex: Int
        if UserDefaults.standard.object(forKey: Self.queueIndexKey) != nil {
            storedIndex = UserDefaults.standard.integer(forKey: Self.queueIndexKey)
        } else {
            storedIndex = 0
        }
        queueIndex = min(max(storedIndex, 0), songs.count - 1)
        if let rawMode = UserDefaults.standard.string(forKey: Self.playbackModeKey),
           let mode = PlaybackMode(rawValue: rawMode) {
            playbackMode = mode
        } else if UserDefaults.standard.bool(forKey: Self.repeatKey) {
            playbackMode = .repeatOne
        } else if UserDefaults.standard.bool(forKey: Self.shuffleKey) {
            playbackMode = .shuffle
        } else {
            playbackMode = .off
        }
        queueIndex = max(0, queueIndex)
        if songs.indices.contains(queueIndex) {
            update(with: songs[queueIndex], preloadNext: false)
            isPlaying = false
            stopTimer()
        }
    }

    func persistQueueState() {
        if !queueSongs.isEmpty {
            WidgetBridge.shared.syncRecentSongs(queueSongs)
        }
        guard SettingsStore.shared.persistQueue else { return }
        if queueSongs.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.queueKey)
            UserDefaults.standard.removeObject(forKey: Self.queueIndexKey)
            UserDefaults.standard.removeObject(forKey: Self.shuffleKey)
            UserDefaults.standard.removeObject(forKey: Self.repeatKey)
            UserDefaults.standard.removeObject(forKey: Self.playbackModeKey)
            return
        }
        if let data = try? JSONEncoder().encode(queueSongs) {
            UserDefaults.standard.set(data, forKey: Self.queueKey)
        }
        UserDefaults.standard.set(queueIndex, forKey: Self.queueIndexKey)
        UserDefaults.standard.set(isShuffleOn, forKey: Self.shuffleKey)
        UserDefaults.standard.set(isRepeatOn, forKey: Self.repeatKey)
        UserDefaults.standard.set(playbackMode.rawValue, forKey: Self.playbackModeKey)
    }

    func setQueue(_ songs: [SongItem], startIndex: Int) {
        queueSongs = songs
        queueIndex = min(max(startIndex, 0), max(songs.count - 1, 0))
        originalQueue = nil
        if playbackMode == .shuffle {
            playbackMode = .off
        }
        persistQueueState()
    }

    /// Ensures `queueIndex` points at a valid entry
    func repairQueueIndex() {
        if queueSongs.isEmpty {
            queueIndex = 0
            return
        }
        if let videoId, let idx = queueSongs.firstIndex(where: { $0.videoId == videoId }) {
            queueIndex = idx
        } else {
            queueIndex = min(max(queueIndex, 0), queueSongs.count - 1)
        }
    }

    func upcomingSongs(prefixLimit: Int? = nil) -> [SongItem] {
        let next = queueIndex + 1
        guard queueSongs.indices.contains(next) else { return [] }
        let rest = Array(queueSongs[next...])
        guard let prefixLimit else { return rest }
        return Array(rest.prefix(prefixLimit))
    }

    /// Cycles the mode button: Off -> Shuffle -> Repeat All -> Repeat One -> Off.
    func cyclePlaybackMode() {
        switch playbackMode {
        case .off:
            shuffleQueue()
        case .shuffle:
            disableShuffle()
            playbackMode = .repeatAll
            persistQueueState()
        case .repeatAll:
            playbackMode = .repeatOne
            persistQueueState()
        case .repeatOne:
            playbackMode = .off
            persistQueueState()
        }
    }

    /// Shuffles upcoming songs, keeping the current one; tapping again re-shuffles.
    func shuffleQueue() {
        guard queueSongs.count > 1 else {
            playbackMode = .shuffle
            persistQueueState()
            return
        }
        if originalQueue == nil {
            originalQueue = queueSongs
        }
        let prefix = queueIndex > 0 ? Array(queueSongs[0..<queueIndex]) : []
        let current = queueSongs[queueIndex]
        var rest = queueIndex + 1 < queueSongs.count ? Array(queueSongs[(queueIndex + 1)...]) : []
        rest.shuffle()
        queueSongs = prefix + [current] + rest
        queueIndex = prefix.count
        playbackMode = .shuffle
        persistQueueState()
    }

    /// Restore the original (unshuffled) queue order.
    func disableShuffle() {
        guard queueSongs.indices.contains(queueIndex) else {
            playbackMode = .off
            return
        }
        if let orig = originalQueue {
            let currentVideoId = queueSongs[queueIndex].videoId
            queueSongs = orig
            // The shuffled index is meaningless against the original array
            // (radio appends, deletes and reorders change lengths).
            let restored = orig.firstIndex(where: { $0.videoId == currentVideoId }) ?? queueIndex
            queueIndex = min(restored, max(orig.count - 1, 0))
        }
        originalQueue = nil
        if playbackMode == .shuffle {
            playbackMode = .off
        }
        persistQueueState()
    }

    func moveQueueSongs(from source: IndexSet, to destination: Int) {
        guard !source.isEmpty, queueSongs.indices.contains(source.first ?? -1) else { return }
        queueSongs.move(fromOffsets: source, toOffset: destination)
        repairQueueIndex()
        persistQueueState()
    }

    func repeatCurrent() {
        guard queueSongs.indices.contains(queueIndex) else { return }
        playCurrentSong(logContext: "repeatCurrent")
    }

    func playNext(automatic: Bool = false) {
        if !automatic && !SyncPlayManager.shared.isApplyingRemoteCommand,
           SyncPlayManager.shared.handleUserSkipNext() {
            return
        }
        guard hasNext else { return }
        guard !isResolvingNext else { return }
        if !automatic { lastManualSkipTime = Date() }
        if queueIndex + 1 < queueSongs.count {
            queueIndex += 1
            playCurrentSong(logContext: "playNext")
        } else if playbackMode == .repeatAll, !queueSongs.isEmpty {
            queueIndex = 0
            playCurrentSong(logContext: "repeatAll")
        }
    }

    func playPrevious() {
        if !SyncPlayManager.shared.isApplyingRemoteCommand,
           SyncPlayManager.shared.handleUserSkipPrevious() {
            return
        }
        if currentTime > 3.0 {
            PlayerController.shared.seek(to: 0)
            return
        }
        guard hasPrevious else {
            PlayerController.shared.seek(to: 0)
            return
        }
        guard !isResolvingNext else { return }
        lastManualSkipTime = Date()
        queueIndex -= 1
        playCurrentSong(logContext: "playPrevious")
    }

    /// Starts the song at `queueIndex`: pushes metadata, persists the queue,
    /// and resolves the stream, clearing `isResolvingNext` afterwards.
    /// Shared by repeatCurrent/playNext/playPrevious and QueueView playback.
    func playCurrentSong(
        logContext: String,
        manageResolvingFlag: Bool = true,
        afterResolve: (() -> Void)? = nil
    ) {
        guard queueSongs.indices.contains(queueIndex) else { return }
        if manageResolvingFlag {
            isResolvingNext = true
        }
        let song = queueSongs[queueIndex]
        update(with: song)
        persistQueueState()
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId)
            } catch {
                Log.nowPlaying.error("\(logContext) failed: \(error)")
                if self.videoId == song.videoId {
                    isPlaying = false
                }
            }
            if manageResolvingFlag {
                isResolvingNext = false
            }
            afterResolve?()
        }
    }

    func update(title: String, artist: String?, videoId: String, album: String? = nil, artists: [YTArtist] = [], thumbnailUrl: String? = nil, duration: TimeInterval? = nil, preloadNext: Bool = true) {
        var cleanedArtist = cleanArtistDisplay(artist ?? "")
        let (cleanedTitle, extractedArtist) = cleanTitleAndExtractArtist(title, fallbackArtist: cleanedArtist)
        if cleanedArtist.isEmpty, let extractedArtist, !extractedArtist.isEmpty {
            cleanedArtist = cleanArtistDisplay(extractedArtist)
        }
        self.isPlaying = true
        self.title = cleanedTitle
        self.artists = artists
        self.artist = cleanedArtist
        self.albumTitle = album ?? ""
        self.currentTime = 0
        self.duration = duration ?? 0
        if self.videoId != videoId {
            self.thumbnailUIImage = nil
            self.thumbnailImage = nil
        }
        self.videoId = videoId
        self.hasVideo = false
        self.isVideoMode = false
        self.isVideoReady = false
        startTimer()
        loadThumbnail(videoId: videoId, thumbnailUrl: thumbnailUrl)
        if preloadNext {
            preloadNextTrack()
        }
        WidgetBridge.shared.syncPlayback(from: self)
        PlayerController.shared.setNowPlayingMetadata()
        SyncPlayManager.shared.onHostTrackChanged()
    }

    /// Convenience pushing a `SongItem`'s metadata into the player state.
    func update(with song: SongItem, preloadNext: Bool = true) {
        update(
            title: song.title,
            artist: song.artists.map(\.name).joined(separator: ", "),
            videoId: song.videoId,
            album: song.album,
            artists: song.artists,
            thumbnailUrl: song.thumbnailUrl,
            duration: Double(song.duration),
            preloadNext: preloadNext
        )
    }

    /// Records video availability: the watchable-video verdict comes from
    /// the shared availability check (row type preferred, authoritative
    /// lookup as fallback); this only stores it alongside the type and
    /// pre-warms when there is one to show.
    func updateVideoAvailability(musicVideoType: String? = nil, hasVideo: Bool = false) {
        if let musicVideoType {
            self.musicVideoType = musicVideoType
        }
        self.hasVideo = hasVideo
        if hasVideo {
            PlayerController.shared.preloadVideoURL()
        }
    }

    /// Pre-warms artwork for the previous and upcoming songs so swiping the
    /// mini player bar shows their art instantly.
    func preloadNeighborArtwork() {
        var urls = upcomingSongs(prefixLimit: 3)
            .compactMap(\.thumbnailUrl)
            .compactMap { URL(string: ArtworkURLs.highRes($0) ?? $0) }
        let neighborIds = queueSongs.indices.compactMap { index -> String? in
            guard index == queueIndex - 1 || (index > queueIndex && index <= queueIndex + 3) else { return nil }
            return queueSongs[index].videoId
        }
        urls.append(contentsOf: neighborIds.compactMap { URL(string: Self.artworkURL(for: $0)) })
        guard !urls.isEmpty else { return }
        Task { await ImagePreloader.shared.append(urls) }
    }

    /// Artist string from `artists`, falling back to `artist`.
    var displayArtist: String {
        let fromArray = artistDisplayString(from: artists)
        if !fromArray.isEmpty { return fromArray }
        return artist
    }

    func stopped(videoId: String?, isEof: Bool = true) {
        guard self.videoId == videoId else { return }
        if let skipTime = lastManualSkipTime, Date().timeIntervalSince(skipTime) < 2, isResolvingNext {
            return
        }
        guard isEof else {
            recoverFromPlaybackFailure(videoId: videoId)
            return
        }
        currentTime = duration
        if let finishedId = videoId,
           duration >= 600 || musicVideoType == "MUSIC_VIDEO_TYPE_PODCAST_EPISODE" {
            Task { await EpisodePlaybackStore.shared.markPlayed(videoId: finishedId) }
        }
        if SyncPlayManager.shared.session != nil && !SyncPlayManager.shared.isHost {
            // Guest waits for host's next track instead of advancing/autoplaying locally.
            isPlaying = false
            stopTimer()
            PlayerController.shared.updateNowPlayingProgress()
            return
        }
        if playbackMode == .repeatOne {
            repeatCurrent()
            return
        }
        if hasNext {
            playNext(automatic: true)
        } else if SettingsStore.shared.autoplaySimilar, let endedVideoId = videoId {
            autoplaySimilar(from: endedVideoId)
        } else {
            // End of queue, pause but keep the last song shown in the player.
            isPlaying = false
            stopTimer()
            PlayerController.shared.updateNowPlayingProgress()
            Task { await PlaybackStateService.shared.stopTracking() }
        }
    }

    /// Continues playback with a radio queue built from the last song when the
    /// queue runs out and "Autoplay Similar" is enabled.
    private func autoplaySimilar(from videoId: String) {
        Task {
            do {
                let radio = try await PersonalizationService.shared.fetchRadio(videoId: videoId)
                let songs = radio.songs
                // Radio mixes include the seed song at `currentIndex` (usually 0).
                // Advance to the next suggested track so we don't replay the song that just ended.
                let nextIndex: Int
                if radio.currentIndex + 1 < songs.count {
                    nextIndex = radio.currentIndex + 1
                } else if let firstOther = songs.firstIndex(where: { $0.videoId != videoId }) {
                    nextIndex = firstOther
                } else {
                    isPlaying = false
                    return
                }
                self.queueSongs = songs
                self.queueIndex = nextIndex
                if self.playbackMode == .shuffle {
                    self.playbackMode = .off
                }
                let first = songs[nextIndex]
                update(with: first)
                try await PlaybackManager.shared.resolveAndPlay(videoId: first.videoId)
                self.persistQueueState()
            } catch {
                Log.nowPlaying.error("Autoplay similar failed: \(error)")
                isPlaying = false
            }
        }
    }

    /// A stream that died mid-play (not EOF, not a manual skip): drop the
    /// possibly-expired cached URL and re-resolve once. Repeated failures for
    /// the same video are only retried after a cooldown to avoid a loop.
    private func recoverFromPlaybackFailure(videoId: String?) {
        guard let videoId else {
            isPlaying = false
            return
        }
        PlayerController.shared.handleVideoStreamFailure()
        if let last = lastFailureAt[videoId], Date().timeIntervalSince(last) < 30 {
            isPlaying = false
            return
        }
        lastFailureAt[videoId] = Date()
        isPlaying = false
        Log.nowPlaying.notice("Stream failed mid-play, re-resolving \(videoId)")
        Task {
            await PlayerConfigStore.shared.notifyStreamRejection()
            await StreamCache.shared.remove(videoId: videoId)
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: videoId)
                // Success – allow future retries for this video
                _ = await MainActor.run { self.lastFailureAt.removeValue(forKey: videoId) }
            } catch {
                Log.nowPlaying.error("Mid-play recovery failed: \(error)")
                if self.videoId == videoId {
                    isPlaying = false
                }
            }
        }
    }

    static func artworkURL(for videoId: String) -> String {
        ArtworkURLs.fallback(for: videoId)
    }

    private var lastLoadedVideoId: String?

    private func loadThumbnail(videoId: String, thumbnailUrl: String? = nil) {
        guard videoId != lastLoadedVideoId else { return }
        lastLoadedVideoId = videoId
        // Safety net: callers that resolve without song metadata pass nil.
        // The queue usually still knows this track's artwork — use it rather
        // than falling back to the low-res ytimg default.
        var thumb = thumbnailUrl
        if thumb == nil {
            thumb = queueSongs.first { $0.videoId == videoId }?.thumbnailUrl
        }

        Task {
            // For downloaded songs, try to extract embedded artwork from the local file first.
            if let localURL = await DownloadManager.shared.localURL(for: videoId) {
                loadArtworkFromLocalFile(localURL, videoId: videoId, thumbnailUrl: thumb)
                return
            }
            loadThumbnailFromCDN(videoId: videoId, thumbnailUrl: thumb)
        }
    }

    private func loadArtworkFromLocalFile(_ fileURL: URL, videoId: String, thumbnailUrl: String?) {
        Task {
            let asset = AVURLAsset(url: fileURL)
            let metadata = try? await asset.load(.metadata)
            var artworkImage: UIImage?
            if let metadata {
                for item in metadata {
                    if let data = try? await item.load(.dataValue),
                       let image = UIImage(data: data) {
                        artworkImage = image
                        break
                    }
                }
            }

            await MainActor.run {
                guard lastLoadedVideoId == videoId else { return }
                if let artworkImage {
                    publishArtwork(artworkImage)
                    let pxWidth = artworkImage.size.width * artworkImage.scale
                    let pxHeight = artworkImage.size.height * artworkImage.scale
                    // Older downloads embedded low-res thumbnails; upgrade from CDN if online.
                    if min(pxWidth, pxHeight) < 500 {
                        loadThumbnailFromCDN(videoId: videoId, thumbnailUrl: thumbnailUrl, keepExistingOnMiss: true)
                    }
                } else {
                    loadThumbnailFromCDN(videoId: videoId, thumbnailUrl: thumbnailUrl)
                }
            }
        }
    }

    /// Publishes a loaded image as the current artwork (cropped square).
    private func publishArtwork(_ image: UIImage) {
        let cropped = image.centerCroppedSquare()
        thumbnailUIImage = cropped
        thumbnailImage = Image(uiImage: cropped)
        thumbnailVersion &+= 1
        updateDominantColors(from: cropped)
        PlayerController.shared.updateNowPlayingArtwork()
        if let videoId {
            WidgetBridge.shared.syncArtwork(cropped, for: videoId)
        }
    }

    private func loadThumbnailFromCDN(videoId: String, thumbnailUrl: String? = nil, keepExistingOnMiss: Bool = false) {
        // Best source first: the track's own artwork upgraded to full
        // resolution, then ytimg step-downs, then the guaranteed hqdefault.
        var candidates: [String] = []
        if let upgraded = ArtworkURLs.highRes(thumbnailUrl) {
            if let maxRes = ArtworkURLs.maxResVariant(upgraded) {
                candidates.append(maxRes)
            }
            if let standard = ArtworkURLs.sdVariant(upgraded) {
                candidates.append(standard)
            }
            candidates.append(upgraded)
        }
        let fallback = Self.artworkURL(for: videoId)
        if !candidates.contains(fallback) {
            candidates.append(fallback)
        }
        let urls = candidates.compactMap(URL.init(string:))
        guard !urls.isEmpty else {
            thumbnailUIImage = nil
            thumbnailImage = Image(systemName: "music.note")
            thumbnailVersion &+= 1
            updateDominantColors(from: nil)
            return
        }

        // Phase 1: instant paint from the best cached candidate. A lesser
        // cached variant must not shadow a better one — Phase 2 upgrades.
        var paintedIndex: Int?
        for (index, url) in urls.enumerated() {
            if let cached = ArtworkLoader.cachedImage(for: url) {
                publishArtwork(cached)
                paintedIndex = index
                break
            }
        }

        // Phase 2: fetch candidates better than the painted one (or all of
        // them when nothing was painted). First success wins and swaps in.
        let fetchCount = paintedIndex ?? urls.count
        if fetchCount == 0 {
            return
        }
        if paintedIndex == nil && !keepExistingOnMiss {
            thumbnailImage = nil
        }
        Task {
            for url in urls.prefix(fetchCount) {
                guard lastLoadedVideoId == videoId else { return }
                do {
                    let platformImage = try await ArtworkLoader.image(for: url)
                    await MainActor.run {
                        guard self.lastLoadedVideoId == videoId else { return }
                        self.publishArtwork(platformImage)
                    }
                    return
                } catch {
                    continue
                }
            }
            if paintedIndex == nil {
                await MainActor.run {
                    guard self.lastLoadedVideoId == videoId else { return }
                    thumbnailImage = Image(systemName: "music.note")
                    thumbnailVersion &+= 1
                    updateDominantColors(from: nil)
                }
            }
        }
    }

    private func preloadNextTrack() {
        guard hasNext else { return }
        let nextIndex = queueIndex + 1 < queueSongs.count ? queueIndex + 1 : 0
        guard queueSongs.indices.contains(nextIndex) else { return }
        let nextId = queueSongs[nextIndex].videoId
        loggedTask(Log.nowPlaying, "Pre-resolve failed") {
            _ = try await PlaybackManager.shared.resolve(videoId: nextId)
            Log.nowPlaying.debug("Pre-resolved next track: \(nextId)")
        }
    }

    private func startTimer() {
        stopTimer()
        // Add to `.common` so progress keeps updating while the user scrolls
        // or drags the slider (the default mode pauses the timer).
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.timerTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @MainActor
    private func timerTick() {
        currentTime = PlayerController.shared.currentTime
        duration = PlayerController.shared.duration
        if let videoId, duration >= 600 || musicVideoType == "MUSIC_VIDEO_TYPE_PODCAST_EPISODE" {
            let vid = videoId
            let pos = currentTime
            let dur = duration
            Task {
                await EpisodePlaybackStore.shared.savePosition(videoId: vid, position: pos, duration: dur)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    private func updateDominantColors(from uiImage: UIImage?) {
        guard let uiImage = uiImage else {
            self.dominantColors = [Color.black, Color.black]
            return
        }
        Task.detached(priority: .userInitiated) {
            let colors = uiImage.extractDominantColors()
            await MainActor.run { [weak self] in
                self?.dominantColors = colors
            }
        }
    }
}

// MARK: - Module-level artist name cleaner

/// Builds a clean, comma-separated artist string from an artist array, dropping
/// names that clean down to empty (junk/blank entries) so no dangling separator
/// is left behind.
func artistDisplayString(from artists: [YTArtist]) -> String {
    artists
        .map { cleanArtistDisplay($0.name) }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
}

func cleanArtistDisplay(_ name: String) -> String {
    var tempName = name

    // Strip " - Topic"
    for suffix in [" - Topic", " - topic", " - TOPIC"] where tempName.lowercased().hasSuffix(suffix.lowercased()) {
        tempName = String(tempName.dropLast(suffix.count))
    }

    // Strip trailing year "(2025)" / "[2025]"
    if let r = try? NSRegularExpression(pattern: "\\s*[\\(\\[]\\d{4}[\\)\\]]\\s*$") {
        tempName = r.stringByReplacingMatches(
            in: tempName,
            range: NSRange(tempName.startIndex..., in: tempName),
            withTemplate: ""
        )
    }

    // Split on commas, ampersands, and bullet separators (•, ·, |) then drop junk segments
    let separatorSet = CharacterSet(charactersIn: ",&•·|")
    let parts = tempName
        .components(separatedBy: separatorSet)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    let cleanParts = parts.filter { !_isJunkArtistSegment($0) }
    if cleanParts.isEmpty {
        return ""
    }
    return cleanParts.joined(separator: ", ")
}

private func _isJunkArtistSegment(_ segment: String) -> Bool {
    let lower = segment.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if lower.isEmpty || lower == "•" || lower == "·" { return true }

    let junkLabels: Set<String> = [
        "song", "video", "track", "music", "podcast", "episode",
        "album", "playlist", "released", "year", "plays", "views",
        "downloads", "listeners", "subscribers", "watchers", "likes"
    ]
    if junkLabels.contains(lower) { return true }

    let patterns = [
        // Number optionally followed by K/M/B/T and an optional metric word
        "^[\\d,\\.]+[KMBT]?\\s*(views|downloads|listeners|subscribers|plays|watchers|likes?)?$",
        "^\\d{4}$",              // bare year
        "^[\\d,\\.\\s]+[KMBT]?$" // purely numeric / abbreviated counts
    ]
    for pattern in patterns where lower.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
        return true
    }
    return false
}

func cleanTitleDisplay(_ title: String, artist: String? = nil) -> String {
    cleanTitleAndExtractArtist(title, fallbackArtist: artist).title
}

func cleanTitleAndExtractArtist(_ title: String, fallbackArtist: String? = nil) -> (title: String, artist: String?) {
    var clean = title

    // Strip video / audio / lyric tags in brackets or parentheses
    let junkPatterns = [
        #"[\(\[]\s*(?:official\s*(?:music\s*)?video|official\s*audio|lyric\s*video|lyrics?|visualizer|official|audio|video|hd|4k)\s*[\)\]]"#,
        #"\|\s*(?:official\s*(?:music\s*)?video|official\s*audio|lyrics?|visualizer).*$"#,
        #"-\s*(?:official\s*(?:music\s*)?video|official\s*audio|lyric\s*video).*$"#
    ]
    for pattern in junkPatterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(clean.startIndex..<clean.endIndex, in: clean)
            clean = regex.stringByReplacingMatches(in: clean, options: [], range: range, withTemplate: "")
        }
    }

    var extractedArtist: String?
    let dashSeparators = [" - ", " – ", " — "]
    for sep in dashSeparators {
        let parts = clean.components(separatedBy: sep)
        if parts.count == 2 {
            let left = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let right = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if let fallback = fallbackArtist?.trimmingCharacters(in: .whitespacesAndNewlines), !fallback.isEmpty {
                let lowerFallback = fallback.lowercased()
                if right.lowercased() == lowerFallback || right.lowercased().contains(lowerFallback) {
                    clean = left
                    extractedArtist = right
                    break
                }
                if left.lowercased() == lowerFallback || left.lowercased().contains(lowerFallback) {
                    clean = right
                    extractedArtist = left
                    break
                }
            } else {
                clean = left
                extractedArtist = right
                break
            }
        }
    }

    if let fallback = fallbackArtist?.trimmingCharacters(in: .whitespacesAndNewlines), !fallback.isEmpty {
        let escaped = NSRegularExpression.escapedPattern(for: fallback)
        if let regex = try? NSRegularExpression(pattern: #"\s*[-–—|]\s*"# + escaped + #"\s*$"#, options: [.caseInsensitive]) {
            let range = NSRange(clean.startIndex..<clean.endIndex, in: clean)
            clean = regex.stringByReplacingMatches(in: clean, options: [], range: range, withTemplate: "")
        }
        if let regex = try? NSRegularExpression(pattern: #"^"# + escaped + #"\s*[-–—|]\s*"#, options: [.caseInsensitive]) {
            let range = NSRange(clean.startIndex..<clean.endIndex, in: clean)
            clean = regex.stringByReplacingMatches(in: clean, options: [], range: range, withTemplate: "")
        }
    }

    let trimmed = clean.trimmingCharacters(in: .whitespacesAndNewlines)
    return (trimmed.isEmpty ? title : trimmed, extractedArtist)
}

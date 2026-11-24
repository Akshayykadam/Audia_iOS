//
//  WidgetBridge.swift
//  Audia
//

import Foundation
import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()

    private let store = WidgetDataStore.shared
    private var lastSavedArtworkId: String?
    private var lastArtworkData: Data?
    private var lastArtworkDataVideoId: String?
    private var isListening = false

    private init() {}

    private func createThumbnailData(from image: UIImage?) -> Data? {
        guard let image else { return nil }
        let targetSize = CGSize(width: 44, height: 44)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        if let data = resized.jpegData(compressionQuality: 0.50), data.count < 1800 {
            return data
        }
        if let data = resized.jpegData(compressionQuality: 0.30), data.count < 2200 {
            return data
        }
        let smallSize = CGSize(width: 32, height: 32)
        let smallRenderer = UIGraphicsImageRenderer(size: smallSize, format: format)
        let smallResized = smallRenderer.image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: smallSize))
            image.draw(in: CGRect(origin: .zero, size: smallSize))
        }
        if let data = smallResized.jpegData(compressionQuality: 0.35), data.count < 2200 {
            return data
        }
        return nil
    }

    // MARK: - Playback Sync

    func syncPlayback(from nowPlaying: NowPlaying) {
        guard let videoId = nowPlaying.videoId, !videoId.isEmpty else {
            let emptyState = WidgetPlaybackState.placeholder
            store.writePlaybackState(emptyState)
            reloadNowPlayingWidgets()
            endLiveActivity()
            return
        }

        var artworkFileName: String?
        var artworkData: Data?
        if let image = nowPlaying.thumbnailUIImage {
            artworkFileName = store.saveArtwork(image: image, for: videoId)
            lastSavedArtworkId = videoId
            if lastArtworkDataVideoId == videoId, let cached = lastArtworkData {
                artworkData = cached
            } else {
                artworkData = createThumbnailData(from: image)
                lastArtworkData = artworkData
                lastArtworkDataVideoId = videoId
            }
        } else if lastSavedArtworkId == videoId, let cached = lastArtworkData {
            artworkFileName = "\(videoId).jpg"
            artworkData = cached
        } else {
            let fileURL = store.artworkDirectory.appendingPathComponent("\(videoId).jpg")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                artworkFileName = "\(videoId).jpg"
                lastSavedArtworkId = videoId
                if let image = store.loadArtwork(fileName: artworkFileName) {
                    artworkData = createThumbnailData(from: image)
                    lastArtworkData = artworkData
                    lastArtworkDataVideoId = videoId
                }
            }
        }

        let currentThumbUrl = nowPlaying.queueSongs.indices.contains(nowPlaying.queueIndex)
            ? nowPlaying.queueSongs[nowPlaying.queueIndex].thumbnailUrl
            : nowPlaying.queueSongs.first(where: { $0.videoId == videoId })?.thumbnailUrl

        if artworkData == nil {
            let thumbUrl = currentThumbUrl ?? "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
            if let url = URL(string: thumbUrl) {
                Task { [weak self] in
                    guard let self else { return }
                    if let (data, _) = try? await URLSession.shared.data(from: url),
                       let img = UIImage(data: data) {
                        await MainActor.run {
                            self.syncArtwork(img, for: videoId)
                        }
                    }
                }
            }
        }

        let state = WidgetPlaybackState(
            videoId: videoId,
            title: nowPlaying.title.isEmpty ? "Unknown Title" : nowPlaying.title,
            artist: nowPlaying.artist.isEmpty ? "Unknown Artist" : nowPlaying.artist,
            album: nowPlaying.albumTitle,
            duration: nowPlaying.duration,
            currentTime: nowPlaying.currentTime,
            isPlaying: nowPlaying.isPlaying,
            isExplicit: false,
            artworkFileName: artworkFileName,
            thumbnailUrl: currentThumbUrl,
            updatedAt: Date()
        )

        store.writePlaybackState(state)
        reloadNowPlayingWidgets()
        syncLiveActivity(from: state, artworkData: artworkData)
    }

    func syncArtwork(_ image: UIImage, for videoId: String) {
        guard !videoId.isEmpty else { return }
        let fileName = store.saveArtwork(image: image, for: videoId)
        lastSavedArtworkId = videoId

        let artworkData = createThumbnailData(from: image)
        lastArtworkData = artworkData
        lastArtworkDataVideoId = videoId

        var state = store.readPlaybackState()
        state.videoId = videoId
        state.artworkFileName = fileName
        store.writePlaybackState(state)
        reloadNowPlayingWidgets()
        syncLiveActivity(from: state, artworkData: artworkData)
    }

    // MARK: - Live Activity Management

    func syncLiveActivity(from state: WidgetPlaybackState, artworkData: Data? = nil) {
        guard #available(iOS 16.2, *) else { return }
        #if canImport(ActivityKit)
        let areEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let activeActivities = Activity<AudiaNowPlayingAttributes>.activities.filter { $0.activityState == .active }
        Log.player.info("SYNC_LIVE_ACTIVITY: areEnabled=\(areEnabled) isPlaying=\(state.isPlaying) videoId=\(state.videoId) activeCount=\(activeActivities.count)")
        guard areEnabled else { return }

        let resolvedData = artworkData ?? (lastArtworkDataVideoId == state.videoId ? lastArtworkData : nil)

        let contentState = AudiaNowPlayingAttributes.ContentState(
            title: state.title,
            artist: state.artist,
            duration: state.duration,
            currentTime: state.currentTime,
            isPlaying: state.isPlaying,
            videoId: state.videoId,
            artworkData: resolvedData,
            artworkFileName: state.artworkFileName,
            updatedAt: Date()
        )

        if let existing = activeActivities.first {
            Task {
                await existing.update(.init(state: contentState, staleDate: nil))
            }
        } else if state.isPlaying && !state.videoId.isEmpty && state.videoId != "sample" {
            let attributes = AudiaNowPlayingAttributes(videoId: state.videoId)
            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: .init(state: contentState, staleDate: nil),
                    pushType: nil
                )
                Log.player.info("Live Activity started for \(state.videoId)")
            } catch {
                Log.player.error("Failed to request Live Activity: \(error)")
            }
        }
        #endif
    }

    func endLiveActivity() {
        guard #available(iOS 16.2, *) else { return }
        #if canImport(ActivityKit)
        for activity in Activity<AudiaNowPlayingAttributes>.activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
    }

    // MARK: - History / Recents Sync

    func syncRecentSongs(_ songs: [SongItem]) {
        guard !songs.isEmpty else { return }
        var uniqueSongs: [SongItem] = []
        var seen = Set<String>()
        for song in songs {
            if !seen.contains(song.videoId) && !song.videoId.isEmpty {
                seen.insert(song.videoId)
                uniqueSongs.append(song)
            }
        }
        let topSongs = Array(uniqueSongs.prefix(8))
        let items: [WidgetRecentItem] = topSongs.map { song in
            WidgetRecentItem(
                videoId: song.videoId,
                title: song.title,
                artist: artistDisplayString(from: song.artists).isEmpty ? (song.album ?? "Audia") : artistDisplayString(from: song.artists),
                album: song.album,
                artworkFileName: "\(song.videoId).jpg",
                thumbnailUrl: song.thumbnailUrl,
                timestamp: Date()
            )
        }
        store.writeRecentItems(items)
        reloadRecentsWidgets()

        let pairs: [(String, String?)] = topSongs.map { ($0.videoId, $0.thumbnailUrl) }
        cacheArtworkForRecentItems(pairs)
    }

    func syncHistoryEntries(_ entries: [DatabaseService.HistoryEntry]) {
        guard !entries.isEmpty else { return }
        var uniqueEntries: [DatabaseService.HistoryEntry] = []
        var seen = Set<String>()
        for entry in entries {
            let songId = entry.event.songId
            if !seen.contains(songId) && !songId.isEmpty {
                seen.insert(songId)
                uniqueEntries.append(entry)
            }
        }
        let top = Array(uniqueEntries.prefix(8))
        let items: [WidgetRecentItem] = top.compactMap { (entry: DatabaseService.HistoryEntry) -> WidgetRecentItem? in
            let songId = entry.event.songId
            guard !songId.isEmpty else { return nil }
            return WidgetRecentItem(
                videoId: songId,
                title: entry.song?.title ?? "Unknown Title",
                artist: entry.song?.artistName ?? "Audia",
                album: entry.song?.albumName,
                artworkFileName: "\(songId).jpg",
                thumbnailUrl: entry.song?.thumbnailUrl,
                timestamp: entry.event.timestamp
            )
        }
        store.writeRecentItems(items)
        reloadRecentsWidgets()

        let pairs: [(String, String?)] = top.compactMap { entry in
            let songId = entry.event.songId
            guard !songId.isEmpty else { return nil }
            return (songId, entry.song?.thumbnailUrl)
        }
        cacheArtworkForRecentItems(pairs)
    }

    private func cacheArtworkForRecentItems(_ pairs: [(String, String?)]) {
        Task { [weak self] in
            guard let self else { return }
            var didSaveAny = false
            for (videoId, thumbUrl) in pairs {
                let fileURL = self.store.artworkDirectory.appendingPathComponent("\(videoId).jpg")
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    continue
                }
                let urlString = thumbUrl ?? "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
                guard let url = URL(string: urlString) else { continue }
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = UIImage(data: data) {
                    self.store.saveArtwork(image: image, for: videoId)
                    didSaveAny = true
                }
            }
            if didSaveAny {
                await MainActor.run {
                    self.reloadRecentsWidgets()
                }
            }
        }
    }

    // MARK: - Widget Timeline Reload

    func reloadNowPlayingWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: "AudiaNowPlayingWidget")
    }

    func reloadRecentsWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: "AudiaRecentlyPlayedWidget")
    }

    func reloadAllWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Darwin Notifications (Interactive Controls)

    func startListening() {
        guard !isListening else { return }
        isListening = true

        // Sync initial state from NowPlaying and Database
        syncPlayback(from: NowPlaying.shared)
        Task { [weak self] in
            guard let self else { return }
            do {
                let history = try await DatabaseService.shared.fetchHistory(limit: 20)
                if !history.isEmpty {
                    await MainActor.run {
                        self.syncHistoryEntries(history)
                    }
                }
            } catch {
                Log.player.error("WidgetBridge startup history sync failed: \(error)")
            }
        }

        let center = CFNotificationCenterGetDarwinNotifyCenter()

        // Toggle Play/Pause
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                let bridge = Unmanaged<WidgetBridge>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    bridge.handleTogglePlayPause()
                }
            },
            WidgetDataStore.notifyTogglePlayPause as CFString,
            nil,
            .deliverImmediately
        )

        // Skip Next
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                let bridge = Unmanaged<WidgetBridge>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    bridge.handleSkipNext()
                }
            },
            WidgetDataStore.notifySkipNext as CFString,
            nil,
            .deliverImmediately
        )

        // Skip Previous
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                let bridge = Unmanaged<WidgetBridge>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    bridge.handleSkipPrevious()
                }
            },
            WidgetDataStore.notifySkipPrevious as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func handleTogglePlayPause() {
        Log.player.info("WidgetBridge: Toggle play/pause received from widget")
        PlayerController.shared.togglePlayPause()
        syncPlayback(from: NowPlaying.shared)
    }

    private func handleSkipNext() {
        Log.player.info("WidgetBridge: Skip next received from widget")
        NowPlaying.shared.playNext(automatic: false)
    }

    private func handleSkipPrevious() {
        Log.player.info("WidgetBridge: Skip previous received from widget")
        NowPlaying.shared.playPrevious()
    }
}

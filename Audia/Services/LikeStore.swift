//
//  LikeStore.swift
//  Audia
//

import Combine
import Foundation
import GRDB

@MainActor
class LikeStore: ObservableObject {
    static let shared = LikeStore()

    @Published private(set) var liked: [String: Bool] = [:]

    private init() {
        Task { await refresh() }
    }

    func isLiked(videoId: String) -> Bool {
        liked[videoId] ?? false
    }

    func refresh() async {
        let songs = (try? await DatabaseService.shared.fetchAllLikedSongs()) ?? []
        var dict: [String: Bool] = [:]
        for song in songs where song.liked {
            dict[song.id] = true
        }
        liked = dict
    }

    func toggle(song: SongItem) async {
        let videoId = song.videoId
        let target = !isLiked(videoId: videoId)

        var updated = liked
        updated[videoId] = target
        liked = updated

        // Always persist locally in SQLite so like status is saved reliably offline or unauthenticated
        do {
            try await DatabaseService.shared.setLiked(videoId: videoId, liked: target, song: song)
        } catch {
            Log.sync.error("Failed to update local like state: \(error) (\(error.localizedDescription))")
        }

        // Only attempt remote sync if user is authenticated with YouTube cookies
        let auth = await InnerTubeClient.audiaShared.currentAuth()
        if !auth.cookies.isEmpty {
            do {
                if target {
                    try await SyncBridge.mutations.likeSong(videoId: videoId)
                } else {
                    try await SyncBridge.mutations.unlikeSong(videoId: videoId)
                }
            } catch {
                Log.sync.notice("Remote sync like ignored for videoId=\(videoId): \(error.localizedDescription)")
                // SwiftyTube's OptimisticMutation rolls back the store on remote failure.
                // Always re-assert the intended local like state so local favorites are never lost!
                try? await DatabaseService.shared.setLiked(videoId: videoId, liked: target, song: song)
            }
        }

        NotificationCenter.default.post(name: .personalizationDataUpdated, object: nil)

        if target, SettingsStore.shared.autoDownloadOnLike {
            await DownloadManager.shared.download(song: song)
        }
    }
}

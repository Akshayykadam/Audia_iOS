//
//  SyncBridge.swift
//  Audia
//

import Foundation

enum SyncBridge {
    static let store = AudiaLibraryStore()
    static let librarySync = LibrarySyncService(client: InnerTubeClient.audiaShared, store: store)
    static let playlistDetail = PlaylistDetailService(client: InnerTubeClient.audiaShared, store: store)
    static let mutations = MutationService(client: InnerTubeClient.audiaShared, store: store)
    static let incremental = IncrementalSyncService(client: InnerTubeClient.audiaShared, librarySync: librarySync)

    static var options: LibrarySyncOptions {
        let settings = SettingsStore.shared
        return LibrarySyncOptions(
            syncArtists: settings.syncArtists,
            syncPlaylists: settings.syncPlaylists,
            syncAlbums: settings.syncAlbums,
            syncPodcasts: settings.syncPodcasts,
            syncSongs: settings.syncSongs
        )
    }

    static func checkAndSyncIfStale() async {
        await incremental.checkAndSyncIfStale(options: options) {
            await LikeStore.shared.refresh()
            await MainActor.run {
                NotificationCenter.default.post(name: .personalizationDataUpdated, object: nil)
            }
        }
    }

    static func forceFullSync() async {
        await incremental.forceFullSync(options: options) {
            await LikeStore.shared.refresh()
            await MainActor.run {
                NotificationCenter.default.post(name: .personalizationDataUpdated, object: nil)
            }
        }
    }
}

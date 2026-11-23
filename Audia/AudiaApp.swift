//
//  AudiaApp.swift
//  Audia
//

import Nuke
import SwiftUI

#if canImport(UIKit)
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }
}
#endif

@main
struct AudiaApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var settings = SettingsStore.shared

    init() {
        SatoshiFontLoader.registerFonts()
        configureNuke()
        ensureDirectories()
        Log.wireSwiftyTube()
        PlayerController.registerRemoteControlSupport()
        observePlaybackSettings()
        Task { await InnerTubeClient.audiaShared.syncAudiaLocale() }
        if CommandLine.arguments.contains("-testSong") {
            let song = SongItem(
                videoId: "kJQP7kiw5Fk",
                title: "Seven - Explicit Ver. (feat. Latto)",
                artists: [YTArtist(name: "Jung Kook", id: "artist1"), YTArtist(name: "Latto", id: "artist2")],
                album: "GOLDEN",
                duration: 184,
                thumbnailUrl: "https://lh3.googleusercontent.com/s640",
                isExplicit: true
            )
            NowPlaying.shared.setQueue([song], startIndex: 0)
            NowPlaying.shared.update(with: song)
        }
        if CommandLine.arguments.contains("-testQueue") {
            let songs = [
                SongItem(
                    videoId: "lY2yjAkatM8",
                    title: "Treat You Better",
                    artists: [YTArtist(name: "Shawn Mendes", id: "sm1")],
                    album: "Illuminate",
                    duration: 187,
                    thumbnailUrl: "https://lh3.googleusercontent.com/s640",
                    isExplicit: false
                ),
                SongItem(
                    videoId: "yXQViqx6GMY",
                    title: "All I Want for Christmas Is You",
                    artists: [YTArtist(name: "Mariah Carey", id: "mc1")],
                    album: "Merry Christmas",
                    duration: 241,
                    thumbnailUrl: "https://lh3.googleusercontent.com/s640",
                    isExplicit: false
                ),
                SongItem(
                    videoId: "oRdxUFDoQe0",
                    title: "Beat It",
                    artists: [YTArtist(name: "Michael Jackson", id: "mj1")],
                    album: "Thriller",
                    duration: 258,
                    thumbnailUrl: "https://lh3.googleusercontent.com/s640",
                    isExplicit: false
                ),
                SongItem(
                    videoId: "mana12345",
                    title: "MAÑA",
                    artists: [YTArtist(name: "Clave Especial", id: "ce1")],
                    album: "Single",
                    duration: 195,
                    thumbnailUrl: "https://lh3.googleusercontent.com/s640",
                    isExplicit: false
                ),
                SongItem(
                    videoId: "snowman123",
                    title: "Snowman",
                    artists: [YTArtist(name: "Sia", id: "sia1")],
                    album: "Everyday Is Christmas",
                    duration: 165,
                    thumbnailUrl: "https://lh3.googleusercontent.com/s640",
                    isExplicit: false
                ),
                SongItem(
                    videoId: "marycross123",
                    title: "Mary On A Cross",
                    artists: [YTArtist(name: "Ghost", id: "ghost1")],
                    album: "Seven Inches of Satanic Panic",
                    duration: 244,
                    thumbnailUrl: "https://lh3.googleusercontent.com/s640",
                    isExplicit: false
                )
            ]
            NowPlaying.shared.setQueue(songs, startIndex: 0)
            NowPlaying.shared.update(with: songs[0])
        }
        if CommandLine.arguments.contains("-expandPlayer") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                AppRouter.shared.expandPlayer()
            }
        }
        if CommandLine.arguments.contains("-openSettings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                AppRouter.shared.open(.settings)
            }
        }
    }

    /// Re-applies mpv playback settings whenever the user changes the
    /// equalizer or the audio filters from any screen.
    private func observePlaybackSettings() {
        func register() {
            withObservationTracking {
                let settings = SettingsStore.shared
                _ = settings.equalizerEnabled
                _ = settings.equalizerGains
                _ = settings.audioNormalization
                _ = settings.gaplessPlayback
            } onChange: {
                Task { @MainActor in
                    PlayerController.shared.applyPlaybackSettings()
                }
            }
        }
        register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .font(.satoshi(.body))
                .preferredColorScheme(settings.preferredColorScheme)
                .tint(settings.accentColor)
                .environment(settings)
                .environment(\.downloadManager, DownloadManager.shared)
                .onOpenURL { url in
                    if url.scheme == "audia" {
                        if url.host == "tab" {
                            if let index = Int(url.lastPathComponent) {
                                AppRouter.shared.selectedTabIndex = index
                            }
                        } else if url.host == "player" {
                            AppRouter.shared.expandPlayer()
                        } else if url.host == "settings" {
                            AppRouter.shared.open(.settings)
                        } else if url.host == "artist" {
                            AppRouter.shared.open(.artist(browseId: url.lastPathComponent))
                        } else if url.host == "playlist" {
                            let listId = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                                .queryItems?.first(where: { $0.name == "list" })?.value ?? url.lastPathComponent
                            if !listId.isEmpty {
                                AppRouter.shared.open(.playlist(playlistId: listId))
                            }
                        } else if url.host == "testplay" {
                            let song = SongItem(
                                videoId: "g-of38yG1vE",
                                title: "Snowman",
                                artists: [YTArtist(name: "Sia", id: "UCaPIRYCKs51kvD4jrbwMH1w")],
                                duration: 165,
                                isExplicit: false
                            )
                            NowPlaying.shared.setQueue([song], startIndex: 0)
                            AppRouter.shared.expandPlayer()
                        } else if url.host == "testlike" {
                            if let song = NowPlaying.shared.queueSongs.first {
                                Task { await LikeStore.shared.toggle(song: song) }
                            }
                        }
                    } else if let parsed = PlaylistLinkParser.parse(url.absoluteString) {
                        if case .youTube(let pid) = parsed {
                            AppRouter.shared.open(.playlist(playlistId: pid))
                        }
                    }
                }
        }
    }

    private func configureNuke() {
        let dataCache = try? DataCache(name: "com.audia.nuke")
        dataCache?.sizeLimit = 2 * 1024 * 1024 * 1024

        var config = ImagePipeline.Configuration()
        config.dataCache = dataCache
        config.imageCache = ImageCache(costLimit: 100 * 1024 * 1024)

        ImagePipeline.shared = ImagePipeline(configuration: config)
    }

    private func ensureDirectories() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: docs.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: docs.appendingPathComponent("Player"), withIntermediateDirectories: true)
    }
}

//
//  SwiftyTubeShared.swift
//  Audia
//

@_exported import SwiftyTube

/// Shared InnerTube client for the music service (replaces `InnerTube.shared`).
extension InnerTubeClient {
    static let audiaShared = InnerTubeClient(config: .music)
}

/// Mirrors the old behavior of reading the region from settings per request.
extension InnerTubeClient {
    func syncAudiaLocale() {
        let country = SettingsStore.shared.contentCountry
        updateLocale(YouTubeLocale(gl: country.isEmpty ? "US" : country, hl: "en"))
    }
}

/// Live cipher/PoToken/format-sink wiring for stream resolution.
extension StreamResolveProviders {
    static var audiaLive: StreamResolveProviders {
        var providers = StreamResolveProviders.live
        providers.poTokenProvider = { videoId in
            try? await PoTokenGenerator.shared.generate(
                videoId: videoId,
                sessionId: PlaybackManager.sessionId
            )
        }
        providers.resolvedFormatHandler = { info in
            _ = try? await DatabaseService.shared.insertOrReplace(FormatEntity(
                id: info.videoId,
                itag: info.itag,
                mimeType: info.mimeType,
                codecs: info.codecs,
                bitrate: info.bitrate,
                sampleRate: 0,
                contentLength: info.contentLength,
                loudnessDb: info.loudnessDb,
                perceptualLoudnessDb: nil,
                playbackUrl: info.playbackUrl
            ))
        }
        return providers
    }
}

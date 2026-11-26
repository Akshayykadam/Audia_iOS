//
//  SwiftyTubeShared.swift
//  Audia
//

import Foundation
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

    /// Calls `youtubei/v1/next` with music-radio flags (`isAudioOnly`,
    /// `enablePersistentPlaylistPanel`) and optional `params` (e.g. from
    /// `watchPlaylistEndpoint` / `automixPreviewVideoRenderer`).
    func nextRadio(
        videoId: String?,
        playlistId: String?,
        params: String? = nil
    ) async throws -> [String: Any] {
        let client = config.defaultClient
        let locale = config.defaultLocale
        let auth = currentAuth()

        var clientDict: [String: Any] = [
            "clientName": client.clientName,
            "clientVersion": client.clientVersion,
            "gl": locale.gl,
            "hl": locale.hl
        ]
        if let visitorData = auth.visitorData {
            clientDict["visitorData"] = visitorData
        }

        var body: [String: Any] = [
            "context": [
                "client": clientDict,
                "request": ["internalExperimentFlags": [] as [String], "useSsl": true],
                "user": ["lockedSafetyMode": false]
            ],
            "isAudioOnly": true,
            "enablePersistentPlaylistPanel": true
        ]
        if let videoId { body["videoId"] = videoId }
        if let playlistId { body["playlistId"] = playlistId }
        if let params { body["params"] = params }

        let url = config.service.baseURL.appendingPathComponent("next")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.setValue("\(client.clientId)", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue(config.service.origin, forHTTPHeaderField: "X-Origin")
        request.setValue(config.service.origin + "/", forHTTPHeaderField: "Referer")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(config.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        if let visitorData = auth.visitorData {
            request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        if !auth.cookies.isEmpty {
            let cookieString = auth.cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieString, forHTTPHeaderField: "Cookie")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else {
            throw InnerTubeError.invalidResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InnerTubeError.decodingFailed
        }
        return json
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

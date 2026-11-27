//
//  SyncPlayManager.swift
//  Audia
//

import Combine
import Foundation
import Observation

@Observable
@MainActor
final class SyncPlayManager {
    static let shared = SyncPlayManager()

    let repository = SyncPlayRepository()
    let driftCorrector: DriftCorrector
    private let localServer = LocalSyncPlayServer()
    private let localDiscoveryManager = LocalDiscoveryManager()

    var isModalPresented = false
    var sessionTerminationNotice: String?

    private(set) var isLocalHosting = false
    private(set) var localServerUrl: String?

    var session: SyncRoomSnapshot? { repository.currentSession }
    var connectionState: SyncConnectionState { repository.connectionState }
    var driftStatus: DriftStatus { driftCorrector.driftStatus }
    var discoveredSessions: [DiscoveredSession] { localDiscoveryManager.discoveredSessions }

    var isHost: Bool { repository.isHost() }

    var canControlPlayback: Bool {
        guard let s = session else { return true }
        return repository.isHost() || s.settings.guestControlAllowed
    }

    var canModifyQueue: Bool {
        guard let s = session else { return true }
        return repository.isHost() || s.settings.guestQueueAllowed
    }

    var participants: [SyncParticipant] {
        session?.participants ?? []
    }

    private var hostBroadcastTask: Task<Void, Never>?
    private var guestSyncTask: Task<Void, Never>?
    private var scheduledPlayTask: Task<Void, Never>?
    private var localServerStopTask: Task<Void, Never>?

    private var lastAppliedTrackId: String?
    private var wasHostSession = false
    private var userInitiatedTermination = false
    private var isLocallyPausedByGuest = false
    private var isTransitioningTrack = false
    var isApplyingRemoteCommand = false

    private final class LocalAudioCache: @unchecked Sendable {
        private let queue = DispatchQueue(label: "audia.syncplay.audio-cache")
        private var urls: [String: URL] = [:]

        func url(for id: String) -> URL? { queue.sync { urls[id] } }
        func contains(_ id: String) -> Bool { queue.sync { urls[id] != nil } }
        func set(_ url: URL, for id: String) { queue.sync { urls[id] = url } }
    }
    private let localAudioCache = LocalAudioCache()

    private init() {
        self.driftCorrector = DriftCorrector(timeSyncEngine: repository.timeSyncEngine)
        setupCallbacks()
    }

    private func setupCallbacks() {
        localServer.audioStreamProvider = { [weak self] mediaId in
            guard let self else { return nil }
            let fileURL = self.localAudioCache.url(for: mediaId)
            if let fileURL {
                let ext = fileURL.pathExtension.lowercased()
                let mime: String
                switch ext {
                case "mp3": mime = "audio/mpeg"
                case "ogg", "opus": mime = "audio/ogg"
                case "flac": mime = "audio/flac"
                case "wav": mime = "audio/wav"
                default: mime = "audio/mp4"
                }
                return LocalAudioStream(fileURL: fileURL, mimeType: mime)
            }
            return nil
        }

        repository.onSessionChanged = { [weak self] newSession in
            self?.handleSessionChanged(newSession)
        }

        repository.onEvent = { [weak self] event in
            self?.handleSyncEvent(event)
        }

        repository.onConnectionStateChanged = { [weak self] state in
            self?.handleConnectionStateChange(state)
        }
    }

    func dismissSessionTerminationNotice() {
        sessionTerminationNotice = nil
    }

    // MARK: - Public Actions for UI

    func startHost(
        serverUrl: String,
        hostName: String,
        settings: SyncRoomSettings = SyncRoomSettings()
    ) {
        sessionTerminationNotice = nil
        wasHostSession = true
        userInitiatedTermination = false
        if isLocalHosting {
            localDiscoveryManager.stopAdvertising()
            localServer.stop()
        }
        isLocalHosting = false
        localServerUrl = nil
        repository.createRoom(serverUrl: serverUrl, hostName: hostName, settings: settings)
    }

    func startLocalHost(
        hostName: String,
        settings: SyncRoomSettings = SyncRoomSettings()
    ) {
        sessionTerminationNotice = nil
        wasHostSession = true
        userInitiatedTermination = false
        localServerStopTask?.cancel()
        localServerStopTask = nil
        if isLocalHosting {
            localDiscoveryManager.stopAdvertising()
            localServer.stop()
        }
        localServer.start(preferredPort: 8088) { [weak self] boundPort in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard boundPort > 0 else {
                    self.repository.failLocalStart(reason: "Could not start local Wi-Fi server.")
                    return
                }
                let ip = NetworkUtils.getLocalIpAddress() ?? "127.0.0.1"
                self.localServerUrl = "ws://\(ip):\(boundPort)/ws"
                self.isLocalHosting = true
                self.repository.createRoom(
                    serverUrl: "ws://127.0.0.1:\(boundPort)/ws",
                    hostName: hostName,
                    settings: settings
                )
            }
        }
    }

    func join(serverUrl: String, roomCode: String, guestName: String) {
        sessionTerminationNotice = nil
        wasHostSession = false
        userInitiatedTermination = false
        if isLocalHosting {
            localDiscoveryManager.stopAdvertising()
            localServer.stop()
        }
        isLocalHosting = false
        localServerUrl = nil
        repository.joinRoom(serverUrl: serverUrl, roomCode: roomCode, participantName: guestName)
    }

    func leave() {
        userInitiatedTermination = true
        sessionTerminationNotice = nil
        cancelPendingScheduledPlay()
        driftCorrector.reset(player: PlayerController.shared)
        if isLocalHosting && repository.isHost() {
            endSession()
            return
        }
        if isLocalHosting {
            localDiscoveryManager.stopAdvertising()
            localServer.stop()
            isLocalHosting = false
            localServerUrl = nil
        }
        repository.leaveRoom()
    }

    func endSession() {
        userInitiatedTermination = true
        wasHostSession = true
        sessionTerminationNotice = nil
        cancelPendingScheduledPlay()
        driftCorrector.reset(player: PlayerController.shared)
        let wasLocal = isLocalHosting
        repository.endSession()
        if wasLocal {
            localDiscoveryManager.stopAdvertising()
            localServerStopTask?.cancel()
            localServerStopTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                self?.localServer.stop()
                self?.isLocalHosting = false
                self?.localServerUrl = nil
            }
        }
    }

    func updateSettings(_ settings: SyncRoomSettings) {
        if repository.isHost() {
            repository.updateSettings(settings)
        }
    }

    func kickParticipant(_ participantId: String) {
        if repository.isHost() {
            repository.kickParticipant(participantId)
        }
    }

    func startDiscovery() {
        localDiscoveryManager.startDiscovery()
    }

    func stopDiscovery() {
        localDiscoveryManager.stopDiscovery()
    }

    func resetConnectionState() {
        repository.resetConnectionState()
    }

    // MARK: - User Playback Controls

    func handleUserSetPaused(_ paused: Bool) -> Bool {
        guard session != nil else { return false }
        let currentlyPlaying = PlayerController.shared.playState.value == .playing
        if paused == !currentlyPlaying {
            return true
        }
        return handleUserPlayPauseToggle()
    }

    func handleUserPlayPauseToggle() -> Bool {
        let player = PlayerController.shared
        guard session != nil else {
            return false
        }

        if repository.isHost() {
            let currentlyPlaying = player.playState.value == .playing
            if currentlyPlaying {
                cancelPendingScheduledPlay()
                isApplyingRemoteCommand = true
                player.setPaused(true)
                isApplyingRemoteCommand = false
                let currentPosMs = Int64(max(0, player.currentTime) * 1000.0)
                repository.broadcastPlaybackCommand(command: "PAUSE", positionMs: currentPosMs)
                broadcastHostState(forcedPlaying: false, forcedPositionMs: currentPosMs)
                driftCorrector.reset(player: player)
            } else {
                let rtt = repository.timeSyncEngine.roundTripTimeMs
                let leadTimeMs: Int64 = isLocalHosting ? 140 : min(300, max(160, rtt + 90))
                let currentServerTime = repository.timeSyncEngine.toServerTime()
                let scheduledServerTime = currentServerTime + leadTimeMs
                let currentPosMs = Int64(max(0, player.currentTime) * 1000.0)
                scheduleLocalPlay(targetPositionMs: currentPosMs, scheduledServerTimeMs: scheduledServerTime)
                repository.broadcastPlaybackCommand(command: "PLAY", positionMs: currentPosMs, scheduledAtMs: scheduledServerTime)
                broadcastHostState(forcedPlaying: true, forcedPositionMs: currentPosMs)
            }
            return true
        }

        if canControlPlayback {
            let currentlyPlaying = player.playState.value == .playing
            if currentlyPlaying {
                cancelPendingScheduledPlay()
                isLocallyPausedByGuest = true
                isApplyingRemoteCommand = true
                player.setPaused(true)
                isApplyingRemoteCommand = false
                let currentPosMs = Int64(max(0, player.currentTime) * 1000.0)
                repository.broadcastPlaybackCommand(command: "PAUSE", positionMs: currentPosMs)
                driftCorrector.reset(player: player)
            } else {
                isLocallyPausedByGuest = false
                let currentPosMs = Int64(max(0, player.currentTime) * 1000.0)
                repository.broadcastPlaybackCommand(command: "PLAY", positionMs: currentPosMs)
            }
            return true
        }

        return true // Swallow when guest lacks permission
    }

    func handleUserSeek(to time: TimeInterval) -> Bool {
        guard session != nil else { return false }
        cancelPendingScheduledPlay()
        let player = PlayerController.shared
        let positionMs = Int64(max(0, time) * 1000.0)
        let currentServerTime = repository.timeSyncEngine.toServerTime()

        if repository.isHost() {
            isApplyingRemoteCommand = true
            player.seek(to: time)
            isApplyingRemoteCommand = false
            broadcastHostState(forcedPositionMs: positionMs)
            repository.broadcastPlaybackCommand(command: "SEEK", positionMs: positionMs, scheduledAtMs: currentServerTime)
            return true
        }

        if canControlPlayback {
            isApplyingRemoteCommand = true
            player.seek(to: time)
            isApplyingRemoteCommand = false
            repository.broadcastPlaybackCommand(command: "SEEK", positionMs: positionMs, scheduledAtMs: currentServerTime)
            return true
        }

        return true
    }

    func handleUserSkipNext() -> Bool {
        guard session != nil else { return false }
        cancelPendingScheduledPlay()
        if repository.isHost() {
            return false // Let NowPlaying advance and broadcast via onHostTrackChanged()
        }
        if canControlPlayback {
            repository.broadcastPlaybackCommand(command: "SKIP_NEXT")
        }
        return true
    }

    func handleUserSkipPrevious() -> Bool {
        guard session != nil else { return false }
        cancelPendingScheduledPlay()
        if repository.isHost() {
            return false // Let NowPlaying go back and broadcast via onHostTrackChanged()
        }
        if canControlPlayback {
            repository.broadcastPlaybackCommand(command: "SKIP_PREV")
        }
        return true
    }

    func onHostTrackChanged() {
        guard session != nil, repository.isHost(), !isApplyingRemoteCommand else { return }
        broadcastHostState()
    }

    func onHostPlaybackStateChanged(isPlaying: Bool) {
        guard session != nil, repository.isHost(), !isApplyingRemoteCommand else { return }
        broadcastHostState(forcedPlaying: isPlaying)
    }

    // MARK: - Session & Event Handling

    private func handleSessionChanged(_ newSession: SyncRoomSnapshot?) {
        guard let s = newSession else {
            if isLocalHosting {
                localDiscoveryManager.stopAdvertising()
                localServer.stop()
                isLocalHosting = false
                localServerUrl = nil
            }
            stopHostBroadcast()
            stopGuestSync()
            cancelPendingScheduledPlay()
            driftCorrector.reset(player: PlayerController.shared)
            lastAppliedTrackId = nil
            return
        }

        if repository.isHost() {
            wasHostSession = true
            if isLocalHosting {
                let hostName = s.participants.first(where: { $0.id == s.hostId })?.name ?? "Host"
                let ip = NetworkUtils.getLocalIpAddress() ?? "127.0.0.1"
                localDiscoveryManager.advertiseSession(
                    roomCode: s.code,
                    hostName: hostName,
                    port: localServer.boundPort,
                    ipAddress: ip
                )
            }
            stopGuestSync()
            startHostBroadcast()
        } else {
            stopHostBroadcast()
            applyGuestSessionState(s)
            if guestSyncTask == nil {
                startGuestSync()
            }
        }
    }

    private func handleSyncEvent(_ event: SyncEvent) {
        switch event {
        case .playbackCommandReceived(let command, let positionMs, let scheduledAtMs, _):
            handleRemotePlaybackCommand(command: command, positionMs: positionMs, scheduledAtMs: scheduledAtMs)

        case .sessionTerminated(let reason, let wasHost):
            cancelPendingScheduledPlay()
            let isHostUser = wasHost || wasHostSession || isHost || isLocalHosting || userInitiatedTermination
            if !isHostUser {
                isApplyingRemoteCommand = true
                PlayerController.shared.setPaused(true)
                isApplyingRemoteCommand = false
                sessionTerminationNotice = reason.isEmpty ? "The host has ended the session." : reason
            } else {
                sessionTerminationNotice = nil
            }
            driftCorrector.reset(player: PlayerController.shared)

        case .errorOccurred(let code, let message):
            Log.player.warning("SyncPlay Error: \(code) - \(message)")
        }
    }

    private func handleConnectionStateChange(_ state: SyncConnectionState) {
        let isHostUser = isHost || wasHostSession || isLocalHosting || userInitiatedTermination
        guard !isHostUser else { return }

        switch state {
        case .failed:
            if session != nil {
                cancelPendingScheduledPlay()
                if PlayerController.shared.playState.value == .playing {
                    isApplyingRemoteCommand = true
                    PlayerController.shared.setPaused(true)
                    isApplyingRemoteCommand = false
                }
            }
        case .connected:
            if let currentSnapshot = session, currentSnapshot.playbackState.isPlaying {
                isLocallyPausedByGuest = false
                if PlayerController.shared.playState.value != .playing {
                    isApplyingRemoteCommand = true
                    PlayerController.shared.setPaused(false)
                    isApplyingRemoteCommand = false
                }
            }
        default:
            break
        }
    }

    // MARK: - Host Broadcast

    private func startHostBroadcast() {
        hostBroadcastTask?.cancel()
        broadcastHostState()
        hostBroadcastTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(2500))
                guard let self, !Task.isCancelled else { return }
                if self.repository.isHost(), self.session != nil, PlayerController.shared.playState.value == .playing {
                    self.broadcastHostState()
                }
            }
        }
    }

    private func stopHostBroadcast() {
        hostBroadcastTask?.cancel()
        hostBroadcastTask = nil
    }

    private func broadcastHostState(
        forcedPlaying: Bool? = nil,
        forcedPositionMs: Int64? = nil
    ) {
        guard var syncTrack = SyncTrack.fromNowPlaying(NowPlaying.shared) else { return }
        if isLocalHosting, localServer.boundPort > 0 {
            let trackId = syncTrack.id
            let hasCachedLocal = localAudioCache.contains(trackId)

            if hasCachedLocal {
                let hostIp = NetworkUtils.getLocalIpAddress() ?? "127.0.0.1"
                syncTrack = SyncTrack(
                    id: syncTrack.id,
                    title: syncTrack.title,
                    artist: syncTrack.artist,
                    album: syncTrack.album,
                    durationMs: syncTrack.durationMs,
                    thumbnailUrl: syncTrack.thumbnailUrl,
                    streamUrl: "http://\(hostIp):\(localServer.boundPort)/audio/\(trackId)"
                )
            } else {
                Task { [weak self] in
                    if let url = await DownloadManager.shared.localURL(for: trackId), let self {
                        self.localAudioCache.set(url, for: trackId)
                    }
                }
            }
        }
        let player = PlayerController.shared
        let isPlaying = forcedPlaying ?? (player.playState.value == .playing)
        let posMs = forcedPositionMs ?? Int64(max(0, player.currentTime) * 1000.0)
        repository.broadcastSyncState(
            currentTrack: syncTrack,
            isPlaying: isPlaying,
            positionMs: posMs,
            speed: Float(player.currentSpeed)
        )
    }

    // MARK: - Guest Sync

    private func startGuestSync() {
        stopGuestSync()
        guestSyncTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let player = PlayerController.shared
                let outputLatencyMs = self.driftCorrector.getEstimatedOutputLatencyMs()
                if let currentSession = self.session, !self.repository.isHost() {
                    let state = currentSession.playbackState
                    if !self.isTransitioningTrack,
                       let targetTrack = state.currentTrack,
                       NowPlaying.shared.videoId == targetTrack.id {
                        self.isApplyingRemoteCommand = true
                        self.driftCorrector.evaluateAndCorrect(
                            player: player,
                            targetPositionMs: state.positionMs,
                            serverTimestampMs: state.serverTimestampMs,
                            targetIsPlaying: state.isPlaying,
                            targetSpeed: state.speed,
                            outputLatencyMs: outputLatencyMs,
                            allowAutoplay: !self.isLocallyPausedByGuest
                        )
                        self.isApplyingRemoteCommand = false
                    }
                }
                let isPlaying = self.session?.playbackState.isPlaying == true && player.playState.value == .playing
                let delayMs: Int = isPlaying ? 120 : 1000
                try? await Task.sleep(for: .milliseconds(delayMs))
            }
        }
    }

    private func stopGuestSync() {
        guestSyncTask?.cancel()
        guestSyncTask = nil
        cancelPendingScheduledPlay()
    }

    private func applyGuestSessionState(_ currentSession: SyncRoomSnapshot) {
        let state = currentSession.playbackState
        guard let targetTrack = state.currentTrack else { return }
        let player = PlayerController.shared
        let outputLatencyMs = driftCorrector.getEstimatedOutputLatencyMs()
        let currentLocalId = NowPlaying.shared.videoId

        if isTransitioningTrack && lastAppliedTrackId == targetTrack.id {
            return
        }

        if currentLocalId != targetTrack.id {
            lastAppliedTrackId = targetTrack.id
            isTransitioningTrack = true
            let song = targetTrack.toSongItem()
            let startPosMs = driftCorrector.calculateExpectedPosition(
                targetPositionMs: state.positionMs,
                serverTimestampMs: state.serverTimestampMs,
                targetIsPlaying: state.isPlaying,
                targetSpeed: state.speed,
                outputLatencyMs: outputLatencyMs
            )
            let shouldPlay = state.isPlaying && !isLocallyPausedByGuest

            NowPlaying.shared.setQueue([song], startIndex: 0)
            NowPlaying.shared.update(with: song)

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isApplyingRemoteCommand = true
                defer {
                    self.isApplyingRemoteCommand = false
                    self.isTransitioningTrack = false
                }

                // Timeout guard: if resolution takes > 15s, unblock
                let trackIdAtStart = targetTrack.id
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(15))
                    guard let self, self.isTransitioningTrack, self.lastAppliedTrackId == trackIdAtStart else { return }
                    self.isTransitioningTrack = false
                }

                if let streamUrl = targetTrack.streamUrl, !streamUrl.isEmpty {
                    await player.play(
                        url: streamUrl,
                        title: targetTrack.title,
                        artist: targetTrack.artist,
                        videoId: targetTrack.id,
                        duration: Double(targetTrack.durationMs) / 1000.0,
                        artists: song.artists,
                        thumbnailUrl: targetTrack.thumbnailUrl
                    )
                } else {
                    try? await PlaybackManager.shared.resolveAndPlay(videoId: targetTrack.id)
                }

                if startPosMs > 300 {
                    player.seek(to: Double(startPosMs) / 1000.0)
                }
                if !shouldPlay {
                    player.setPaused(true)
                }
            }
        } else {
            isApplyingRemoteCommand = true
            defer { isApplyingRemoteCommand = false }

            if !state.isPlaying {
                cancelPendingScheduledPlay()
                if player.playState.value == .playing {
                    player.setPaused(true)
                }
                let currentPosMs = Int64(player.currentTime * 1000.0)
                if abs(currentPosMs - state.positionMs) > 15 {
                    player.seek(to: Double(max(0, state.positionMs)) / 1000.0)
                }
                driftCorrector.reset(player: player)
            } else {
                isLocallyPausedByGuest = false
                if player.playState.value != .playing {
                    player.setPaused(false)
                }
                driftCorrector.evaluateAndCorrect(
                    player: player,
                    targetPositionMs: state.positionMs,
                    serverTimestampMs: state.serverTimestampMs,
                    targetIsPlaying: state.isPlaying,
                    targetSpeed: state.speed,
                    outputLatencyMs: outputLatencyMs,
                    allowAutoplay: true
                )
            }
        }
    }

    private func handleRemotePlaybackCommand(command: String, positionMs: Int64?, scheduledAtMs: Int64?) {
        let player = PlayerController.shared
        isApplyingRemoteCommand = true
        defer {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(80))
                self?.isApplyingRemoteCommand = false
            }
        }

        switch command {
        case "PLAY":
            isLocallyPausedByGuest = false
            if let scheduledAtMs {
                scheduleLocalPlay(targetPositionMs: positionMs, scheduledServerTimeMs: scheduledAtMs)
            } else {
                cancelPendingScheduledPlay()
                if let positionMs {
                    let currentPosMs = Int64(player.currentTime * 1000.0)
                    if abs(currentPosMs - positionMs) > 15 {
                        player.seek(to: Double(max(0, positionMs)) / 1000.0)
                    }
                }
                player.setPaused(false)
            }

        case "PAUSE":
            cancelPendingScheduledPlay()
            player.setPaused(true)
            if let positionMs {
                let currentPosMs = Int64(player.currentTime * 1000.0)
                if abs(currentPosMs - positionMs) > 15 {
                    player.seek(to: Double(max(0, positionMs)) / 1000.0)
                }
            }
            driftCorrector.reset(player: player)

        case "SEEK":
            cancelPendingScheduledPlay()
            if let positionMs {
                let expected: Int64
                if let scheduledAtMs, player.playState.value == .playing {
                    expected = driftCorrector.calculateExpectedPosition(
                        targetPositionMs: positionMs,
                        serverTimestampMs: scheduledAtMs,
                        targetIsPlaying: true
                    )
                } else {
                    expected = positionMs
                }
                player.seek(to: Double(max(0, expected)) / 1000.0)
            }

        case "SKIP_NEXT":
            if repository.isHost() {
                cancelPendingScheduledPlay()
                isApplyingRemoteCommand = false
                NowPlaying.shared.playNext()
            }

        case "SKIP_PREV":
            if repository.isHost() {
                cancelPendingScheduledPlay()
                isApplyingRemoteCommand = false
                NowPlaying.shared.playPrevious()
            }

        default:
            break
        }
    }

    private func cancelPendingScheduledPlay() {
        scheduledPlayTask?.cancel()
        scheduledPlayTask = nil
    }

    private func scheduleLocalPlay(targetPositionMs: Int64?, scheduledServerTimeMs: Int64) {
        cancelPendingScheduledPlay()
        scheduledPlayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let player = PlayerController.shared
            let localTargetTime = self.repository.timeSyncEngine.toLocalTime(serverTimeMs: scheduledServerTimeMs)
            let now = TimeSyncEngine.currentEpochMs()
            let delayMs = localTargetTime - now

            self.isApplyingRemoteCommand = true
            if delayMs > 0 && delayMs < 3000 {
                if let targetPositionMs {
                    let currentPosMs = Int64(player.currentTime * 1000.0)
                    if abs(currentPosMs - targetPositionMs) > 15 {
                        player.seek(to: Double(max(0, targetPositionMs)) / 1000.0)
                    }
                }
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard !Task.isCancelled else {
                    self.isApplyingRemoteCommand = false
                    return
                }
                player.setPaused(false)
            } else {
                let currentServerTime = self.repository.timeSyncEngine.toServerTime()
                let elapsed = max(0, currentServerTime - scheduledServerTimeMs)
                let basePos = targetPositionMs ?? Int64(player.currentTime * 1000.0)
                let expectedPos = basePos + elapsed
                let currentPosMs = Int64(player.currentTime * 1000.0)
                if abs(currentPosMs - expectedPos) > 15 {
                    player.seek(to: Double(max(0, expectedPos)) / 1000.0)
                }
                player.setPaused(false)
            }
            self.isApplyingRemoteCommand = false
            self.scheduledPlayTask = nil
        }
    }
}

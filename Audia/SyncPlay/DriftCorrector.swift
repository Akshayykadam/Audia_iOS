//
//  DriftCorrector.swift
//  Audia
//

import AVFoundation
import Combine
import Foundation
import Observation

struct DriftStatus: Equatable, Sendable {
    var isInSync: Bool = true
    var driftMs: Int64 = 0
    var appliedSpeed: Float = 1.0
    var isMacroSeeking: Bool = false
}

@Observable
@MainActor
final class DriftCorrector {
    private let timeSyncEngine: TimeSyncEngine
    private(set) var driftStatus = DriftStatus()

    private static let tightSyncToleranceMs: Int64 = 20
    private static let microDriftThresholdMs: Int64 = 80
    private static let moderateDriftThresholdMs: Int64 = 300

    private static let speedMicroSlowdown: Double = 0.985
    private static let speedMicroSpeedup: Double = 1.015
    private static let speedFastSlowdown: Double = 0.94
    private static let speedFastSpeedup: Double = 1.06
    private static let speedNormal: Double = 1.0

    private static let macroSeekCooldownMs: Int64 = 800
    private static let bluetoothLatencyCompensationMs: Int64 = 140

    private var lastMacroSeekTimeMs: Int64 = 0
    private var smoothedDrift: Double?

    init(timeSyncEngine: TimeSyncEngine) {
        self.timeSyncEngine = timeSyncEngine
    }

    func getEstimatedOutputLatencyMs() -> Int64 {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let isBluetooth = outputs.contains { port in
            port.portType == .bluetoothA2DP ||
            port.portType == .bluetoothHFP ||
            port.portType == .bluetoothLE
        }
        return isBluetooth ? Self.bluetoothLatencyCompensationMs : 0
    }

    func calculateExpectedPosition(
        targetPositionMs: Int64,
        serverTimestampMs: Int64,
        targetIsPlaying: Bool,
        targetSpeed: Float = 1.0,
        outputLatencyMs: Int64 = 0
    ) -> Int64 {
        guard targetIsPlaying else { return max(0, targetPositionMs) }
        let currentServerTime = timeSyncEngine.toServerTime()
        if currentServerTime < serverTimestampMs {
            return max(0, targetPositionMs)
        }
        let elapsedSinceSample = currentServerTime - serverTimestampMs
        let expectedPosition = targetPositionMs + Int64(Double(elapsedSinceSample) * Double(targetSpeed)) + outputLatencyMs
        return max(0, expectedPosition)
    }

    func evaluateAndCorrect(
        player: PlayerController,
        targetPositionMs: Int64,
        serverTimestampMs: Int64,
        targetIsPlaying: Bool,
        targetSpeed: Float = 1.0,
        outputLatencyMs: Int64 = 0,
        allowAutoplay: Bool = true
    ) {
        if !targetIsPlaying {
            if player.playState.value == .playing {
                player.setPaused(true)
            }
            if abs(player.currentSpeed - Self.speedNormal) > 0.001 {
                player.setSpeed(Self.speedNormal)
            }
            smoothedDrift = nil
            let currentPosMs = Int64(player.currentTime * 1000.0)
            let pauseDrift = currentPosMs - targetPositionMs
            if abs(pauseDrift) > 15 {
                player.seek(to: Double(max(0, targetPositionMs)) / 1000.0)
            }
            driftStatus = DriftStatus(
                isInSync: abs(pauseDrift) <= Self.tightSyncToleranceMs,
                driftMs: pauseDrift,
                appliedSpeed: Float(Self.speedNormal),
                isMacroSeeking: false
            )
            return
        }

        if allowAutoplay && player.playState.value != .playing && player.currentVideoId != nil {
            player.setPaused(false)
        }

        guard player.currentVideoId != nil else { return }

        let currentServerTime = timeSyncEngine.toServerTime()

        if currentServerTime < serverTimestampMs {
            let currentPosMs = Int64(player.currentTime * 1000.0)
            if abs(currentPosMs - targetPositionMs) > 15 {
                player.seek(to: Double(max(0, targetPositionMs)) / 1000.0)
            }
            if abs(player.currentSpeed - Self.speedNormal) > 0.001 {
                player.setSpeed(Self.speedNormal)
            }
            return
        }

        let elapsedSinceSample = max(0, currentServerTime - serverTimestampMs)
        let expectedPosition = targetPositionMs + Int64(Double(elapsedSinceSample) * Double(targetSpeed)) + outputLatencyMs
        let currentLocalPosMs = Int64(player.currentTime * 1000.0)
        let rawDrift = currentLocalPosMs - expectedPosition

        let drift: Int64
        if let prevSmoothed = smoothedDrift, abs(Double(rawDrift) - prevSmoothed) <= 250.0 {
            let newSmoothed = prevSmoothed * 0.75 + Double(rawDrift) * 0.25
            smoothedDrift = newSmoothed
            drift = Int64(newSmoothed)
        } else {
            smoothedDrift = Double(rawDrift)
            drift = rawDrift
        }

        let absDrift = abs(drift)
        if absDrift <= Self.tightSyncToleranceMs {
            applySpeedIfNeeded(player, Self.speedNormal)
            driftStatus = DriftStatus(isInSync: true, driftMs: drift, appliedSpeed: Float(Self.speedNormal), isMacroSeeking: false)
        } else if drift > Self.tightSyncToleranceMs && drift <= Self.microDriftThresholdMs {
            applySpeedIfNeeded(player, Self.speedMicroSlowdown)
            driftStatus = DriftStatus(isInSync: true, driftMs: drift, appliedSpeed: Float(Self.speedMicroSlowdown), isMacroSeeking: false)
        } else if drift < -Self.tightSyncToleranceMs && drift >= -Self.microDriftThresholdMs {
            applySpeedIfNeeded(player, Self.speedMicroSpeedup)
            driftStatus = DriftStatus(isInSync: true, driftMs: drift, appliedSpeed: Float(Self.speedMicroSpeedup), isMacroSeeking: false)
        } else if drift > Self.microDriftThresholdMs && drift <= Self.moderateDriftThresholdMs {
            applySpeedIfNeeded(player, Self.speedFastSlowdown)
            driftStatus = DriftStatus(isInSync: false, driftMs: drift, appliedSpeed: Float(Self.speedFastSlowdown), isMacroSeeking: false)
        } else if drift < -Self.microDriftThresholdMs && drift >= -Self.moderateDriftThresholdMs {
            applySpeedIfNeeded(player, Self.speedFastSpeedup)
            driftStatus = DriftStatus(isInSync: false, driftMs: drift, appliedSpeed: Float(Self.speedFastSpeedup), isMacroSeeking: false)
        } else {
            let now = TimeSyncEngine.currentEpochMs()
            if now - lastMacroSeekTimeMs > Self.macroSeekCooldownMs {
                lastMacroSeekTimeMs = now
                smoothedDrift = nil
                applySpeedIfNeeded(player, Self.speedNormal)
                player.seek(to: Double(max(0, expectedPosition)) / 1000.0)
            }
            driftStatus = DriftStatus(isInSync: false, driftMs: drift, appliedSpeed: Float(Self.speedNormal), isMacroSeeking: true)
        }
    }

    private func applySpeedIfNeeded(_ player: PlayerController, _ target: Double) {
        if abs(player.currentSpeed - target) > 0.001 {
            player.setSpeed(target)
        }
    }

    func reset(player: PlayerController? = nil) {
        smoothedDrift = nil
        if let player, abs(player.currentSpeed - Self.speedNormal) > 0.001 {
            player.setSpeed(Self.speedNormal)
        }
        driftStatus = DriftStatus()
    }
}

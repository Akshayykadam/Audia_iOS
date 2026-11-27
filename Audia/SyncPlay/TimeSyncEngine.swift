//
//  TimeSyncEngine.swift
//  Audia
//

import Foundation
import Observation

@Observable
@MainActor
final class TimeSyncEngine {
    private(set) var clockOffsetMs: Int64 = 0
    private(set) var roundTripTimeMs: Int64 = 0
    private(set) var isCalibrated: Bool = false

    private var samples: [(offset: Int64, rtt: Int64)] = []
    private let maxSamples = 8

    nonisolated static func currentEpochMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000.0)
    }

    func onTimePongReceived(clientTimeMs: Int64, serverReceiveTimeMs: Int64, serverSendTimeMs: Int64) {
        let now = Self.currentEpochMs()
        let totalRoundTrip = now - clientTimeMs
        let serverProcessingTime = serverSendTimeMs - serverReceiveTimeMs
        let networkRtt = max(0, totalRoundTrip - serverProcessingTime)

        // Cristian's algorithm: offset = ((t1 - t0) + (t2 - t3)) / 2
        let offset = ((serverReceiveTimeMs - clientTimeMs) + (serverSendTimeMs - now)) / 2

        if !samples.isEmpty {
            let sortedRtts = samples.map(\.rtt).sorted()
            let medianRtt = sortedRtts[samples.count / 2]
            if networkRtt > medianRtt * 3 && networkRtt > 400 {
                return
            }
        }

        samples.append((offset: offset, rtt: networkRtt))
        if samples.count > maxSamples {
            samples.removeFirst()
        }

        let sortedByRtt = samples.sorted { $0.rtt < $1.rtt }
        let bestCount = max(1, samples.count / 2)
        let bestSamples = sortedByRtt.prefix(bestCount)
        let avgOffset = Int64(Double(bestSamples.map(\.offset).reduce(0, +)) / Double(bestCount))
        let avgRtt = Int64(Double(bestSamples.map(\.rtt).reduce(0, +)) / Double(bestCount))

        if !isCalibrated {
            clockOffsetMs = avgOffset
        } else {
            let prev = clockOffsetMs
            let delta = avgOffset - prev
            if abs(delta) > 400 {
                clockOffsetMs = avgOffset
            } else {
                clockOffsetMs = Int64(Double(prev) * 0.75 + Double(avgOffset) * 0.25)
            }
        }

        roundTripTimeMs = avgRtt
        if !isCalibrated && samples.count >= 2 {
            isCalibrated = true
        }
    }

    var estimatedOneWayLatencyMs: Int64 {
        max(1, roundTripTimeMs / 2)
    }

    func toServerTime(localTimeMs: Int64 = TimeSyncEngine.currentEpochMs()) -> Int64 {
        localTimeMs + clockOffsetMs
    }

    func toLocalTime(serverTimeMs: Int64) -> Int64 {
        serverTimeMs - clockOffsetMs
    }

    func reset() {
        samples.removeAll()
        clockOffsetMs = 0
        roundTripTimeMs = 0
        isCalibrated = false
    }
}

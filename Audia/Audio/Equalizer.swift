//
//  Equalizer.swift
//  Audia
//

import AVFAudio
import Foundation

/// A fixed set of 10 band center frequencies used by the equalizer.
let equalizerFrequencies: [Double] = [60, 120, 250, 500, 1000, 2000, 4000, 8000, 12000, 16000]
let equalizerFrequencyLabels: [String] = ["60", "120", "250", "500", "1k", "2k", "4k", "8k", "12k", "16k"]

/// Gain bounds in dB, matching Spotify's ±12 dB range.
let equalizerMinGain: Double = -12
let equalizerMaxGain: Double = 12

struct EqualizerPreset: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let gains: [Double]
}

enum AudioOutputRoute: String, CaseIterable, Codable, Sendable {
    case speaker
    case headphones
    case bluetooth
    case other

    var displayName: String {
        switch self {
        case .speaker: return "Speaker"
        case .headphones: return "Headphones"
        case .bluetooth: return "Bluetooth"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .speaker: return "iphone"
        case .headphones: return "headphones"
        case .bluetooth: return "airpodspro"
        case .other: return "hifispeaker"
        }
    }

    static func current() -> AudioOutputRoute {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        for output in outputs {
            switch output.portType {
            case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
                return .bluetooth
            case .headphones, .headsetMic, .usbAudio:
                return .headphones
            case .builtInSpeaker, .builtInReceiver:
                return .speaker
            default:
                continue
            }
        }
        return outputs.isEmpty ? .speaker : .other
    }
}

struct EqualizerOutputProfile: Codable, Hashable, Sendable {
    var presetID: String
    var gains: [Double]
    var preampDb: Double
    var spatialMode: SpatialAudioMode?
}

enum SpatialAudioMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case off
    case natural
    case wideStereo
    case surround3D
    case concertHall

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .natural: return "Natural"
        case .wideStereo: return "Wide"
        case .surround3D: return "3D"
        case .concertHall: return "Concert"
        }
    }

    var mpvFilters: [String] {
        switch self {
        case .off:
            return []
        case .natural:
            return ["crossfeed=strength=0.35:range=0.6"]
        case .wideStereo:
            return ["stereotools=mlev=1.0:slev=1.35:softclip=1"]
        case .surround3D:
            return [
                "crossfeed=strength=0.3:range=0.55",
                "stereotools=mlev=1.0:slev=1.25:softclip=1",
                "aecho=0.8:0.9:14:0.12"
            ]
        case .concertHall:
            return [
                "stereotools=mlev=0.95:slev=1.45:softclip=1",
                "aecho=0.8:0.88:28|44:0.18|0.12"
            ]
        }
    }
}

enum EqualizerPresets {
    /// The built-in presets. Gains are dB values for `equalizerFrequencies`.
    static let all: [EqualizerPreset] = [
        EqualizerPreset(id: "flat", name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EqualizerPreset(id: "bassBoost", name: "Bass Boost", gains: [7, 6, 4, 2, 1, 0, 0, 0, 0, 0]),
        EqualizerPreset(id: "bassReducer", name: "Bass Reducer", gains: [-7, -6, -4, -2, -1, 0, 0, 0, 0, 0]),
        EqualizerPreset(id: "trebleBoost", name: "Treble Boost", gains: [0, 0, 0, 0, 0, 1, 2, 4, 6, 7]),
        EqualizerPreset(id: "trebleReducer", name: "Treble Reducer", gains: [0, 0, 0, 0, 0, -1, -2, -4, -6, -7]),
        EqualizerPreset(id: "vShape", name: "V-Shape", gains: [6, 5, 3, 1, 0, 0, 1, 3, 5, 6]),
        EqualizerPreset(id: "uShape", name: "U-Shape", gains: [5, 4, 1, -1, -2, -2, -1, 1, 4, 5]),
        EqualizerPreset(id: "mShape", name: "M-Shape", gains: [-2, 3, 4, 2, -2, 2, 4, 3, 0, -3]),
        EqualizerPreset(id: "wShape", name: "W-Shape", gains: [5, 4, 0, -2, 2, 4, 1, -1, 3, 5]),
        EqualizerPreset(id: "harman", name: "Harman", gains: [4, 3, 1, 0, 0, 2, 3, 2, 1, 0]),
        EqualizerPreset(id: "warm", name: "Warm", gains: [4, 4, 3, 2, 1, 0, -1, -2, -3, -4]),
        EqualizerPreset(id: "bright", name: "Bright", gains: [-2, -1, 0, 0, 1, 2, 3, 4, 5, 5]),
        EqualizerPreset(id: "deepBass", name: "Deep Bass", gains: [9, 7, 4, 1, 0, 0, 0, 1, 1, 0]),
        EqualizerPreset(id: "lateNight", name: "Late Night", gains: [-4, -2, 0, 2, 3, 3, 2, 0, -2, -3]),
        EqualizerPreset(id: "rock", name: "Rock", gains: [5, 4, 2, 0, -1, -1, 0, 2, 4, 5]),
        EqualizerPreset(id: "pop", name: "Pop", gains: [-1, 0, 1, 3, 3, 2, 1, 0, -1, -1]),
        EqualizerPreset(id: "hiphop", name: "Hip-Hop", gains: [6, 5, 3, 1, 0, 0, 1, 2, 3, 4]),
        EqualizerPreset(id: "electronic", name: "Electronic", gains: [5, 4, 3, 1, 0, 1, 2, 3, 4, 5]),
        EqualizerPreset(id: "jazz", name: "Jazz", gains: [3, 2, 1, 2, 1, 0, 1, 2, 3, 4]),
        EqualizerPreset(id: "classical", name: "Classical", gains: [4, 3, 2, 1, 0, 0, 1, 2, 3, 4]),
        EqualizerPreset(id: "acoustic", name: "Acoustic", gains: [4, 3, 2, 1, 0, 0, 1, 2, 3, 4]),
        EqualizerPreset(id: "vocal", name: "Vocal", gains: [-2, -1, 0, 1, 3, 4, 3, 1, 0, -2]),
        EqualizerPreset(id: "loudness", name: "Loudness", gains: [4, 3, 2, 1, 0, 1, 2, 3, 4, 5])
    ]
}

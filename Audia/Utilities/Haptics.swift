//
//  Haptics.swift
//  Audia
//

import UIKit

@MainActor
enum Haptics {
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static func light() {
        mediumGenerator.prepare()
        mediumGenerator.impactOccurred(intensity: 0.75)
    }

    static func medium() {
        heavyGenerator.prepare()
        heavyGenerator.impactOccurred(intensity: 0.9)
    }

    static func heavy() {
        heavyGenerator.prepare()
        heavyGenerator.impactOccurred(intensity: 1.0)
    }

    static func soft() {
        mediumGenerator.prepare()
        mediumGenerator.impactOccurred(intensity: 0.65)
    }

    static func rigid() {
        rigidGenerator.prepare()
        rigidGenerator.impactOccurred(intensity: 1.0)
    }

    /// Tactile feedback for tapping a song to start playback.
    static func playTrack() {
        heavyGenerator.prepare()
        heavyGenerator.impactOccurred(intensity: 1.0)
    }

    /// Crisp feedback when skipping/swiping to another track.
    static func trackChanged() {
        rigidGenerator.prepare()
        rigidGenerator.impactOccurred(intensity: 1.0)
    }

    /// Distinct feedback when toggling/cycling playback modes.
    static func toggle() {
        rigidGenerator.prepare()
        rigidGenerator.impactOccurred(intensity: 0.95)
    }

    static func selection() {
        rigidGenerator.prepare()
        rigidGenerator.impactOccurred(intensity: 0.65)
    }

    static func success() {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.success)
    }

    static func warning() {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.warning)
    }
}

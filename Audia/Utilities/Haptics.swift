//
//  Haptics.swift
//  Audia
//

import UIKit

@MainActor
enum Haptics {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static func light() {
        lightGenerator.prepare()
        lightGenerator.impactOccurred()
    }

    static func medium() {
        mediumGenerator.prepare()
        mediumGenerator.impactOccurred()
    }

    static func soft() {
        softGenerator.prepare()
        softGenerator.impactOccurred()
    }

    static func rigid() {
        rigidGenerator.prepare()
        rigidGenerator.impactOccurred()
    }

    /// Tactile feedback for tapping a song to start playback.
    static func playTrack() {
        mediumGenerator.prepare()
        mediumGenerator.impactOccurred(intensity: 0.85)
    }

    /// Crisp feedback when skipping/swiping to another track.
    static func trackChanged() {
        rigidGenerator.prepare()
        rigidGenerator.impactOccurred(intensity: 0.75)
    }

    /// Distinct feedback when toggling/cycling playback modes.
    static func toggle() {
        softGenerator.prepare()
        softGenerator.impactOccurred(intensity: 0.9)
    }

    static func selection() {
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
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

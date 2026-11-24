//
//  AudiaWidgetIntents.swift
//  AudiaWidgets
//

import AppIntents
import Foundation
import WidgetKit

@available(iOS 17.0, *)
public struct TogglePlayPauseIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource = "Play / Pause"
    public static var description = IntentDescription("Toggles Audia audio playback")

    public init() {}

    public func perform() async throws -> some IntentResult {
        // Optimistically flip the isPlaying flag in shared storage for instant UI responsiveness
        var state = WidgetDataStore.shared.readPlaybackState()
        state.isPlaying.toggle()
        WidgetDataStore.shared.writePlaybackState(state)

        // Broadcast to main app via Darwin notification
        WidgetDataStore.postDarwinNotification(WidgetDataStore.notifyTogglePlayPause)

        // Trigger widget reload
        WidgetCenter.shared.reloadTimelines(ofKind: "AudiaNowPlayingWidget")
        return .result()
    }
}

@available(iOS 17.0, *)
public struct SkipNextIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource = "Next Track"
    public static var description = IntentDescription("Skips to the next track in queue")

    public init() {}

    public func perform() async throws -> some IntentResult {
        WidgetDataStore.postDarwinNotification(WidgetDataStore.notifySkipNext)
        return .result()
    }
}

@available(iOS 17.0, *)
public struct SkipPreviousIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource = "Previous Track"
    public static var description = IntentDescription("Skips to the previous track in queue")

    public init() {}

    public func perform() async throws -> some IntentResult {
        WidgetDataStore.postDarwinNotification(WidgetDataStore.notifySkipPrevious)
        return .result()
    }
}

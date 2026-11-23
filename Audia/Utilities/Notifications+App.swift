//
//  Notifications+App.swift
//  Audia
//

import Foundation

extension Notification.Name {
    // durationDidUpdate comes from SwiftyTube's DurationCache.
    static let personalizationDataUpdated = Notification.Name("personalizationDataUpdated")
    static let nowPlayingDidChange = Notification.Name("nowPlayingDidChange")
    static let libraryPlaylistsUpdated = Notification.Name("libraryPlaylistsUpdated")
}

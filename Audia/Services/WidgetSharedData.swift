//
//  WidgetSharedData.swift
//  Audia
//

import Foundation
import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Playback State Model

public struct WidgetPlaybackState: Codable, Sendable, Equatable {
    public var videoId: String
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    public var currentTime: TimeInterval
    public var isPlaying: Bool
    public var isExplicit: Bool
    public var artworkFileName: String?
    public var thumbnailUrl: String?
    public var updatedAt: Date

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    public var remainingTime: TimeInterval {
        max(0, duration - currentTime)
    }

    public init(
        videoId: String = "",
        title: String = "",
        artist: String = "",
        album: String = "",
        duration: TimeInterval = 0,
        currentTime: TimeInterval = 0,
        isPlaying: Bool = false,
        isExplicit: Bool = false,
        artworkFileName: String? = nil,
        thumbnailUrl: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.videoId = videoId
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.currentTime = currentTime
        self.isPlaying = isPlaying
        self.isExplicit = isExplicit
        self.artworkFileName = artworkFileName
        self.thumbnailUrl = thumbnailUrl
        self.updatedAt = updatedAt
    }

    public static let placeholder = WidgetPlaybackState(
        videoId: "sample",
        title: "No Music Playing",
        artist: "Audia",
        album: "Open app to play",
        duration: 180,
        currentTime: 0,
        isPlaying: false,
        isExplicit: false,
        artworkFileName: nil,
        thumbnailUrl: nil,
        updatedAt: Date()
    )
}

// MARK: - Recent Item Model

public struct WidgetRecentItem: Codable, Identifiable, Sendable, Equatable {
    public var id: String { videoId }
    public var videoId: String
    public var title: String
    public var artist: String
    public var album: String?
    public var artworkFileName: String?
    public var thumbnailUrl: String?
    public var timestamp: Date

    public init(
        videoId: String,
        title: String,
        artist: String,
        album: String? = nil,
        artworkFileName: String? = nil,
        thumbnailUrl: String? = nil,
        timestamp: Date = Date()
    ) {
        self.videoId = videoId
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkFileName = artworkFileName
        self.thumbnailUrl = thumbnailUrl
        self.timestamp = timestamp
    }
}

// MARK: - Apple-Grade Monochrome Adaptive Theme

public enum AudiaWidgetTheme {
    /// Pure Black in Dark Mode (#000000 OLED), Pure White in Light Mode (#FFFFFF)
    public static func backgroundColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black : Color.white
    }

    /// Background for cards/tiles within the widget
    public static func surfaceColor(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 20/255, green: 20/255, blue: 22/255)
            : Color(red: 242/255, green: 242/255, blue: 247/255)
    }

    /// High-contrast primary text (bold white on dark, bold black on light)
    public static func primaryTextColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white : Color(red: 18/255, green: 18/255, blue: 20/255)
    }

    /// Secondary muted text for subtitles/artists
    public static func secondaryTextColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.62) : Color(white: 0.42)
    }

    /// Tertiary text for kicker labels ("NOW PLAYING", "RECENTLY PLAYED")
    public static func tertiaryTextColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.45) : Color(white: 0.58)
    }

    /// Playback circular button fill
    public static func controlFillColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white : Color(red: 18/255, green: 18/255, blue: 20/255)
    }

    /// Playback circular button icon
    public static func controlIconColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black : Color.white
    }

    /// Artwork hairline border for crisp edge separation against pure black/white
    public static func artworkBorder(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    /// Progress bar track background
    public static func progressTrackColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.10)
    }

    /// Subtle placeholder gradient for album art
    public static func placeholderGradient(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(white: 0.16), Color(white: 0.10)]
                : [Color(red: 236/255, green: 236/255, blue: 240/255), Color(red: 228/255, green: 228/255, blue: 234/255)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Shared Data Store

public final class WidgetDataStore {
    public static let shared = WidgetDataStore()

    public static let appGroupId = "group.com.akshayysk.Audia"
    public static let playbackKey = "audia_widget_playback_state"
    public static let recentsKey = "audia_widget_recent_items"

    // Darwin Notification Names for real-time widget controls
    public static let notifyTogglePlayPause = "com.akshayysk.Audia.togglePlayPause"
    public static let notifySkipNext = "com.akshayysk.Audia.skipNext"
    public static let notifySkipPrevious = "com.akshayysk.Audia.skipPrevious"
    public static let notifyPlaySong = "com.akshayysk.Audia.playSong"

    public var defaults: UserDefaults {
        UserDefaults(suiteName: Self.appGroupId) ?? .standard
    }

    public var containerDirectory: URL {
        if let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupId) {
            return shared
        }
        #if targetEnvironment(simulator)
        var cur = URL(fileURLWithPath: NSHomeDirectory())
        while cur.pathComponents.count > 1 {
            let candidate = cur.appendingPathComponent("Shared/AppGroup")
            if FileManager.default.fileExists(atPath: candidate.path),
               let subdirs = try? FileManager.default.contentsOfDirectory(at: candidate, includingPropertiesForKeys: nil) {
                for dir in subdirs {
                    let meta = dir.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                    if let data = try? Data(contentsOf: meta),
                       data.range(of: Data(Self.appGroupId.utf8)) != nil {
                        return dir
                    }
                }
            }
            if cur.lastPathComponent == "Containers" || cur.lastPathComponent == "data" {
                break
            }
            cur = cur.deletingLastPathComponent()
        }
        // Universal simulator fallback shared across all simulator processes
        let tempShared = URL(fileURLWithPath: "/tmp/audia_shared_widget", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempShared, withIntermediateDirectories: true)
        return tempShared
        #else
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        #endif
    }

    public var artworkDirectory: URL {
        let dir = containerDirectory.appendingPathComponent("WidgetArtworkCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var playbackStateFileURL: URL {
        containerDirectory.appendingPathComponent("widget_playback_state.json")
    }

    private var recentItemsFileURL: URL {
        containerDirectory.appendingPathComponent("widget_recent_items.json")
    }

    private init() {}

    // MARK: - Playback State Persistence

    public func readPlaybackState() -> WidgetPlaybackState {
        // 1. Check primary shared container JSON
        if let data = try? Data(contentsOf: playbackStateFileURL),
           let state = try? JSONDecoder().decode(WidgetPlaybackState.self, from: data) {
            return state
        }
        #if targetEnvironment(simulator)
        // 2. Check universal simulator fallback
        let tempFile = URL(fileURLWithPath: "/tmp/audia_shared_widget/widget_playback_state.json")
        if let data = try? Data(contentsOf: tempFile),
           let state = try? JSONDecoder().decode(WidgetPlaybackState.self, from: data) {
            return state
        }
        #endif
        // 3. Fall back to UserDefaults
        if let data = defaults.data(forKey: Self.playbackKey),
           let state = try? JSONDecoder().decode(WidgetPlaybackState.self, from: data) {
            return state
        }
        return .placeholder
    }

    public func writePlaybackState(_ state: WidgetPlaybackState) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.playbackKey)
            defaults.synchronize()
            try? data.write(to: playbackStateFileURL, options: .atomic)
            #if targetEnvironment(simulator)
            let tempFile = URL(fileURLWithPath: "/tmp/audia_shared_widget/widget_playback_state.json")
            try? data.write(to: tempFile, options: .atomic)
            #endif
        }
    }

    // MARK: - Recent Items Persistence

    public func readRecentItems() -> [WidgetRecentItem] {
        // 1. Check primary shared container JSON
        if let data = try? Data(contentsOf: recentItemsFileURL),
           let items = try? JSONDecoder().decode([WidgetRecentItem].self, from: data) {
            return items
        }
        #if targetEnvironment(simulator)
        // 2. Check universal simulator fallback
        let tempFile = URL(fileURLWithPath: "/tmp/audia_shared_widget/widget_recent_items.json")
        if let data = try? Data(contentsOf: tempFile),
           let items = try? JSONDecoder().decode([WidgetRecentItem].self, from: data) {
            return items
        }
        #endif
        // 3. Fall back to UserDefaults
        if let data = defaults.data(forKey: Self.recentsKey),
           let items = try? JSONDecoder().decode([WidgetRecentItem].self, from: data) {
            return items
        }
        return []
    }

    public func writeRecentItems(_ items: [WidgetRecentItem]) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.recentsKey)
            defaults.synchronize()
            try? data.write(to: recentItemsFileURL, options: .atomic)
            #if targetEnvironment(simulator)
            let tempFile = URL(fileURLWithPath: "/tmp/audia_shared_widget/widget_recent_items.json")
            try? data.write(to: tempFile, options: .atomic)
            #endif
        }
    }

    // MARK: - Artwork Helpers

    #if canImport(UIKit)
    @discardableResult
    public func saveArtwork(image: UIImage, for videoId: String) -> String? {
        guard !videoId.isEmpty else { return nil }
        let fileName = "\(videoId).jpg"
        let fileURL = artworkDirectory.appendingPathComponent(fileName)

        // Strict 240x240 pt at 2x scale (480x480 pixels) to stay safely under WidgetArchiver imageTooLarge limit
        let targetSize = CGSize(width: 240, height: 240)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        if let jpegData = resized.jpegData(compressionQuality: 0.85) {
            try? jpegData.write(to: fileURL, options: .atomic)
            #if targetEnvironment(simulator)
            let tempDir = URL(fileURLWithPath: "/tmp/audia_shared_widget/WidgetArtworkCache", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try? jpegData.write(to: tempDir.appendingPathComponent(fileName), options: .atomic)
            #endif
            return fileName
        }
        return nil
    }

    public func loadArtwork(fileName: String?) -> UIImage? {
        guard let fileName, !fileName.isEmpty else { return nil }
        let fileURL = artworkDirectory.appendingPathComponent(fileName)
        var sourceImage: UIImage?
        if FileManager.default.fileExists(atPath: fileURL.path) {
            sourceImage = UIImage(contentsOfFile: fileURL.path)
        }
        #if targetEnvironment(simulator)
        if sourceImage == nil {
            let tempFile = URL(fileURLWithPath: "/tmp/audia_shared_widget/WidgetArtworkCache").appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: tempFile.path) {
                sourceImage = UIImage(contentsOfFile: tempFile.path)
            }
        }
        #endif

        guard let img = sourceImage else { return nil }
        return img
    }
    #endif

    // MARK: - Darwin Notification Dispatch

    public static func postDarwinNotification(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }
}

// MARK: - ActivityKit Live Activity Attributes

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
public struct AudiaNowPlayingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var title: String
        public var artist: String
        public var duration: TimeInterval
        public var currentTime: TimeInterval
        public var isPlaying: Bool
        public var videoId: String
        public var artworkData: Data?
        public var artworkFileName: String?
        public var updatedAt: Date

        public init(
            title: String = "",
            artist: String = "",
            duration: TimeInterval = 0,
            currentTime: TimeInterval = 0,
            isPlaying: Bool = false,
            videoId: String = "",
            artworkData: Data? = nil,
            artworkFileName: String? = nil,
            updatedAt: Date = Date()
        ) {
            self.title = title
            self.artist = artist
            self.duration = duration
            self.currentTime = currentTime
            self.isPlaying = isPlaying
            self.videoId = videoId
            self.artworkData = artworkData
            self.artworkFileName = artworkFileName
            self.updatedAt = updatedAt
        }
    }

    public var videoId: String

    public init(videoId: String = "") {
        self.videoId = videoId
    }
}
#endif

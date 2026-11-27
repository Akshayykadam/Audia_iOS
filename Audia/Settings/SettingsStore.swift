//
//  SettingsStore.swift
//  Audia
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

protocol SettingsOption: CaseIterable, Hashable, Identifiable, RawRepresentable where RawValue == String {
    var displayName: String { get }
}

enum ThemeMode: String, CaseIterable, Identifiable, SettingsOption {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum PlayerBackgroundStyle: String, CaseIterable, Identifiable, SettingsOption {
    case dynamic
    case solid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dynamic: return "Album Art"
        case .solid: return "Solid"
        }
    }
}

extension AudioQuality: SettingsOption {
    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }
}

extension DownloadQuality: SettingsOption {
    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .high: return "High"
        case .standard: return "Standard"
        }
    }
}

struct AccentPreset: Identifiable, Hashable {
    let name: String
    let color: Color

    var id: String { name }

    /// The pre-baked alternate app icon matching this accent, or nil when
    /// the accent equals the default.
    var alternateIconName: String? {
        nil
    }

    static let all: [AccentPreset] = [
        AccentPreset(
            name: "White",
            color: Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .light ? UIColor(white: 0.1, alpha: 1.0) : UIColor.white
            })
        ),
        AccentPreset(name: "Audia Green", color: Color(red: 0.133, green: 0.835, blue: 0.380)),
        AccentPreset(name: "Green", color: Color(red: 0.18, green: 0.72, blue: 0.32)),
        AccentPreset(name: "Red", color: Color(red: 0.91, green: 0.22, blue: 0.22)),
        AccentPreset(name: "Blue", color: Color(red: 0, green: 0.48, blue: 1)),
        AccentPreset(name: "Orange", color: Color(red: 0.95, green: 0.45, blue: 0.13)),
        AccentPreset(name: "Amber", color: Color(red: 0.98, green: 0.70, blue: 0.15)),
        AccentPreset(name: "Teal", color: Color(red: 0.12, green: 0.65, blue: 0.60)),
        AccentPreset(name: "Cyan", color: Color(red: 0.15, green: 0.70, blue: 0.90)),
        AccentPreset(name: "Purple", color: Color(red: 0.60, green: 0.35, blue: 0.90)),
        AccentPreset(name: "Pink", color: Color(red: 0.94, green: 0.35, blue: 0.66)),
        AccentPreset(name: "Indigo", color: Color(red: 0.33, green: 0.40, blue: 0.95)),
        AccentPreset(name: "Lime", color: Color(red: 0.55, green: 0.75, blue: 0.20)),
        AccentPreset(name: "Brown", color: Color(red: 0.62, green: 0.43, blue: 0.30))
    ]
}

@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    // MARK: - Appearance

    var themeMode: ThemeMode {
        didSet { Self.defaults.set(themeMode.rawValue, forKey: Keys.themeMode) }
    }

    var accentColor: Color = AccentPreset.all[0].color

    var effectiveAccentColor: Color {
        accentColor
    }

    var accentName: String {
        didSet {
            Self.defaults.set(accentName, forKey: Keys.accentName)
            accentColor = AccentPreset.all.first { $0.name == accentName }?.color ?? AccentPreset.all[0].color
        }
    }

    var playerBackgroundStyle: PlayerBackgroundStyle {
        didSet { Self.defaults.set(playerBackgroundStyle.rawValue, forKey: Keys.playerBackgroundStyle) }
    }

    var preferredColorScheme: ColorScheme? {
        switch themeMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var defaultTab: Int {
        didSet { Self.defaults.set(defaultTab, forKey: Keys.defaultTab) }
    }

    // MARK: - Playback

    var equalizerEnabled: Bool {
        didSet { Self.defaults.set(equalizerEnabled, forKey: Keys.equalizerEnabled) }
    }

    /// The id of the selected preset, or "custom" when the user edited bands manually.
    var equalizerPresetID: String {
        didSet { Self.defaults.set(equalizerPresetID, forKey: Keys.equalizerPresetID) }
    }

    /// Current band gains in dB, one per `equalizerFrequencies`.
    var equalizerGains: [Double] {
        didSet { Self.defaults.set(equalizerGains, forKey: Keys.equalizerGains) }
    }

    /// Overall EQ preamp gain in dB (-12...+12).
    var equalizerPreampDb: Double {
        didSet { Self.defaults.set(equalizerPreampDb, forKey: Keys.equalizerPreampDb) }
    }

    /// User-saved custom presets.
    var equalizerCustomPresets: [EqualizerPreset] {
        didSet {
            if let data = try? JSONEncoder().encode(equalizerCustomPresets) {
                Self.defaults.set(data, forKey: Keys.equalizerCustomPresets)
            }
        }
    }

    /// Whether EQ automatically switches profiles per audio output route.
    var equalizerPerOutputEnabled: Bool {
        didSet { Self.defaults.set(equalizerPerOutputEnabled, forKey: Keys.equalizerPerOutputEnabled) }
    }

    /// Stored EQ profiles keyed by `AudioOutputRoute.rawValue`.
    var equalizerOutputProfiles: [String: EqualizerOutputProfile] {
        didSet {
            if let data = try? JSONEncoder().encode(equalizerOutputProfiles) {
                Self.defaults.set(data, forKey: Keys.equalizerOutputProfiles)
            }
        }
    }

    /// Spatial sound mode applied via mpv audio filters.
    var spatialAudioMode: SpatialAudioMode {
        didSet { Self.defaults.set(spatialAudioMode.rawValue, forKey: Keys.spatialAudioMode) }
    }

    var audioQuality: AudioQuality {
        didSet { Self.defaults.set(audioQuality.rawValue, forKey: Keys.audioQuality) }
    }

    var audioNormalization: Bool {
        didSet { Self.defaults.set(audioNormalization, forKey: Keys.audioNormalization) }
    }

    var gaplessPlayback: Bool {
        didSet { Self.defaults.set(gaplessPlayback, forKey: Keys.gaplessPlayback) }
    }

    var autoplaySimilar: Bool {
        didSet { Self.defaults.set(autoplaySimilar, forKey: Keys.autoplaySimilar) }
    }

    var persistQueue: Bool {
        didSet { Self.defaults.set(persistQueue, forKey: Keys.persistQueue) }
    }

    var lastRadioStyle: RadioStyle {
        didSet { Self.defaults.set(lastRadioStyle.rawValue, forKey: Keys.lastRadioStyle) }
    }

    var lastRadioLimit: Int {
        didSet { Self.defaults.set(lastRadioLimit, forKey: Keys.lastRadioLimit) }
    }

    var lastRadioAllowExplicit: Bool {
        didSet { Self.defaults.set(lastRadioAllowExplicit, forKey: Keys.lastRadioAllowExplicit) }
    }

    var playerVolume: Double {
        didSet { Self.defaults.set(playerVolume, forKey: Keys.playerVolume) }
    }

    var artworkSwipeNavigation: Bool {
        didSet { Self.defaults.set(artworkSwipeNavigation, forKey: Keys.artworkSwipeNavigation) }
    }

    // MARK: - Content

    var audioOnlyMode: Bool {
        didSet { Self.defaults.set(audioOnlyMode, forKey: Keys.audioOnlyMode) }
    }

    var hideExplicit: Bool {
        didSet { Self.defaults.set(hideExplicit, forKey: Keys.hideExplicit) }
    }

    var showQuickPicks: Bool {
        didSet { Self.defaults.set(showQuickPicks, forKey: Keys.showQuickPicks) }
    }

    var topListsLength: Int {
        didSet { Self.defaults.set(topListsLength, forKey: Keys.topListsLength) }
    }

    var contentCountry: String {
        didSet {
            Self.defaults.set(contentCountry, forKey: Keys.contentCountry)
            Task { await InnerTubeClient.audiaShared.syncAudiaLocale() }
        }
    }

    // MARK: - Privacy

    var trackSearchHistory: Bool {
        didSet { Self.defaults.set(trackSearchHistory, forKey: Keys.trackSearchHistory) }
    }

    var trackPlayHistory: Bool {
        didSet { Self.defaults.set(trackPlayHistory, forKey: Keys.trackPlayHistory) }
    }

    // MARK: - Downloads & storage

    var downloadQuality: DownloadQuality {
        didSet { Self.defaults.set(downloadQuality.rawValue, forKey: Keys.downloadQuality) }
    }

    var wifiOnlyDownloads: Bool {
        didSet { Self.defaults.set(wifiOnlyDownloads, forKey: Keys.wifiOnlyDownloads) }
    }

    var autoDownloadOnLike: Bool {
        didSet { Self.defaults.set(autoDownloadOnLike, forKey: Keys.autoDownloadOnLike) }
    }

    var autoDownloadNewEpisodes: Bool {
        didSet { Self.defaults.set(autoDownloadNewEpisodes, forKey: Keys.autoDownloadNewEpisodes) }
    }

    // MARK: - Sync

    var syncArtists: Bool {
        didSet { Self.defaults.set(syncArtists, forKey: Keys.syncArtists) }
    }

    var syncPlaylists: Bool {
        didSet { Self.defaults.set(syncPlaylists, forKey: Keys.syncPlaylists) }
    }

    var syncAlbums: Bool {
        didSet { Self.defaults.set(syncAlbums, forKey: Keys.syncAlbums) }
    }

    var syncPodcasts: Bool {
        didSet { Self.defaults.set(syncPodcasts, forKey: Keys.syncPodcasts) }
    }

    var syncSongs: Bool {
        didSet { Self.defaults.set(syncSongs, forKey: Keys.syncSongs) }
    }

    // MARK: - Spotify Integration

    var spotifyClientId: String {
        didSet { Self.defaults.set(spotifyClientId, forKey: Keys.spotifyClientId) }
    }

    var spotifyClientSecret: String {
        didSet { Self.defaults.set(spotifyClientSecret, forKey: Keys.spotifyClientSecret) }
    }

    // MARK: - Listen Together (SyncPlay)

    var syncPlayGuestName: String {
        didSet { Self.defaults.set(syncPlayGuestName, forKey: Keys.syncPlayGuestName) }
    }

    var syncPlayServerUrl: String {
        didSet { Self.defaults.set(syncPlayServerUrl, forKey: Keys.syncPlayServerUrl) }
    }

    // MARK: - Keys

    private enum Keys {
        static let themeMode = "settings.themeMode"
        static let accentName = "settings.accentName"
        static let playerBackgroundStyle = "settings.playerBackgroundStyle"
        static let defaultTab = "settings.defaultTab"
        static let equalizerEnabled = "settings.equalizerEnabled"
        static let equalizerPresetID = "settings.equalizerPresetID"
        static let equalizerGains = "settings.equalizerGains"
        static let equalizerPreampDb = "settings.equalizerPreampDb"
        static let equalizerCustomPresets = "settings.equalizerCustomPresets"
        static let equalizerPerOutputEnabled = "settings.equalizerPerOutputEnabled"
        static let equalizerOutputProfiles = "settings.equalizerOutputProfiles"
        static let spatialAudioMode = "settings.spatialAudioMode"
        static let audioQuality = "settings.audioQuality"
        static let audioNormalization = "settings.audioNormalization"
        static let gaplessPlayback = "settings.gaplessPlayback"
        static let autoplaySimilar = "settings.autoplaySimilar"
        static let persistQueue = "settings.persistQueue"
        static let lastRadioStyle = "settings.lastRadioStyle"
        static let lastRadioLimit = "settings.lastRadioLimit"
        static let lastRadioAllowExplicit = "settings.lastRadioAllowExplicit"
        static let playerVolume = "settings.playerVolume"
        static let artworkSwipeNavigation = "settings.artworkSwipeNavigation"
        static let audioOnlyMode = "settings.audioOnlyMode"
        static let hideExplicit = "settings.hideExplicit"
        static let showQuickPicks = "settings.showQuickPicks"
        static let topListsLength = "settings.topListsLength"
        static let contentCountry = "settings.contentCountry"
        static let trackSearchHistory = "settings.trackSearchHistory"
        static let trackPlayHistory = "settings.trackPlayHistory"
        static let downloadQuality = "settings.downloadQuality"
        static let wifiOnlyDownloads = "settings.wifiOnlyDownloads"
        static let autoDownloadOnLike = "settings.autoDownloadOnLike"
        static let autoDownloadNewEpisodes = "settings.autoDownloadNewEpisodes"
        static let syncArtists = "settings.syncArtists"
        static let syncPlaylists = "settings.syncPlaylists"
        static let syncAlbums = "settings.syncAlbums"
        static let syncPodcasts = "settings.syncPodcasts"
        static let syncSongs = "settings.syncSongs"
        static let spotifyClientId = "settings.spotifyClientId"
        static let spotifyClientSecret = "settings.spotifyClientSecret"
        static let syncPlayGuestName = "settings.syncPlayGuestName"
        static let syncPlayServerUrl = "settings.syncPlayServerUrl"
    }

    private static let defaults: UserDefaults = .standard

    private static func load<T>(_ key: String, default defaultValue: T) -> T {
        defaults.object(forKey: key) as? T ?? defaultValue
    }

    private static func loadString(_ key: String, default defaultValue: String) -> String {
        defaults.string(forKey: key) ?? defaultValue
    }

    private static func loadEnum<E: RawRepresentable>(_ key: String, default defaultValue: E) -> E where E.RawValue == String {
        E(rawValue: defaults.string(forKey: key) ?? "") ?? defaultValue
    }

    private init() {
        let d = Self.defaults
        themeMode = Self.loadEnum(Keys.themeMode, default: .system)
        accentColor = AccentPreset.all
            .first { $0.name == (d.string(forKey: Keys.accentName) ?? AccentPreset.all[0].name) }?
            .color ?? AccentPreset.all[0].color
        accentName = d.string(forKey: Keys.accentName) ?? AccentPreset.all[0].name
        playerBackgroundStyle = Self.loadEnum(Keys.playerBackgroundStyle, default: .dynamic)
        defaultTab = 0
        Self.defaults.set(0, forKey: Keys.defaultTab)
        equalizerEnabled = Self.load(Keys.equalizerEnabled, default: false)
        equalizerPresetID = Self.loadString(Keys.equalizerPresetID, default: "flat")
        if let saved = d.array(forKey: Keys.equalizerGains) as? [Double], saved.count == equalizerFrequencies.count {
            equalizerGains = saved
        } else {
            equalizerGains = EqualizerPresets.all.first?.gains ?? Array(repeating: 0, count: equalizerFrequencies.count)
        }
        equalizerPreampDb = Self.load(Keys.equalizerPreampDb, default: 0.0)
        if let data = d.data(forKey: Keys.equalizerCustomPresets),
           let decoded = try? JSONDecoder().decode([EqualizerPreset].self, from: data) {
            equalizerCustomPresets = decoded
        } else {
            equalizerCustomPresets = []
        }
        equalizerPerOutputEnabled = Self.load(Keys.equalizerPerOutputEnabled, default: false)
        if let data = d.data(forKey: Keys.equalizerOutputProfiles),
           let decoded = try? JSONDecoder().decode([String: EqualizerOutputProfile].self, from: data) {
            equalizerOutputProfiles = decoded
        } else {
            equalizerOutputProfiles = [:]
        }
        spatialAudioMode = Self.loadEnum(Keys.spatialAudioMode, default: .off)
        audioQuality = Self.loadEnum(Keys.audioQuality, default: .auto)
        audioNormalization = Self.load(Keys.audioNormalization, default: false)
        gaplessPlayback = Self.load(Keys.gaplessPlayback, default: true)
        autoplaySimilar = Self.load(Keys.autoplaySimilar, default: true)
        persistQueue = Self.load(Keys.persistQueue, default: false)
        lastRadioStyle = Self.loadEnum(Keys.lastRadioStyle, default: .similar)
        lastRadioLimit = Self.load(Keys.lastRadioLimit, default: 25)
        lastRadioAllowExplicit = Self.load(Keys.lastRadioAllowExplicit, default: true)
        playerVolume = Self.load(Keys.playerVolume, default: 1)
        artworkSwipeNavigation = true
        audioOnlyMode = Self.load(Keys.audioOnlyMode, default: true)
        hideExplicit = Self.load(Keys.hideExplicit, default: false)
        showQuickPicks = Self.load(Keys.showQuickPicks, default: true)
        topListsLength = Self.load(Keys.topListsLength, default: 8)
        contentCountry = Self.loadString(Keys.contentCountry, default: "US")
        trackSearchHistory = Self.load(Keys.trackSearchHistory, default: true)
        trackPlayHistory = Self.load(Keys.trackPlayHistory, default: true)
        downloadQuality = Self.loadEnum(Keys.downloadQuality, default: .auto)
        wifiOnlyDownloads = Self.load(Keys.wifiOnlyDownloads, default: false)
        autoDownloadOnLike = Self.load(Keys.autoDownloadOnLike, default: false)
        autoDownloadNewEpisodes = Self.load(Keys.autoDownloadNewEpisodes, default: false)
        syncArtists = Self.load(Keys.syncArtists, default: true)
        syncPlaylists = Self.load(Keys.syncPlaylists, default: true)
        syncAlbums = Self.load(Keys.syncAlbums, default: true)
        syncPodcasts = Self.load(Keys.syncPodcasts, default: true)
        syncSongs = Self.load(Keys.syncSongs, default: true)
        spotifyClientId = Self.loadString(Keys.spotifyClientId, default: "")
        spotifyClientSecret = Self.loadString(Keys.spotifyClientSecret, default: "")
        syncPlayGuestName = Self.loadString(Keys.syncPlayGuestName, default: "")
        syncPlayServerUrl = Self.loadString(Keys.syncPlayServerUrl, default: SyncPlayWebSocketClient.defaultServerUrl)
        applyEqualizerProfileIfNeeded(for: AudioOutputRoute.current())
    }

    // MARK: - Equalizer Helpers

    func saveCustomEqualizerPreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = "custom_\(UUID().uuidString.prefix(8))"
        let preset = EqualizerPreset(id: id, name: trimmed, gains: equalizerGains)
        equalizerCustomPresets.append(preset)
        equalizerPresetID = id
        saveCurrentEqualizerProfileIfNeeded()
    }

    func deleteCustomEqualizerPreset(id: String) {
        equalizerCustomPresets.removeAll { $0.id == id }
        if equalizerPresetID == id {
            equalizerPresetID = "custom"
        }
    }

    func saveCurrentEqualizerProfileIfNeeded(for route: AudioOutputRoute = AudioOutputRoute.current()) {
        guard equalizerPerOutputEnabled else { return }
        equalizerOutputProfiles[route.rawValue] = EqualizerOutputProfile(
            presetID: equalizerPresetID,
            gains: equalizerGains,
            preampDb: equalizerPreampDb,
            spatialMode: spatialAudioMode
        )
    }

    func applyEqualizerProfileIfNeeded(for route: AudioOutputRoute = AudioOutputRoute.current()) {
        guard equalizerPerOutputEnabled, let profile = equalizerOutputProfiles[route.rawValue] else { return }
        equalizerPresetID = profile.presetID
        if profile.gains.count == equalizerFrequencies.count {
            equalizerGains = profile.gains
        }
        equalizerPreampDb = profile.preampDb
        if let spatial = profile.spatialMode {
            spatialAudioMode = spatial
        }
    }

    func resetEqualizer() {
        equalizerGains = EqualizerPresets.all.first?.gains ?? Array(repeating: 0, count: equalizerFrequencies.count)
        equalizerPreampDb = 0
        equalizerPresetID = "flat"
        spatialAudioMode = .off
        saveCurrentEqualizerProfileIfNeeded()
    }
}

// MARK: - Environment Key

private struct SettingsStoreKey: EnvironmentKey {
    static let defaultValue: SettingsStore = .shared
}

extension EnvironmentValues {
    var settingsStore: SettingsStore {
        get { self[SettingsStoreKey.self] }
        set { self[SettingsStoreKey.self] = newValue }
    }
}

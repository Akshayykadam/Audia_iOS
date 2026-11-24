//
//  ContentSettingsView.swift
//  Audia
//

import SwiftUI

struct ContentSettingsView: View {
    @Environment(\.settingsStore) private var settings

    private static let countries = ["US", "GB", "CA", "AU", "FR", "DE", "ES", "IT", "PT", "JP", "KR", "MX", "BR", "IN"]

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                SettingsToggleRow("Audio Only Mode", icon: "waveform", isOn: $settings.audioOnlyMode)
                SettingsToggleRow("Hide Explicit Content", icon: "eye.slash", isOn: $settings.hideExplicit)
            } header: {
                Text("Content Filtering")
            } footer: {
                Text("When enabled, only YouTube Music songs are shown, and videos are filtered across search, explore, and playback.")
            }

            Section {
                SettingsToggleRow("Show Quick Picks", icon: "sparkles", isOn: $settings.showQuickPicks)
                Stepper(value: $settings.topListsLength, in: 4...20, step: 2) {
                    HStack(spacing: 0) {
                        Label("Top Lists Length", systemImage: "list.number")
                        Text(": \(settings.topListsLength)")
                    }
                }
            } header: {
                Text("Home Feed")
            }

            Section {
                Picker("Country", selection: $settings.contentCountry) {
                    ForEach(Self.countries, id: \.self) { code in
                        Text(countryName(for: code)).tag(code)
                    }
                }
            } header: {
                Text("Region")
            } footer: {
                Text("Controls the region used for YouTube Music requests.")
            }

            Section {
                SettingsToggleRow("Track Search History", icon: "magnifyingglass", isOn: $settings.trackSearchHistory)
                SettingsToggleRow("Track Play History", icon: "clock.arrow.circlepath", isOn: $settings.trackPlayHistory)
            } header: {
                Text("Privacy")
            } footer: {
                Text("When off, searches and playback are not recorded locally.")
            }

            Section {
                HStack {
                    Label("Spotify Client ID", systemImage: "key.fill")
                    Spacer()
                    TextField("Optional", text: $settings.spotifyClientId)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(AudiaTheme.textSecondary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                HStack {
                    Label("Spotify Client Secret", systemImage: "lock.fill")
                    Spacer()
                    SecureField("Optional", text: $settings.spotifyClientSecret)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(AudiaTheme.textSecondary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            } header: {
                Text("Spotify Integration")
            } footer: {
                Text("Optional: Used for large playlist imports (>100 tracks). If left empty, Audia uses the zero-config web embed import automatically.")
            }

            Section {
                SettingsToggleRow("Sync Artists", icon: "music.mic", isOn: $settings.syncArtists)
                SettingsToggleRow("Sync Playlists", icon: "music.note.list", isOn: $settings.syncPlaylists)
                SettingsToggleRow("Sync Albums", icon: "square.stack", isOn: $settings.syncAlbums)
                SettingsToggleRow("Sync Podcasts", icon: "antenna.radiowaves.left.and.right", isOn: $settings.syncPodcasts)
                SettingsToggleRow("Sync Liked Songs", icon: "heart.fill", isOn: $settings.syncSongs)
            } header: {
                Text("Library Sync")
            } footer: {
                Text("Choose which library sections sync from your YouTube Music account.")
            }
        }
        .navigationTitle("Content")
        .navigationBarTitleDisplayMode(.inline)
        .appListBottomClearance()
        .miniPlayerTracksScroll()
    }

    private func countryName(for code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}

//
//  SettingsView.swift
//  Audia
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.settingsStore) private var settings
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var storageBytes: Int64 = 0
    @State private var trackCount = 0

    private var storageLabel: String {
        ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)
    }

    private var customTopBar: some View {
        HStack(spacing: 12) {
            Button(action: {
                dismiss()
                AppRouter.shared.popActiveRoute()
            }) {
                Image(systemName: "chevron.left")
                    .font(.satoshi(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text("Settings")
                .font(.satoshi(size: 26, weight: .bold))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.satoshi(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .textCase(nil)
    }

    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(.satoshi(size: 13, weight: .regular))
            .foregroundStyle(AudiaTheme.textSecondary)
    }

    var body: some View {
        @Bindable var settings = settings

        VStack(spacing: 0) {
            customTopBar

            List {
                Section {
                    SettingsNavigationRow("Equalizer", icon: "slider.vertical.3") {
                        EqualizerView()
                    }
                } header: {
                    sectionHeader("Equalizer")
                } footer: {
                    sectionFooter("Adjust the sound with presets or a custom curve.")
                }

                Section {
                    SettingsPickerRow("Audio Quality", icon: "waveform", selection: $settings.audioQuality)
                    SettingsToggleRow("Audio Normalization", icon: "speaker.wave.2", isOn: $settings.audioNormalization)
                    SettingsToggleRow("Gapless Playback", icon: "arrow.right.arrow.left", isOn: $settings.gaplessPlayback)
                } header: {
                    sectionHeader("Audio")
                }

                Section {
                    SettingsToggleRow("Autoplay Similar", icon: "infinity", isOn: $settings.autoplaySimilar)
                    SettingsToggleRow("Persist Queue", icon: "clock.arrow.circlepath", isOn: $settings.persistQueue)
                } header: {
                    sectionHeader("Queue")
                } footer: {
                    sectionFooter("Persist Queue restores your queue, shuffle, and repeat state when the app relaunches.")
                }

                Section {
                    SettingsToggleRow("Swipe Artwork to Skip", icon: "hand.draw", isOn: $settings.artworkSwipeNavigation)
                } header: {
                    sectionHeader("Gestures")
                } footer: {
                    sectionFooter("Swipe left or right on the artwork in the full player to play the next or previous song.")
                }

                Section {
                    HStack {
                        Label("Offline Storage", systemImage: "internaldrive")
                            .font(.satoshi(size: 16, weight: .medium))
                        Spacer()
                        Text(trackCount > 0 ? "\(storageLabel) (\(trackCount))" : storageLabel)
                            .font(.satoshi(size: 15, weight: .regular))
                            .foregroundStyle(AudiaTheme.textSecondary)
                    }
                    SettingsPickerRow("Download Quality", icon: "waveform", selection: $settings.downloadQuality)
                    SettingsToggleRow("Wi-Fi Only", icon: "wifi", isOn: $settings.wifiOnlyDownloads)
                    SettingsToggleRow("Auto-Download on Like", icon: "heart.fill", isOn: $settings.autoDownloadOnLike)
                    SettingsToggleRow("Auto-Download New Episodes", icon: "antenna.radiowaves.left.and.right", isOn: $settings.autoDownloadNewEpisodes)
                } header: {
                    sectionHeader("Downloads")
                } footer: {
                    sectionFooter("Auto-download saves liked songs for offline playback. Wi-Fi Only blocks downloads on cellular data.")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .audiaScreenBackground()
        .tint(AudiaTheme.primary)
        .toolbar(.hidden, for: .navigationBar)
        .task { await refreshStats() }
        .onChange(of: downloadManager.persistedDownloadCount) { _, _ in
            Task { await refreshStats() }
        }
    }

    private func refreshStats() async {
        storageBytes = await downloadManager.totalStorageBytes()
        trackCount = downloadManager.persistedDownloadCount
    }
}

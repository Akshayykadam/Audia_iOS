//
//  SettingsView.swift
//  Audia
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.settingsStore) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var storageBytes: Int64 = 0
    @State private var trackCount = 0
    @State private var showCleanupConfirmation = false
    @State private var isCleaningUp = false

    private var storageLabel: String {
        ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)
    }

    private var customTopBar: some View {
        HStack(spacing: 10) {
            Button(action: {
                Haptics.light()
                dismiss()
                AppRouter.shared.popActiveRoute()
            }) {
                Image(systemName: "chevron.left")
                    .font(.satoshi(size: 16, weight: .semibold))
                    .foregroundStyle(AudiaTheme.textPrimary)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
                    .audiaGlassCircle()
            }
            .buttonStyle(BouncyScaleButtonStyle(scale: 0.9))
            .accessibilityLabel("Back")

            Text("Settings")
                .font(.satoshi(size: 20, weight: .bold))
                .foregroundStyle(AudiaTheme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .audiaGlassCapsule(isInteractive: false)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: AudiaTheme.background, location: 0.0),
                    .init(color: AudiaTheme.background.opacity(0.92), location: 0.48),
                    .init(color: AudiaTheme.background.opacity(0.55), location: 0.78),
                    .init(color: AudiaTheme.background.opacity(0), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 135)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.satoshi(size: 15, weight: .bold))
            .foregroundStyle(AudiaTheme.textPrimary)
            .textCase(nil)
    }

    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(.satoshi(size: 13, weight: .regular))
            .foregroundStyle(AudiaTheme.textSecondary)
    }

    var body: some View {
        @Bindable var settings = settings

        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                List {
                Section {
                    SettingsToggleRow(
                        "Dark Mode",
                        icon: "moon.fill",
                        isOn: Binding(
                            get: {
                                if settings.themeMode == .system {
                                    return colorScheme == .dark
                                }
                                return settings.themeMode == .dark
                            },
                            set: { isDark in
                                settings.themeMode = isDark ? .dark : .light
                            }
                        )
                    )
                    SettingsToggleRow(
                        "Match System",
                        icon: "circle.lefthalf.filled",
                        isOn: Binding(
                            get: { settings.themeMode == .system },
                            set: { isSystem in
                                if isSystem {
                                    settings.themeMode = .system
                                } else {
                                    settings.themeMode = colorScheme == .dark ? .dark : .light
                                }
                            }
                        )
                    )
                } header: {
                    sectionHeader("Appearance")
                } footer: {
                    sectionFooter("Switch between light and dark mode, or follow your device settings.")
                }

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
                    HStack {
                        SettingsIconLabel(title: "Offline Storage", icon: "internaldrive")
                        Spacer()
                        Text(trackCount > 0 ? "\(storageLabel) (\(trackCount))" : storageLabel)
                            .font(.satoshi(size: 15, weight: .regular))
                            .foregroundStyle(AudiaTheme.textSecondary)
                    }
                    SettingsPickerRow("Download Quality", icon: "waveform", selection: $settings.downloadQuality)
                    SettingsToggleRow("Wi-Fi Only", icon: "wifi", isOn: $settings.wifiOnlyDownloads)
                    SettingsToggleRow("Auto-Download on Like", icon: "heart.fill", isOn: $settings.autoDownloadOnLike)
                    SettingsToggleRow("Auto-Download New Episodes", icon: "antenna.radiowaves.left.and.right", isOn: $settings.autoDownloadNewEpisodes)

                    Button(action: {
                        showCleanupConfirmation = true
                    }) {
                        HStack {
                            let hasDownloads = trackCount > 0 || storageBytes > 0
                            SettingsIconLabel(
                                title: "Cleanup Downloads",
                                icon: "trash",
                                iconColor: hasDownloads ? AudiaTheme.primary : AudiaTheme.textMuted,
                                textColor: hasDownloads ? AudiaTheme.textPrimary : AudiaTheme.textMuted
                            )
                            Spacer()
                            if isCleaningUp {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(isCleaningUp || (trackCount == 0 && storageBytes == 0))
                } header: {
                    sectionHeader("Downloads")
                } footer: {
                    sectionFooter("Auto-download saves liked songs for offline playback. Wi-Fi Only blocks downloads on cellular data.")
                }
                .id("downloads")

                Section {
                    SettingsToggleRow("Share Audia Links", icon: "square.and.arrow.up", isOn: $settings.shareAudiaLink)
                    SettingsNavigationRow("Link Opening & Extensions", icon: "arrow.up.forward.app.fill") {
                        SafariExtensionGuideView()
                    }
                } header: {
                    sectionHeader("Sharing & Links")
                } footer: {
                    sectionFooter("When Share Audia Links is enabled, sharing sends Audia links that open in Audia on iOS and Android instead of YouTube Music links. Downloaded songs still share as audio files.")
                }
            }
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 56, for: .scrollContent)
            .appListBottomClearance()
            .onAppear {
                if AppRouter.shared.settingsTargetSection == "downloads" {
                    proxy.scrollTo("downloads", anchor: .top)
                    AppRouter.shared.settingsTargetSection = nil
                }
            }
        }

        customTopBar
        }
        .audiaScreenBackground()
        .tint(AudiaTheme.primary)
        .toolbar(.hidden, for: .navigationBar)
        .destructiveConfirm(
            "Cleanup Downloads?",
            isPresented: $showCleanupConfirmation,
            message: Text("This will permanently remove \(trackCount > 0 ? "\(trackCount) downloaded songs" : "offline tracks") and free up \(storageLabel) on this device."),
            confirmTitle: "Cleanup",
            onConfirm: {
                Task {
                    isCleaningUp = true
                    await downloadManager.deleteAll()
                    await refreshStats()
                    isCleaningUp = false
                }
            }
        )
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

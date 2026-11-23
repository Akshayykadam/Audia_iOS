//
//  AppearanceSettingsView.swift
//  Audia
//

import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 6)

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                SettingsPickerRow("Theme Mode", icon: "sun.max", selection: $settings.themeMode)
            } header: {
                Text("Theme")
            } footer: {
                Text("Choose how the app follows your device appearance.")
            }

            Section {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(AccentPreset.all) { preset in
                        Button {
                            applyAppIcon(for: preset)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(preset.color)
                                    .frame(width: 34, height: 34)
                                if settings.accentName == preset.name {
                                    Image(systemName: "checkmark")
                                        .font(.satoshi(size: 15, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.name)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Accent Color")
            } footer: {
                Text("Applies to buttons, highlights, and selected items.")
            }

            Section {
                SettingsPickerRow("Player Background", icon: "photo", selection: $settings.playerBackgroundStyle)
            } header: {
                Text("Player")
            }

            Section {
                Picker("Default Tab", selection: $settings.defaultTab) {
                    Text("Home").tag(0)
                    Text("Podcasts").tag(1)
                    Text("Library").tag(2)
                }
            } header: {
                Text("General")
            }
        }
        .scrollContentBackground(.hidden)
        .audiaScreenBackground()
        .id(settings.accentName)
        .tint(settings.accentColor)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }

    /// Applies the selected accent and selects its bundled alternate app icon.
    private func applyAppIcon(for preset: AccentPreset) {
        settings.accentName = preset.name

        guard UIApplication.shared.supportsAlternateIcons else { return }
        let target = preset.alternateIconName
        guard UIApplication.shared.alternateIconName != target else { return }

        UIApplication.shared.setAlternateIconName(target) { error in
            if let error {
                Log.settings.error("Failed to set alternate icon '\(target ?? "nil")': \(error)")
            }
        }
    }
}

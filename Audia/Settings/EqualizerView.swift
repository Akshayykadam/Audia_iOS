//
//  EqualizerView.swift
//  Audia
//
//  Created by Audia.
//

import AVFAudio
import SwiftUI

/// A 10-band interactive equalizer with smooth spline curve, live dB tooltip,
/// dropdown preset picker (built-in + custom saved presets), preamp slider,
/// and per-output route profiles.
struct EqualizerView: View {
    var isSheet: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.settingsStore) private var settings
    @State private var dragIndex: Int?
    @State private var showSavePresetPrompt = false
    @State private var newPresetName = ""
    @State private var currentRoute: AudioOutputRoute = AudioOutputRoute.current()

    private var effectiveAccent: Color {
        settings.accentName == AccentPreset.all.first?.name ? AudiaTheme.primary : settings.accentColor
    }

    private var isFlat: Bool {
        settings.equalizerPresetID == "flat"
            && abs(settings.equalizerPreampDb) < 0.05
            && settings.spatialAudioMode == .off
            && settings.equalizerGains.allSatisfy { abs($0) < 0.05 }
    }

    private var currentPresetTitle: String {
        if let builtIn = EqualizerPresets.all.first(where: { $0.id == settings.equalizerPresetID }) {
            return builtIn.name
        }
        if let custom = settings.equalizerCustomPresets.first(where: { $0.id == settings.equalizerPresetID }) {
            return custom.name
        }
        return "Custom"
    }

    private var selectedCustomPreset: EqualizerPreset? {
        settings.equalizerCustomPresets.first(where: { $0.id == settings.equalizerPresetID })
    }

    private var customTopBar: some View {
        HStack(spacing: 10) {
            Button(action: {
                Haptics.light()
                dismiss()
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

            Text("Equalizer")
                .font(.satoshi(size: 20, weight: .bold))
                .foregroundStyle(AudiaTheme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .audiaGlassCapsule(isInteractive: false)

            Spacer()

            Button {
                Haptics.light()
                settings.resetEqualizer()
                PlayerController.shared.applyPlaybackSettings()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.satoshi(size: 15, weight: .semibold))
                    .foregroundStyle(isFlat ? AudiaTheme.textMuted : AudiaTheme.textPrimary)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
                    .audiaGlassCircle()
            }
            .buttonStyle(BouncyScaleButtonStyle(scale: 0.9))
            .disabled(isFlat)
            .accessibilityLabel("Reset Equalizer")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(alignment: .top) {
            if !isSheet {
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
    }

    var body: some View {
        @Bindable var settings = settings

        ZStack(alignment: .top) {
            if isSheet {
                ScrollView {
                    VStack(spacing: 12) {
                        presetDropdownRow(settings: settings)
                            .padding(.horizontal, 16)

                        equalizerCard(settings: settings)
                            .padding(.horizontal, 16)

                        controlsCard(settings: settings)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                .contentMargins(.top, 56, for: .scrollContent)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        presetDropdownRow(settings: settings)
                            .padding(.horizontal, 16)

                        equalizerCard(settings: settings)
                            .padding(.horizontal, 16)

                        controlsCard(settings: settings)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 6)
                    .appBottomClearance()
                }
                .contentMargins(.top, 56, for: .scrollContent)
            }

            customTopBar
        }
        .background {
            if !isSheet {
                AudiaTheme.background.ignoresSafeArea()
            } else {
                Color.clear
            }
        }
        .containerBackground(.clear, for: .navigation)
        .toolbar(.hidden, for: .navigationBar)
        .textPrompt(
            "Save Custom Preset",
            isPresented: $showSavePresetPrompt,
            placeholder: "Preset name (e.g. AirPods)",
            text: $newPresetName,
            okTitle: "Save"
        ) {
            settings.saveCustomEqualizerPreset(name: newPresetName)
            newPresetName = ""
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            currentRoute = AudioOutputRoute.current()
        }
    }

    // MARK: - Dropdown Preset Picker

    private func presetDropdownRow(settings: SettingsStore) -> some View {
        HStack(spacing: 10) {
            Menu {
                Section("Built-in") {
                    ForEach(EqualizerPresets.all, id: \.id) { preset in
                        Button {
                            selectPreset(preset)
                        } label: {
                            if settings.equalizerPresetID == preset.id {
                                Label(LocalizedStringKey(preset.name), systemImage: "checkmark")
                            } else {
                                Text(LocalizedStringKey(preset.name))
                            }
                        }
                    }
                }

                if !settings.equalizerCustomPresets.isEmpty {
                    Section("Custom") {
                        ForEach(settings.equalizerCustomPresets, id: \.id) { preset in
                            Button {
                                selectPreset(preset)
                            } label: {
                                if settings.equalizerPresetID == preset.id {
                                    Label(preset.name, systemImage: "checkmark")
                                } else {
                                    Text(preset.name)
                                }
                            }
                        }
                    }
                }

                Divider()

                Button {
                    Haptics.light()
                    newPresetName = ""
                    showSavePresetPrompt = true
                } label: {
                    Label("Save Current Curve…", systemImage: "plus.circle")
                }

                if let custom = selectedCustomPreset {
                    Button(role: .destructive) {
                        Haptics.light()
                        settings.deleteCustomEqualizerPreset(id: custom.id)
                    } label: {
                        Label("Delete \"\(custom.name)\"", systemImage: "trash")
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.satoshi(size: 14, weight: .semibold))
                        .foregroundStyle(effectiveAccent)
                    Text(LocalizedStringKey(currentPresetTitle))
                        .font(.satoshi(size: 15, weight: .semibold))
                        .foregroundStyle(AudiaTheme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AudiaTheme.textSecondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .contentShape(Capsule())
                .audiaGlassCapsule()
            }

            if settings.equalizerPresetID == "custom" {
                Button {
                    Haptics.light()
                    newPresetName = ""
                    showSavePresetPrompt = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.satoshi(size: 13, weight: .bold))
                        Text("Save")
                            .font(.satoshi(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(AudiaTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .contentShape(Capsule())
                    .audiaGlassCapsule()
                }
                .buttonStyle(BouncyScaleButtonStyle(scale: 0.94))
            } else if let custom = selectedCustomPreset {
                Button {
                    Haptics.light()
                    settings.deleteCustomEqualizerPreset(id: custom.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.satoshi(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 42, height: 42)
                        .contentShape(Circle())
                        .audiaGlassCircle()
                }
                .buttonStyle(BouncyScaleButtonStyle(scale: 0.9))
                .accessibilityLabel("Delete custom preset")
            }
        }
    }

    private func selectPreset(_ preset: EqualizerPreset) {
        Haptics.selection()
        settings.equalizerGains = preset.gains
        settings.equalizerPresetID = preset.id
        if !settings.equalizerEnabled && preset.id != "flat" {
            settings.equalizerEnabled = true
        }
        settings.saveCurrentEqualizerProfileIfNeeded()
        PlayerController.shared.applyPlaybackSettings()
    }

    // MARK: - Graph Card

    private func equalizerCard(settings: SettingsStore) -> some View {
        @Bindable var settings = settings
        return VStack(spacing: isSheet ? 8 : 12) {
            HStack {
                Text(LocalizedStringKey(settings.equalizerEnabled ? "Equalizer On" : "Equalizer Off"))
                    .font(.satoshi(.subheadline, weight: .semibold))
                    .foregroundStyle(AudiaTheme.textPrimary)
                Spacer()
                Toggle("", isOn: $settings.equalizerEnabled)
                    .labelsHidden()
                    .toggleStyle(.amoled)
            }

            EqualizerGraph(
                gains: $settings.equalizerGains,
                accentColor: effectiveAccent,
                isEnabled: settings.equalizerEnabled,
                activeDrag: $dragIndex
            )
            .frame(height: isSheet ? 160 : 250)
            .opacity(settings.equalizerEnabled ? 1.0 : 0.42)
            .animation(.easeInOut(duration: 0.2), value: settings.equalizerEnabled)

            // Frequency labels aligned with the 10 bands
            HStack(spacing: 0) {
                ForEach(Array(equalizerFrequencyLabels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.satoshi(size: 10, weight: dragIndex == index ? .bold : .medium))
                        .foregroundStyle(dragIndex == index ? effectiveAccent : AudiaTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)

            HStack {
                Text("\(Int(equalizerMinGain)) dB")
                Spacer()
                Text("0 dB")
                Spacer()
                Text("+\(Int(equalizerMaxGain)) dB")
            }
            .font(.satoshi(.caption2))
            .foregroundStyle(AudiaTheme.textMuted)
        }
        .padding(isSheet ? 10 : 16)
        .background {
            if !isSheet {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.clear)
                    .audiaGlassCard(cornerRadius: 18)
            }
        }
        .onChange(of: settings.equalizerEnabled) { _, _ in
            Haptics.light()
            PlayerController.shared.applyPlaybackSettings()
        }
    }

    // MARK: - Boost & Device Profile Controls

    private func bassBinding(settings: SettingsStore) -> Binding<Double> {
        Binding(
            get: {
                guard settings.equalizerGains.indices.contains(0) else { return 0 }
                return settings.equalizerGains[0]
            },
            set: { newValue in
                var gains = settings.equalizerGains
                guard gains.count >= 4 else { return }
                let clamped = min(equalizerMaxGain, max(equalizerMinGain, newValue)).rounded()
                guard gains[0] != clamped else { return }
                if clamped == 0 {
                    Haptics.light()
                } else {
                    Haptics.selection()
                }
                gains[0] = clamped
                gains[1] = (clamped * 0.85).rounded()
                gains[2] = (clamped * 0.55).rounded()
                gains[3] = (clamped * 0.25).rounded()
                applyMacroBands(gains, settings: settings)
            }
        )
    }

    private func trebleBinding(settings: SettingsStore) -> Binding<Double> {
        Binding(
            get: {
                guard settings.equalizerGains.indices.contains(9) else { return 0 }
                return settings.equalizerGains[9]
            },
            set: { newValue in
                var gains = settings.equalizerGains
                guard gains.count >= 10 else { return }
                let clamped = min(equalizerMaxGain, max(equalizerMinGain, newValue)).rounded()
                guard gains[9] != clamped else { return }
                if clamped == 0 {
                    Haptics.light()
                } else {
                    Haptics.selection()
                }
                gains[6] = (clamped * 0.35).rounded()
                gains[7] = (clamped * 0.65).rounded()
                gains[8] = (clamped * 0.85).rounded()
                gains[9] = clamped
                applyMacroBands(gains, settings: settings)
            }
        )
    }

    private func applyMacroBands(_ gains: [Double], settings: SettingsStore) {
        settings.equalizerGains = gains
        if !settings.equalizerEnabled {
            settings.equalizerEnabled = true
        }
        settings.equalizerPresetID = "custom"
        settings.saveCurrentEqualizerProfileIfNeeded()
        PlayerController.shared.applyPlaybackSettings()
    }

    private func macroSlider(
        title: String,
        value: Binding<Double>,
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.satoshi(size: 15, weight: .semibold))
                    .foregroundStyle(AudiaTheme.textPrimary)
                Spacer()
                let rounded = value.wrappedValue
                let text = abs(rounded) < 0.25 ? "0 dB" : String(format: "%+.0f dB", rounded)
                Text(text)
                    .font(.satoshi(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(abs(rounded) >= 0.25 ? accentColor : AudiaTheme.textSecondary)
            }

            Slider(value: value, in: -12...12, step: 1)
                .tint(accentColor)

            SliderStepMarks(accentColor: accentColor, currentValue: value.wrappedValue)
        }
    }

    private func controlsCard(settings: SettingsStore) -> some View {
        @Bindable var settings = settings
        return VStack(spacing: isSheet ? 12 : 16) {
            // Tone & Boost sliders card
            VStack(spacing: 16) {
                macroSlider(
                    title: "Bass",
                    value: bassBinding(settings: settings),
                    accentColor: effectiveAccent
                )

                macroSlider(
                    title: "Treble",
                    value: trebleBinding(settings: settings),
                    accentColor: effectiveAccent
                )
            }
            .padding(isSheet ? 12 : 16)
            .background {
                if !isSheet {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.clear)
                        .audiaGlassCard(cornerRadius: 18)
                }
            }

            // Volume Boost (preamp) pill + external footer
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Volume Boost")
                            .font(.satoshi(size: 15, weight: .semibold))
                            .foregroundStyle(AudiaTheme.textPrimary)
                        Spacer()
                        let preampText = abs(settings.equalizerPreampDb) < 0.05
                            ? "0 dB"
                            : String(format: "%+.1f dB", settings.equalizerPreampDb)
                        Text(preampText)
                            .font(.satoshi(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(abs(settings.equalizerPreampDb) > 0.05 ? effectiveAccent : AudiaTheme.textSecondary)
                    }

                    Slider(
                        value: $settings.equalizerPreampDb,
                        in: -12...12,
                        step: 0.5
                    )
                    .tint(effectiveAccent)
                    .onChange(of: settings.equalizerPreampDb) { _, newVal in
                        if abs(newVal) < 0.05 {
                            Haptics.light()
                        } else {
                            Haptics.selection()
                        }
                        if !settings.equalizerEnabled && abs(newVal) > 0.05 {
                            settings.equalizerEnabled = true
                        }
                        settings.saveCurrentEqualizerProfileIfNeeded()
                        PlayerController.shared.applyPlaybackSettings()
                    }

                    SliderStepMarks(accentColor: effectiveAccent, currentValue: settings.equalizerPreampDb)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background {
                    if !isSheet {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.clear)
                            .audiaGlassCard(cornerRadius: 22)
                    }
                }

                Text("Adjust overall loudness or reduce clipping when boosting bass.")
                    .font(.satoshi(size: 13, weight: .regular))
                    .foregroundStyle(AudiaTheme.textSecondary)
                    .padding(.horizontal, 14)
            }

            // Spatial Sound pill (dropdown) + external footer
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Spatial Sound")
                        .font(.satoshi(size: 15, weight: .semibold))
                        .foregroundStyle(AudiaTheme.textPrimary)

                    Spacer()

                    Menu {
                        ForEach(SpatialAudioMode.allCases) { mode in
                            Button {
                                Haptics.selection()
                                settings.spatialAudioMode = mode
                                settings.saveCurrentEqualizerProfileIfNeeded()
                                PlayerController.shared.applyPlaybackSettings()
                            } label: {
                                if settings.spatialAudioMode == mode {
                                    Label(mode.displayName, systemImage: "checkmark")
                                } else {
                                    Text(mode.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(settings.spatialAudioMode.displayName)
                                .font(.satoshi(size: 14, weight: .semibold))
                                .foregroundStyle(settings.spatialAudioMode == .off ? AudiaTheme.textSecondary : effectiveAccent)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AudiaTheme.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Capsule())
                        .audiaGlassCapsule()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    if !isSheet {
                        Capsule()
                            .fill(Color.clear)
                            .audiaGlassCapsule(isInteractive: false)
                    }
                }

                Text("Widens stereo and adds room depth for a 3D surround feel.")
                    .font(.satoshi(size: 13, weight: .regular))
                    .foregroundStyle(AudiaTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
            }

            // Auto-Switch by Device pill + external footer
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Auto-Switch by Device")
                        .font(.satoshi(size: 15, weight: .semibold))
                        .foregroundStyle(AudiaTheme.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Toggle("", isOn: $settings.equalizerPerOutputEnabled)
                        .labelsHidden()
                        .toggleStyle(.amoled)
                        .onChange(of: settings.equalizerPerOutputEnabled) { _, enabled in
                            Haptics.light()
                            if enabled {
                                settings.saveCurrentEqualizerProfileIfNeeded(for: currentRoute)
                            }
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    if !isSheet {
                        Capsule()
                            .fill(Color.clear)
                            .audiaGlassCapsule(isInteractive: false)
                    }
                }

                Text("Remember a separate sound for Bluetooth, headphones, and speaker.")
                    .font(.satoshi(size: 13, weight: .regular))
                    .foregroundStyle(AudiaTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
            }
        }
    }
}

/// Smooth spline interactive band graph with live floating dB tooltip and 0 dB snap haptic.
private struct EqualizerGraph: View {
    @Binding var gains: [Double]
    let accentColor: Color
    let isEnabled: Bool
    @Binding var activeDrag: Int?

    private let horizontalInset: CGFloat = 14
    private let verticalInset: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let drawWidth = size.width - horizontalInset * 2
            let drawHeight = size.height - verticalInset * 2
            let points = gains.enumerated().map { index, gain -> CGPoint in
                let x = horizontalInset + drawWidth * CGFloat(index) / CGFloat(max(1, gains.count - 1))
                let normalized = (gain - equalizerMinGain) / (equalizerMaxGain - equalizerMinGain)
                let y = verticalInset + drawHeight * CGFloat(1 - normalized)
                return CGPoint(x: x, y: y)
            }

            ZStack {
                graphGrid(size: size)

                if points.count >= 2 {
                    let minY = verticalInset
                    let maxY = verticalInset + drawHeight
                    fillPath(points, minY: minY, maxY: maxY)
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.24), accentColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    splinePath(points, minY: minY, maxY: maxY)
                        .stroke(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.65)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            style: StrokeStyle(lineWidth: 2.75, lineCap: .round, lineJoin: .round)
                        )
                }

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    let isActive = activeDrag == index
                    Circle()
                        .fill(.white)
                        .frame(width: isActive ? 18 : 14, height: isActive ? 18 : 14)
                        .overlay(Circle().stroke(accentColor, lineWidth: isActive ? 3 : 2))
                        .shadow(color: .black.opacity(0.28), radius: isActive ? 4 : 2, y: 1)
                        .position(point)
                        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isActive)
                }

                // Live floating dB + Hz tooltip while dragging
                if let dragIdx = activeDrag,
                   points.indices.contains(dragIdx),
                   gains.indices.contains(dragIdx),
                   equalizerFrequencyLabels.indices.contains(dragIdx) {
                    let pt = points[dragIdx]
                    let g = Int(gains[dragIdx].rounded())
                    let freq = equalizerFrequencyLabels[dragIdx]
                    let clampedX = min(max(pt.x, 48), size.width - 48)
                    let tooltipY = pt.y > 46 ? pt.y - 28 : pt.y + 28

                    Text("\(g >= 0 ? "+" : "")\(g) dB · \(freq) Hz")
                        .font(.satoshi(size: 11, weight: .bold))
                        .foregroundStyle(AudiaTheme.textPrimary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .audiaGlassCapsule(isInteractive: false)
                        .position(x: clampedX, y: tooltipY)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let index = bandIndex(for: value.location, size: size)
                        let gain = gain(for: value.location, size: size)
                        activeDrag = index
                        setGain(gain, at: index)
                    }
                    .onEnded { _ in
                        activeDrag = nil
                    }
            )
        }
    }

    // MARK: - Drawing helpers

    private func graphGrid(size: CGSize) -> some View {
        Canvas { context, _ in
            let drawWidth = size.width - horizontalInset * 2
            let drawHeight = size.height - verticalInset * 2
            var path = Path()
            path.move(to: CGPoint(x: horizontalInset, y: verticalInset))
            path.addLine(to: CGPoint(x: horizontalInset + drawWidth, y: verticalInset))
            path.addLine(to: CGPoint(x: horizontalInset + drawWidth, y: verticalInset + drawHeight))
            path.addLine(to: CGPoint(x: horizontalInset, y: verticalInset + drawHeight))
            path.closeSubpath()
            context.stroke(path, with: .color(.secondary.opacity(0.15)), lineWidth: 1)

            // Vertical band guide lines
            for i in 0..<max(1, gains.count) {
                let x = horizontalInset + drawWidth * CGFloat(i) / CGFloat(max(1, gains.count - 1))
                var v = Path()
                v.move(to: CGPoint(x: x, y: verticalInset))
                v.addLine(to: CGPoint(x: x, y: verticalInset + drawHeight))
                context.stroke(v, with: .color(.secondary.opacity(0.08)), lineWidth: 1)
            }
        }
        .overlay {
            GeometryReader { geo in
                let drawWidth = geo.size.width - horizontalInset * 2
                let drawHeight = geo.size.height - verticalInset * 2
                let zeroY = verticalInset + drawHeight * (1 - (0 - equalizerMinGain) / (equalizerMaxGain - equalizerMinGain))
                Path { p in
                    p.move(to: CGPoint(x: horizontalInset, y: zeroY))
                    p.addLine(to: CGPoint(x: horizontalInset + drawWidth, y: zeroY))
                }
                .stroke(.secondary.opacity(0.32), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
    }

    /// Catmull-Rom smooth cubic spline through all band control points, clamped inside the graph bounds.
    private func splinePath(_ points: [CGPoint], minY: CGFloat, maxY: CGFloat) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }
        path.move(to: points[0])

        for i in 0..<(points.count - 1) {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : points[i + 1]

            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6.0,
                y: min(maxY, max(minY, p1.y + (p2.y - p0.y) / 6.0))
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6.0,
                y: min(maxY, max(minY, p2.y - (p3.y - p1.y) / 6.0))
            )
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        return path
    }

    private func fillPath(_ points: [CGPoint], minY: CGFloat, maxY: CGFloat) -> Path {
        var path = splinePath(points, minY: minY, maxY: maxY)
        if let last = points.last, let first = points.first {
            path.addLine(to: CGPoint(x: last.x, y: maxY))
            path.addLine(to: CGPoint(x: first.x, y: maxY))
            path.closeSubpath()
        }
        return path
    }

    // MARK: - Hit testing

    private func bandIndex(for location: CGPoint, size: CGSize) -> Int {
        let drawWidth = size.width - horizontalInset * 2
        let x = max(0, min(1, (location.x - horizontalInset) / drawWidth))
        let raw = x * CGFloat(gains.count - 1)
        return min(max(0, Int(raw.rounded())), gains.count - 1)
    }

    private func gain(for location: CGPoint, size: CGSize) -> Double {
        let drawHeight = size.height - verticalInset * 2
        let y = max(0, min(1, (location.y - verticalInset) / drawHeight))
        let gain = equalizerMinGain + (1 - Double(y)) * (equalizerMaxGain - equalizerMinGain)
        return min(equalizerMaxGain, max(equalizerMinGain, gain.rounded()))
    }

    private func setGain(_ gain: Double, at index: Int) {
        guard gains.indices.contains(index), gains[index] != gain else { return }
        if gain == 0 {
            Haptics.light()
        } else {
            Haptics.selection()
        }
        gains[index] = gain
        let settings = SettingsStore.shared
        if !settings.equalizerEnabled {
            settings.equalizerEnabled = true
        }
        settings.equalizerPresetID = "custom"
        settings.saveCurrentEqualizerProfileIfNeeded()
        PlayerController.shared.applyPlaybackSettings()
    }
}

/// Subtle step tick marks and dB scale labels aligned to ±12 dB sliders.
private struct SliderStepMarks: View {
    let accentColor: Color
    let currentValue: Double

    private let steps = [-12, -9, -6, -3, 0, 3, 6, 9, 12]

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 0) {
                ForEach(steps, id: \.self) { step in
                    let isMajor = step % 6 == 0
                    let isZero = step == 0
                    let isReached = (currentValue > 0 && step >= 0 && Double(step) <= currentValue)
                        || (currentValue < 0 && step <= 0 && Double(step) >= currentValue)
                    Rectangle()
                        .fill(isZero ? accentColor.opacity(0.65) : (isReached ? accentColor.opacity(0.55) : AudiaTheme.textMuted.opacity(isMajor ? 0.55 : 0.3)))
                        .frame(width: isZero ? 1.5 : 1, height: isZero ? 7 : (isMajor ? 5 : 3))
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 0) {
                ForEach(steps, id: \.self) { step in
                    if step % 6 == 0 {
                        Text(step > 0 ? "+\(step)" : "\(step)")
                            .font(.satoshi(size: 9.5, weight: step == 0 ? .semibold : .regular))
                            .foregroundStyle(AudiaTheme.textMuted)
                            .frame(maxWidth: .infinity)
                    } else {
                        Spacer()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .allowsHitTesting(false)
    }
}

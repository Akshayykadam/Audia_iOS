//
//  NowPlayingWidget.swift
//  AudiaWidgets
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let state: WidgetPlaybackState
    let artwork: UIImage?
}

// MARK: - Timeline Provider

struct NowPlayingTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), state: .placeholder, artwork: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        let state = WidgetDataStore.shared.readPlaybackState()
        let artwork = WidgetDataStore.shared.loadArtwork(fileName: state.artworkFileName)
        completion(NowPlayingEntry(date: Date(), state: state, artwork: artwork))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let state = WidgetDataStore.shared.readPlaybackState()
        let artwork = WidgetDataStore.shared.loadArtwork(fileName: state.artworkFileName)
        let entry = NowPlayingEntry(date: Date(), state: state, artwork: artwork)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// MARK: - Main Widget View

struct NowPlayingWidgetView: View {
    let entry: NowPlayingEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                NowPlayingSmallView(entry: entry, colorScheme: colorScheme, renderingMode: renderingMode)
            case .systemMedium:
                NowPlayingMediumView(entry: entry, colorScheme: colorScheme, renderingMode: renderingMode)
            case .accessoryInline:
                NowPlayingInlineView(entry: entry)
            case .accessoryCircular:
                NowPlayingCircularView(entry: entry)
            case .accessoryRectangular:
                NowPlayingRectangularView(entry: entry)
            default:
                NowPlayingMediumView(entry: entry, colorScheme: colorScheme, renderingMode: renderingMode)
            }
        }
        .widgetURL(URL(string: "audia://player"))
        .containerBackground(for: .widget) {
            AudiaWidgetTheme.backgroundColor(for: colorScheme)
        }
    }
}

// MARK: - Small Widget (Apple Music Hero Square)

private struct NowPlayingSmallView: View {
    let entry: NowPlayingEntry
    let colorScheme: ColorScheme
    let renderingMode: WidgetRenderingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Strictly 1:1 Square Album Artwork (Preserved Full Color in Accented/Liquid Glass)
            ZStack {
                if let artwork = entry.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .widgetAccentedRenderingMode(.fullColor)
                        .aspectRatio(contentMode: .fill)
                } else {
                    AudiaWidgetTheme.placeholderGradient(for: colorScheme)
                    Image(systemName: "music.note")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(AudiaWidgetTheme.secondaryTextColor(for: colorScheme))
                        .unredacted()
                }
            }
            .aspectRatio(1.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AudiaWidgetTheme.artworkBorder(for: colorScheme), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 6, x: 0, y: 2)
            .unredacted()

            Spacer(minLength: 2)

            // Metadata and Tactile Play Button Row
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.state.title.isEmpty ? "Not Playing" : entry.state.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AudiaWidgetTheme.primaryTextColor(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text(entry.state.artist.isEmpty ? "Audia" : entry.state.artist)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AudiaWidgetTheme.secondaryTextColor(for: colorScheme))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if #available(iOS 17.0, *) {
                    Button(intent: TogglePlayPauseIntent()) {
                        ZStack {
                            Circle()
                                .fill(
                                    renderingMode == .accented
                                        ? Color.white.opacity(0.18)
                                        : AudiaWidgetTheme.controlFillColor(for: colorScheme)
                                )
                                .frame(width: 28, height: 28)
                                .shadow(color: renderingMode == .accented ? Color.clear : Color.black.opacity(colorScheme == .dark ? 0.45 : 0.16), radius: 3, x: 0, y: 1.5)
                            Image(systemName: entry.state.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(
                                    renderingMode == .accented
                                        ? Color.white
                                        : AudiaWidgetTheme.controlIconColor(for: colorScheme)
                                )
                                .offset(x: entry.state.isPlaying ? 0 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .unredacted()
                }
            }
            .padding(.horizontal, 2)
            .unredacted()
        }
    }
}

// MARK: - Medium Widget (Apple Music Split View)

private struct NowPlayingMediumView: View {
    let entry: NowPlayingEntry
    let colorScheme: ColorScheme
    let renderingMode: WidgetRenderingMode

    var body: some View {
        HStack(spacing: 16) {
            // Large 126x126 Album Artwork (Preserved Full Color in Accented/Liquid Glass)
            ZStack {
                if let artwork = entry.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .widgetAccentedRenderingMode(.fullColor)
                        .aspectRatio(contentMode: .fill)
                } else {
                    AudiaWidgetTheme.placeholderGradient(for: colorScheme)
                    Image(systemName: "music.note")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(AudiaWidgetTheme.secondaryTextColor(for: colorScheme))
                        .unredacted()
                }
            }
            .frame(width: 126, height: 126)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AudiaWidgetTheme.artworkBorder(for: colorScheme), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.40 : 0.12), radius: 8, x: 0, y: 3)
            .unredacted()

            // Track Details, Scrubber & Controls
            VStack(alignment: .leading, spacing: 0) {
                // Title
                Text(entry.state.title.isEmpty ? "Not Playing" : entry.state.title)
                    .font(.system(size: 16.5, weight: .bold, design: .rounded))
                    .foregroundStyle(AudiaWidgetTheme.primaryTextColor(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                // Artist
                Text(entry.state.artist.isEmpty ? "Tap to open Audia" : entry.state.artist)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AudiaWidgetTheme.secondaryTextColor(for: colorScheme))
                    .lineLimit(1)
                    .padding(.top, 2)

                Spacer(minLength: 8)

                // Apple-Style Capsule Scrubber Bar (Always Visible)
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(AudiaWidgetTheme.progressTrackColor(for: colorScheme))
                                .frame(height: 3.5)
                            Capsule()
                                .fill(AudiaWidgetTheme.primaryTextColor(for: colorScheme))
                                .frame(width: max(0, geo.size.width * entry.state.progress), height: 3.5)
                                .widgetAccentable()
                        }
                    }
                    .frame(height: 3.5)

                    HStack {
                        Text(formatTime(entry.state.currentTime))
                        Spacer()
                        Text(entry.state.duration > 0 ? "-\(formatTime(entry.state.remainingTime))" : "--:--")
                    }
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AudiaWidgetTheme.secondaryTextColor(for: colorScheme))
                }
                .unredacted()

                Spacer(minLength: 8)

                // Interactive Media Controls - Perfectly Centered & Balanced Under Scrubber
                if #available(iOS 17.0, *) {
                    HStack(alignment: .center) {
                        Spacer()

                        Button(intent: SkipPreviousIntent()) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AudiaWidgetTheme.primaryTextColor(for: colorScheme))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(intent: TogglePlayPauseIntent()) {
                            ZStack {
                                Circle()
                                    .fill(
                                        renderingMode == .accented
                                            ? Color.white.opacity(0.20)
                                            : AudiaWidgetTheme.controlFillColor(for: colorScheme)
                                    )
                                    .frame(width: 40, height: 40)
                                    .shadow(color: renderingMode == .accented ? Color.clear : Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 4, x: 0, y: 2)
                                Image(systemName: entry.state.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(
                                        renderingMode == .accented
                                            ? Color.white
                                            : AudiaWidgetTheme.controlIconColor(for: colorScheme)
                                    )
                                    .offset(x: entry.state.isPlaying ? 0 : 1.5)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(intent: SkipNextIntent()) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AudiaWidgetTheme.primaryTextColor(for: colorScheme))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .unredacted()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 126, alignment: .leading)
            .padding(.vertical, 2)
            .unredacted()
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let s = Int(time)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

// MARK: - Lock Screen Accessories

private struct NowPlayingInlineView: View {
    let entry: NowPlayingEntry

    var body: some View {
        Label(
            entry.state.title.isEmpty ? "Audia" : "\(entry.state.title) • \(entry.state.artist)",
            systemImage: entry.state.isPlaying ? "speaker.wave.2.fill" : "music.note"
        )
    }
}

private struct NowPlayingCircularView: View {
    let entry: NowPlayingEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Gauge(value: entry.state.progress) {
                Image(systemName: entry.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        }
    }
}

private struct NowPlayingRectangularView: View {
    let entry: NowPlayingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .semibold))
                Text(entry.state.title.isEmpty ? "Audia" : entry.state.title)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
            }
            Text(entry.state.artist.isEmpty ? "Not Playing" : entry.state.artist)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if entry.state.duration > 0 {
                ProgressView(value: entry.state.progress)
                    .progressViewStyle(.linear)
                    .tint(.primary)
            }
        }
    }
}

// MARK: - Widget Configuration

public struct AudiaNowPlayingWidget: Widget {
    public static let kind = "AudiaNowPlayingWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NowPlayingTimelineProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("View and interactively control what is currently playing.")
        .containerBackgroundRemovable(false)
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

// MARK: - Live Activity & Dynamic Island Widget

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
public struct AudiaNowPlayingLiveActivity: Widget {
    public static let kind = "AudiaNowPlayingLiveActivity"

    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: AudiaNowPlayingAttributes.self) { context in
            // Lock Screen / Notification Banner presentation
            NowPlayingLiveActivityLockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Leading: Album Artwork (52x52 with 12pt corner radius)
                DynamicIslandExpandedRegion(.leading) {
                    NowPlayingLiveActivityArtworkView(
                        data: context.state.artworkData,
                        fileName: context.state.artworkFileName,
                        size: 52
                    )
                    .padding(.leading, 2)
                }

                // Expanded Trailing: Waveform / Visualizer
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.trailing, 4)
                        .frame(maxHeight: 52, alignment: .center)
                }

                // Expanded Center: Title & Artist
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title.isEmpty ? "Unknown Title" : context.state.title)
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text(context.state.artist.isEmpty ? "Audia" : context.state.artist)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: 52, alignment: .center)
                    .padding(.leading, 6)
                    .padding(.trailing, 4)
                }

                // Expanded Bottom: Single-row Scrubber Bar & Transport Controls
                DynamicIslandExpandedRegion(.bottom) {
                    NowPlayingLiveActivityControlsView(state: context.state)
                        .padding(.top, 4)
                        .padding(.bottom, 6)
                }
            } compactLeading: {
                NowPlayingLiveActivityArtworkView(
                    data: context.state.artworkData,
                    fileName: context.state.artworkFileName,
                    size: 22
                )
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.trailing, 2)
            } minimal: {
                NowPlayingLiveActivityArtworkView(
                    data: context.state.artworkData,
                    fileName: context.state.artworkFileName,
                    size: 18
                )
                .clipShape(Circle())
            }
            .widgetURL(URL(string: "audia://player"))
            .keylineTint(Color.white)
        }
    }
}

// MARK: - Live Activity Expanded Controls View

@available(iOS 16.1, *)
struct NowPlayingLiveActivityControlsView: View {
    let state: AudiaNowPlayingAttributes.ContentState

    var body: some View {
        VStack(spacing: 8) {
            // Row 1: Single-row Apple-style scrubber bar (time on left, slider in middle, time on right)
            HStack(spacing: 8) {
                Text(formatTime(state.currentTime))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.22))
                            .frame(height: 3.5)

                        Capsule()
                            .fill(Color.white)
                            .frame(
                                width: state.duration > 0
                                    ? max(0, min(geo.size.width, geo.size.width * CGFloat(min(max(state.currentTime / state.duration, 0), 1))))
                                    : 0,
                                height: 3.5
                            )
                    }
                    .frame(height: 3.5)
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 12)

                Text(state.duration > 0 ? "-\(formatTime(max(0, state.duration - state.currentTime)))" : "--:--")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(.horizontal, 2)

            // Row 2: Transport Controls - Perfectly Centered & High Contrast
            if #available(iOS 17.0, *) {
                HStack(alignment: .center) {
                    Spacer()

                    Button(intent: SkipPreviousIntent()) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(intent: TogglePlayPauseIntent()) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 42, height: 42)
                            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Color.black)
                                .offset(x: state.isPlaying ? 0 : 1.5)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(intent: SkipNextIntent()) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let s = Int(time)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Live Activity Artwork View

@available(iOS 16.1, *)
struct NowPlayingLiveActivityArtworkView: View {
    let data: Data?
    let fileName: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .preserveAccentedFullColor()
                    .aspectRatio(contentMode: .fill)
            } else if let fileName, let img = WidgetDataStore.shared.loadArtwork(fileName: fileName) {
                Image(uiImage: img)
                    .resizable()
                    .preserveAccentedFullColor()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color(white: 0.18)
                    Image(systemName: "music.note")
                        .font(.system(size: max(8, size * 0.45), weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 30 ? 12 : 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size > 30 ? 12 : 5, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// MARK: - Live Activity Lock Screen View

@available(iOS 16.1, *)
struct NowPlayingLiveActivityLockScreenView: View {
    let state: AudiaNowPlayingAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            NowPlayingLiveActivityArtworkView(
                data: state.artworkData,
                fileName: state.artworkFileName,
                size: 52
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(state.title.isEmpty ? "Unknown Title" : state.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(state.artist.isEmpty ? "Audia" : state.artist)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            if #available(iOS 17.0, *) {
                HStack(spacing: 12) {
                    Button(intent: SkipPreviousIntent()) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)

                    Button(intent: TogglePlayPauseIntent()) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 36, height: 36)
                            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.black)
                                .offset(x: state.isPlaying ? 0 : 1)
                        }
                    }
                    .buttonStyle(.plain)

                    Button(intent: SkipNextIntent()) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(Color.black)
    }
}
#endif

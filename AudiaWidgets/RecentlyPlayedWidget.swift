//
//  RecentlyPlayedWidget.swift
//  AudiaWidgets
//

import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct RecentlyPlayedEntry: TimelineEntry {
    let date: Date
    let items: [(item: WidgetRecentItem, artwork: UIImage?)]
}

// MARK: - Timeline Provider

struct RecentlyPlayedTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentlyPlayedEntry {
        let dummies = [
            WidgetRecentItem(videoId: "1", title: "Seven", artist: "Jung Kook"),
            WidgetRecentItem(videoId: "2", title: "Treat You Better", artist: "Shawn Mendes"),
            WidgetRecentItem(videoId: "3", title: "All I Want for Christmas", artist: "Mariah Carey"),
            WidgetRecentItem(videoId: "4", title: "Beat It", artist: "Michael Jackson")
        ]
        return RecentlyPlayedEntry(date: Date(), items: dummies.map { ($0, nil) })
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentlyPlayedEntry) -> Void) {
        let rawItems = WidgetDataStore.shared.readRecentItems()
        var uniqueItems: [WidgetRecentItem] = []
        var seenIds = Set<String>()
        for item in rawItems {
            if !seenIds.contains(item.videoId) && !item.videoId.isEmpty {
                seenIds.insert(item.videoId)
                uniqueItems.append(item)
            }
        }
        let itemsWithArt: [(item: WidgetRecentItem, artwork: UIImage?)] = uniqueItems.prefix(6).map { item in
            (item, WidgetDataStore.shared.loadArtwork(fileName: item.artworkFileName))
        }
        completion(RecentlyPlayedEntry(date: Date(), items: itemsWithArt))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentlyPlayedEntry>) -> Void) {
        let rawItems = WidgetDataStore.shared.readRecentItems()
        var uniqueItems: [WidgetRecentItem] = []
        var seenIds = Set<String>()
        for item in rawItems {
            if !seenIds.contains(item.videoId) && !item.videoId.isEmpty {
                seenIds.insert(item.videoId)
                uniqueItems.append(item)
            }
        }

        guard !uniqueItems.isEmpty else {
            let entry = RecentlyPlayedEntry(date: Date(), items: [])
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
            return
        }

        let resolvedItems: [(item: WidgetRecentItem, artwork: UIImage?)] = uniqueItems.prefix(6).map { item in
            let image = WidgetDataStore.shared.loadArtwork(fileName: item.artworkFileName)
            return (item, image)
        }

        let entry = RecentlyPlayedEntry(date: Date(), items: resolvedItems)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Main Widget View

struct RecentlyPlayedWidgetView: View {
    let entry: RecentlyPlayedEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                RecentlyPlayedSmallView(entry: entry, colorScheme: colorScheme, renderingMode: renderingMode)
            case .systemMedium:
                RecentlyPlayedMediumView(entry: entry, colorScheme: colorScheme, renderingMode: renderingMode)
            case .systemLarge:
                RecentlyPlayedLargeView(entry: entry, colorScheme: colorScheme, renderingMode: renderingMode)
            default:
                RecentlyPlayedMediumView(entry: entry, colorScheme: colorScheme, renderingMode: renderingMode)
            }
        }
        .containerBackground(for: .widget) {
            AudiaWidgetTheme.backgroundColor(for: colorScheme)
        }
    }
}

// MARK: - Small Widget (Apple Music Hero Most Recent)

private struct RecentlyPlayedSmallView: View {
    let entry: RecentlyPlayedEntry
    let colorScheme: ColorScheme
    let renderingMode: WidgetRenderingMode

    var body: some View {
        if let first = entry.items.first {
            VStack(alignment: .leading, spacing: 6) {
                // Square Artwork (Preserved Full Color in Accented/Liquid Glass)
                ZStack {
                    if let artwork = first.artwork {
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

                // Metadata and Play Badge Row
                HStack(alignment: .center, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(first.item.title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AudiaWidgetTheme.primaryTextColor(for: colorScheme))
                            .lineLimit(1)

                        Text(first.item.artist)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AudiaWidgetTheme.secondaryTextColor(for: colorScheme))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    ZStack {
                        Circle()
                            .fill(
                                renderingMode == .accented
                                    ? Color.white.opacity(0.18)
                                    : AudiaWidgetTheme.controlFillColor(for: colorScheme)
                            )
                            .frame(width: 28, height: 28)
                            .shadow(color: renderingMode == .accented ? Color.clear : Color.black.opacity(colorScheme == .dark ? 0.45 : 0.16), radius: 3, x: 0, y: 1.5)
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(
                                renderingMode == .accented
                                    ? Color.white
                                    : AudiaWidgetTheme.controlIconColor(for: colorScheme)
                            )
                            .offset(x: 1)
                    }
                }
                .padding(.horizontal, 2)
                .unredacted()
            }
            .widgetURL(URL(string: "audia://play?id=\(first.item.videoId)"))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(AudiaWidgetTheme.secondaryTextColor(for: colorScheme))
                Text("No Recents")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AudiaWidgetTheme.primaryTextColor(for: colorScheme))
                Text("Play songs in Audia")
                    .font(.system(size: 12))
                    .foregroundStyle(AudiaWidgetTheme.secondaryTextColor(for: colorScheme))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(URL(string: "audia://tab/0"))
        }
    }
}

// MARK: - Medium Widget (Apple Music 4-Item Shelf)

private struct RecentlyPlayedMediumView: View {
    let entry: RecentlyPlayedEntry
    let colorScheme: ColorScheme
    let renderingMode: WidgetRenderingMode

    var body: some View {
        let displayItems = Array(entry.items.prefix(4))

        if displayItems.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(AudiaWidgetTheme.secondaryTextColor(for: colorScheme))
                Text("No Recently Played Music")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AudiaWidgetTheme.primaryTextColor(for: colorScheme))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 10) {
                ForEach(displayItems, id: \.item.videoId) { tuple in
                    Link(destination: URL(string: "audia://play?id=\(tuple.item.videoId)") ?? URL(string: "audia://player")!) {
                        VStack(alignment: .leading, spacing: 5) {
                            // Square Artwork (Preserved Full Color in Accented/Liquid Glass)
                            ZStack {
                                if let artwork = tuple.artwork {
                                    Image(uiImage: artwork)
                                        .resizable()
                                        .widgetAccentedRenderingMode(.fullColor)
                                        .aspectRatio(contentMode: .fill)
                                } else {
                                    AudiaWidgetTheme.placeholderGradient(for: colorScheme)
                                    Image(systemName: "music.note")
                                        .font(.system(size: 24, weight: .light))
                                        .foregroundStyle(AudiaWidgetTheme.secondaryTextColor(for: colorScheme))
                                }
                            }
                            .aspectRatio(1.0, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(AudiaWidgetTheme.artworkBorder(for: colorScheme), lineWidth: 0.5)
                            )
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 5, x: 0, y: 2)
                            .unredacted()

                            // Title (Fixed 2 lines height for uniform row height)
                            Text(tuple.item.title)
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(AudiaWidgetTheme.primaryTextColor(for: colorScheme))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
                                .unredacted()

                            // Artist
                            Text(tuple.item.artist)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(AudiaWidgetTheme.secondaryTextColor(for: colorScheme))
                                .lineLimit(1)
                                .unredacted()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Large Widget (Apple Music 2x3 Grid)

private struct RecentlyPlayedLargeView: View {
    let entry: RecentlyPlayedEntry
    let colorScheme: ColorScheme
    let renderingMode: WidgetRenderingMode

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        let displayItems = Array(entry.items.prefix(6))

        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("RECENTLY PLAYED")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(AudiaWidgetTheme.secondaryTextColor(for: colorScheme))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(AudiaWidgetTheme.tertiaryTextColor(for: colorScheme))
            }

            if displayItems.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(AudiaWidgetTheme.secondaryTextColor(for: colorScheme))
                    Text("No Recently Played Music")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AudiaWidgetTheme.primaryTextColor(for: colorScheme))
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(displayItems, id: \.item.videoId) { tuple in
                        Link(destination: URL(string: "audia://play?id=\(tuple.item.videoId)") ?? URL(string: "audia://player")!) {
                            VStack(alignment: .leading, spacing: 5) {
                                // Square Artwork (Preserved Full Color in Accented/Liquid Glass)
                                ZStack {
                                    if let artwork = tuple.artwork {
                                        Image(uiImage: artwork)
                                            .resizable()
                                            .widgetAccentedRenderingMode(.fullColor)
                                            .aspectRatio(contentMode: .fill)
                                    } else {
                                        AudiaWidgetTheme.placeholderGradient(for: colorScheme)
                                        Image(systemName: "music.note")
                                            .font(.system(size: 26, weight: .light))
                                            .foregroundStyle(AudiaWidgetTheme.secondaryTextColor(for: colorScheme))
                                            .unredacted()
                                    }
                                }
                                .aspectRatio(1.0, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(AudiaWidgetTheme.artworkBorder(for: colorScheme), lineWidth: 0.5)
                                )
                                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 5, x: 0, y: 2)
                                .unredacted()

                                // Title (Fixed 2 lines)
                                Text(tuple.item.title)
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AudiaWidgetTheme.primaryTextColor(for: colorScheme))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
                                    .unredacted()

                                // Artist
                                Text(tuple.item.artist)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(AudiaWidgetTheme.secondaryTextColor(for: colorScheme))
                                    .lineLimit(1)
                                    .unredacted()
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Widget Configuration

public struct AudiaRecentlyPlayedWidget: Widget {
    public static let kind = "AudiaRecentlyPlayedWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: RecentlyPlayedTimelineProvider()) { entry in
            RecentlyPlayedWidgetView(entry: entry)
        }
        .configurationDisplayName("Recently Played")
        .description("Quickly play your recent tracks and albums.")
        .containerBackgroundRemovable(false)
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge
        ])
    }
}

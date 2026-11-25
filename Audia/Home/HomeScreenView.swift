//
//  HomeScreenView.swift
//  Audia
//

import SwiftUI

struct HomeScreenView: View {
    @Environment(SettingsStore.self) private var settings
    @ObservedObject private var router = AppRouter.shared
    @State private var viewModel = HomeViewModel()

    @State private var pendingRoute: DetailRoute?
    @State private var speedDialEntries: [SpeedDialEntry] = []

    var body: some View {
        NavigationStack(path: $router.homePath) {
            ZStack(alignment: .top) {
                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        ShimmerLoadingView()
                        Spacer()
                    }
                } else if let error = viewModel.error {
                    errorView(error)
                } else {
                    homescreenContent
                        .transition(.opacity)
                }

                VStack(spacing: 0) {
                    let hasChips = !viewModel.isLoading && viewModel.error == nil && (viewModel.homePage?.chips.isEmpty == false)
                    TabHeaderView(
                        title: "Home",
                        scrimHeight: hasChips ? 185 : 135,
                        onAccount: { router.homePath.append(DetailRoute.settings) }
                    )

                    if hasChips, let chips = viewModel.homePage?.chips {
                        ChipsRowView(
                            chips: chips,
                            selectedChip: viewModel.selectedChip,
                            onChipTap: { viewModel.toggleChip($0) }
                        )
                    }
                }
            }
            .animation(.easeOut(duration: 0.28), value: viewModel.isLoading)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: viewModel.selectedChip?.title)
            .frame(maxHeight: .infinity, alignment: .top)
            .audiaScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .detailRouteDestinations()
            .onChange(of: pendingRoute) { _, route in
                if let route {
                    router.homePath.append(route)
                    pendingRoute = nil
                }
            }
            .task {
                viewModel.loadHomeData()
                await reloadSpeedDial()
                // Trigger library sync in background
                Task {
                    await SyncBridge.checkAndSyncIfStale()
                    await MainActor.run {
                        NotificationCenter.default.post(name: .personalizationDataUpdated, object: nil)
                    }
                }
            }
            .task(id: viewModel.homeSections.count) {
                let urls = viewModel.homeSections
                    .flatMap(\.items)
                    .compactMap(\.thumbnailUrl)
                    .compactMap(URL.init)
                await ImagePreloader.shared.preload(urls)
            }
        }
    }

    private var homescreenContent: some View {
        let hasChips = (viewModel.homePage?.chips.isEmpty == false)
        return ScrollView {
            LazyVStack(spacing: 0) {
                Color.clear.frame(height: hasChips ? 110 : 62)

                ForEach(viewModel.homeSections) { section in
                    sectionView(for: section)
                }

                GeometryReader { _ in
                    Color.clear
                        .onAppear {
                            let total = viewModel.homeSections.count
                            if total > 0 {
                                viewModel.loadMoreIfNeeded(
                                    currentIndex: total - 1,
                                    total: total
                                )
                            }
                        }
                }
                .frame(height: 1)
            }
            .appBottomClearance(isRootTab: true)
        }
        .scrollIndicators(.automatic)
        .miniPlayerTracksScroll()
        .refreshable {
            await viewModel.refresh()
            await reloadSpeedDial()
            await SyncBridge.checkAndSyncIfStale()
        }
        .onChange(of: settings.hideExplicit) { _, _ in
            viewModel.syncSettings()
        }
        .onChange(of: settings.showQuickPicks) { _, _ in
            viewModel.syncSettings()
            Task { await viewModel.refresh() }
        }
        .onChange(of: settings.topListsLength) { _, _ in
            Task { await viewModel.refresh() }
        }
        .onChange(of: settings.contentCountry) { _, _ in
            Task { await viewModel.refresh() }
        }
    }

    @ViewBuilder
    private func sectionView(for section: HomeSection) -> some View {
        switch section {
        case .quickPicks:
            quickPicksSection(section)
        case .keepListening:
            mixedSection(section)
        case .homePageSection(let sectionData, _):
            if sectionData.isSongsOnly {
                songsSection(section)
            } else {
                mixedSection(section)
            }
        default:
            mixedSection(section)
        }
    }

    @ViewBuilder
    private func quickPicksSection(_ section: HomeSection) -> some View {
        let pinnedSongs = speedDialEntries.map { $0.toSongItem() }
        let pinnedIds = Set(speedDialEntries.map(\.videoId))
        let visibleItems = section.items.filter { item in
            if case .song(let s) = item { return !pinnedIds.contains(s.videoId) }
            return true
        }
        let quickSongs = visibleItems.compactMap { if case .song(let s) = $0 { return s } else { return nil } }
        let combinedQueue = pinnedSongs + quickSongs

        if combinedQueue.isEmpty {
            EmptyView()
        } else {
            HorizontalSection(title: section.displayTitle, vSpacing: 8, contentVerticalPadding: 0) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(60)), count: 4), spacing: 12) {
                    ForEach(speedDialEntries, id: \.videoId) { entry in
                        let song = entry.toSongItem()
                        YouTubeListItemView(
                            item: .song(song),
                            onTap: { handleSongTap(song, in: combinedQueue) },
                            onNavigate: { pendingRoute = $0 }
                        )
                        .frame(width: 280)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "pin.fill")
                                .font(.satoshi(size: 12, weight: .bold))
                                .foregroundStyle(settings.accentColor)
                                .padding(6)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                Task {
                                    try? await DatabaseService.shared.removeFromSpeedDial(videoId: entry.videoId)
                                    await reloadSpeedDial()
                                }
                            } label: {
                                Label("Unpin", systemImage: "pin.slash")
                            }
                        }
                    }

                    ForEach(visibleItems.indices, id: \.self) { i in
                        let item = visibleItems[i]
                        if case .song(let s) = item {
                            YouTubeListItemView(
                                item: item,
                                onTap: { handleSongTap(s, in: combinedQueue) },
                                onNavigate: { pendingRoute = $0 }
                            )
                                .frame(width: 280)
                        } else {
                            YouTubeListItemView(item: item, onTap: { handleItemTap(item) }, onNavigate: { pendingRoute = $0 })
                                .frame(width: 280)
                        }
                    }
                }
            }
        }
    }

    private func songsSection(_ section: HomeSection) -> some View {
        let queue = section.items.compactMap { if case .song(let s) = $0 { return s } else { return nil } }
        return HorizontalSection(title: section.displayTitle, vSpacing: 8, contentVerticalPadding: 0) {
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(60)), count: 4), spacing: 12) {
                ForEach(section.items.indices, id: \.self) { i in
                    let item = section.items[i]
                    if case .song(let s) = item {
                        YouTubeListItemView(item: item, onTap: { handleSongTap(s, in: queue) }, onNavigate: { pendingRoute = $0 })
                            .frame(width: 280)
                    } else {
                        YouTubeListItemView(item: item, onTap: { handleItemTap(item) }, onNavigate: { pendingRoute = $0 })
                            .frame(width: 280)
                    }
                }
            }
        }
    }

    private func mixedSection(_ section: HomeSection) -> some View {
        let queue = section.items.compactMap { if case .song(let s) = $0 { return s } else { return nil } }
        return HorizontalSection(title: section.displayTitle, vSpacing: 8, contentVerticalPadding: 0) {
            HStack(spacing: 12) {
                ForEach(section.items.indices, id: \.self) { i in
                    let item = section.items[i]
                    if case .song(let s) = item, !queue.isEmpty {
                        YouTubeGridItemView(item: item, onTap: { handleSongTap(s, in: queue) })
                    } else {
                        YouTubeGridItemView(item: item, onTap: { handleItemTap(item) })
                    }
                }
            }
        }.padding(.top, 8)
    }

    // MARK: - Quick Picks (pinned)

    private func reloadSpeedDial() async {
        speedDialEntries = (try? await DatabaseService.shared.fetchSpeedDial()) ?? []
    }

    private func handleSongTap(_ song: SongItem, in queue: [SongItem]) {
        Log.homeScreenView.debug("Tapped song in queue: \(song.title) queueCount=\(queue.count)")
        PlaybackQueue.play(song, in: queue, log: Log.homeScreenView, context: "Tapped song")
    }

    private func handleItemTap(_ item: YTItem) {
        Log.homeScreenView.debug("Tapped item: \(item.title) type=\(typeName(item))")
        YTItemRouter.route(
            item,
            playSong: { PlaybackQueue.playSingleWithRadio($0, log: Log.homeScreenView) },
            appendRoute: { router.homePath.append($0) }
        )
    }

    private func typeName(_ item: YTItem) -> String {
        switch item {
        case .song: return "song"
        case .album: return "album"
        case .artist: return "artist"
        case .playlist: return "playlist"
        case .podcast: return "podcast"
        case .episode: return "episode"
        }
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView(
            "Couldn't load your homescreen",
            systemImage: "wifi.slash",
            description: Text(error.localizedDescription)
        )
    }
}

#Preview {
    HomeScreenView()
}

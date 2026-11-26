//
//  SearchView.swift
//  Audia
//

import SwiftUI

struct SearchView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var viewModel = SearchViewModel()
    @ObservedObject private var router = AppRouter.shared
    @FocusState private var fieldFocused: Bool

    @State private var pendingRoute: DetailRoute?
    @State private var showImportDialog = false
    @State private var importLink = ""

    var body: some View {
        NavigationStack(path: $router.searchPath) {
            ZStack(alignment: .top) {
                content
                    .contentMargins(.top, PlaylistLinkParser.parse(viewModel.fieldText) != nil ? 124 : 62, for: .scrollContent)

                VStack(spacing: 0) {
                    searchTopBar

                    if let linkType = PlaylistLinkParser.parse(viewModel.fieldText) {
                        importBanner(for: linkType)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .toolbar(.hidden, for: .navigationBar)
            .detailRouteDestinations()
            .overlay {
                if showImportDialog {
                    CreatePlaylistDialog(
                        isPresented: $showImportDialog,
                        prefilledLink: importLink,
                        initialTab: .importLink,
                        onCreated: { }
                    )
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showImportDialog)
            .audiaScreenBackground()
            .onChange(of: pendingRoute) { _, route in
                if let route {
                    router.searchPath.append(route)
                    pendingRoute = nil
                }
            }
            .onAppear {
                viewModel.loadSearchHistory()
                focusIfSearchTab()
            }
            .onChange(of: router.selectedTabIndex) { _, _ in
                focusIfSearchTab()
            }
            .task(id: viewModel.results.count) {
                let urls = viewModel.results
                    .flatMap(\.items)
                    .compactMap(\.thumbnailUrl)
                    .compactMap(URL.init)
                await ImagePreloader.shared.preload(urls)
            }
        }
    }

    // MARK: - Top bar

    /// Search field + sort menu pinned above the filter chips.
    private var searchTopBar: some View {
        HStack(spacing: 10) {
            Button {
                fieldFocused = false
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                if !router.searchPath.isEmpty {
                    router.searchPath.removeLast()
                } else if !viewModel.fieldText.isEmpty {
                    viewModel.fieldText = ""
                } else {
                    router.selectedTabIndex = 0
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.satoshi(size: 16, weight: .semibold))
                    .foregroundStyle(AudiaTheme.textPrimary)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
                    .audiaGlassCircle()
            }
            .buttonStyle(BouncyScaleButtonStyle(scale: 0.9))
            .accessibilityLabel("Back")

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AudiaTheme.textSecondary)
                TextField("Search Music", text: $viewModel.fieldText)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .foregroundStyle(AudiaTheme.textPrimary)
                    .onSubmit { submit(nil) }
                if !viewModel.fieldText.isEmpty {
                    Button {
                        viewModel.fieldText = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.satoshi(size: 14.5, weight: .bold))
                            .foregroundStyle(AudiaTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .audiaGlassCapsule()
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

    // MARK: - Import Link Banner

    private func importBanner(for linkType: PlaylistLinkType) -> some View {
        Button {
            importLink = viewModel.fieldText
            fieldFocused = false
            showImportDialog = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: linkType.systemIcon)
                    .font(.satoshi(size: 18, weight: .semibold))
                    .foregroundColor(linkType.serviceName == "Spotify" ? .green : .red)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Import \(linkType.serviceName) Playlist")
                        .font(.satoshi(.subheadline, weight: .bold))
                        .foregroundColor(AudiaTheme.textPrimary)
                    Text("Tap to preview and add to your library")
                        .font(.satoshi(.caption))
                        .foregroundColor(AudiaTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.satoshi(size: 14, weight: .semibold))
                    .foregroundColor(AudiaTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AudiaTheme.surfaceVariant)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(settings.accentColor.opacity(0.6), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
    }

    /// Focuses the field (raising the keyboard) whenever the Search tab
    /// becomes active.
    private func focusIfSearchTab() {
        if AppRouter.shared.selectedTabIndex == 1 {
            fieldFocused = true
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            if viewModel.searchHistory.isEmpty {
                noRecentSearchesView
            } else {
                searchHistoryView
            }
        case .suggestions:
            suggestionsView
        case .loading:
            loadingView
        case .results:
            searchResultsList
        case .noResults:
            noResultsView
        case .failed:
            errorView(viewModel.error)
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ShimmerLoadingView()
            Spacer()
        }
    }

    // MARK: - Submission

    private func submit(_ text: String? = nil) {
        if let text {
            viewModel.fieldText = text
        }
        fieldFocused = false
        viewModel.submit()
    }

    // MARK: - Suggestions View

    private var suggestionsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // 1. Direct Entity Suggestions (e.g. Artist avatar or Top Song match)
                if !viewModel.entitySuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.entitySuggestions.prefix(3), id: \.id) { item in
                            YouTubeListItemView(item: item, onTap: {
                                fieldFocused = false
                                viewModel.recordHistory(item.title)
                                handleItemTap(item)
                            }, onNavigate: { route in
                                fieldFocused = false
                                viewModel.recordHistory(item.title)
                                pendingRoute = route
                            })
                        }
                    }
                    .padding(.top, 4)

                    Divider()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }

                // 2. Matching Local Search History
                ForEach(viewModel.matchingHistory, id: \.query) { entry in
                    suggestionRow(
                        icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        iconColor: settings.accentColor,
                        text: entry.query,
                        onSelect: {
                            submit(entry.query)
                        },
                        onFill: {
                            viewModel.fieldText = entry.query
                        }
                    )
                }

                // 3. Remote Query Suggestions
                ForEach(viewModel.querySuggestions, id: \.self) { suggestion in
                    suggestionRow(
                        icon: "magnifyingglass",
                        iconColor: AudiaTheme.textSecondary,
                        text: suggestion,
                        onSelect: {
                            submit(suggestion)
                        },
                        onFill: {
                            viewModel.fieldText = suggestion
                        }
                    )
                }

                // Subtle loading spinner when awaiting first suggestions
                if viewModel.isLoadingSuggestions && viewModel.entitySuggestions.isEmpty && viewModel.querySuggestions.isEmpty && viewModel.matchingHistory.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(AudiaTheme.textSecondary)
                            .padding(.top, 40)
                        Spacer()
                    }
                }
            }
            .appBottomClearance(isRootTab: true)
        }
        .scrollIndicators(.automatic)
        .scrollDismissesKeyboard(.immediately)
        .miniPlayerTracksScroll()
    }

    private func suggestionRow(
        icon: String,
        iconColor: Color,
        text: String,
        onSelect: @escaping () -> Void,
        onFill: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.satoshi(size: 15))
                    .foregroundStyle(iconColor)
                    .frame(width: 24, height: 24)

                Button(action: onSelect) {
                    Text(text)
                        .font(.satoshi(.body))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button(action: onFill) {
                    Image(systemName: "arrow.up.backward")
                        .font(.satoshi(size: 14, weight: .semibold))
                        .foregroundStyle(AudiaTheme.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Insert query")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())

            Divider()
                .padding(.leading, 52)
        }
    }

    private var searchHistoryView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Recently searched")
                        .font(.satoshi(.headline))
                        .foregroundColor(.primary)
                    Spacer()
                    Button("Clear") {
                        viewModel.clearSearchHistory()
                    }
                    .font(.satoshi(.subheadline))
                    .foregroundColor(settings.accentColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                ForEach(viewModel.searchHistory, id: \.query) { entry in
                    Button {
                        submit(entry.query)
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .foregroundColor(settings.accentColor)
                            Text(entry.query)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.deleteSearchHistoryEntry(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                    Divider()
                        .padding(.leading, 16)
                }
            }
            .appBottomClearance(isRootTab: true)
        }
        .scrollIndicators(.automatic)
        .scrollDismissesKeyboard(.immediately)
        .miniPlayerTracksScroll()
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.filteredResults) { section in
                    sectionHeader(section.title)

                    switch section.title {
                    case "Artists":
                        artistCarousel(items: section.items)
                    case "Albums":
                        albumCarousel(items: section.items)
                    default:
                        ForEach(section.items, id: \.id) { item in
                            YouTubeListItemView(item: item, onTap: {
                                handleItemTap(item)
                            }, onNavigate: { pendingRoute = $0 })
                        }
                    }
                }
            }
            .appBottomClearance(isRootTab: true)
        }
        .scrollIndicators(.automatic)
        .scrollDismissesKeyboard(.immediately)
        .miniPlayerTracksScroll()
    }

    /// Section title with chevron — taps drill into (or clear) the filter.
    private func sectionHeader(_ title: String) -> some View {
        Button {
            if viewModel.selectedSectionFilter == title {
                viewModel.selectedSectionFilter = nil
            } else {
                viewModel.selectedSectionFilter = title
                viewModel.isShowingLibrary = false
            }
        } label: {
            HStack(spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(.satoshi(.headline))
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.right")
                    .font(.satoshi(.subheadline))
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    /// Artist-first hero: big circular artwork + name, then top songs.
    private func artistHeroCard(_ artist: ArtistItem, songs: [SongItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                router.searchPath.append(DetailRoute.artist(browseId: artist.browseId))
            } label: {
                HStack(spacing: 12) {
                    AsyncImageView(url: artist.thumbnailUrl)
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                    Text(artist.name)
                        .font(.satoshi(.title3))
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text("•••")
                        .font(.satoshi(.body, weight: .black))
                        .foregroundStyle(settings.accentColor)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ForEach(songs, id: \.videoId) { song in
                let item = YTItem.song(song)
                YouTubeListItemView(item: item, onTap: {
                    handleItemTap(item)
                }, onNavigate: { pendingRoute = $0 })
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AudiaTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AudiaTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func artistCarousel(items: [YTItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(items, id: \.id) { item in
                    if case .artist(let artist) = item {
                        Button {
                            router.searchPath.append(DetailRoute.artist(browseId: artist.browseId))
                        } label: {
                            VStack(spacing: 8) {
                                AsyncImageView(url: artist.thumbnailUrl)
                                    .frame(width: 110, height: 110)
                                    .clipShape(Circle())
                                Text(artist.name)
                                    .font(.satoshi(.subheadline))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(width: 110)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func albumCarousel(items: [YTItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(items, id: \.id) { item in
                    if case .album(let album) = item {
                        Button {
                            router.searchPath.append(DetailRoute.album(browseId: album.browseId))
                        } label: {
                            MediaGridCell(
                                thumbnailUrl: album.thumbnailUrl,
                                title: album.title,
                                subtitle: album.artists.map(\.name).joined(separator: ", "),
                                size: 140
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private var noResultsView: some View {
        ContentUnavailableView(
            "No Results",
            systemImage: "magnifyingglass",
            description: Text("No results found for \"\(viewModel.submittedQuery)\"")
        )
    }

    private var noRecentSearchesView: some View {
        ContentUnavailableView(
            "No Recent Searches",
            systemImage: "magnifyingglass",
            description: Text("Your recent searches will appear here.")
        )
    }

    private func errorView(_ error: Error?) -> some View {
        ContentUnavailableView(
            "Search failed",
            systemImage: "exclamationmark.triangle",
            description: Text(error?.localizedDescription ?? "Something went wrong.")
        )
    }

    private func handleItemTap(_ item: YTItem) {
        YTItemRouter.route(
            item,
            playSong: { PlaybackQueue.playSingleWithRadio($0, log: Log.searchView) },
            appendRoute: { router.searchPath.append($0) }
        )
    }
}

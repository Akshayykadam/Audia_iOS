//
//  HomeViewModel.swift
//  Audia
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class HomeViewModel {
    var homePage: HomePage?
    var homeSections: [HomeSection] = []
    var isLoading = true
    var isRefreshing = false
    var selectedChip: HomePage.Chip?
    var error: Error?

    var isLoggedIn = false

    var hideExplicit = false {
        didSet { mergeSections() }
    }

    private var isHomeDataLoaded = false
    private var isLoadingMore = false
    private var loadGeneration = 0
    private var previousHomePage: HomePage?
    private let personalization = PersonalizationService.shared

    private var cachedLocalSections: [HomeSection] = []
    private var cachedPhase2Sections: [HomeSection] = []

    private let cleanup = HomeViewModelCleanup()

    deinit {
        if let observer = cleanup.notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        cleanup.chipTask?.cancel()
    }

    init() {
        hideExplicit = SettingsStore.shared.hideExplicit
        if let existing = cleanup.notificationObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        cleanup.notificationObserver = NotificationCenter.default.addObserver(
            forName: .personalizationDataUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshLocalSections()
        }
    }

    private nonisolated func refreshLocalSections() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let settings = SettingsStore.shared
            async let qp: HomeSection = settings.showQuickPicks
                ? await personalization.buildQuickPicks(limit: max(settings.topListsLength, 16))
                : .quickPicks(items: [])
            async let kl: HomeSection = await personalization.buildKeepListening()
            async let ff: HomeSection = await personalization.buildForgottenFavorites()
            let (qpResult, klResult, ffResult) = await (qp, kl, ff)
            var local: [HomeSection] = []
            if !qpResult.items.isEmpty { local.append(qpResult) }
            if !klResult.items.isEmpty { local.append(klResult) }
            if !ffResult.items.isEmpty { local.append(ffResult) }
            self.cachedLocalSections = local
            self.mergeSections()
            await self.personalization.drainEnrichments()
            let refreshed = await (
                self.personalization.buildForgottenFavorites(),
                self.personalization.buildKeepListening()
            )
            var merged = local
            merged.removeAll { section in
                switch section {
                case .forgottenFavorites, .keepListening: return true
                default: return false
                }
            }
            if !refreshed.0.items.isEmpty { merged.append(refreshed.0) }
            if !refreshed.1.items.isEmpty { merged.append(refreshed.1) }
            self.cachedLocalSections = merged
            self.mergeSections()
        }
    }

    /// Re-reads settings that affect the feed (explicit filter, quick picks).
    func syncSettings() {
        let settings = SettingsStore.shared
        hideExplicit = settings.hideExplicit
    }

    func loadHomeData() {
        guard !isHomeDataLoaded else { return }
        isHomeDataLoaded = true
        Task { await load() }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        cachedLocalSections = []
        cachedPhase2Sections = []
        await load()
        isRefreshing = false
    }

    // MARK: - Home Data Loading

    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        error = nil

        async let localTask: Void = storeLocalSections()
        _ = await localTask
        guard generation == loadGeneration else { return }
        await personalization.drainEnrichments()

        async let phase2Work: Void = loadPhase2Sections()

        await fetchHomePage(generation: generation)
        guard generation == loadGeneration else {
            await phase2Work
            return
        }
        await ensureQuickPicksAvailable(generation: generation)
        guard generation == loadGeneration else {
            await phase2Work
            return
        }
        await phase2Work

        guard generation == loadGeneration else { return }
        mergeSections()
        isLoading = false
    }

    private func ensureQuickPicksAvailable(generation: Int) async {
        guard SettingsStore.shared.showQuickPicks else { return }
        var attempts = 0
        while attempts < 3,
              generation == loadGeneration,
              !hasQuickPicksServerSection(),
              let continuation = homePage?.continuation {
            attempts += 1
            do {
                let json = try await InnerTubeClient.audiaShared.browse(continuation: continuation)
                guard let (newSections, next) = HomePageParser.parseContinuationSections(from: json) else {
                    break
                }
                homePage?.sections.append(contentsOf: newSections)
                homePage?.continuation = next
                mergeSections()
            } catch {
                break
            }
        }
    }

    private func hasQuickPicksServerSection() -> Bool {
        guard let sections = homePage?.sections else { return false }
        let totalSongs = sections.flatMap(\.items).filter { if case .song = $0 { return true } else { return false } }.count
        if totalSongs >= 16 { return true }
        return sections.contains { section in
            if case .quickPicks = mapServerSection(section, index: 0) { return true }
            return false
        }
    }

    private func fetchHomePage(generation: Int) async {
        do {
            let json = try await InnerTubeClient.audiaShared.browse(browseId: "FEmusic_home")
            guard let page = HomePageParser.parseHomePage(from: json) else {
                if generation == loadGeneration {
                    error = InnerTubeError.decodingFailed
                }
                return
            }
            homePage = page
        } catch {
            if generation == loadGeneration {
                self.error = error
            }
        }
    }

    private func storeLocalSections() async {
        let settings = SettingsStore.shared
        async let qp: HomeSection = settings.showQuickPicks
            ? personalization.buildQuickPicks(limit: max(settings.topListsLength, 16))
            : .quickPicks(items: [])
        async let kl: HomeSection = personalization.buildKeepListening()
        async let ff: HomeSection = personalization.buildForgottenFavorites()

        let (qpResult, klResult, ffResult) = await (qp, kl, ff)

        var local: [HomeSection] = []
        if !qpResult.items.isEmpty { local.append(qpResult) }
        if !klResult.items.isEmpty { local.append(klResult) }
        if !ffResult.items.isEmpty { local.append(ffResult) }
        cachedLocalSections = local
    }

    private func loadPhase2Sections() async {
        guard isLoggedIn else { return }

        async let ap: HomeSection = personalization.buildAccountPlaylists()
        async let dd: HomeSection = personalization.buildDailyDiscover()
        async let ct: HomeSection = personalization.buildFromTheCommunity()
        async let sr: [HomeSection] = personalization.buildSimilarRecommendations()

        let (apResult, ddResult, ctResult, srResults) = await (ap, dd, ct, sr)
        var phase2: [HomeSection] = []
        if !apResult.items.isEmpty { phase2.append(apResult) }
        if !ddResult.items.isEmpty { phase2.append(ddResult) }
        if !ctResult.items.isEmpty { phase2.append(ctResult) }
        phase2.append(contentsOf: srResults)
        cachedPhase2Sections = phase2

        mergeSections()
    }

    func toggleChip(_ chip: HomePage.Chip?) {
        cleanup.chipTask?.cancel()
        if chip == nil || chip?.params == nil || chip?.title == selectedChip?.title || chip?.title == "Home" {
            if let prev = previousHomePage {
                homePage = prev
                previousHomePage = nil
            }
            selectedChip = nil
            mergeSections()
            return
        }

        if selectedChip == nil {
            previousHomePage = homePage
        }

        selectedChip = chip
        let generation = loadGeneration
        cleanup.chipTask = Task {
            do {
                let json = try await InnerTubeClient.audiaShared.browse(
                    browseId: "FEmusic_home",
                    params: chip?.params
                )
                guard !Task.isCancelled, generation == loadGeneration else { return }
                if let page = HomePageParser.parseHomePage(from: json) {
                    homePage?.sections = page.sections
                    // The filtered feed carries its own continuation; reusing
                    // the unfiltered one would page wrong sections in below.
                    homePage?.continuation = page.continuation
                    mergeSections()
                }
            } catch {
                guard !Task.isCancelled else { return }
                guard generation == loadGeneration else { return }
                homePage = previousHomePage
                previousHomePage = nil
                selectedChip = nil
                mergeSections()
            }
        }
    }

    func loadMoreIfNeeded(currentIndex: Int, total: Int) {
        guard total - currentIndex <= 3,
              let continuation = homePage?.continuation,
              !isLoadingMore else { return }
        isLoadingMore = true
        Task {
            defer { isLoadingMore = false }
            do {
                let json = try await InnerTubeClient.audiaShared.browse(continuation: continuation)
                if let (newSections, newContinuation) = HomePageParser.parseContinuationSections(from: json) {
                    homePage?.sections.append(contentsOf: newSections)
                    homePage?.continuation = newContinuation
                    mergeSections()
                }
            } catch {
                Log.homeViewModel.error("Continuation error: \(error)")
            }
        }
    }

    // MARK: - Section Management

    private var isHomeChipActive: Bool {
        selectedChip == nil || selectedChip?.title == "Home" || selectedChip?.params == nil
    }

    private func mergeSections() {
        let isHome = isHomeChipActive
        let localSections = isHome ? cachedLocalSections : cachedLocalSections.filter {
            if case .keepListening = $0 { return false }
            return true
        }
        let serverSections = homePage?.sections.enumerated().map { mapServerSection($1, index: $0) } ?? []
        let all = localSections + serverSections + (isHome ? cachedPhase2Sections : [])
        let merged = orderSections(all)
        homeSections = merged
    }

    private func mapServerSection(_ section: HomePage.Section, index: Int) -> HomeSection {
        let title = section.title.lowercased()
        if title == "quick picks" || title.contains("quick pick") {
            if !SettingsStore.shared.showQuickPicks {
                return .quickPicks(items: [])
            }
            return .quickPicks(items: section.items)
        }
        if title.contains("listen again") || title.contains("keep listening") {
            return .keepListening(items: section.items)
        }
        if title.contains("forgotten") || title.contains("favorite") {
            return .forgottenFavorites(items: section.items)
        }
        return .homePageSection(section, index: index)
    }

    private func orderSections(_ sections: [HomeSection]) -> [HomeSection] {
        let filtered = sections.compactMap { section -> HomeSection? in
            let title = section.displayTitle.lowercased()
            if title.contains("community playlist") || title.contains("from the community") || title.contains("trending community") {
                return nil
            }
            if title.contains("trending songs") || title.contains("covers and remixes") {
                return nil
            }
            if title.contains("song mix") || title.contains("song mixes") || title.contains("mixed for you") || title.contains("为你混配") {
                return nil
            }
            if case .fromTheCommunity = section {
                return nil
            }
            if !isHomeChipActive {
                if case .keepListening = section {
                    return nil
                }
                if title.contains("keep listening") || title.contains("listen again") {
                    return nil
                }
            }
            let f = applyFilters(section)
            if case .quickPicks = f { return f }
            return f.items.isEmpty ? nil : f
        }

        var byId: [String: HomeSection] = [:]
        for section in filtered {
            if let existing = byId[section.id] {
                if section.items.count > existing.items.count {
                    byId[section.id] = section
                }
            } else {
                byId[section.id] = section
            }
        }

        var ordered = byId.values.sorted { a, b in
            sectionWeight(a) > sectionWeight(b)
        }

        // Always ensure Quick Picks is at the start and has a full grid of songs (at least 16 songs)
        guard SettingsStore.shared.showQuickPicks else {
            return ordered
        }

        var qpItems: [YTItem] = []
        if let qpIndex = ordered.firstIndex(where: { if case .quickPicks = $0 { return true } else { return false } }) {
            let qp = ordered.remove(at: qpIndex)
            if case .quickPicks(let items) = qp {
                qpItems = items
            }
        }

        let targetCount = max(SettingsStore.shared.topListsLength, 16)
        if qpItems.count < targetCount {
            var seenIds = Set<String>()
            for item in qpItems {
                if case .song(let s) = item { seenIds.insert(s.videoId) }
            }

            // 1. Collect candidate songs from homePage sections (including raw server sections)
            var candidates: [YTItem] = []
            if let hpSections = homePage?.sections {
                for sec in hpSections {
                    let secTitle = sec.title.lowercased()
                    if secTitle.contains("song mix") || secTitle.contains("song mixes") || secTitle.contains("mixed for you") || secTitle.contains("为你混配") {
                        continue
                    }
                    for item in sec.items {
                        if case .song(let s) = item, !seenIds.contains(s.videoId) {
                            seenIds.insert(s.videoId)
                            candidates.append(item)
                        }
                    }
                }
            }

            // 2. Also collect from current ordered sections
            for sec in ordered {
                for item in sec.items {
                    if case .song(let s) = item, !seenIds.contains(s.videoId) {
                        seenIds.insert(s.videoId)
                        candidates.append(item)
                    }
                }
            }

            let needed = targetCount - qpItems.count
            if !candidates.isEmpty {
                qpItems.append(contentsOf: candidates.prefix(needed))
            }
        }

        if !qpItems.isEmpty {
            let qpSongIds = Set(qpItems.compactMap { item -> String? in
                if case .song(let s) = item { return s.videoId }
                return nil
            })

            // Deduplicate: if downstream sections had their songs borrowed into Quick Picks,
            // remove those duplicate tracks so songs don't repeat immediately.
            // If a section is now empty or lost its distinct tracks, remove it.
            ordered = ordered.compactMap { section in
                let remainingItems = section.items.filter { item in
                    if case .song(let s) = item {
                        return !qpSongIds.contains(s.videoId)
                    }
                    return true
                }
                guard !remainingItems.isEmpty else { return nil }
                if section.isSongsOnly && remainingItems.count < 2 && remainingItems.count < section.items.count {
                    return nil
                }
                return self.withItems(section, remainingItems)
            }

            ordered.insert(.quickPicks(items: qpItems), at: 0)
        }

        return ordered
    }

    private func withItems(_ section: HomeSection, _ items: [YTItem]) -> HomeSection {
        switch section {
        case .quickPicks:
            return .quickPicks(items: items)
        case .keepListening:
            return .keepListening(items: items)
        case .forgottenFavorites:
            return .forgottenFavorites(items: items)
        case .homePageSection(var s, let index):
            s.items = items
            return .homePageSection(s, index: index)
        case .accountPlaylists:
            return .accountPlaylists(items: items)
        case .similarRecommendation(_, let t):
            return .similarRecommendation(items: items, title: t)
        case .dailyDiscover:
            return .dailyDiscover(items: items)
        case .fromTheCommunity:
            return .fromTheCommunity(items: items)
        case .speedDial:
            return .speedDial(items: items)
        case .moodAndGenres:
            return .moodAndGenres(items: items)
        }
    }

    private func applyFilters(_ section: HomeSection) -> HomeSection {
        if SettingsStore.shared.audioOnlyMode && section.displayTitle.localizedCaseInsensitiveContains("video") {
            return .quickPicks(items: [])
        }

        let filteredItems = section.items.filter { item in
            if SettingsStore.shared.audioOnlyMode && item.isMusicVideo {
                return false
            }
            if hideExplicit {
                switch item {
                case .song(let s) where s.isExplicit: return false
                case .album(let a) where a.isExplicit: return false
                default: break
                }
            }
            return true
        }

        switch section {
        case .quickPicks: return .quickPicks(items: filteredItems)
        case .keepListening: return .keepListening(items: filteredItems)
        case .forgottenFavorites: return .forgottenFavorites(items: filteredItems)
        case .homePageSection(let sectionData, let index):
            if SettingsStore.shared.audioOnlyMode && sectionData.title.localizedCaseInsensitiveContains("video") {
                return .quickPicks(items: [])
            }
            let filteredSectionItems = sectionData.items.filter { item in
                if SettingsStore.shared.audioOnlyMode && item.isMusicVideo {
                    return false
                }
                if hideExplicit {
                    switch item {
                    case .song(let s) where s.isExplicit: return false
                    case .album(let a) where a.isExplicit: return false
                    default: break
                    }
                }
                return true
            }
            var newSection = sectionData
            newSection.items = filteredSectionItems
            return .homePageSection(newSection, index: index)
        case .accountPlaylists: return .accountPlaylists(items: filteredItems)
        case .similarRecommendation(_, let t): return .similarRecommendation(items: filteredItems, title: t)
        case .dailyDiscover: return .dailyDiscover(items: filteredItems)
        case .fromTheCommunity: return .fromTheCommunity(items: filteredItems)
        case .speedDial: return .speedDial(items: filteredItems)
        case .moodAndGenres: return .moodAndGenres(items: filteredItems)
        }
    }

    private func sectionWeight(_ section: HomeSection) -> Int {
        switch section {
        case .quickPicks: return 1000
        case .homePageSection(let sectionData, let index):
            let title = sectionData.title.lowercased()
            if title.contains("quick pick") {
                return 900 - index
            }
            return 400 - index
        case .keepListening: return 800
        case .forgottenFavorites: return 600
        case .dailyDiscover: return 500
        case .similarRecommendation: return 350
        case .accountPlaylists: return 300
        case .fromTheCommunity: return 250
        case .speedDial: return 200
        case .moodAndGenres: return 150
        }
    }
}

private final class HomeViewModelCleanup: @unchecked Sendable {
    var chipTask: Task<Void, Never>?
    var notificationObserver: NSObjectProtocol?
}

//
//  LyricsView.swift
//  Audia
//

import SwiftUI

struct LyricsScrollSection: View {
    @Binding var showTranslation: Bool
    @Binding var isTranslating: Bool
    @Binding var hasLyrics: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var np = NowPlaying.shared
    private let player = PlayerController.shared

    @State private var result: LyricsResult?
    @State private var isLoading = false
    @State private var userScrolledAt: Date?
    @State private var isUserScrolling = false

    private var activeLineIndex: Int? {
        guard let result, result.isSynced else { return nil }
        let t = np.currentTime + 0.15
        var lastMatch: Int?
        for (idx, line) in result.lines.enumerated() {
            if let lineTime = line.time, lineTime <= t {
                lastMatch = idx
            } else {
                break
            }
        }
        return lastMatch
    }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(AudiaTheme.textPrimary.opacity(0.85))
                        .scaleEffect(1.1)
                    Text("Loading Lyrics")
                        .font(.satoshi(size: 15, weight: .semibold))
                        .foregroundStyle(AudiaTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result, !result.lines.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            Spacer().frame(height: 18)

                            ForEach(Array(result.lines.enumerated()), id: \.element.id) { index, line in
                                lyricRow(line: line, index: index, isSynced: result.isSynced)
                                    .id(line.id)
                            }

                            Spacer().frame(height: 110)
                        }
                        .padding(.horizontal, 28)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { _ in
                                userScrolledAt = Date()
                                if !isUserScrolling {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isUserScrolling = true
                                    }
                                }
                            }
                            .onEnded { _ in
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 2_800_000_000)
                                    if let scrolled = userScrolledAt, Date().timeIntervalSince(scrolled) >= 2.7 {
                                        withAnimation(.easeInOut(duration: 0.35)) {
                                            isUserScrolling = false
                                        }
                                        if let idx = activeLineIndex, result.lines.indices.contains(idx) {
                                            withAnimation(.spring(response: 0.6, dampingFraction: 0.88)) {
                                                proxy.scrollTo(result.lines[idx].id, anchor: UnitPoint(x: 0.5, y: 0.32))
                                            }
                                        }
                                    }
                                }
                            }
                    )
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .white, location: 0.06),
                                .init(color: .white, location: 0.84),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .onChange(of: activeLineIndex) { _, newIdx in
                        guard let newIdx, result.lines.indices.contains(newIdx), !isUserScrolling else { return }
                        withAnimation(.spring(response: 0.58, dampingFraction: 0.86)) {
                            proxy.scrollTo(result.lines[newIdx].id, anchor: UnitPoint(x: 0.5, y: 0.32))
                        }
                    }
                    .onAppear {
                        if let idx = activeLineIndex, result.lines.indices.contains(idx) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) {
                                    proxy.scrollTo(result.lines[idx].id, anchor: UnitPoint(x: 0.5, y: 0.32))
                                }
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(AudiaTheme.textMuted)

                    Text("Lyrics Not Available")
                        .font(.satoshi(size: 17, weight: .semibold))
                        .foregroundStyle(AudiaTheme.textSecondary)

                    Button {
                        Haptics.light()
                        Task { await loadLyricsForCurrentSong() }
                    } label: {
                        Text("Try Again")
                            .font(.satoshi(size: 14, weight: .semibold))
                            .foregroundStyle(AudiaTheme.textPrimary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(AudiaTheme.textPrimary.opacity(0.12)))
                    }
                    .buttonStyle(BouncyScaleButtonStyle(scale: 0.92))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: np.videoId) {
            await loadLyricsForCurrentSong()
        }
        .onChange(of: showTranslation) { _, newValue in
            guard newValue, let vid = np.videoId, let current = result, !current.lines.isEmpty else { return }
            if !current.lines.contains(where: { $0.translatedText != nil }) {
                Task {
                    await performTranslation(videoId: vid, lines: current.lines)
                }
            }
        }
    }

    @ViewBuilder
    private func lyricRow(line: LyricLine, index: Int, isSynced: Bool) -> some View {
        let isActive = !isSynced || activeLineIndex == index
        let distance = activeLineIndex.map { abs($0 - index) } ?? 0
        let blurRadius: CGFloat = {
            guard isSynced, !isUserScrolling, !isActive else { return 0 }
            return distance == 1 ? 0.55 : 1.4
        }()
        let textOpacity: Double = {
            if !isSynced { return 0.95 }
            if isUserScrolling { return isActive ? 1.0 : 0.65 }
            return isActive ? 1.0 : (distance == 1 ? 0.40 : 0.28)
        }()

        VStack(alignment: .leading, spacing: 6) {
            Text(line.text)
                .font(.satoshi(size: 27, weight: .bold))
                .lineSpacing(2)
                .foregroundStyle(AudiaTheme.textPrimary.opacity(textOpacity))
                .shadow(color: (isActive && colorScheme == .dark) ? .white.opacity(0.22) : .clear, radius: 10, y: 0)
                .multilineTextAlignment(.leading)

            if showTranslation, let translated = line.translatedText, !translated.isEmpty {
                Text(translated)
                    .font(.satoshi(size: 16, weight: .medium))
                    .lineSpacing(1.5)
                    .foregroundStyle(AudiaTheme.textPrimary.opacity(isActive ? 0.78 : (isUserScrolling ? 0.5 : 0.3)))
                    .multilineTextAlignment(.leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blur(radius: blurRadius)
        .scaleEffect(isSynced ? (isActive ? 1.0 : 0.95) : 1.0, anchor: .leading)
        .animation(.spring(response: 0.55, dampingFraction: 0.84), value: activeLineIndex)
        .animation(.easeInOut(duration: 0.25), value: showTranslation)
        .animation(.easeInOut(duration: 0.25), value: isUserScrolling)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isSynced, let time = line.time else { return }
            Haptics.selection()
            userScrolledAt = nil
            isUserScrolling = false
            player.seek(to: time)
            np.currentTime = time
            player.updateNowPlayingProgress()
        }
    }

    private func loadLyricsForCurrentSong() async {
        guard let vid = np.videoId, !vid.isEmpty else {
            result = nil
            hasLyrics = false
            return
        }
        isLoading = true
        let fetched = await LyricsService.shared.fetchLyrics(
            videoId: vid,
            title: np.title,
            artist: np.displayArtist,
            duration: np.duration
        )
        result = fetched
        hasLyrics = (fetched?.lines.isEmpty == false)
        isLoading = false

        if showTranslation, let fetched, !fetched.lines.isEmpty {
            await performTranslation(videoId: vid, lines: fetched.lines)
        }
    }

    private func performTranslation(videoId: String, lines: [LyricLine]) async {
        isTranslating = true
        let translated = await LyricsService.shared.translateLines(videoId: videoId, lines: lines)
        if np.videoId == videoId, var current = result {
            current.lines = translated
            result = current
        }
        isTranslating = false
    }
}

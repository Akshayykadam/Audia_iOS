//
//  HistoryView.swift
//  Audia
//

import SwiftUI

struct HistoryScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @State private var viewModel = HistoryView()
    @State private var isSelecting = false
    @State private var selectedEvents: Set<Event> = []

    private var displayableSections: [(title: String, entries: [DatabaseService.HistoryEntry])] {
        viewModel.groupedEntries.filter { !$0.entries.isEmpty }
    }

    private var allEvents: [Event] {
        displayableSections.flatMap(\.entries).map(\.event)
    }

    private var allDisplayableSongs: [SongItem] {
        displayableSections.flatMap(\.entries).map { entry in
            if let entity = entry.song {
                return SongItem(entity: entity)
            } else {
                return SongItem(
                    videoId: entry.event.songId,
                    title: entry.event.songId,
                    artists: [],
                    album: nil,
                    albumId: nil,
                    duration: 0,
                    thumbnailUrl: ArtworkURLs.fallback(for: entry.event.songId),
                    isExplicit: false,
                    playlistId: nil
                )
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if viewModel.isLoading {
                    LoadingStateView("Loading history...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    localHistoryContent
                }
            }

            customTopBar
        }
        .audiaScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
    }

    private var customTopBar: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.light()
                if isSelecting {
                    isSelecting = false
                    selectedEvents.removeAll()
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: isSelecting ? "xmark" : "chevron.left")
                    .font(.satoshi(size: 16, weight: .semibold))
                    .foregroundStyle(AudiaTheme.textPrimary)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
                    .audiaGlassCircle()
            }
            .buttonStyle(BouncyScaleButtonStyle(scale: 0.9))
            .accessibilityLabel(isSelecting ? "Cancel selection" : "Back")

            Text(isSelecting ? "\(selectedEvents.count) selected" : "History")
                .font(.satoshi(size: 20, weight: .bold))
                .foregroundStyle(AudiaTheme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .audiaGlassCapsule(isInteractive: false)

            Spacer()

            if !displayableSections.isEmpty {
                if isSelecting {
                    Button {
                        Haptics.selection()
                        if selectedEvents.count == allEvents.count {
                            selectedEvents.removeAll()
                        } else {
                            selectedEvents = Set(allEvents)
                        }
                    } label: {
                        Text(selectedEvents.count == allEvents.count ? "Deselect All" : "Select All")
                            .font(.satoshi(size: 14, weight: .semibold))
                            .foregroundStyle(AudiaTheme.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .contentShape(Capsule())
                            .audiaGlassCapsule()
                    }
                    .buttonStyle(BouncyScaleButtonStyle(scale: 0.94))

                    if !selectedEvents.isEmpty {
                        Button(role: .destructive) {
                            Haptics.medium()
                            Task {
                                await viewModel.deleteEvents(Array(selectedEvents))
                                selectedEvents.removeAll()
                                isSelecting = false
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.satoshi(size: 15, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(width: 40, height: 40)
                                .contentShape(Circle())
                                .audiaGlassCircle()
                        }
                        .buttonStyle(BouncyScaleButtonStyle(scale: 0.9))
                        .accessibilityLabel("Delete selected")
                    }
                } else {
                    Button {
                        Haptics.light()
                        isSelecting = true
                    } label: {
                        Text("Select")
                            .font(.satoshi(size: 14, weight: .semibold))
                            .foregroundStyle(AudiaTheme.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .contentShape(Capsule())
                            .audiaGlassCapsule()
                    }
                    .buttonStyle(BouncyScaleButtonStyle(scale: 0.94))
                }
            }
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

    // MARK: - Local

    private var localHistoryContent: some View {
        Group {
            if displayableSections.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Songs you play will appear here.")
                )
            } else {
                localList
            }
        }
    }

    private var localList: some View {
        List {
            ForEach(displayableSections.indices, id: \.self) { sectionIndex in
                let section = displayableSections[sectionIndex]
                Section {
                    ForEach(section.entries, id: \.event) { entry in
                        localRow(entry)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    Text(LocalizedStringKey(section.title))
                        .font(.satoshi(.title3))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .textCase(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 56, for: .scrollContent)
        .appListBottomClearance()
        .miniPlayerTracksScroll()
    }

    @ViewBuilder
    private func localRow(_ entry: DatabaseService.HistoryEntry) -> some View {
        let song: SongItem = {
            if let entity = entry.song {
                return SongItem(entity: entity)
            } else {
                return SongItem(
                    videoId: entry.event.songId,
                    title: entry.event.songId,
                    artists: [],
                    album: nil,
                    albumId: nil,
                    duration: 0,
                    thumbnailUrl: ArtworkURLs.fallback(for: entry.event.songId),
                    isExplicit: false,
                    playlistId: nil
                )
            }
        }()
        let allItems = allDisplayableSongs
        let isSelected = selectedEvents.contains(entry.event)
        HStack(spacing: 0) {
            if isSelecting {
                Button {
                    if isSelected {
                        selectedEvents.remove(entry.event)
                    } else {
                        selectedEvents.insert(entry.event)
                    }
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.satoshi(.title3))
                        .foregroundStyle(isSelected ? settings.accentColor : .secondary)
                        .padding(.leading, 16)
                        .padding(.trailing, 4)
                }
                .buttonStyle(.plain)
            }
            SongRowView(song: song, onTap: {
                if isSelecting {
                    if isSelected {
                        selectedEvents.remove(entry.event)
                    } else {
                        selectedEvents.insert(entry.event)
                    }
                } else {
                    PlaybackQueue.play(song, in: allItems, log: Log.historyView, context: "History play")
                }
            })
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    Task { await viewModel.deleteEvents([entry.event]) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

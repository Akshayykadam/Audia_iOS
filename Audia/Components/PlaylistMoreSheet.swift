//
//  PlaylistMoreSheet.swift
//  Audia
//

import SwiftUI

/// Actions menu content for Playlist popup Menu.
struct PlaylistMenuActionsView: View {
    let playlist: PlaylistDetailInfo
    var onEdit: () -> Void
    var onDelete: (() -> Void)? = nil

    @ObservedObject private var downloadManager = DownloadManager.shared

    var body: some View {
        Group {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                let np = NowPlaying.shared
                np.queueSongs.append(contentsOf: playlist.songs)
                np.persistQueueState()
            } label: {
                Label("Add to Queue", systemImage: "text.badge.plus")
            }

            Button {
                for song in playlist.songs {
                    Task { await downloadManager.download(song: song) }
                }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }

            Divider()

            Button {
                if let shareUrl = URL.playlistShareURL(id: playlist.playlistId) {
                    presentShareSheet(items: [shareUrl])
                } else {
                    presentShareSheet(items: [playlist.title])
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            if let onDelete {
                Divider()

                Button {
                    onDelete()
                } label: {
                    Label("Delete Playlist", systemImage: "trash")
                }
            }
        }
    }
}

struct PlaylistMoreSheet: View {
    let playlist: PlaylistDetailInfo
    var onSync: (() -> Void)?
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showEditAlert = false
    @State private var editedName = ""

    var body: some View {
        SheetChrome {
            MenuCard {
                MenuRow(
                    icon: "pencil",
                    title: "Edit",
                    subtitle: "Edit playlist"
                ) {
                    editedName = playlist.title
                    showEditAlert = true
                }
                Divider()
                MenuRow(
                    icon: "list.bullet",
                    title: "Add to Queue",
                    subtitle: "Add to the end of the queue"
                ) {
                    addToQueue()
                    dismiss()
                }
                Divider()
                MenuRow(
                    icon: "square.and.arrow.down",
                    title: "Download",
                    subtitle: "Download all songs for offline playback"
                ) {
                    downloadAll()
                    dismiss()
                }
                Divider()
                MenuRow(
                    icon: "square.and.arrow.up",
                    title: "Share",
                    subtitle: "Share this playlist with others"
                ) {
                    share()
                    dismiss()
                }
                if let onDelete {
                    Divider()
                    MenuRow(
                        icon: "trash",
                        title: "Delete Playlist",
                        subtitle: "Delete this playlist",
                        destructive: false
                    ) {
                        onDelete()
                        dismiss()
                    }
                }
            }
        }
        .textPrompt(
            "Rename Playlist",
            isPresented: $showEditAlert,
            placeholder: "Playlist name",
            text: $editedName,
            okTitle: "Rename",
            onOK: renamePlaylist
        )
    }

    // MARK: - Actions

    private func renamePlaylist() {
        let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != playlist.title else { return }
        Task {
            try? await SyncBridge.mutations.renamePlaylist(
                playlistId: playlist.playlistId,
                newName: name
            )
        }
    }

    private func addToQueue() {
        let np = NowPlaying.shared
        np.queueSongs.append(contentsOf: playlist.songs)
        np.persistQueueState()
    }

    private func downloadAll() {
        for song in playlist.songs {
            Task { await DownloadManager.shared.download(song: song) }
        }
    }

    private func share() {
        guard let url = URL.playlistShareURL(id: playlist.playlistId) else { return }
        presentShareSheet(items: [url])
        dismiss()
    }

    private func deleteAllDownloads() {
        let dm = DownloadManager.shared
        for song in playlist.songs {
            Task { await dm.delete(videoId: song.videoId) }
        }
    }
}

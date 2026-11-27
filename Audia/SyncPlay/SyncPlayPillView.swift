//
//  SyncPlayPillView.swift
//  Audia
//

import SwiftUI

struct SyncPlayPillView: View {
    @Environment(SettingsStore.self) private var settings
    private let syncPlay = SyncPlayManager.shared

    var body: some View {
        if let session = syncPlay.session {
            Button {
                Haptics.light()
                syncPlay.isModalPresented = true
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)

                    Image(systemName: "person.2.wave.2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(settings.accentColor)

                    Text("\(session.participants.count)")
                        .font(.satoshi(.caption, weight: .bold))
                        .foregroundStyle(AudiaTheme.textPrimary)

                    if !syncPlay.isHost {
                        Text(syncPlay.driftStatus.isInSync ? "Synced" : "\(syncPlay.driftStatus.driftMs)ms")
                            .font(.satoshi(.caption2, weight: .medium))
                            .foregroundStyle(AudiaTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .strokeBorder(settings.accentColor.opacity(0.35), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(BouncyScaleButtonStyle(scale: 0.94))
            .accessibilityLabel("Listen Together session, \(session.participants.count) participants")
        }
    }

    private var statusColor: Color {
        switch syncPlay.connectionState {
        case .connected:
            return syncPlay.driftStatus.isInSync || syncPlay.isHost ? .green : .orange
        case .connecting, .reconnecting:
            return .yellow
        case .disconnected, .failed:
            return .red
        }
    }
}

//
//  PlaybackControlsView.swift
//  Audia
//

import SwiftUI

/// Shuffle / play / more circular buttons shared by every detail header.
/// Canonicalizes on the PlaylistHeaderView styling (48/64pt, grouped
/// background, accent glow shadow).
struct PlaybackControlsView: View {
    var accent: Color = .accentColor
    var showsShuffle: Bool = true
    var showsMore: Bool = false
    var horizontalPadding: CGFloat = 16
    var onPlay: () -> Void
    var onShuffle: () -> Void = {}
    var onMore: () -> Void = {}
    var moreCustomView: AnyView? = nil

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.satoshi(size: 14, weight: .bold))
                    Text("Play")
                        .font(.satoshi(size: 15, weight: .bold))
                }
                .foregroundStyle(AudiaTheme.onPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(AudiaTheme.primary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play all")

            if showsShuffle {
                Button(action: onShuffle) {
                    Image(systemName: "shuffle")
                        .font(.satoshi(size: 16, weight: .semibold))
                        .foregroundStyle(AudiaTheme.textSecondary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(AudiaTheme.surfaceVariant))
                        .overlay(Circle().stroke(AudiaTheme.surfaceBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shuffle")
            }

            Spacer()

            if let moreCustomView {
                moreCustomView
            } else if showsMore {
                Button(action: onMore) {
                    Image(systemName: "ellipsis")
                        .font(.satoshi(size: 17, weight: .semibold))
                        .foregroundStyle(AudiaTheme.textSecondary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(AudiaTheme.surfaceVariant))
                        .overlay(Circle().stroke(AudiaTheme.surfaceBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More options")
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 4)
    }
}

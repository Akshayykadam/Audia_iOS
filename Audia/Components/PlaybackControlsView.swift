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
    var compactPlay: Bool = false
    var horizontalPadding: CGFloat = 16
    var onPlay: () -> Void
    var onShuffle: () -> Void = {}
    var onMore: () -> Void = {}
    var secondaryActions: AnyView? = nil
    var moreCustomView: AnyView? = nil

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.light()
                onPlay()
            } label: {
                if compactPlay {
                    Image(systemName: "play.fill")
                        .font(.satoshi(size: 15, weight: .bold))
                        .foregroundStyle(AudiaTheme.textPrimary)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                        .audiaGlassCircle()
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.satoshi(size: 14, weight: .bold))
                        Text("Play")
                            .font(.satoshi(size: 15, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(AudiaTheme.textPrimary)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .contentShape(Capsule())
                    .audiaGlassCapsule()
                }
            }
            .buttonStyle(BouncyScaleButtonStyle(scale: 0.94))
            .accessibilityLabel("Play all")

            if showsShuffle {
                Button {
                    Haptics.light()
                    onShuffle()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.satoshi(size: 16, weight: .semibold))
                        .foregroundStyle(AudiaTheme.textPrimary)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                        .audiaGlassCircle()
                }
                .buttonStyle(BouncyScaleButtonStyle(scale: 0.90))
                .accessibilityLabel("Shuffle")
            }

            if let secondaryActions {
                secondaryActions
            }

            Spacer()

            if let moreCustomView {
                moreCustomView
            } else if showsMore {
                Button {
                    Haptics.light()
                    onMore()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.satoshi(size: 17, weight: .semibold))
                        .foregroundStyle(AudiaTheme.textPrimary)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                        .audiaGlassCircle()
                }
                .buttonStyle(BouncyScaleButtonStyle(scale: 0.90))
                .accessibilityLabel("More options")
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 4)
    }
}

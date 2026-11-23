//
//  PlayerComponents.swift
//  Audia
//

import SwiftUI
import AVKit

// MARK: - ProgressBar
struct ProgressBar: View {
    @Binding var progress: Float
    let accentColor: Color
    let isPlaying: Bool
    let onEditingChanged: (Bool) -> Void
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let elapsedWidth = max(0, min(width, width * CGFloat(progress)))

            ZStack(alignment: .leading) {
                // Remaining track (unwatched)
                Capsule()
                    .fill(AudiaTheme.surfaceElevated)
                    .frame(height: isDragging ? 7 : 4.5)

                // Elapsed track (watched, marked)
                Capsule()
                    .fill(AudiaTheme.primary)
                    .frame(width: elapsedWidth, height: isDragging ? 7 : 4.5)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            Haptics.selection()
                        }
                        onEditingChanged(true)
                        let loc = value.location.x
                        let percent = max(0, min(1, loc / width))
                        progress = Float(percent)
                    }
                    .onEnded { _ in
                        isDragging = false
                        Haptics.light()
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 16)
    }
}

// MARK: - PlaybackControlsRow
struct PlayerPlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.medium()
            action()
        }) {
            ZStack {
                Circle()
                    .fill(AudiaTheme.primary)
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.black.opacity(0.4), radius: 8, y: 3)

                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.satoshi(size: 26, weight: .bold))
                    .foregroundStyle(AudiaTheme.onPrimary)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(BouncyScaleButtonStyle(scale: 0.90))
        .frame(width: 72, height: 72)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

struct PlaybackControlsRow: View {
    let isPlaying: Bool
    let hasPrevious: Bool
    let hasNext: Bool
    var isShuffle: Bool = false
    var isLiked: Bool = false

    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    var onShuffle: (() -> Void)? = nil
    var onLike: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            Button(action: {
                Haptics.light()
                onShuffle?()
            }) {
                Image(systemName: "shuffle")
                    .font(.satoshi(size: 19, weight: .semibold))
                    .foregroundStyle(isShuffle ? AudiaTheme.primary : AudiaTheme.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(BouncyScaleButtonStyle(scale: 0.85))
            .frame(maxWidth: .infinity)

            Button(action: {
                Haptics.light()
                onPrevious()
            }) {
                Image(systemName: "backward.end.fill")
                    .font(.satoshi(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(BouncyScaleButtonStyle(scale: 0.85))
            .disabled(!hasPrevious)
            .opacity(hasPrevious ? 1 : 0.35)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Previous")

            PlayerPlayPauseButton(isPlaying: isPlaying, action: onPlayPause)
                .frame(maxWidth: .infinity)

            Button(action: {
                Haptics.light()
                onNext()
            }) {
                Image(systemName: "forward.end.fill")
                    .font(.satoshi(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(BouncyScaleButtonStyle(scale: 0.85))
            .disabled(!hasNext)
            .opacity(hasNext ? 1 : 0.35)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Next")

            Button(action: {
                Haptics.success()
                onLike?()
            }) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.satoshi(size: 21, weight: .medium))
                    .foregroundStyle(isLiked ? AudiaTheme.primary : AudiaTheme.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(BouncyScaleButtonStyle(scale: 0.82))
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Like")
        }
        .padding(.horizontal, 16)
    }
}

struct PlayerTransportAirPlayFooter: View {
    let isPlaying: Bool
    let hasPrevious: Bool
    let hasNext: Bool
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PlaybackControlsRow(
                isPlaying: isPlaying,
                hasPrevious: hasPrevious,
                hasNext: hasNext,
                onPrevious: onPrevious,
                onPlayPause: onPlayPause,
                onNext: onNext
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPlaying)

            HStack {
                Spacer()
                PlayerAirPlayControl()
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
    }
}

// MARK: - SecondaryActionsRow
struct SecondaryActionsRow: View {
    @Binding var showQueue: Bool
    @Binding var isRepeatOn: Bool

    var body: some View {
        HStack(spacing: 0) {
            PlayerAirPlayControl()
                .frame(maxWidth: .infinity)

            // Queue + Repeat stacked like Apple Music
            ZStack(alignment: .topTrailing) {
                Button {
                    showQueue.toggle()
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.satoshi(.title3))
                        .foregroundStyle(showQueue ? .white : .white.opacity(0.7))
                        .padding(10)
                        .background(showQueue ? Circle().fill(AudiaTheme.surfaceVariant) : Circle().fill(.clear))
                        .overlay(showQueue ? Circle().stroke(AudiaTheme.surfaceBorder, lineWidth: 1) : nil)
                }
                .accessibilityLabel("Queue")

                if !showQueue {
                    Button {
                        isRepeatOn.toggle()
                    } label: {
                        Image(systemName: isRepeatOn ? "repeat.1" : "repeat")
                            .font(.satoshi(size: 15, weight: .semibold))
                            .foregroundStyle(isRepeatOn ? .white : .white.opacity(0.7))
                            .padding(4)
                    }
                    .offset(x: 2, y: -2)
                    .accessibilityLabel(isRepeatOn ? "Repeat one" : "Repeat all")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
    }
}

struct PlayerAirPlayControl: View {
    var body: some View {
        Button {} label: {
            Image(systemName: "airplayaudio")
                .font(.satoshi(.title3))
                .foregroundStyle(.white.opacity(0.7))
                .padding(10)
        }
        .overlay(AirPlayButton())
        .accessibilityLabel("AirPlay")
    }
}

// MARK: - AirPlayButton
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: UIViewRepresentableContext<Self>) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = UIColor.clear
        picker.activeTintColor = UIColor.clear
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: UIViewRepresentableContext<Self>) {}
}

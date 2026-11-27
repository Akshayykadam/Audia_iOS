//
//  TabHeaderView.swift
//  Audia
//

import SwiftUI

/// Shared large-title header with history and account buttons,
/// used by the Home and Library tabs.
struct TabHeaderView: View {
    let title: String
    var scrimHeight: CGFloat = 135
    var onSearch: (() -> Void)? = nil
    var onHistory: (() -> Void)? = nil
    var onAdd: (() -> Void)? = nil
    var showListenTogether: Bool = false
    var onAccount: () -> Void

    private var displayTitle: String {
        if title == "Home" {
            let hour = Calendar.current.component(.hour, from: Date())
            switch hour {
            case 5..<12: return "Good morning"
            case 12..<17: return "Good afternoon"
            default: return "Good evening"
            }
        }
        return title
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(displayTitle)
                .font(.satoshi(size: 20, weight: .bold))
                .foregroundStyle(AudiaTheme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .audiaGlassCapsule(isInteractive: false)

            Spacer()

            actionButtons
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
            .frame(height: scrimHeight)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                actionButtonsRow
            }
        } else {
            actionButtonsRow
        }
    }

    private var actionButtonsRow: some View {
        HStack(spacing: 8) {
            if let onSearch {
                glassCircleButton(systemName: "magnifyingglass", size: 17, label: "Search", action: onSearch)
            }

            if let onHistory {
                glassCircleButton(systemName: "clock.arrow.circlepath", size: 17, label: "History", action: onHistory)
            }

            if let onAdd {
                glassCircleButton(systemName: "plus", size: 18, label: "Add playlist", action: onAdd)
            }

            if showListenTogether {
                listenTogetherButton
            }

            glassCircleButton(systemName: "gearshape.fill", size: 17, label: "Settings", action: onAccount)
        }
    }

    private var listenTogetherButton: some View {
        let isActive = SyncPlayManager.shared.session != nil
        return Button {
            Haptics.light()
            SyncPlayManager.shared.isModalPresented = true
        } label: {
            Image(systemName: "person.2.wave.2.fill")
                .font(.satoshi(size: 15, weight: .semibold))
                .foregroundStyle(isActive ? Color.green : AudiaTheme.textPrimary)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
                .audiaGlassCircle(isActive: false)
        }
        .buttonStyle(BouncyScaleButtonStyle(scale: 0.9))
        .accessibilityLabel("Listen Together")
    }

    private func glassCircleButton(
        systemName: String,
        size: CGFloat,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.satoshi(size: size, weight: .semibold))
                .foregroundStyle(AudiaTheme.textPrimary)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
                .audiaGlassCircle()
        }
        .buttonStyle(BouncyScaleButtonStyle(scale: 0.9))
        .accessibilityLabel(label)
    }
}

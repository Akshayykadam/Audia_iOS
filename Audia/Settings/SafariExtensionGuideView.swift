//
//  SafariExtensionGuideView.swift
//  Audia
//

import SwiftUI
import UIKit

struct SafariExtensionGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "safari.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(AudiaTheme.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open in Audia Extension")
                                .font(.satoshi(size: 17, weight: .bold))
                                .foregroundStyle(AudiaTheme.textPrimary)
                            Text("Automatic YouTube Music link redirection")
                                .font(.satoshi(size: 13, weight: .regular))
                                .foregroundStyle(AudiaTheme.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Text("Because Apple reserves web link routing on iOS, links sent in WhatsApp, Messages, or Mail normally open Safari. With the **Open in Audia** Safari Extension enabled, any YouTube Music link tapped in Safari will immediately prompt you to jump straight into playback inside Audia.")
                        .font(.satoshi(size: 14, weight: .regular))
                        .foregroundStyle(AudiaTheme.textSecondary)
                        .lineSpacing(3)
                }
                .padding(.vertical, 6)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(AudiaTheme.primary)
                        Text("Any App (WhatsApp, Messages, etc.)")
                            .font(.satoshi(size: 15, weight: .bold))
                            .foregroundStyle(AudiaTheme.textPrimary)
                    }

                    Text("When a YouTube Music link is sent to you in any app:")
                        .font(.satoshi(size: 13, weight: .regular))
                        .foregroundStyle(AudiaTheme.textSecondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Tap and hold (or tap) the link and tap **Share**.")
                        Text("2. In the share sheet app list, tap **Audia**.")
                        Text("3. Audia opens and starts playback immediately!")
                    }
                    .font(.satoshi(size: 13, weight: .medium))
                    .foregroundStyle(AudiaTheme.textPrimary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Share Sheet Extension")
                    .font(.satoshi(size: 14, weight: .bold))
                    .foregroundStyle(AudiaTheme.textPrimary)
            } footer: {
                Text("The Share Sheet extension lets you jump directly from any messaging app into Audia.")
                    .font(.satoshi(size: 12, weight: .regular))
                    .foregroundStyle(AudiaTheme.textSecondary)
            }

            Section {
                instructionRow(
                    step: "1",
                    title: "Open iOS Settings",
                    detail: "Go to your iPhone's main Settings app."
                )

                instructionRow(
                    step: "2",
                    title: "Navigate to Safari",
                    detail: "Scroll down and tap Safari, then tap Extensions."
                )

                instructionRow(
                    step: "3",
                    title: "Enable 'Open in Audia'",
                    detail: "Turn on the toggle switch for Open in Audia."
                )

                instructionRow(
                    step: "4",
                    title: "Allow Permissions",
                    detail: "Under Permissions, set music.youtube.com and youtube.com to 'Always Allow'."
                )
            } header: {
                Text("Safari Extension Setup")
                    .font(.satoshi(size: 14, weight: .bold))
                    .foregroundStyle(AudiaTheme.textPrimary)
            }

            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Label("Open iOS Settings", systemImage: "gear")
                            .font(.satoshi(size: 15, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    if let url = URL(string: "https://music.youtube.com/watch?v=dQw4w9WgXcQ") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Label("Test in Safari", systemImage: "play.circle.fill")
                            .font(.satoshi(size: 15, weight: .medium))
                            .foregroundStyle(AudiaTheme.primary)
                        Spacer()
                        Image(systemName: "safari")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Actions")
                    .font(.satoshi(size: 14, weight: .bold))
                    .foregroundStyle(AudiaTheme.textPrimary)
            } footer: {
                Text("After enabling the extension, tap 'Test in Safari' to see the instant 'Open in Audia' prompt.")
                    .font(.satoshi(size: 12, weight: .regular))
                    .foregroundStyle(AudiaTheme.textSecondary)
            }
        }
        .navigationTitle("Link Opening & Extensions")
        .navigationBarTitleDisplayMode(.inline)
        .appListBottomClearance()
        .miniPlayerTracksScroll()
    }

    private func instructionRow(step: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(AudiaTheme.primary.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text(step)
                    .font(.satoshi(size: 14, weight: .bold))
                    .foregroundStyle(AudiaTheme.primary)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.satoshi(size: 15, weight: .semibold))
                    .foregroundStyle(AudiaTheme.textPrimary)
                Text(detail)
                    .font(.satoshi(size: 13, weight: .regular))
                    .foregroundStyle(AudiaTheme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

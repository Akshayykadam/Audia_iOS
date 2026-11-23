//
//  TabHeaderView.swift
//  Audia
//

import SwiftUI

/// Shared large-title header with history and account buttons,
/// used by the Home and Library tabs.
struct TabHeaderView: View {
    let title: String
    var onSearch: (() -> Void)? = nil
    var onHistory: (() -> Void)? = nil
    var onAdd: (() -> Void)? = nil
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
        HStack(alignment: .center) {
            Text(displayTitle)
                .font(.satoshi(size: 26, weight: .bold))
                .foregroundStyle(Color.white)
            Spacer()
            HStack(spacing: 16) {
                if let onSearch {
                    Button(action: onSearch) {
                        Image(systemName: "magnifyingglass")
                            .font(.satoshi(size: 19, weight: .medium))
                            .foregroundStyle(AudiaTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search")
                }

                if let onHistory {
                    Button(action: onHistory) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.satoshi(size: 19, weight: .medium))
                            .foregroundStyle(AudiaTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("History")
                }

                if let onAdd {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.satoshi(size: 20, weight: .medium))
                            .foregroundStyle(AudiaTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add playlist")
                }

                Button(action: onAccount) {
                    Image(systemName: "gearshape.fill")
                        .font(.satoshi(size: 19, weight: .medium))
                        .foregroundStyle(AudiaTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

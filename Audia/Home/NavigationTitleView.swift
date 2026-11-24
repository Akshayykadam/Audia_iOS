//
//  NavigationTitleView.swift
//  Audia
//

import SwiftUI

struct NavigationTitleView: View {
    var title: String
    var label: String?
    var thumbnailUrl: String?
    var onClick: (() -> Void)?

    var body: some View {
        Button(
            action: { onClick?() },
            label: {
                HStack(spacing: 10) {
                    if let thumbnailUrl {
                        AsyncImageView(url: thumbnailUrl)
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        if let label {
                            Text(LocalizedStringKey(label))
                                .font(.satoshi(.footnote, weight: .medium))
                                .foregroundColor(AudiaTheme.textSecondary)
                        }
                        Text(LocalizedStringKey(title))
                            .font(.satoshi(size: 21, weight: .bold))
                            .foregroundColor(AudiaTheme.textPrimary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if onClick != nil {
                        Image(systemName: "chevron.right")
                            .font(.satoshi(.subheadline, weight: .semibold))
                            .foregroundColor(AudiaTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        )
        .buttonStyle(.plain)
    }
}

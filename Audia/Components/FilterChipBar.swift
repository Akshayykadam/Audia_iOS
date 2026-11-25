//
//  FilterChipBar.swift
//  Audia
//

import SwiftUI

/// Horizontal scrollable row of capsule filter chips.
/// Replaces the duplicated chip rows in Home, Library and Search.
struct FilterChipBar<Item, ID: Hashable>: View {
    @Environment(SettingsStore.self) private var settings
    @Namespace private var chipNamespace
    let items: [Item]
    let id: KeyPath<Item, ID>
    let title: (Item) -> String
    let isSelected: (Item) -> Bool
    let onTap: (Item) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: id) { item in
                    let selected = isSelected(item)
                    Button {
                        if !selected {
                            Haptics.selection()
                        }
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                            onTap(item)
                        }
                    } label: {
                        Text(LocalizedStringKey(title(item)))
                            .font(.satoshi(size: 14.5, weight: selected ? .bold : .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background {
                                if selected {
                                    Capsule()
                                        .fill(AudiaTheme.primary)
                                        .matchedGeometryEffect(id: "selectedChipPill", in: chipNamespace)
                                } else {
                                    Capsule()
                                        .fill(AudiaTheme.surfaceVariant)
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(AudiaTheme.surfaceBorder, lineWidth: 1)
                                        )
                                }
                            }
                            .foregroundStyle(selected
                                ? AudiaTheme.onPrimary
                                : AudiaTheme.textPrimary)
                            .foregroundColor(selected
                                ? AudiaTheme.onPrimary
                                : AudiaTheme.textPrimary)
                    }
                    .buttonStyle(BouncyScaleButtonStyle(scale: 0.92))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

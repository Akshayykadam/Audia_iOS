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
            chipRow
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var chipRow: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                chipsHStack
            }
        } else {
            chipsHStack
        }
    }

    private var chipsHStack: some View {
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
                        .foregroundStyle(AudiaTheme.textPrimary)
                        .audiaGlassCapsule(isActive: selected)
                }
                .buttonStyle(BouncyScaleButtonStyle(scale: 0.92))
            }
        }
    }
}

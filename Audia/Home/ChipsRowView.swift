//
//  ChipsRowView.swift
//  Audia
//

import SwiftUI

struct ChipsRowView: View {
    var chips: [HomePage.Chip]
    var selectedChip: HomePage.Chip?
    var onChipTap: (HomePage.Chip) -> Void

    var body: some View {
        FilterChipBar(
            items: chips,
            id: \.title,
            title: \.title,
            isSelected: { chip in
                if chip.params == nil {
                    return selectedChip == nil || selectedChip?.title == "Home"
                }
                return selectedChip?.title == chip.title
            },
            onTap: onChipTap
        )
    }
}

//
//  SectionLabel.swift
//  Audia
//

import SwiftUI

struct SectionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(LocalizedStringKey(title), systemImage: systemImage)
            .font(.satoshi(.footnote, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .padding(.leading, 4)
            .padding(.bottom, 4)
    }
}

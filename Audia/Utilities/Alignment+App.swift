//
//  Alignment+App.swift
//  Audia
//

import SwiftUI

extension Alignment {
    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }
}

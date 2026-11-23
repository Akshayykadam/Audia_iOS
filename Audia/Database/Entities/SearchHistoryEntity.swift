//
//  SearchHistoryEntity.swift
//  Audia
//

import Foundation

struct SearchHistoryEntity: Codable, Hashable {
    var query: String
    var timestamp: Date
}

//
//  Double+App.swift
//  Audia
//

import Foundation

extension Double {
    /// Clamps to the 0...1 range used by volume and sliders.
    var clamped01: Double { min(1, max(0, self)) }
}

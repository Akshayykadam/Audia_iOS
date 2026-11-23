//
//  ButtonStyles.swift
//  Audia
//

import SwiftUI

/// Fluid spring press scale effect for interactive buttons (play/pause, tabs, controls, chips).
struct BouncyScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.92
    var pressedOpacity: CGFloat = 0.88

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

/// Subtle press feedback for list rows and song cells
struct SongRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.08 : 0.0))
            )
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

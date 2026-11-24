//
//  MoodCardView.swift
//  Audia
//

import SwiftUI

/// Compact browse card with an iconic vertical left accent stripe, ambient glow bleed,
/// bold leading typography, and mood-specific SF Symbol iconography.
struct MoodCardView: View {
    let mood: MoodItem

    var body: some View {
        let color = resolvedColor
        let iconName = resolvedIcon

        HStack(spacing: 0) {
            // Left vertical accent stripe with smooth rounded caps
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(color)
                .frame(width: 4.5)
                .padding(.vertical, 10)
                .padding(.leading, 7)

            // Mood title (leading-aligned, bold, multi-line capable)
            Text(LocalizedStringKey(mood.title))
                .font(.satoshi(size: 15, weight: .bold))
                .foregroundStyle(AudiaTheme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Mood-specific SF Symbol icon badge
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color.opacity(0.85))
                .frame(width: 28, height: 28)
                .padding(.trailing, 10)
        }
        .frame(width: 158, height: 60)
        .background(
            ZStack(alignment: .leading) {
                // Base surface
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AudiaTheme.surfaceVariant)

                // Soft ambient horizontal gradient radiating from the left stripe
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                color.opacity(0.20),
                                color.opacity(0.04),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            color.opacity(0.45),
                            AudiaTheme.surfaceBorder.opacity(0.7)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Color Resolution

    private var resolvedColor: Color {
        if let raw = mood.stripeColor {
            return Color(argb: raw)
        }
        return Self.fallbackColor(for: mood.title)
    }

    static func fallbackColor(for title: String) -> Color {
        let lower = title.lowercased()

        if lower.contains("chill") || lower.contains("relax") || lower.contains("ambient") || lower.contains("lo-fi") || lower.contains("lofi") || lower.contains("calm") {
            return Color(red: 0.16, green: 0.72, blue: 0.76) // Ice Teal
        }
        if lower.contains("energ") || lower.contains("workout") || lower.contains("gym") || lower.contains("pump") || lower.contains("fit") {
            return Color(red: 0.96, green: 0.36, blue: 0.20) // Coral Flame
        }
        if lower.contains("commute") || lower.contains("travel") || lower.contains("drive") || lower.contains("road") {
            return Color(red: 0.26, green: 0.58, blue: 0.94) // Transit Electric Blue
        }
        if lower.contains("feel good") || lower.contains("happy") || lower.contains("joy") || lower.contains("mood boost") || lower.contains("sun") {
            return Color(red: 0.98, green: 0.72, blue: 0.16) // Warm Amber Gold
        }
        if lower.contains("focus") || lower.contains("study") || lower.contains("work") || lower.contains("read") {
            return Color(red: 0.18, green: 0.78, blue: 0.46) // Emerald
        }
        if lower.contains("party") || lower.contains("dance") || lower.contains("club") || lower.contains("celebrat") {
            return Color(red: 0.72, green: 0.30, blue: 0.95) // Neon Violet
        }
        if lower.contains("romance") || lower.contains("love") || lower.contains("date") {
            return Color(red: 0.94, green: 0.32, blue: 0.56) // Warm Rose
        }
        if lower.contains("sleep") || lower.contains("bed") || lower.contains("night") || lower.contains("dream") {
            return Color(red: 0.44, green: 0.42, blue: 0.90) // Deep Midnight
        }
        if lower.contains("rock") || lower.contains("metal") || lower.contains("punk") {
            return Color(red: 0.92, green: 0.20, blue: 0.26) // Crimson
        }
        if lower.contains("pop") {
            return Color(red: 0.95, green: 0.26, blue: 0.66) // Vivid Magenta
        }
        if lower.contains("hip-hop") || lower.contains("hip hop") || lower.contains("rap") || lower.contains("r&b") || lower.contains("soul") {
            return Color(red: 0.92, green: 0.58, blue: 0.20) // Bronze Honey
        }
        if lower.contains("electronic") || lower.contains("edm") || lower.contains("techno") || lower.contains("house") {
            return Color(red: 0.12, green: 0.86, blue: 0.76) // Electric Cyan
        }
        if lower.contains("indie") || lower.contains("alternative") {
            return Color(red: 0.54, green: 0.76, blue: 0.46) // Sage
        }
        if lower.contains("classical") || lower.contains("acoustic") || lower.contains("piano") || lower.contains("instrumental") {
            return Color(red: 0.88, green: 0.76, blue: 0.48) // Champagne Gold
        }
        if lower.contains("jazz") || lower.contains("blues") {
            return Color(red: 0.86, green: 0.56, blue: 0.26) // Ochre Brass
        }
        if lower.contains("country") || lower.contains("folk") || lower.contains("americana") {
            return Color(red: 0.82, green: 0.48, blue: 0.28) // Terracotta
        }

        // Deterministic fallback palette from hash
        let palette: [Color] = [
            Color(red: 0.16, green: 0.72, blue: 0.76),
            Color(red: 0.96, green: 0.36, blue: 0.20),
            Color(red: 0.26, green: 0.58, blue: 0.94),
            Color(red: 0.98, green: 0.72, blue: 0.16),
            Color(red: 0.18, green: 0.78, blue: 0.46),
            Color(red: 0.72, green: 0.30, blue: 0.95),
            Color(red: 0.94, green: 0.32, blue: 0.56),
            Color(red: 0.44, green: 0.42, blue: 0.90),
            Color(red: 0.88, green: 0.60, blue: 0.22)
        ]
        let index = abs(title.hashValue) % palette.count
        return palette[index]
    }

    // MARK: - Icon Resolution

    private var resolvedIcon: String {
        let lower = mood.title.lowercased()

        if lower.contains("chill") || lower.contains("relax") || lower.contains("ambient") || lower.contains("lo-fi") || lower.contains("lofi") || lower.contains("calm") {
            return "moon.stars.fill"
        }
        if lower.contains("energ") {
            return "bolt.fill"
        }
        if lower.contains("workout") || lower.contains("gym") || lower.contains("pump") || lower.contains("fit") {
            return "flame.fill"
        }
        if lower.contains("commute") || lower.contains("travel") || lower.contains("drive") || lower.contains("road") {
            return "car.fill"
        }
        if lower.contains("feel good") || lower.contains("happy") || lower.contains("joy") || lower.contains("mood boost") || lower.contains("sun") {
            return "sun.max.fill"
        }
        if lower.contains("focus") || lower.contains("study") || lower.contains("work") || lower.contains("read") {
            return "headphones"
        }
        if lower.contains("party") || lower.contains("dance") || lower.contains("club") || lower.contains("celebrat") {
            return "speaker.wave.3.fill"
        }
        if lower.contains("romance") || lower.contains("love") || lower.contains("date") {
            return "heart.fill"
        }
        if lower.contains("sleep") || lower.contains("bed") || lower.contains("night") || lower.contains("dream") {
            return "bed.double.fill"
        }
        if lower.contains("rock") || lower.contains("metal") || lower.contains("punk") {
            return "guitars.fill"
        }
        if lower.contains("pop") {
            return "music.mic"
        }
        if lower.contains("hip-hop") || lower.contains("hip hop") || lower.contains("rap") || lower.contains("r&b") || lower.contains("soul") {
            return "waveform.path"
        }
        if lower.contains("electronic") || lower.contains("edm") || lower.contains("techno") || lower.contains("house") {
            return "opticaldisc.fill"
        }
        if lower.contains("classical") || lower.contains("piano") || lower.contains("instrumental") {
            return "pianokeys"
        }
        if lower.contains("jazz") || lower.contains("blues") {
            return "music.quarternote.3"
        }
        if lower.contains("country") || lower.contains("folk") {
            return "guitars"
        }

        return "music.note"
    }
}

// MARK: - Spring Press Animation

/// Smooth tactile spring scale effect for browse cards.
struct SpringPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - ARGB Color Support

extension Color {
    /// Creates a Color from a 32-bit ARGB unsigned integer.
    init(argb: UInt32) {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        let alpha = a > 0 ? a : 1.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

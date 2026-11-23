import CoreText
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public extension Font.Weight {
    func satoshiFontName(italic: Bool = false) -> String {
        let base: String
        switch self {
        case .ultraLight, .thin, .light:
            base = "Satoshi-Light"
        case .regular:
            base = "Satoshi-Regular"
        case .medium:
            base = "Satoshi-Medium"
        case .semibold, .bold:
            base = "Satoshi-Bold"
        case .heavy, .black:
            base = "Satoshi-Black"
        default:
            base = "Satoshi-Regular"
        }
        if italic {
            return base == "Satoshi-Regular" ? "Satoshi-Italic" : base + "Italic"
        }
        return base
    }

    var satoshiFontName: String {
        satoshiFontName(italic: false)
    }
}

public extension Font {
    static func satoshi(
        size: CGFloat,
        weight: Font.Weight = .regular,
        italic: Bool = false,
        relativeTo style: Font.TextStyle? = nil
    ) -> Font {
        let name = weight.satoshiFontName(italic: italic)
        if let style = style {
            return .custom(name, size: size, relativeTo: style)
        } else {
            return .custom(name, size: size)
        }
    }

    static func satoshi(
        _ style: Font.TextStyle,
        weight: Font.Weight = .regular,
        italic: Bool = false
    ) -> Font {
        let size: CGFloat
        switch style {
        case .largeTitle: size = 34
        case .title: size = 28
        case .title2: size = 24
        case .title3: size = 21
        case .headline: size = 18
        case .body: size = 17
        case .callout: size = 16
        case .subheadline: size = 15.5
        case .footnote: size = 14
        case .caption: size = 13.5
        case .caption2: size = 12.5
        @unknown default: size = 17
        }
        return .custom(weight.satoshiFontName(italic: italic), size: size, relativeTo: style)
    }

    // High-level semantic typography styles
    static var satoshiLargeTitle: Font { satoshi(.largeTitle, weight: .bold) }
    static var satoshiTitle: Font { satoshi(.title, weight: .bold) }
    static var satoshiTitle2: Font { satoshi(.title2, weight: .bold) }
    static var satoshiTitle3: Font { satoshi(.title3, weight: .semibold) }
    static var satoshiHeadline: Font { satoshi(.headline, weight: .semibold) }
    static var satoshiSubheadline: Font { satoshi(.subheadline, weight: .regular) }
    static var satoshiBody: Font { satoshi(.body, weight: .regular) }
    static var satoshiCallout: Font { satoshi(.callout, weight: .regular) }
    static var satoshiFootnote: Font { satoshi(.footnote, weight: .regular) }
    static var satoshiCaption: Font { satoshi(.caption, weight: .regular) }
    static var satoshiCaption2: Font { satoshi(.caption2, weight: .regular) }
}

#if canImport(UIKit)
public extension UIFont {
    static func satoshi(size: CGFloat, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont {
        let base: String
        switch weight {
        case .ultraLight, .thin, .light:
            base = "Satoshi-Light"
        case .regular:
            base = "Satoshi-Regular"
        case .medium:
            base = "Satoshi-Medium"
        case .semibold, .bold:
            base = "Satoshi-Bold"
        case .heavy, .black:
            base = "Satoshi-Black"
        default:
            base = "Satoshi-Regular"
        }
        let fontName = italic ? (base == "Satoshi-Regular" ? "Satoshi-Italic" : base + "Italic") : base
        return UIFont(name: fontName, size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)
    }
}
#endif

public enum SatoshiFontLoader {
    public static func registerFonts() {
        let fontNames = [
            "Satoshi-Regular",
            "Satoshi-Medium",
            "Satoshi-Bold",
            "Satoshi-Black",
            "Satoshi-Light",
            "Satoshi-Italic",
            "Satoshi-MediumItalic",
            "Satoshi-BoldItalic",
            "Satoshi-BlackItalic",
            "Satoshi-LightItalic"
        ]
        for name in fontNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "otf") ??
               Bundle.main.url(forResource: name, withExtension: "otf", subdirectory: "Fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }

        #if canImport(UIKit)
        DispatchQueue.main.async {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .black
            appearance.shadowColor = .clear
            if let largeFont = UIFont(name: "Satoshi-Bold", size: 32) {
                appearance.largeTitleTextAttributes = [.font: largeFont, .foregroundColor: UIColor.white]
            }
            if let inlineFont = UIFont(name: "Satoshi-Bold", size: 17) {
                appearance.titleTextAttributes = [.font: inlineFont, .foregroundColor: UIColor.white]
            }
            let barItemAppearance = UIBarButtonItemAppearance()
            if let buttonFont = UIFont(name: "Satoshi-Medium", size: 16) {
                barItemAppearance.normal.titleTextAttributes = [.font: buttonFont, .foregroundColor: UIColor.white]
            }
            appearance.buttonAppearance = barItemAppearance
            appearance.backButtonAppearance = barItemAppearance

            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            UINavigationBar.appearance().tintColor = .white
        }
        #endif
    }
}

public enum AudiaTheme {
    // MARK: - Monochrome AMOLED Brand Colors (Pure Black & White)
    public static let primary = Color.white // Solid Crisp White #FFFFFF
    public static let primaryDark = Color(white: 0.82) // #D1D1D1
    public static let primaryLight = Color.white
    public static let onPrimary = Color.black // Pure Pitch Black #000000 for high-contrast on white pills/buttons

    // MARK: - AMOLED Backgrounds (Pure Solid Pitch Black, Zero Translucency)
    public static let background = Color.black
    public static let backgroundGradient = Color.black
    
    // MARK: - Surfaces & Containers (Neutral Monochrome Grayscale, 0% Green Tint)
    public static let surface = Color(white: 0.08) // Solid dark neutral surface #141414
    public static let surfaceVariant = Color(white: 0.14) // Solid chip/card neutral #242424
    public static let surfaceElevated = Color(white: 0.20) // Solid elevated neutral #333333
    public static let surfaceBorder = Color(white: 0.18) // Solid neutral border #2E2E2E
    
    // MARK: - Typography Colors (Crisp Monochrome Grayscale)
    public static let textPrimary = Color.white
    public static let textSecondary = Color(white: 0.65) // Neutral crisp light gray #A6A6A6
    public static let textMuted = Color(white: 0.42) // Neutral muted gray #6B6B6B
    
    // MARK: - Corner Radii (Extra Smooth & Rounded Curves)
    public static let radiusThumb: CGFloat = 12
    public static let radiusSmall: CGFloat = 12
    public static let radiusMedium: CGFloat = 18
    public static let radiusCard: CGFloat = 22
    public static let radiusLarge: CGFloat = 28
    public static let radiusPill: CGFloat = 34
}

// Convenient View modifier to apply Audia screen canvas
public struct AudiaScreenBackground: ViewModifier {
    public init() {}
    public func body(content: Content) -> some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            content
                .font(.satoshi(.body))
        }
    }
}

public extension Font {
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }

    static func rounded(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

public extension View {
    func audiaScreenBackground() -> some View {
        modifier(AudiaScreenBackground())
    }
}

/// Solid AMOLED monochrome toggle style:
/// OFF: Neutral dark capsule with crisp white knob on left.
/// ON: Crisp solid white capsule with pitch black knob on right.
public struct AmoledToggleStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Color.white : AudiaTheme.surfaceVariant)
                    .frame(width: 48, height: 28)
                    .overlay(
                        Capsule()
                            .strokeBorder(configuration.isOn ? Color.clear : AudiaTheme.surfaceBorder, lineWidth: 1)
                    )

                Circle()
                    .fill(configuration.isOn ? Color.black : Color.white)
                    .frame(width: 22, height: 22)
                    .padding(.horizontal, 3)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isOn)
            .contentShape(Rectangle())
            .onTapGesture {
                configuration.isOn.toggle()
            }
        }
    }
}

public extension ToggleStyle where Self == AmoledToggleStyle {
    static var amoled: AmoledToggleStyle { AmoledToggleStyle() }
}

public extension Color {
    /// Returns black when the color is bright/white, and white when dark, ensuring readable contrast.
    var highContrastTextColor: Color {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var white: CGFloat = 0
        uiColor.getWhite(&white, alpha: nil)
        if white > 0.6 {
            return .black
        }
        return .white
        #else
        return .black
        #endif
    }
}

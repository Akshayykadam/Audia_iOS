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
            appearance.backgroundColor = UIColor { traits in
                traits.userInterfaceStyle == .light ? .systemBackground : .black
            }
            appearance.shadowColor = .clear
            let titleColor = UIColor { traits in
                traits.userInterfaceStyle == .light ? .label : .white
            }
            if let largeFont = UIFont(name: "Satoshi-Bold", size: 32) {
                appearance.largeTitleTextAttributes = [.font: largeFont, .foregroundColor: titleColor]
            }
            if let inlineFont = UIFont(name: "Satoshi-Bold", size: 17) {
                appearance.titleTextAttributes = [.font: inlineFont, .foregroundColor: titleColor]
            }
            let barItemAppearance = UIBarButtonItemAppearance()
            if let buttonFont = UIFont(name: "Satoshi-Medium", size: 16) {
                barItemAppearance.normal.titleTextAttributes = [.font: buttonFont, .foregroundColor: titleColor]
            }
            appearance.buttonAppearance = barItemAppearance
            appearance.backButtonAppearance = barItemAppearance

            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            UINavigationBar.appearance().tintColor = titleColor
        }
        #endif
    }
}

#if canImport(UIKit)
private func dynamicColor(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .light ? light : dark
    })
}
#endif

public enum AudiaTheme {
    // MARK: - Monochrome Brand Colors (Dynamic High-Contrast)
    #if canImport(UIKit)
    public static let primary = dynamicColor(
        light: UIColor.black,
        dark: UIColor.white
    )
    public static let primaryDark = dynamicColor(
        light: UIColor(white: 0.18, alpha: 1.0),
        dark: UIColor(white: 0.82, alpha: 1.0)
    )
    public static let primaryLight = dynamicColor(
        light: UIColor(white: 0.05, alpha: 1.0),
        dark: UIColor.white
    )
    public static let onPrimary = dynamicColor(
        light: UIColor.white,
        dark: UIColor.black
    )

    // MARK: - Backgrounds
    public static let background = dynamicColor(
        light: UIColor.systemBackground,
        dark: UIColor.black
    )
    public static let backgroundGradient = dynamicColor(
        light: UIColor.systemBackground,
        dark: UIColor.black
    )
    
    // MARK: - Surfaces & Containers
    public static let surface = dynamicColor(
        light: UIColor(white: 0.95, alpha: 1.0),
        dark: UIColor(white: 0.08, alpha: 1.0)
    )
    public static let surfaceVariant = dynamicColor(
        light: UIColor(white: 0.90, alpha: 1.0),
        dark: UIColor(white: 0.14, alpha: 1.0)
    )
    public static let surfaceElevated = dynamicColor(
        light: UIColor(white: 0.98, alpha: 1.0),
        dark: UIColor(white: 0.20, alpha: 1.0)
    )
    public static let surfaceBorder = dynamicColor(
        light: UIColor(white: 0.86, alpha: 1.0),
        dark: UIColor(white: 0.18, alpha: 1.0)
    )

    // MARK: - Sheets & Menus
    public static let sheetBackground = dynamicColor(
        light: UIColor(red: 242/255, green: 242/255, blue: 247/255, alpha: 1.0),
        dark: UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)
    )
    public static let sheetSurface = dynamicColor(
        light: UIColor.white,
        dark: UIColor(red: 44/255, green: 44/255, blue: 46/255, alpha: 1.0)
    )
    public static let sheetBorder = dynamicColor(
        light: UIColor(white: 0.88, alpha: 1.0),
        dark: UIColor(white: 0.28, alpha: 0.45)
    )
    public static let sheetTrack = dynamicColor(
        light: UIColor(white: 0.85, alpha: 1.0),
        dark: UIColor(white: 0.35, alpha: 1.0)
    )
    
    // MARK: - Typography Colors
    public static let textPrimary = dynamicColor(
        light: UIColor.black,
        dark: UIColor.white
    )
    public static let textSecondary = dynamicColor(
        light: UIColor(white: 0.42, alpha: 1.0),
        dark: UIColor(white: 0.65, alpha: 1.0)
    )
    public static let textMuted = dynamicColor(
        light: UIColor(white: 0.60, alpha: 1.0),
        dark: UIColor(white: 0.42, alpha: 1.0)
    )
    #else
    public static let primary = Color.white
    public static let primaryDark = Color(white: 0.82)
    public static let primaryLight = Color.white
    public static let onPrimary = Color.black

    public static let background = Color.black
    public static let backgroundGradient = Color.black
    
    public static let surface = Color(white: 0.08)
    public static let surfaceVariant = Color(white: 0.14)
    public static let surfaceElevated = Color(white: 0.20)
    public static let surfaceBorder = Color(white: 0.18)

    public static let sheetBackground = Color(red: 28/255, green: 28/255, blue: 30/255)
    public static let sheetSurface = Color(red: 44/255, green: 44/255, blue: 46/255)
    public static let sheetBorder = Color(white: 0.28).opacity(0.45)
    public static let sheetTrack = Color(white: 0.35)
    
    public static let textPrimary = Color.white
    public static let textSecondary = Color(white: 0.65)
    public static let textMuted = Color(white: 0.42)
    #endif
    
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
            AudiaTheme.background
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

/// Solid monochrome toggle style:
/// OFF: Neutral surface capsule with knob.
/// ON: High-contrast primary capsule with onPrimary knob.
public struct AmoledToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? AudiaTheme.primary : AudiaTheme.surfaceVariant)
                    .frame(width: 48, height: 28)
                    .overlay(
                        Capsule()
                            .strokeBorder(configuration.isOn ? Color.clear : AudiaTheme.surfaceBorder, lineWidth: 1)
                    )

                Circle()
                    .fill(configuration.isOn ? AudiaTheme.onPrimary : (colorScheme == .light ? AudiaTheme.textSecondary : Color.white))
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

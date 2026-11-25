//
//  View+App.swift
//  Audia
//

import SwiftUI

extension View {
    /// Keeps the mini player's inline layout in sync with this scroll container:
    /// collapsing when scrolled down and restoring when back at the top.
    func miniPlayerTracksScroll() -> some View {
        modifier(MiniPlayerInlineOnScrollModifier())
    }

    /// Registers standard DetailRoute navigation
    func detailRouteDestinations() -> some View {
        self.navigationDestination(for: DetailRoute.self) { route in
            DetailRouteDestinationView(route: route)
        }
    }

    /// Presents a DetailRoute destination in a NavigationStack
    func detailRouteSheet(item: Binding<DetailRoute?>) -> some View {
        self.sheet(item: item) { route in
            NavigationStack {
                DetailRouteDestinationView(route: route)
            }
        }
    }

    /// Standard sheet presentation: detents plus a visible drag indicator.
    func appSheetChrome(_ detents: Set<PresentationDetent> = [.medium, .large]) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .audiaSheetBackground()
            .font(.satoshi(.body))
    }

    /// Uses native iOS 26 Liquid Glass sheet background on iOS 26+, falling back to ultraThinMaterial.
    @ViewBuilder
    func audiaSheetBackground() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self.presentationBackground(.ultraThinMaterial)
        }
    }

    /// Dynamic bottom clearance for scrollable views, ensuring content can be scrolled
    /// past floating bottom chrome (AudiaSolidTabBar and MiniPlayerBarView).
    func appBottomClearance(isRootTab: Bool = false) -> some View {
        modifier(AppBottomClearanceModifier(isRootTab: isRootTab))
    }

    /// Dynamic bottom clearance for `List` containers, inserting an invisible bottom safe area inset.
    func appListBottomClearance(isRootTab: Bool = false) -> some View {
        modifier(AppListBottomClearanceModifier(isRootTab: isRootTab))
    }

    /// Circular iOS 26 Liquid Glass treatment with an ultra-thin material fallback.
    func audiaGlassCircle(isActive: Bool = false, isInteractive: Bool = false) -> some View {
        modifier(AudiaGlassCircleModifier(isActive: isActive, isInteractive: isInteractive))
    }

    /// Capsule iOS 26 Liquid Glass treatment with an ultra-thin material fallback.
    func audiaGlassCapsule(isActive: Bool = false, isInteractive: Bool = false) -> some View {
        modifier(AudiaGlassCapsuleModifier(isActive: isActive, isInteractive: isInteractive))
    }

    /// Rounded-rectangle iOS 26 Liquid Glass card treatment with an ultra-thin material fallback.
    func audiaGlassCard(cornerRadius: CGFloat = 16, isInteractive: Bool = false) -> some View {
        modifier(AudiaGlassCardModifier(cornerRadius: cornerRadius, isInteractive: isInteractive))
    }
}

struct AudiaGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var isInteractive: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    isInteractive ? .regular.interactive() : .regular,
                    in: shape
                )
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape.stroke(
                        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08),
                        lineWidth: 0.8
                    )
                )
        }
    }
}

struct AudiaGlassCapsuleModifier: ViewModifier {
    var isActive: Bool = false
    var isInteractive: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let tintColor: Color = colorScheme == .dark
            ? Color.white.opacity(0.28)
            : Color.black.opacity(0.14)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    isActive
                        ? .regular.tint(tintColor).interactive(isInteractive)
                        : .regular.interactive(isInteractive),
                    in: .capsule
                )
        } else {
            let fill = colorScheme == .dark
                ? Color.white.opacity(isActive ? 0.24 : 0.10)
                : Color.black.opacity(isActive ? 0.14 : 0.06)
            let stroke = colorScheme == .dark
                ? Color.white.opacity(isActive ? 0.36 : 0.14)
                : Color.black.opacity(isActive ? 0.22 : 0.10)
            content
                .background(
                    Capsule()
                        .fill(fill)
                        .background(.ultraThinMaterial, in: Capsule())
                )
                .overlay(
                    Capsule()
                        .stroke(stroke, lineWidth: 0.8)
                )
        }
    }
}

struct AudiaGlassCircleModifier: ViewModifier {
    var isActive: Bool = false
    var isInteractive: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let tintColor: Color = colorScheme == .dark
            ? Color.white.opacity(0.28)
            : Color.black.opacity(0.14)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    isActive
                        ? .regular.tint(tintColor).interactive(isInteractive)
                        : .regular.interactive(isInteractive),
                    in: .circle
                )
        } else {
            let fill = colorScheme == .dark
                ? Color.white.opacity(isActive ? 0.24 : 0.10)
                : Color.black.opacity(isActive ? 0.14 : 0.06)
            let stroke = colorScheme == .dark
                ? Color.white.opacity(isActive ? 0.36 : 0.14)
                : Color.black.opacity(isActive ? 0.22 : 0.10)
            content
                .background(
                    Circle()
                        .fill(fill)
                        .background(.ultraThinMaterial, in: Circle())
                )
                .overlay(
                    Circle()
                        .stroke(stroke, lineWidth: 0.8)
                )
        }
    }
}

/// Dynamic bottom clearance for scrollable views (ScrollView / LazyVStack), ensuring content
/// can always be scrolled comfortably past the floating MiniPlayer and TabBar.
struct AppBottomClearanceModifier: ViewModifier {
    var isRootTab: Bool = false
    @ObservedObject private var router = AppRouter.shared

    func body(content: Content) -> some View {
        let isRoot = isRootTab && router.isAtRootTab
        let hasMiniPlayer = NowPlaying.shared.isBarPresented
        let clearance: CGFloat = isRoot
            ? (hasMiniPlayer ? 190 : 110)
            : (hasMiniPlayer ? 140 : 44)

        content
            .padding(.bottom, clearance)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: clearance)
    }
}

/// Dynamic bottom clearance for `List` containers, inserting an invisible bottom safe area inset.
struct AppListBottomClearanceModifier: ViewModifier {
    var isRootTab: Bool = false
    @ObservedObject private var router = AppRouter.shared

    func body(content: Content) -> some View {
        let isRoot = isRootTab && router.isAtRootTab
        let hasMiniPlayer = NowPlaying.shared.isBarPresented
        let clearance: CGFloat = isRoot
            ? (hasMiniPlayer ? 190 : 110)
            : (hasMiniPlayer ? 140 : 44)

        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: clearance)
                    .allowsHitTesting(false)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: clearance)
    }
}

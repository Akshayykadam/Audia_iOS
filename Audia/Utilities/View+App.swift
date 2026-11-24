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
            .presentationBackground(AudiaTheme.sheetBackground)
            .font(.satoshi(.body))
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

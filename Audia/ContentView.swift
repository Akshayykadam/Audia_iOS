//
//  ContentView.swift
//  Audia
//

import Combine
import SwiftUI

struct ContentView: View {
    @Environment(SettingsStore.self) private var settings
    @ObservedObject private var router = AppRouter.shared
    @State private var nowPlaying = NowPlaying.shared
    @State private var selectedTab = SettingsStore.shared.defaultTab
    @State private var isExpanded = false
    @State private var scrollState = MiniPlayerScrollState()

    var body: some View {
        GeometryReader { proxy in
            let bottomInset = proxy.safeAreaInsets.bottom
            let controlsBottomPadding: CGFloat = bottomInset > 0 ? 18 : 10

            ZStack(alignment: .bottom) {
                // Main Content Area (preserves scroll & state for each tab)
                ZStack {
                    HomeScreenView()
                        .opacity(selectedTab == 0 ? 1 : 0)
                        .allowsHitTesting(selectedTab == 0)

                    SearchView()
                        .opacity(selectedTab == 1 ? 1 : 0)
                        .allowsHitTesting(selectedTab == 1)

                    ExploreView()
                        .opacity(selectedTab == 2 ? 1 : 0)
                        .allowsHitTesting(selectedTab == 2)

                    LibraryView()
                        .opacity(selectedTab == 3 ? 1 : 0)
                        .allowsHitTesting(selectedTab == 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AudiaTheme.background.ignoresSafeArea())

                // Floating Controls: Solid Mini Player + Solid Audia Tab Bar (Zero Glass)
                // Tab bar is only shown on the root 4 tabs; Mini Player is shown on both
                // root tabs and detail/subpages whenever audio is loaded/playing.
                VStack(spacing: 8) {
                    if nowPlaying.isBarPresented {
                        MiniPlayerBarView(onExpand: {
                            UIApplication.shared.sendAction(
                                #selector(UIResponder.resignFirstResponder),
                                to: nil,
                                from: nil,
                                for: nil
                            )
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                isExpanded = true
                            }
                        })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if router.isAtRootTab {
                        AudiaSolidTabBar(selectedTab: $selectedTab)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, router.isAtRootTab ? controlsBottomPadding : (bottomInset > 0 ? bottomInset + 6 : 14))
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: router.isAtRootTab)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: router.isAtRootTab)
        .toggleStyle(.amoled)
        .preferredColorScheme(.dark)
        .overlay {
            if isExpanded {
                FullPlayerView(onCollapse: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        isExpanded = false
                    }
                })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(scrollState)
        .onAppear { AppRouter.shared.selectedTabIndex = selectedTab }
        .onChange(of: selectedTab) { _, newValue in
            AppRouter.shared.selectedTabIndex = newValue
        }
        .onReceive(AppRouter.shared.$activeRoute) { route in
            if route != nil {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    isExpanded = false
                }
            }
        }
        .onReceive(AppRouter.shared.$playerExpandToken.dropFirst()) { _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                isExpanded = true
            }
        }
        .onChange(of: router.selectedTabIndex) { _, newIndex in
            if selectedTab != newIndex {
                selectedTab = newIndex
            }
        }
        .onChange(of: selectedTab) { _, newIndex in
            if router.selectedTabIndex != newIndex {
                router.selectedTabIndex = newIndex
            }
        }
        .simultaneousGesture(backSwipeGesture)
        .font(.satoshi(.body))
    }

    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                guard !isExpanded,
                      value.startLocation.x <= 28,
                      isHorizontal,
                      value.translation.width > 80 else { return }

                let router = AppRouter.shared
                let depth = router.activePathDepth
                guard depth > 0 else { return }
                Haptics.light()
                router.popActiveRoute()
            }
    }
}

/// Solid AMOLED Tab Bar - completely opaque, zero liquid glass, minimal icon-only design
struct AudiaSolidTabBar: View {
    @Binding var selectedTab: Int

    var body: some View {
        HStack(spacing: 8) {
            tabButton(icon: "house", selectedIcon: "house.fill", index: 0)
            tabButton(icon: "magnifyingglass", selectedIcon: "magnifyingglass", index: 1)
            tabButton(icon: "square.grid.2x2", selectedIcon: "square.grid.2x2.fill", index: 2)
            tabButton(icon: "music.note.list", selectedIcon: "music.note.list", index: 3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(AudiaTheme.surface)
        )
        .overlay(
            Capsule()
                .stroke(AudiaTheme.surfaceBorder, lineWidth: 1.2)
        )
        .shadow(color: Color.black, radius: 16, y: 6)
    }

    private func tabButton(icon: String, selectedIcon: String, index: Int) -> some View {
        let isSelected = selectedTab == index
        return Button {
            if selectedTab != index {
                Haptics.selection()
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                selectedTab = index
            }
        } label: {
            ZStack {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(AudiaTheme.surfaceVariant)
                        .frame(width: 56, height: 40)
                }

                Image(systemName: isSelected ? selectedIcon : icon)
                    .font(.system(size: 23, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : AudiaTheme.textSecondary)
            }
            .frame(width: 56, height: 46)
        }
        .buttonStyle(BouncyScaleButtonStyle(scale: 0.88))
    }
}

#Preview {
    ContentView()
}

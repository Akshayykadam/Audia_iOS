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
    @State private var syncPlay = SyncPlayManager.shared
    @State private var selectedTab = 0
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
        .toggleStyle(.amoled)
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
            if router.selectedTabIndex != newValue {
                router.selectedTabIndex = newValue
            }
        }
        .onChange(of: router.selectedTabIndex) { _, newIndex in
            if selectedTab != newIndex {
                selectedTab = newIndex
            }
        }
        .onReceive(AppRouter.shared.$activeRoute) { route in
            if route != nil {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    isExpanded = false
                }
            }
        }
        .onReceive(AppRouter.shared.$playerExpandToken.dropFirst()) { _ in
            guard nowPlaying.isBarPresented else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                isExpanded = true
            }
        }
        .simultaneousGesture(backSwipeGesture)
        .font(.satoshi(.body))
        .overlay {
            if syncPlay.isModalPresented {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                syncPlay.isModalPresented = false
                            }
                        }

                    SyncPlayModalView()
                        .padding(.horizontal, 18)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                .zIndex(50)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: syncPlay.isModalPresented)
        .alert(
            "Listen Together",
            isPresented: Binding(
                get: { syncPlay.sessionTerminationNotice != nil },
                set: { if !$0 { syncPlay.dismissSessionTerminationNotice() } }
            )
        ) {
            Button("OK", role: .cancel) {
                syncPlay.dismissSessionTerminationNotice()
            }
        } message: {
            Text(syncPlay.sessionTerminationNotice ?? "")
        }
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

/// Solid Monochrome Tab Bar - completely opaque, minimal icon-only design
struct AudiaSolidTabBar: View {
    @Binding var selectedTab: Int
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var tabNamespace

    var body: some View {
        HStack(spacing: 8) {
            tabButton(icon: "house", selectedIcon: "house.fill", index: 0)
            tabButton(icon: "magnifyingglass", selectedIcon: "magnifyingglass", index: 1)
            tabButton(icon: "square.grid.2x2", selectedIcon: "square.grid.2x2.fill", index: 2)
            tabButton(icon: "music.note.list", selectedIcon: "music.note.list", index: 3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .audiaGlassCapsule()
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.08), radius: 16, y: 6)
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
                        .fill(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08))
                        .frame(width: 56, height: 40)
                        .matchedGeometryEffect(id: "activeTabPill", in: tabNamespace)
                }

                Image(systemName: isSelected ? selectedIcon : icon)
                    .font(.system(size: 23, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? AudiaTheme.textPrimary : AudiaTheme.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(isSelected ? 1.04 : 1.0)
            }
            .frame(width: 56, height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyScaleButtonStyle(scale: 0.88))
    }
}

#Preview {
    ContentView()
}

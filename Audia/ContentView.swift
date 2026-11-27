//
//  ContentView.swift
//  Audia
//

import Combine
import SwiftUI

struct ContentView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var router = AppRouter.shared
    @State private var nowPlaying = NowPlaying.shared
    @State private var syncPlay = SyncPlayManager.shared
    @State private var selectedTab = 0
    @State private var isExpanded = false
    @State private var scrollState = MiniPlayerScrollState()

    var body: some View {
        GeometryReader { proxy in
            let bottomInset = proxy.safeAreaInsets.bottom

            ZStack(alignment: .bottom) {
                if #available(iOS 26.0, *) {
                    TabView(selection: $selectedTab) {
                        Tab(value: 0) {
                            HomeScreenView()
                                .toolbarVisibility(router.isAtRootTab ? .visible : .hidden, for: .tabBar)
                        } label: {
                            Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                        }

                        Tab(value: 2) {
                            ExploreView()
                                .toolbarVisibility(router.isAtRootTab ? .visible : .hidden, for: .tabBar)
                        } label: {
                            Image(systemName: selectedTab == 2 ? "square.grid.2x2.fill" : "square.grid.2x2")
                        }

                        Tab(value: 3) {
                            LibraryView()
                                .toolbarVisibility(router.isAtRootTab ? .visible : .hidden, for: .tabBar)
                        } label: {
                            Image(systemName: "music.note.list")
                        }

                        Tab(value: 1, role: .search) {
                            SearchView()
                                .toolbarVisibility(router.isAtRootTab ? .visible : .hidden, for: .tabBar)
                        }
                    }
                    .tabBarMinimizeBehavior(.onScrollDown)
                    .tabViewBottomAccessory(isEnabled: nowPlaying.isBarPresented && router.isAtRootTab) {
                        MiniPlayerAccessoryWrapper(appColorScheme: colorScheme) {
                            UIApplication.shared.sendAction(
                                #selector(UIResponder.resignFirstResponder),
                                to: nil,
                                from: nil,
                                for: nil
                            )
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                isExpanded = true
                            }
                        }
                    }
                    .tint(settings.accentName == AccentPreset.all.first?.name ? (colorScheme == .dark ? Color.white : Color(red: 0.06, green: 0.06, blue: 0.06)) : settings.accentColor)
                    .background(TabBarSmoothTransitionInstaller())
                } else {
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
                }

                // Floating Mini Player on detail pages (or on iOS < 26)
                VStack(spacing: 8) {
                    if nowPlaying.isBarPresented && !router.isAtRootTab {
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

                    if #unavailable(iOS 26.0) {
                        if nowPlaying.isBarPresented && router.isAtRootTab {
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
                }
                .padding(.bottom, {
                    if #available(iOS 26.0, *) {
                        return bottomInset > 0 ? bottomInset + 6 : 14
                    } else {
                        let controlsBottomPadding: CGFloat = bottomInset > 0 ? 18 : 10
                        return router.isAtRootTab ? controlsBottomPadding : (bottomInset > 0 ? bottomInset + 6 : 14)
                    }
                }())
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
        .onChange(of: selectedTab) { oldValue, newValue in
            if oldValue != newValue {
                Haptics.selection()
            }
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

/// iOS 26 Liquid Glass floating tab bar with interactive sliding glass pill and detached Search circle button.
struct AudiaSolidTabBar: View {
    @Binding var selectedTab: Int
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @State private var dragLocationX: CGFloat?
    @State private var hoveredPillSlot: Int?

    private let pillTabs: [(index: Int, title: String, icon: String, selectedIcon: String)] = [
        (0, "Home", "house", "house.fill"),
        (2, "Explore", "square.grid.2x2", "square.grid.2x2.fill"),
        (3, "Library", "music.note.list", "music.note.list")
    ]
    private let itemWidth: CGFloat = 64
    private let itemSpacing: CGFloat = 4
    private let pillPadding: CGFloat = 5

    private var activeTint: Color {
        settings.accentName == AccentPreset.all.first?.name ? AudiaTheme.primary : settings.accentColor
    }

    private var selectedSlot: Int? {
        if let hoveredPillSlot { return hoveredPillSlot }
        return pillTabs.firstIndex(where: { $0.index == selectedTab })
    }

    private var sliderOffsetX: CGFloat? {
        let step = itemWidth + itemSpacing
        let maxOffset = step * CGFloat(pillTabs.count - 1)
        if let dragX = dragLocationX {
            let centered = dragX - pillPadding - itemWidth / 2
            return min(max(0, centered), maxOffset)
        }
        guard let slot = pillTabs.firstIndex(where: { $0.index == selectedTab }) else { return nil }
        return step * CGFloat(slot)
    }

    var body: some View {
        tabBarContent
    }

    private var tabBarContent: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                // Real iOS 26 Liquid Glass base bar (sized by invisible slot placeholders so icons stay on top & bubble isn't clipped)
                HStack(spacing: itemSpacing) {
                    ForEach(pillTabs, id: \.index) { _ in
                        Color.clear
                            .frame(width: itemWidth, height: 44)
                    }
                }
                .padding(pillPadding)
                .audiaGlassCapsule()
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.10), radius: 16, y: 6)

                // Sliding Liquid Glass lens bubble (unclipped, can overflow bar height while dragging)
                if let offsetX = sliderOffsetX {
                    let isDragging = dragLocationX != nil
                    let lensWidth = itemWidth + (isDragging ? 14 : 2)
                    let lensHeight: CGFloat = isDragging ? 60 : 44
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.26), Color.white.opacity(0.10)]
                                    : [Color.white.opacity(0.92), Color.white.opacity(0.60)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: lensWidth, height: lensHeight)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(colorScheme == .dark ? 0.70 : 1.0),
                                            Color.white.opacity(colorScheme == .dark ? 0.14 : 0.35),
                                            Color.white.opacity(colorScheme == .dark ? 0.42 : 0.80)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        )
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.14), radius: isDragging ? 10 : 5, y: 2)
                        .offset(x: pillPadding + offsetX - (isDragging ? 7 : 1))
                        .allowsHitTesting(false)
                        .animation(.spring(response: 0.26, dampingFraction: 0.76), value: offsetX)
                        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isDragging)
                }

                // Crisp icons always on top
                HStack(spacing: itemSpacing) {
                    ForEach(Array(pillTabs.enumerated()), id: \.element.index) { slot, item in
                        tabIcon(
                            slot: slot,
                            title: item.title,
                            icon: item.icon,
                            selectedIcon: item.selectedIcon
                        )
                    }
                }
                .padding(pillPadding)
            }
            .fixedSize(horizontal: true, vertical: true)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let slot = nearestSlot(forX: value.location.x)
                        if abs(value.translation.width) >= 6 || dragLocationX != nil {
                            dragLocationX = value.location.x
                        }
                        if hoveredPillSlot != slot {
                            hoveredPillSlot = slot
                            Haptics.selection()
                        }
                    }
                    .onEnded { value in
                        let slot = nearestSlot(forX: value.location.x)
                        let targetTab = pillTabs[slot].index
                        if selectedTab != targetTab && hoveredPillSlot == nil {
                            Haptics.selection()
                        }
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            dragLocationX = nil
                            hoveredPillSlot = nil
                            selectedTab = targetTab
                        }
                    }
            )

            searchCircleButton
        }
    }

    private func nearestSlot(forX x: CGFloat) -> Int {
        let step = itemWidth + itemSpacing
        let normalized = (x - pillPadding - itemWidth / 2) / step
        let slot = Int(normalized.rounded())
        return min(max(0, slot), pillTabs.count - 1)
    }

    private func tabIcon(slot: Int, title: String, icon: String, selectedIcon: String) -> some View {
        let isSelected = selectedSlot == slot
        return Image(systemName: isSelected ? selectedIcon : icon)
            .font(.system(size: 22, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? activeTint : AudiaTheme.textSecondary)
            .frame(width: itemWidth, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
    }

    private var searchCircleButton: some View {
        let isSelected = selectedTab == 1
        return Button {
            if selectedTab != 1 {
                Haptics.selection()
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                selectedTab = 1
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 21, weight: isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? activeTint : AudiaTheme.textPrimary)
                .frame(width: 54, height: 54)
                .background {
                    if isSelected {
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08))
                    }
                }
                .contentShape(Circle())
                .audiaGlassCircle()
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.10), radius: 16, y: 6)
        }
        .buttonStyle(BouncyScaleButtonStyle(scale: 0.90))
        .accessibilityLabel("Search")
    }
}

#Preview {
    ContentView()
}

@available(iOS 26.0, *)
private struct MiniPlayerAccessoryWrapper: View {
    let appColorScheme: ColorScheme
    let onExpand: () -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        MiniPlayerBarView(
            isAccessory: true,
            isCompactInline: placement == .inline,
            overrideColorScheme: appColorScheme,
            onExpand: onExpand
        )
    }
}

#if canImport(UIKit)
private struct TabBarSmoothTransitionInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        attachDelegate(from: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        attachDelegate(from: uiView, coordinator: context.coordinator)
    }

    private func attachDelegate(from view: UIView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            guard let tbc = findTabBarController(from: view) else { return }
            if tbc.delegate !== coordinator {
                coordinator.previousDelegate = tbc.delegate
                tbc.delegate = coordinator
            }
        }
    }

    private func findTabBarController(from view: UIView) -> UITabBarController? {
        var responder: UIResponder? = view
        while let next = responder?.next {
            if let tbc = next as? UITabBarController { return tbc }
            responder = next
        }
        return nil
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        weak var previousDelegate: UITabBarControllerDelegate?

        func tabBarController(
            _ tabBarController: UITabBarController,
            shouldSelect viewController: UIViewController
        ) -> Bool {
            if let prev = previousDelegate,
               prev.responds(to: #selector(UITabBarControllerDelegate.tabBarController(_:shouldSelect:))),
               prev.tabBarController?(tabBarController, shouldSelect: viewController) == false {
                return false
            }

            guard let fromView = tabBarController.selectedViewController?.view,
                  let toView = viewController.view,
                  fromView !== toView else {
                return true
            }

            UIView.transition(
                from: fromView,
                to: toView,
                duration: 0.18,
                options: [.transitionCrossDissolve, .allowUserInteraction],
                completion: nil
            )
            return true
        }
    }
}
#endif

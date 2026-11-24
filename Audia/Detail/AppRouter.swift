//
// AppRouter.swift
// Audia
//

import Combine
import SwiftUI

/// Owns each tab's NavigationPath so overlays (e.g. the Big Player menu) can
/// push detail pages onto the regular tab navigation. Appending to a path is
/// plain state mutation, so it works even while views are transitioning —
/// unlike pub/sub events, which tabs can miss during player teardown.
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var homePath: [DetailRoute] = []
    @Published var libraryPath: [DetailRoute] = []
    @Published var explorePath: [DetailRoute] = []
    @Published var searchPath: [DetailRoute] = []
    @Published var selectedTabIndex = 0
    @Published var settingsTargetSection: String? = nil

    /// Last route opened from an overlay; ContentView listens to collapse the player.
    @Published private(set) var activeRoute: DetailRoute?

    @Published private(set) var playerExpandToken = 0

    var isAtRootTab: Bool {
        activePathDepth == 0
    }

    var isSettingsActive: Bool {
        let currentPath: [DetailRoute]
        switch selectedTabIndex {
        case 1: currentPath = searchPath
        case 2: currentPath = explorePath
        case 3: currentPath = libraryPath
        default: currentPath = homePath
        }
        return currentPath.contains { route in
            if case .settings = route { return true }
            return false
        }
    }

    var activePathDepth: Int {
        switch selectedTabIndex {
        case 1: searchPath.count
        case 2: explorePath.count
        case 3: libraryPath.count
        default: homePath.count
        }
    }

    func popActiveRoute() {
        guard activePathDepth > 0 else { return }
        switch selectedTabIndex {
        case 1: searchPath.removeLast()
        case 2: explorePath.removeLast()
        case 3: libraryPath.removeLast()
        default: homePath.removeLast()
        }
    }

    func expandPlayer() {
        playerExpandToken += 1
    }

    func open(_ route: DetailRoute) {
        switch selectedTabIndex {
        case 1: searchPath.append(route)
        case 2: explorePath.append(route)
        case 3: libraryPath.append(route)
        default: homePath.append(route)
        }
        activeRoute = route
    }
}

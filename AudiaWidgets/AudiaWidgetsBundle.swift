//
//  AudiaWidgetsBundle.swift
//  AudiaWidgets
//

import SwiftUI
import WidgetKit

@main
struct AudiaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AudiaNowPlayingWidget()
        AudiaRecentlyPlayedWidget()
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            AudiaNowPlayingLiveActivity()
        }
        #endif
    }
}

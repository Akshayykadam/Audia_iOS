//
//  AboutSettingsView.swift
//  Audia
//

import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        List {
            Section {
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(build.map { "\(version) (\($0))" } ?? version)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Link(destination: URL(string: "https://github.com/Akshayykadam/Audia_iOS")!) {
                    Text("GitHub")
                }
            } header: {
                Text("Links")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .appListBottomClearance()
        .miniPlayerTracksScroll()
    }
}

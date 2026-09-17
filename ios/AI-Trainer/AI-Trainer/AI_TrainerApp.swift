//
//  AI_TrainerApp.swift
//  AI-Trainer
//
//  Created by Federico on 15.09.26.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct AI_TrainerApp: App {
    // Resolved once, before any tab's own .task can fire a request
    // against a possibly-dead cached address. See
    // ServerDiscovery.resolveBaseURL(): a quick /health probe first
    // (near-instant on the normal, unchanged-address day), a real
    // Bonjour browse only if that fails -- never the 60-second hang a
    // stale address would otherwise cause on the very first screen.
    @State private var backendReady = false

    init() {
        #if os(iOS)
        // Screen titles ("Today", "This Week", "Progress", "Coach")
        // are UIKit nav-bar text, not SwiftUI Text -- this is the one
        // way to actually restyle them. SF Rounded on both the large
        // and standard title, matching Theme.rounded() everywhere else
        // a "header" is drawn in SwiftUI directly.
        let largeDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
            .withDesign(.rounded)?
            .withSymbolicTraits(.traitBold) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
        let titleDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline)
            .withDesign(.rounded) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline)
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFont(descriptor: largeDescriptor, size: largeDescriptor.pointSize)
        ]
        UINavigationBar.appearance().titleTextAttributes = [
            .font: UIFont(descriptor: titleDescriptor, size: titleDescriptor.pointSize)
        ]
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if backendReady {
                    TabView {
                        TodayView()
                            .tabItem { Label("Today", systemImage: "sun.max") }
                        WeekView()
                            .tabItem { Label("Week", systemImage: "calendar") }
                        ProgressChartView()
                            .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                        ChatView()
                            .tabItem { Label("Coach", systemImage: "bubble.left.and.bubble.right") }
                    }
                } else {
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .appBackground()
                        .task {
                            APIClient.baseURL = await ServerDiscovery.resolveBaseURL(
                                candidate: APIClient.baseURL
                            )
                            backendReady = true
                        }
                }
            }
            .tint(Theme.accent)
            .preferredColorScheme(.dark)
        }
    }
}

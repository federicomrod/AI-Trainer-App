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
    enum LaunchState {
        case connecting
        /// Backend answered, or it didn't but we have something
        /// remembered worth showing -- either way the app opens.
        case open
        /// Nowhere to connect and nothing cached. The only state that
        /// has nothing to show, so it's the only one that gets an
        /// error screen instead of a black one.
        case unreachable
    }

    @State private var launchState: LaunchState = .connecting
    /// Bumped by the retry button so the connect task runs again even
    /// if SwiftUI reuses the same spinner view.
    @State private var retryToken = 0
    // nil until we've asked the server. Once asked: false means there's
    // no profile yet, so onboarding runs before anything else -- asking
    // the coach about a week it knows nothing about would produce
    // confident nonsense.
    @State private var isOnboarded: Bool?

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
                switch launchState {
                case .open where isOnboarded == false:
                    OnboardingView { isOnboarded = true }
                case .open:
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
                case .unreachable:
                    ConnectionErrorView(
                        host: Config.backendURL.host ?? Config.backendURL.absoluteString,
                        isRetrying: false
                    ) {
                        retryToken += 1
                        launchState = .connecting
                    }
                case .connecting:
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .appBackground()
                        .task(id: retryToken) { await connect() }
                }
            }
            .tint(Theme.accent)
            .preferredColorScheme(.dark)
        }
    }

    /// Work out where the backend is and what to show. Resolution is
    /// bounded (see ServerDiscovery.resolveBaseURL), so this always
    /// finishes -- the spinner is never the final state.
    private func connect() async {
        if let url = await ServerDiscovery.resolveBaseURL() {
            APIClient.baseURL = url
            ConnectionState.shared.markOnline(url)
            isOnboarded = await hasProfile()
            launchState = .open
            return
        }

        ConnectionState.shared.markOffline()
        // Nothing answered. Open anyway if there's something remembered
        // to show -- this morning's session, clearly marked stale, is
        // far more use than an error screen. Only a cold start with no
        // cache has genuinely nothing to offer.
        if Cache.load(TurnResponse.self, for: .today) != nil {
            isOnboarded = true
            launchState = .open
        } else {
            launchState = .unreachable
        }
    }

    /// If the server can't be reached at all, assume onboarding is
    /// already done: the tabs surface connection errors properly, while
    /// onboarding would wrongly imply the athlete's setup was lost.
    private func hasProfile() async -> Bool {
        do {
            return try await APIClient().fetchProfile().profile != nil
        } catch {
            return true
        }
    }
}

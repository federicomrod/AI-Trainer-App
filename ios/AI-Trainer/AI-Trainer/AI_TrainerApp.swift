//
//  AI_TrainerApp.swift
//  AI-Trainer
//
//  Created by Federico on 15.09.26.
//

import SwiftUI

@main
struct AI_TrainerApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                TodayView()
                    .tabItem { Label("Today", systemImage: "sun.max") }
                WeekView()
                    .tabItem { Label("Week", systemImage: "calendar") }
                ChatView()
                    .tabItem { Label("Coach", systemImage: "bubble.left.and.bubble.right") }
            }
        }
    }
}

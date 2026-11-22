//
//  MainTabView.swift
//  AI-Trainer
//
//  The four tabs plus a big lime mic in the middle of the bar. The mic
//  isn't a tab: it jumps to Coach and starts the existing voice input
//  there (ChatView's VoiceInputButton and SpeechRecognizer, unchanged).
//  A second tap finishes the take, which sends itself exactly as it
//  always has.
//
//  The system tab bar is hidden and this one drawn instead, because a
//  system TabView can't hold a raised centre button.

import SwiftUI

struct MainTabView: View {
    enum Tab: Int {
        case today = 0, week, progress, coach
    }

    /// Debug builds can start on a given tab with the launch argument
    /// `-startTab 2` (used to take screenshots).
    @State private var selected = Tab(rawValue: UserDefaults.standard.integer(forKey: "startTab")) ?? .today

    /// Coach's recognizer, owned here so the centre mic can start it
    /// and show that it's listening.
    @StateObject private var voice = SpeechRecognizer()

    var body: some View {
        // The bar sits below the screens in a stack, not on top of them
        // as a safe-area inset: an inset on the TabView did not reach
        // the Coach screen, so its typing box ended up under the bar.
        VStack(spacing: 0) {
            TabView(selection: $selected) {
                TodayView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.today)
                WeekView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.week)
                ProgressChartView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.progress)
                ChatView(voice: voice)
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.coach)
            }
            bar
        }
        .background(Theme.surface1.ignoresSafeArea(edges: .bottom))
    }

    private var bar: some View {
        HStack(alignment: .center, spacing: 0) {
            item(.today, "Today", "sun.max.fill")
            item(.week, "Week", "calendar")
            micButton
                .frame(maxWidth: .infinity)
            item(.progress, "Progress", "chart.bar.fill")
            item(.coach, "Coach", "bubble.left.and.bubble.right.fill")
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(
            Theme.surface1
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func item(_ tab: Tab, _ title: String, _ symbol: String) -> some View {
        let isSelected = selected == tab
        return Button {
            selected = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(height: 24)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Theme.accent : Theme.textMuted)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var micButton: some View {
        Button {
            selected = .coach
            voice.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(voice.isActive ? Color.red.opacity(0.85) : Theme.accent)
                    .frame(width: 64, height: 64)
                    .shadow(color: (voice.isActive ? Color.red : Theme.accent).opacity(0.35), radius: 12, y: 4)
                switch voice.phase {
                case .idle:
                    Image(systemName: "mic.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                case .starting, .finishing:
                    ProgressView().tint(Theme.onAccent)
                case .recording:
                    Image(systemName: "waveform")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                }
            }
            .offset(y: -14)
        }
        .buttonStyle(.plain)
        .disabled(voice.phase == .finishing)
        .accessibilityLabel(voice.isActive ? "Stop and send" : "Talk to the coach")
    }
}

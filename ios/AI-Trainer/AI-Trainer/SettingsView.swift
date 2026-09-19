//
//  SettingsView.swift
//  AI-Trainer
//
//  Integrations and how they work, plus what to do instead when
//  there's no API to integrate with. CLAUDE.md is explicit that
//  HealthKit is the one real integration (Garmin and Whoop both write
//  into it) and that Strava is excluded outright (their API terms
//  prohibit AI use). A sheet off Today, like Check-in/Log/Goals --
//  this is an occasional visit, not a screen to browse.

import Combine
import SwiftUI

struct SettingsView: View {
    @StateObject private var healthKit = HealthKitManager()
    @Environment(\.dismiss) private var dismiss
    @State private var accessKey = ""
    @State private var keySaved = false
    @State private var showingSetup = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    healthKitRow
                    if let message = healthKit.lastSyncMessage, healthKit.isAuthorized {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let error = healthKit.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Garmin, Whoop and Apple Watch all write workouts into Health, so this one connection covers most watches. Read-only -- nothing is ever written back. Only fills in days with nothing already planned or logged.")
                }

                Section {
                    Label("Strava isn't supported", systemImage: "xmark.circle")
                        .foregroundStyle(Theme.textPrimary)
                    Text("Their API terms don't allow AI use, so this app can't connect to it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                } header: {
                    Text("Other apps")
                }

                Section {
                    Text("No direct connection to Garmin Connect's own stats (VO2 max, training load, etc.) -- share a screenshot with the coach in chat instead and it'll read it directly.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                } header: {
                    Text("Everything else")
                }

                Section {
                    Button {
                        showingSetup = true
                    } label: {
                        Label("Redo setup", systemImage: "person.crop.circle.badge.checkmark")
                    }
                } header: {
                    Text("Your profile")
                } footer: {
                    Text("Goals, availability, equipment and your usual week. Replaces what's there now; your training history is kept.")
                }

                Section {
                    SecureField("Paste access key", text: $accessKey)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.textPrimary)
                    Button("Save key") {
                        BackendAuth.save(accessKey)
                        keySaved = true
                    }
                    .disabled(accessKey.isEmpty && BackendAuth.token == nil)
                    if keySaved {
                        Text("Saved. Restart the app to reconnect.")
                            .font(.footnote)
                            .foregroundStyle(Theme.accent)
                    }
                } header: {
                    Text("Backend access key")
                } footer: {
                    Text("Only needed if your coach backend runs on the internet and you've set HYBRID_COACH_API_KEY on it. Leave empty when running on your own computer. Stored on this phone only.")
                }

                Section {
                    NavigationLink {
                        DebugBriefingView()
                    } label: {
                        Label("Raw briefing", systemImage: "wrench.and.screwdriver")
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Debug tools, not meant for day-to-day use. Shows the actual text sent to the model, unfiltered.")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingSetup) {
                OnboardingView { showingSetup = false }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                // Just reflects whatever the system already knows --
                // doesn't prompt on its own. The prompt only happens
                // when the athlete taps Connect.
                healthKit.isAuthorized = UserDefaults.standard.bool(forKey: healthKitConnectedKey)
            }
        }
    }

    @ViewBuilder
    private var healthKitRow: some View {
        if healthKit.isAuthorized {
            HStack {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
                Spacer()
                Button("Sync now") {
                    Task { await healthKit.sync() }
                }
                .disabled(healthKit.isSyncing)
            }
        } else {
            Button {
                Task {
                    await healthKit.requestAuthorization()
                    UserDefaults.standard.set(healthKit.isAuthorized, forKey: healthKitConnectedKey)
                }
            } label: {
                Label("Connect Apple Health", systemImage: "heart.fill")
            }
            .disabled(healthKit.isSyncing || !healthKit.isAvailable)
        }
    }
}

private let healthKitConnectedKey = "healthKitConnected"

#Preview {
    SettingsView()
}

//
//  ConnectionErrorView.swift
//  AI-Trainer
//
//  What the app shows when it can't find the backend anywhere and has
//  no cached data to fall back on. The point is that this screen
//  exists at all: the alternative was a blank screen with a spinner
//  that never resolved, which tells the athlete nothing and offers
//  them nothing to do.
//
//  It names the address it tried, says the two things that are
//  actually wrong nine times out of ten, and has a button.

import SwiftUI

struct ConnectionErrorView: View {
    let host: String
    let isRetrying: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)

            Text("Can't reach your coach")
                .font(Theme.rounded(.title2, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("Nothing answered at \(host).")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                checkItem("Is the backend running on that machine?")
                checkItem("Is this phone on the same Wi-Fi?")
                checkItem("Local network access allowed for this app?")
            }

            Button(action: retry) {
                HStack {
                    Spacer()
                    if isRetrying {
                        ProgressView().tint(Theme.background)
                    } else {
                        Text("Try again")
                            .font(Theme.rounded(.headline, weight: .bold))
                    }
                    Spacer()
                }
                .padding()
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .foregroundStyle(Theme.background)
            }
            .buttonStyle(.plain)
            .disabled(isRetrying)

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .appBackground()
    }

    private func checkItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 7)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// The strip that sits at the top of a screen showing remembered data.
/// Stale data presented as current is worse than no data, so this
/// always says when the copy was taken.
struct OfflineBanner: View {
    let savedAt: Date?
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Offline — showing last known")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let savedAt {
                    Text(savedAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            Button("Retry", action: retry)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.cardElevated, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .padding(.horizontal)
    }
}

#Preview {
    ConnectionErrorView(host: "Federicos-Mac-mini.local", isRetrying: false, retry: {})
}

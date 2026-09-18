//
//  Cache.swift
//  AI-Trainer
//
//  Last-known-good copies of the few screens worth seeing when the
//  backend can't be reached. Opening to today's session from this
//  morning, clearly marked stale, beats opening to a spinner or an
//  empty screen -- the plan doesn't stop being useful because the
//  laptop went to sleep.
//
//  Deliberately small: JSON in UserDefaults, no database, no eviction
//  policy. These payloads are a few kilobytes and there is exactly one
//  of each.

import Combine
import Foundation

enum Cache {
    enum Key: String {
        case today = "cache.today"
        case week = "cache.week"
    }

    private static let savedAtSuffix = ".savedAt"

    static func save<T: Encodable>(_ value: T, for key: Key) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key.rawValue)
        UserDefaults.standard.set(Date(), forKey: key.rawValue + savedAtSuffix)
    }

    static func load<T: Decodable>(_ type: T.Type, for key: Key) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// When this copy was taken, for "last updated ..." on the offline
    /// banner. Stale data shown without a date is just wrong data.
    static func savedAt(_ key: Key) -> Date? {
        UserDefaults.standard.object(forKey: key.rawValue + savedAtSuffix) as? Date
    }
}

/// Whether the app currently believes it can reach the backend.
///
/// Shared because it's genuinely one fact about the process, and
/// because knowing it up front is what keeps the offline path quick:
/// a screen that already knows the host is unreachable renders its
/// cached copy immediately instead of sitting through another timeout
/// to rediscover the same thing.
@MainActor
final class ConnectionState: ObservableObject {
    static let shared = ConnectionState()

    @Published private(set) var isOffline = false
    /// The address actually in use, for the error screen to name.
    @Published private(set) var resolvedURL: URL?

    private init() {}

    func markOnline(_ url: URL) {
        resolvedURL = url
        isOffline = false
    }

    func markOffline() {
        isOffline = true
    }
}

//
//  HealthKitManager.swift
//  AI-Trainer
//
//  CLAUDE.md's tech decisions: HealthKit read-only, minimum
//  categories. Garmin/Whoop/Apple Watch all write into HealthKit
//  rather than exposing their own API, so reading just HKWorkoutType
//  here is the one integration that covers most watches -- nothing
//  else (sleep, heart rate, etc.) is requested. Imported workouts only
//  fill days with no session at all; see server/healthkit_import.py
//  for why and APIClient.importHealthKitWorkouts for the call.
//
//  #if os(iOS): this project's scheme can offer "My Mac" as a build
//  destination on Apple Silicon, and HealthKit doesn't exist there.

#if os(iOS)
import HealthKit
#endif
import Combine
import Foundation

@MainActor
final class HealthKitManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var isSyncing = false
    @Published var lastSyncMessage: String?
    @Published var errorMessage: String?

    #if os(iOS)
    private let store = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    #else
    var isAvailable: Bool { false }
    #endif

    /// How far back to look each sync. Generous enough to catch a
    /// missed week without re-scanning someone's whole history every
    /// time.
    private let daysBack = 14

    func requestAuthorization() async {
        #if os(iOS)
        guard isAvailable else {
            errorMessage = "Health data isn't available on this device."
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()])
            // HealthKit never tells a reader whether authorization was
            // actually granted, to keep the athlete's health data
            // private from the app itself -- only whether the prompt
            // was shown. isAuthorized here just means "the flow
            // completed"; a sync that comes back with nothing is the
            // only real signal of a denied read.
            isAuthorized = true
            errorMessage = nil
            await sync()
        } catch {
            errorMessage = error.localizedDescription
        }
        #else
        errorMessage = "Health data isn't available on this device."
        #endif
    }

    func sync() async {
        #if os(iOS)
        guard isAvailable else { return }
        isSyncing = true
        errorMessage = nil
        do {
            let workouts = try await fetchRecentWorkouts()
            let result = try await APIClient().importHealthKitWorkouts(workouts)
            lastSyncMessage = result.imported == 0
                ? "Nothing new to add."
                : "Added \(result.imported) session\(result.imported == 1 ? "" : "s") from Health."
        } catch {
            errorMessage = error.localizedDescription
        }
        isSyncing = false
        #endif
    }

    #if os(iOS)
    private func fetchRecentWorkouts() async throws -> [HealthKitWorkout] {
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let workouts = (samples as? [HKWorkout] ?? []).map { workout -> HealthKitWorkout in
                    let minutes = Int(workout.duration / 60)
                    let distanceKm = workout.totalDistance.map { $0.doubleValue(for: .meterUnit(with: .kilo)) }
                    let summary = distanceKm.map { String(format: "%.1f km", $0) }
                    return HealthKitWorkout(
                        date: isoDayFormatter.string(from: workout.startDate),
                        hkType: Self.hkTypeName(workout.workoutActivityType),
                        durationMin: minutes,
                        summary: summary
                    )
                }
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }

    /// Only the types server/healthkit_import.py actually recognizes
    /// need exact names -- anything else just needs a stable, non-
    /// matching string so the server skips it the same way it skips
    /// any other strength/other workout.
    private static func hkTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "running"
        case .cycling: return "cycling"
        case .swimming: return "swimming"
        case .highIntensityIntervalTraining: return "highIntensityIntervalTraining"
        default: return "other"
        }
    }
    #endif
}

//
//  FocusWorkoutSessionManager.swift
//  prenatalPregnancy
//
//  Created by Codex on 15/04/26.
//

import Foundation
import HealthKit
import CoreMotion
import ActivityKit

enum FocusWorkoutSessionState {
    case active
    case paused
    case stopped
}

struct FocusWorkoutStats: Equatable {
    var isConnected = false
    var heartRate: Int?
    var spo2: Int?
    var calories: Int?
    var steps: Int?
}

struct FocusWorkoutSnapshot {
    let routineItem: RoutineItem
    let elapsedSeconds: Int
    let totalSeconds: Int
    let state: FocusWorkoutSessionState
    let stats: FocusWorkoutStats
}

@available(iOS 16.1, *)
struct FocusWorkoutLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var totalSeconds: Int
        var heartRate: Int?
        var steps: Int?
        var state: String
        var displayText: String
    }

    var activityName: String
}

@MainActor
final class FocusWorkoutSessionManager {

    static let shared = FocusWorkoutSessionManager()

    private let healthTracker = FocusWorkoutHealthTracker()
    private var liveActivity: Any?
    private var observers: [UUID: (FocusWorkoutSnapshot) -> Void] = [:]

    private var timer: Timer?
    private var dataController: DataController?
    private var selectedDate: Date?
    private var routineItem: RoutineItem?
    private var stats = FocusWorkoutStats()

    private var state: FocusWorkoutSessionState = .stopped
    private var accumulatedElapsedSeconds = 0
    private var activeStartedAt: Date?
    private var didFinishSession = false

    private init() {
        healthTracker.onStatsChanged = { [weak self] stats in
            Task { @MainActor in
                self?.stats = stats
                self?.emitSnapshot()
                self?.updateLiveActivity()
            }
        }
    }

    func start(
        routineItem: RoutineItem,
        dataController: DataController,
        selectedDate: Date,
        initialElapsed: Int
    ) {
        if self.routineItem?.activityId == routineItem.activityId, state != .stopped {
            emitSnapshot()
            return
        }

        stopTimer()

        self.routineItem = routineItem
        self.dataController = dataController
        self.selectedDate = selectedDate
        self.accumulatedElapsedSeconds = initialElapsed
        self.activeStartedAt = Date()
        self.state = .active
        self.didFinishSession = false
        self.stats = FocusWorkoutStats()

        dataController.startWorkout(activityId: routineItem.activityId)
        healthTracker.start()
        startTimer()
        startLiveActivityIfNeeded()
        emitSnapshot()
    }

    func addObserver(_ observer: @escaping (FocusWorkoutSnapshot) -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        emitSnapshot(to: observer)
        return id
    }

    func removeObserver(_ id: UUID?) {
        guard let id else { return }
        observers.removeValue(forKey: id)
    }

    func pause() {
        guard state == .active else { return }
        accumulatedElapsedSeconds = currentElapsedSeconds()
        activeStartedAt = nil
        state = .paused
        stopTimer()
        saveProgress(status: .pending)
        emitSnapshot()
        updateLiveActivity()
    }

    func resume() {
        guard state == .paused else { return }
        activeStartedAt = Date()
        state = .active
        startTimer()
        emitSnapshot()
        updateLiveActivity()
    }

    func stop(saveAsCompleted: Bool = false, completion: (() -> Void)? = nil) {
        guard state != .stopped else {
            completion?()
            return
        }

        accumulatedElapsedSeconds = currentElapsedSeconds()
        activeStartedAt = nil
        state = .stopped
        didFinishSession = true
        stopTimer()
        healthTracker.stop()

        if saveAsCompleted {
            markCompleted()
            dataController?.stopWorkout { _ in }
        } else {
            saveProgress(status: .pending)
            dataController?.stopWorkout { _ in }
        }

        Task {
            await endLiveActivity()
            completion?()
        }

        emitSnapshot()
    }

    func skip() {
        state = .stopped
        didFinishSession = true
        stopTimer()
        healthTracker.stop()
        Task { await endLiveActivity() }
        emitSnapshot()
    }

    func startLiveActivityIfNeeded() {
        guard state != .stopped else { return }
        guard #available(iOS 16.1, *) else { return }
        guard liveActivity == nil, let routineItem else {
            updateLiveActivity()
            return
        }

        let attributes = FocusWorkoutLiveActivityAttributes(activityName: routineItem.routineType.displayTitle)
        let content = FocusWorkoutLiveActivityAttributes.ContentState(
            elapsedSeconds: currentElapsedSeconds(),
            totalSeconds: routineItem.durationSeconds,
            heartRate: stats.heartRate,
            steps: stats.steps,
            state: stateLabel,
            displayText: displayText(for: routineItem)
        )

        do {
            liveActivity = try Activity<FocusWorkoutLiveActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: content, staleDate: Date().addingTimeInterval(30)),
                pushType: nil
            )
        } catch {
            print("Live Activity request failed:", error)
        }
    }

    var isStopped: Bool {
        state == .stopped || didFinishSession
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.tick()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard state == .active else { return }

        saveProgress(status: .pending)
        emitSnapshot()
        updateLiveActivity()

        if currentElapsedSeconds() >= (routineItem?.durationSeconds ?? 0) {
            stop(saveAsCompleted: true)
        }
    }

    private func currentElapsedSeconds() -> Int {
        guard state == .active, let activeStartedAt else {
            return accumulatedElapsedSeconds
        }

        return accumulatedElapsedSeconds + Int(Date().timeIntervalSince(activeStartedAt))
    }

    private func saveProgress(status: RoutineItemStatus) {
        guard let routineItem, let selectedDate else { return }
        dataController?.saveProgress(
            for: routineItem,
            elapsedSeconds: min(currentElapsedSeconds(), routineItem.durationSeconds),
            status: status,
            date: selectedDate
        )
    }

    private func markCompleted() {
        guard var routineItem, let selectedDate else { return }
        dataController?.markItemCompleted(&routineItem, date: selectedDate)
        self.routineItem = routineItem
    }

    private func emitSnapshot() {
        observers.values.forEach { emitSnapshot(to: $0) }
    }

    private func emitSnapshot(to observer: (FocusWorkoutSnapshot) -> Void) {
        guard let routineItem else { return }
        observer(
            FocusWorkoutSnapshot(
                routineItem: routineItem,
                elapsedSeconds: min(currentElapsedSeconds(), routineItem.durationSeconds),
                totalSeconds: routineItem.durationSeconds,
                state: state,
                stats: stats
            )
        )
    }

    private var stateLabel: String {
        switch state {
        case .active: return "Active"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        }
    }

    private func updateLiveActivity() {
        guard #available(iOS 16.1, *) else { return }
        guard let activity = liveActivity as? Activity<FocusWorkoutLiveActivityAttributes>,
              let routineItem else { return }

        let content = FocusWorkoutLiveActivityAttributes.ContentState(
            elapsedSeconds: currentElapsedSeconds(),
            totalSeconds: routineItem.durationSeconds,
            heartRate: stats.heartRate,
            steps: stats.steps,
            state: stateLabel,
            displayText: displayText(for: routineItem)
        )

        Task {
            await activity.update(ActivityContent(state: content, staleDate: Date().addingTimeInterval(30)))
        }
    }

    private func endLiveActivity() async {
        guard #available(iOS 16.1, *) else { return }
        guard let activity = liveActivity as? Activity<FocusWorkoutLiveActivityAttributes> else { return }

        let content = FocusWorkoutLiveActivityAttributes.ContentState(
            elapsedSeconds: currentElapsedSeconds(),
            totalSeconds: routineItem?.durationSeconds ?? currentElapsedSeconds(),
            heartRate: stats.heartRate,
            steps: stats.steps,
            state: "Stopped",
            displayText: routineItem.map { displayText(for: $0) } ?? "Workout stopped"
        )

        await activity.end(ActivityContent(state: content, staleDate: nil), dismissalPolicy: .immediate)
        liveActivity = nil
    }

    private func displayText(for item: RoutineItem) -> String {
        let remaining = max(item.durationSeconds - currentElapsedSeconds(), 0)
        return "\(item.routineType.displayTitle) • \(formatTime(remaining)) left"
    }

    private func formatTime(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

final class FocusWorkoutHealthTracker {

    var onStatsChanged: ((FocusWorkoutStats) -> Void)?

    private let healthStore = HKHealthStore()
    private let pedometer = CMPedometer()
    private var pollingTimer: Timer?
    private var startDate = Date()
    private var stats = FocusWorkoutStats()

    func start() {
        startDate = Date()
        
        guard HealthManager.shared.canUseHealthKitQueries else {
            print("Focus workout using free fallback; HealthKit entitlement unavailable")
            stats = FocusWorkoutStats(isConnected: false)
            onStatsChanged?(stats)
            pollFreeFallback()
            startPolling()
            return
        }

        requestAuthorization { [weak self] success in
            guard let self else { return }
            guard success else {
                self.stats = FocusWorkoutStats(isConnected: false)
                self.onStatsChanged?(self.stats)
                self.pollFreeFallback()
                self.startPolling()
                return
            }
            self.stats = FocusWorkoutStats(isConnected: true)
            self.onStatsChanged?(self.stats)
            self.poll()
            self.startPolling()
        }
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            if HealthManager.shared.canUseHealthKitQueries {
                self?.poll()
            } else {
                self?.pollFreeFallback()
            }
        }
        RunLoop.main.add(pollingTimer!, forMode: .common)
    }

    private func requestAuthorization(completion: @escaping (Bool) -> Void) {
        HealthManager.shared.requestHealthAccess { success in
            completion(success)
        }
    }
    
    private func pollFreeFallback() {
        guard CMPedometer.isStepCountingAvailable() else {
            update {
                $0.heartRate = nil
                $0.spo2 = nil
                $0.calories = estimatedCalories(steps: nil, durationSeconds: Int(Date().timeIntervalSince(startDate)))
                $0.steps = nil
            }
            return
        }
        
        pedometer.queryPedometerData(from: startDate, to: Date()) { [weak self] data, error in
            guard let self else { return }
            
            if let error {
                print("Focus free fallback pedometer error:", error.localizedDescription)
            }
            
            let steps = data?.numberOfSteps.intValue
            let elapsed = Int(Date().timeIntervalSince(self.startDate))
            DispatchQueue.main.async {
                self.update {
                    $0.heartRate = nil
                    $0.spo2 = nil
                    $0.steps = steps
                    $0.calories = self.estimatedCalories(steps: steps, durationSeconds: elapsed)
                }
            }
        }
    }
    
    private func estimatedCalories(steps: Int?, durationSeconds: Int) -> Int? {
        if let steps, steps > 0 {
            return Int((Double(steps) * 0.04).rounded())
        }
        
        guard durationSeconds > 0 else { return nil }
        
        let defaultWeightKg = 70.0
        let gentleWalkingMET = 3.5
        let calories = gentleWalkingMET * defaultWeightKg * (Double(durationSeconds) / 3600.0)
        return Int(calories.rounded())
    }

    private func poll() {
        fetchLatest(.heartRate, unit: HKUnit(from: "count/min"), allowRecentFallback: true) { [weak self] value in
            self?.update { $0.heartRate = Int((value ?? 0).rounded()) }
        }

        fetchLatest(.oxygenSaturation, unit: .percent(), allowRecentFallback: true) { [weak self] value in
            self?.update { $0.spo2 = Int(((value ?? 0) * 100).rounded()) }
        }

        fetchSum(.activeEnergyBurned, unit: .kilocalorie()) { [weak self] value in
            self?.update { $0.calories = Int(value.rounded()) }
        }

        fetchSum(.stepCount, unit: .count()) { [weak self] value in
            self?.update { $0.steps = Int(value.rounded()) }
        }
    }

    private func update(_ mutation: (inout FocusWorkoutStats) -> Void) {
        mutation(&stats)
        DispatchQueue.main.async { [stats] in
            self.onStatsChanged?(stats)
        }
    }

    private func fetchLatest(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        allowRecentFallback: Bool = false,
        completion: @escaping (Double?) -> Void
    ) {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            completion(nil)
            return
        }

        let now = Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { [weak self] _, samples, _ in
            let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
            if value == nil, allowRecentFallback {
                self?.fetchRecentLatest(type: type, unit: unit, end: now, completion: completion)
                return
            }
            DispatchQueue.main.async {
                completion(value)
            }
        }

        healthStore.execute(query)
    }

    private func fetchRecentLatest(
        type: HKQuantityType,
        unit: HKUnit,
        end: Date,
        completion: @escaping (Double?) -> Void
    ) {
        let recentStart = Calendar.current.date(byAdding: .minute, value: -30, to: end) ?? end.addingTimeInterval(-1800)
        let predicate = HKQuery.predicateForSamples(withStart: recentStart, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
            let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
            DispatchQueue.main.async {
                completion(value)
            }
        }

        healthStore.execute(query)
    }

    private func fetchSum(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        completion: @escaping (Double) -> Void
    ) {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            completion(0)
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            let value = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
            DispatchQueue.main.async {
                completion(value)
            }
        }

        healthStore.execute(query)
    }
}

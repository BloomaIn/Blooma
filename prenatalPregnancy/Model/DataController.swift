//
//  DataModel.swift
//  prenatalPregnancy
//
//  Created by GEU on 30/01/26.
//

import Foundation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import FirebaseFirestore
import UIKit
import CoreMotion

struct HomeWeeklyProgressActivity {
    let routineType: RoutineType
    let category: String
    let name: String
    let value: Double
    let unit: String
    let goal: Double
    let goalUnit: String
    let progress: Double
    let color: UIColor
    let imageName: String
}

struct HomeWeeklyProgressSnapshot {
    let displayWeek: Int
    let overallPercent: Int
    let motivation: String
    let dayLabels: [String]
    let chartValues: [RoutineType: [Double]]
    let activities: [HomeWeeklyProgressActivity]
}

final class DataController {
    
    //Core Data
    
    var userProfile: UserProfile
    var currentUserId: String? {
        didSet {
            guard oldValue != currentUserId else { return }
            startProgressListener()
        }
    }
    private var lastAccessedDayKey: String?
    private var activeActivityId: String?
    var latestHealthVitals: ActivityExecutionRecord?
    
    var progressStore: [String: ActivityExecutionRecord] = [:]
    private var progressWeekIndex: [Int: [String: [String: ActivityExecutionRecord]]] = [:]
    
    private(set) var allActivities: [ActivityDefinition] = []
    private(set) var rotationHistory: [ActivityRotationRecord] = []
    private(set) var userFeedback: [UserFeedback] = []
    
    //Storage
    
    private var dailyRoutineStore: [String: [RoutineType: [RoutineItem]]] = [:]
    private let db = Firestore.firestore()
    private var progressListener: ListenerRegistration?
    
    private var activitySchedule: ActivitySchedule?
    
    static let progressDidChangeNotification = Notification.Name("DataController.progressDidChangeNotification")
    
    // Init
    
    init(userProfile: UserProfile) {
        self.userProfile = userProfile
        self.allActivities = ActivityLoader.loadActivities()
    }
    
    deinit {
        progressListener?.remove()
    }
    
    //Date Helpers
    
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    private func dayKey(_ date: Date) -> String {
        Self.dayKeyFormatter.string(from: date)
    }
    
    private func progressKey(activityId: String, date: Date) -> String {
        "\(activityId)_\(date.timeIntervalSince1970)"
    }
    
    private func progressEntry(activityId: String, on date: Date) -> (key: String, record: ActivityExecutionRecord)? {
        let exactKey = progressKey(activityId: activityId, date: date)
        if let exactRecord = progressStore[exactKey] {
            return (exactKey, exactRecord)
        }
        
        return progressStore
            .filter { _, record in
                record.activityId == activityId && dayKey(record.date) == dayKey(date)
            }
            .sorted { lhs, rhs in
                (lhs.value.endTime ?? lhs.value.date) > (rhs.value.endTime ?? rhs.value.date)
            }
            .first
            .map { (key: $0.key, record: $0.value) }
    }

    private func progressWeekDocumentId(for week: Int) -> String {
        "W\(max(1, min(week, 40)))"
    }

    private func firestoreRecordMapKey(for key: String) -> String {
        key
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }

    private func replaceProgressState(
        restored: [String: ActivityExecutionRecord],
        feedbackLookup: [UUID: UserFeedback]
    ) {
        progressStore = restored
        rebuildProgressWeekIndex()
        userFeedback = feedbackLookup.values.sorted { $0.createdAt > $1.createdAt }
        notifyProgressChanged()
    }

    private func rebuildProgressWeekIndex() {
        progressWeekIndex.removeAll()

        for (key, record) in progressStore {
            // NEW: Prefer the explicit Firestore week for Insights indexing.
            // This keeps graph data aligned with progress_weeks/Wxx even when
            // the local profile timeline has shifted after the record was saved.
            guard let week = record.firestoreWeek ?? gestationalWeek(for: record.date) else { continue }
            let keyForDay = dayKey(record.date)
            progressWeekIndex[week, default: [:]][keyForDay, default: [:]][key] = record
        }
    }

    private func weekRecords(for gestationalWeek: Int) -> [String: [String: ActivityExecutionRecord]] {
        progressWeekIndex[gestationalWeek] ?? [:]
    }
    
    private func removeProgressIndexEntry(for key: String) {
        for week in Array(progressWeekIndex.keys) {
            let dayKeys = progressWeekIndex[week].map { Array($0.keys) } ?? []
            
            for day in dayKeys {
                progressWeekIndex[week]?[day]?[key] = nil
                
                if progressWeekIndex[week]?[day]?.isEmpty == true {
                    progressWeekIndex[week]?[day] = nil
                }
            }
            
            if progressWeekIndex[week]?.isEmpty == true {
                progressWeekIndex[week] = nil
            }
        }
    }
    
    private func progressWeek(for date: Date) -> Int? {
        if dayKey(date) == dayKey(Date()) {
            return max(1, min(userProfile.gestationalWeek, 40))
        }
        
        return gestationalWeek(for: date)
    }
    
    private func pregnancyProgressDefaultsKey(_ suffix: String) -> String {
        let userKey = currentUserId ?? "guest"
        return "pregnancyProgress.\(userKey).\(suffix)"
    }
    
    func resetPregnancyProgressDayAnchor() {
        UserDefaults.standard.set(dayKey(Date()), forKey: pregnancyProgressDefaultsKey("lastDayKey"))
    }
    
    func refreshPregnancyProgressIfNeeded(referenceDate: Date = Date()) {
        let todayKey = dayKey(referenceDate)
        let defaultsKey = pregnancyProgressDefaultsKey("lastDayKey")
        let defaults = UserDefaults.standard
        
        guard let lastKey = defaults.string(forKey: defaultsKey), !lastKey.isEmpty else {
            defaults.set(todayKey, forKey: defaultsKey)
            return
        }
        
        guard lastKey != todayKey,
              let lastDate = Self.dayKeyFormatter.date(from: lastKey),
              let today = Self.dayKeyFormatter.date(from: todayKey) else {
            return
        }
        
        let elapsedDays = istCalendar.dateComponents([.day], from: lastDate, to: today).day ?? 0
        guard elapsedDays > 0 else { return }
        
        let totalDays = max(0, userProfile.gestationalDay + elapsedDays)
        userProfile.gestationalWeek = min(40, max(1, userProfile.gestationalWeek + (totalDays / 7)))
        userProfile.gestationalDay = totalDays % 7
        userProfile.trimester = PregnancyDateCalculation.trimester(for: userProfile.gestationalWeek)
        
        defaults.set(todayKey, forKey: defaultsKey)
        refreshProgressIndexesAfterProfileUpdate()
        saveProfileToFirestore()
    }

    // NEW: Rebuild the Insights week/day cache after the actual pregnancy
    // profile loads. The Firestore listener can start while the app still has
    // the placeholder profile, which can index valid records into the wrong
    // gestational week and leave the Insights cards at zero.
    func refreshProgressIndexesAfterProfileUpdate() {
        rebuildProgressWeekIndex()
        notifyProgressChanged()
    }

    private func progressWeekWritePayload(
        record: ActivityExecutionRecord,
        item: RoutineItem? = nil,
        feedback: UserFeedback? = nil,
        documentKey: String
    ) -> (documentId: String, data: [String: Any])? {
        refreshPregnancyProgressIfNeeded()
        
        guard let week = progressWeek(for: record.date) else { return nil }

        let safeDayKey = dayKey(record.date)
        let recordFieldKey = firestoreRecordMapKey(for: documentKey)
        let startOfDay = startOfDayInIST(for: record.date)
        var recordPayload = firestoreData(for: record, item: item, feedback: feedback)
        recordPayload["documentKey"] = documentKey
        recordPayload["week"] = week
        recordPayload["dayKey"] = safeDayKey

        let dayPrefix = "days.\(safeDayKey)"
        let recordPrefix = "\(dayPrefix).records.\(recordFieldKey)"

        return (
            documentId: progressWeekDocumentId(for: week),
            data: [
                "week": week,
                "updatedAt": FieldValue.serverTimestamp(),
                "\(dayPrefix).dayKey": safeDayKey,
                "\(dayPrefix).date": Timestamp(date: startOfDay),
                "\(dayPrefix).updatedAt": FieldValue.serverTimestamp(),
                recordPrefix: recordPayload
            ]
        )
    }

    private func restoreProgressRecords(fromWeekDocuments docs: [QueryDocumentSnapshot]) -> [String: ActivityExecutionRecord] {
        var restored: [String: ActivityExecutionRecord] = [:]

        for doc in docs {
            let fallbackWeek = Int(doc.documentID.replacingOccurrences(of: "W", with: ""))
            let days = normalizedDaysPayload(from: doc.data())
            guard !days.isEmpty else { continue }

            for (_, dayValue) in days {
                guard let dayPayload = dayValue as? [String: Any],
                      let records = dayPayload["records"] as? [String: Any] else { continue }

                for (_, recordValue) in records {
                    guard let recordPayload = recordValue as? [String: Any],
                          let record = progressRecord(from: recordPayload, fallbackWeek: fallbackWeek) else { continue }

                    let key = (recordPayload["documentKey"] as? String)
                        ?? progressKey(activityId: record.activityId, date: record.date)
                    restored[key] = record
                }
            }
        }

        return restored
    }

    private func normalizedDaysPayload(from documentData: [String: Any]) -> [String: Any] {
        if let nestedDays = documentData["days"] as? [String: Any], !nestedDays.isEmpty {
            return nestedDays
        }

        return flattenedDaysPayload(from: documentData)
    }

    private func flattenedDaysPayload(from documentData: [String: Any]) -> [String: Any] {
        var days: [String: [String: Any]] = [:]

        for (key, value) in documentData {
            guard key.hasPrefix("days.") else { continue }

            let components = key.split(separator: ".").map(String.init)
            guard components.count >= 3 else { continue }

            let dayKey = components[1]
            var dayPayload = days[dayKey] ?? [:]

            if components.count == 3 {
                let fieldName = components[2]
                dayPayload[fieldName] = value
                days[dayKey] = dayPayload
                continue
            }

            guard components[2] == "records", components.count >= 4 else { continue }

            let recordKey = components[3]
            var records = dayPayload["records"] as? [String: Any] ?? [:]

            if components.count == 4 {
                records[recordKey] = value
                dayPayload["records"] = records
                days[dayKey] = dayPayload
                continue
            }

            let recordFieldPath = Array(components.dropFirst(4))
            var recordPayload = records[recordKey] as? [String: Any] ?? [:]
            setValue(value, forPath: recordFieldPath, in: &recordPayload)
            records[recordKey] = recordPayload
            dayPayload["records"] = records
            days[dayKey] = dayPayload
        }

        return days.mapValues { $0 }
    }

    private func setValue(_ value: Any, forPath path: [String], in dictionary: inout [String: Any]) {
        guard let head = path.first else { return }

        if path.count == 1 {
            dictionary[head] = value
            return
        }

        var child = dictionary[head] as? [String: Any] ?? [:]
        setValue(value, forPath: Array(path.dropFirst()), in: &child)
        dictionary[head] = child
    }
    
    private var istCalendar: Calendar {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }
    
    func startOfDayInIST(for date: Date = Date()) -> Date {
        istCalendar.startOfDay(for: date)
    }
    
    func currentISTWeekday() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        return formatter.string(from: Date())
    }
    
    func currentISTHour() -> Int {
        istCalendar.component(.hour, from: Date())
    }
    
    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        return formatter
    }()
    
    private static let insightDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMM"
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        return formatter
    }()
    
    private static let insightTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        return formatter
    }()
    
    private static let graphDayLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        return formatter
    }()
    
    func getRoutineItems(for type: RoutineType, date: Date) -> [RoutineItem] {
        
        let key = dayKey(date)
        
        if lastAccessedDayKey != key {
            resetForNewDay(key: key)
        }

        lastAccessedDayKey = key
        
        let oldItems = dailyRoutineStore[key]?[type] ?? []
        
        let newItems = generateRoutineItems(for: type, date: date)
        
        let preserved = oldItems.filter {
            let progress = loadProgress(for: $0, date: date)
            return progress.status == .completed || progress.status == .skipped
        }
        
        var mergedActivities = newItems
        
        for old in preserved {
            if !mergedActivities.contains(where: { $0.activityId == old.activityId }) {
                mergedActivities.append(old)
            }
        }
        
        let mergedItems = mergedActivities.map { item -> RoutineItem in
            var updatedItem = item
            let progress = loadProgress(for: item, date: date)
            updatedItem.status = progress.status
            return updatedItem
        }
        
        dailyRoutineStore[key, default: [:]][type] = mergedItems
        
        return mergedItems
    }
    
    private func resetForNewDay(key: String) {
        
        print("New day detected — resetting routine")
        
        dailyRoutineStore.removeAll()
    }
    
    private func cleanOldProgress(keepingDays: Int) {
        
        let calendar = Calendar.current
        
        progressStore = progressStore.filter { _, record in
            guard let diff = calendar.dateComponents([.day], from: record.date, to: Date()).day else {
                return true
            }
            return diff <= keepingDays
        }
    }
    
    func getTodayRoutineSummary(for date: Date) -> [RoutineSession] {
        
        RoutineType.allCases.map { type in
            
            let items = getRoutineItems(for: type, date: date)
            
            let totalDuration = items.reduce(0) { $0 + $1.durationSeconds }
            
            return RoutineSession(
                routineType: type,
                totalItems: items.count,
                totalDuration: totalDuration
            )
        }
    }
    
    //MAIN ENGINE
    
    private func generateRoutineItems(for type: RoutineType, date: Date) -> [RoutineItem] {
        
        var activities = allActivities
        
        debug("Initial", activities.count)
        
        // 1. Type Filter
        activities = activities.filter { mapCategory($0) == type }
        debug("Type", activities.count)
        
        // 2. Trimester
        activities = activities.filter { trimesterAllowed($0) }
        debug("Trimester", activities.count)
        
        // 3. Age (custom)
        activities = activities.filter { ageAllowed($0) }
        debug("Age", activities.count)
        
        // 4. Medical
        activities = activities.filter { medicalSafe($0) }
        debug("Medical", activities.count)
        
        // 5. Activity Level
        activities = activities.filter { activityLevelAllowed($0) }
        debug("ActivityLevel", activities.count)
        
        // 7. Rotation
        activities = activities.filter { notRecentlyUsed($0, on: date) }
        debug("Rotation", activities.count)
        
        // 8. Scoring
        let scored = activities.map { ($0, score($0, type: type, on: date)) }
        let sorted = scored.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.activityId < $1.0.activityId
        }.map { $0.0 }
        
        debug("Scored", sorted.count)
        
        // 9. Count
        let count = dynamicCount(for: type)
        
        var selected = Array(sorted.prefix(count))

        // SAFETY NET
        if selected.isEmpty {
            
            selected = allActivities
                .filter { mapCategory($0) == type }
                .sorted { deterministicRoutineOrderValue(for: $0, type: type, on: date) > deterministicRoutineOrderValue(for: $1, type: type, on: date) }
                .prefix(count)
                .map { $0 }
        }
        
        debug("Final", selected.count)
        
        return buildRoutineItems(from: selected, type: type)
    }
    
    //FILTERS
    
    private func mapCategory(_ activity: ActivityDefinition) -> RoutineType {
        routineType(for: activity.activityId)
    }
    
    private func trimesterAllowed(_ activity: ActivityDefinition) -> Bool {
        activity.prescription.trimester.contains("\(userProfile.trimester.rawValue)")
    }
    
    private func ageAllowed(_ activity: ActivityDefinition) -> Bool {
        
        let age = userProfile.age
        let intensity = activity.intensity.intensityLevel.lowercased()
        
        if age < 20 {
            return intensity == "low"
        } else if age <= 30 {
            return intensity.contains("low") || intensity.contains("moderate")
        } else {
            return !intensity.contains("high")
        }
    }
    
    private func medicalSafe(_ activity: ActivityDefinition) -> Bool {
        
        let userConditions = Set(userProfile.medicalConditions.map { $0.rawValue })
        let allowedConditions = Set(activity.medicalSafety.medicalConditions)
        
        // If activity is safe for all
        if allowedConditions.contains("none") {
            return true
        }
        
        // If ANY condition matches then allow
        if !userConditions.isDisjoint(with: allowedConditions) {
            return true
        }
        
        // allow low intensity always
        if activity.intensity.intensityLevel.lowercased() == "low" {
            return true
        }
        
        return false
    }
    
    private func activityLevelAllowed(_ activity: ActivityDefinition) -> Bool {
        
        let userLevel = userProfile.activityLevel.rawValue
        
        let allowed = activity.userCapabilityRequirement.allowedActivityLevels
        
        // Direct match
        if allowed.contains(userLevel) {
            return true
        }
        
        // HIGH users can do LOWER activities
        if userLevel == "high" {
            return allowed.contains("moderate") || allowed.contains("low")
        }
        
        // MODERATE users can do LOW
        if userLevel == "moderate" {
            return allowed.contains("low")
        }
        
        return false
    }
    
    private func notRecentlyUsed(_ activity: ActivityDefinition, on date: Date) -> Bool {
        let cal = istCalendar
        let today = cal.startOfDay(for: date)
        let recentWindowStart = cal.date(byAdding: .day, value: -1, to: today) ?? today
        
        let recentProgress = progressStore.values.contains { record in
            record.activityId == activity.activityId
                && record.status == .completed
                && cal.startOfDay(for: record.date) >= recentWindowStart
                && cal.startOfDay(for: record.date) <= today
        }
        
        if recentProgress {
            return false
        }
        
        guard let record = rotationHistory.first(where: { $0.activityId == activity.activityId }) else {
            return true
        }
        
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: record.lastPerformedDate), to: today).day ?? 0
        return days >= 2
    }
    
    //SCORING
    
    private func score(_ activity: ActivityDefinition, type: RoutineType, on date: Date) -> Int {
        
        var score = 0
        
        if trimesterAllowed(activity) { score += 20 }
        if notRecentlyUsed(activity, on: date) { score += 18 }
        score += exactActivityLevelBoost(for: activity)
        score += medicalConditionBoost(for: activity)
        score += recentCompletionPenalty(for: activity, on: date)
        score += feedbackAdjustment(for: activity)
        score += gestationalWeekBoost(for: activity, on: date)
        score += deterministicRoutineOrderValue(for: activity, type: type, on: date)
        
        return score
    }
    
    private func exactActivityLevelBoost(for activity: ActivityDefinition) -> Int {
        let userLevel = userProfile.activityLevel.rawValue
        let allowed = activity.userCapabilityRequirement.allowedActivityLevels
        
        if allowed.contains(userLevel) {
            return 10
        }
        
        switch userProfile.activityLevel {
        case .high:
            return allowed.contains("moderate") ? 6 : (allowed.contains("low") ? 4 : 0)
        case .moderate:
            return allowed.contains("low") ? 5 : 0
        case .low:
            return 0
        }
    }
    
    private func medicalConditionBoost(for activity: ActivityDefinition) -> Int {
        let conditions = Set(userProfile.medicalConditions.map(\.rawValue)).subtracting(["none"])
        guard !conditions.isEmpty else {
            return activity.medicalSafety.medicalConditions.contains("none") ? 4 : 2
        }
        
        let supported = Set(activity.medicalSafety.medicalConditions)
        if !conditions.isDisjoint(with: supported) {
            return 12
        }
        
        if activity.intensity.intensityLevel.lowercased() == "low" {
            return 6
        }
        
        return -6
    }
    
    private func feedbackAdjustment(for activity: ActivityDefinition) -> Int {
        let recentFeedback = userFeedback
            .filter { $0.activityId == activity.activityId }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(3)
        
        return recentFeedback.reduce(0) { partial, feedback in
            switch feedback.fatigue {
            case .high:
                return partial - 10
            case .moderate:
                return partial - 4
            case .low:
                return partial + 2
            case .none:
                return partial + 4
            }
        }
    }
    
    private func recentCompletionPenalty(for activity: ActivityDefinition, on date: Date) -> Int {
        let cal = istCalendar
        let today = cal.startOfDay(for: date)
        let sevenDaysAgo = cal.date(byAdding: .day, value: -6, to: today) ?? today
        
        let recentCompletions = progressStore.values.filter { record in
            record.activityId == activity.activityId
                && record.status == .completed
                && cal.startOfDay(for: record.date) >= sevenDaysAgo
                && cal.startOfDay(for: record.date) <= today
        }.count
        
        return -(recentCompletions * 8)
    }
    
    private func gestationalWeekBoost(for activity: ActivityDefinition, on date: Date) -> Int {
        let week = max(1, userProfile.gestationalWeek)
        let intensity = activity.intensity.intensityLevel.lowercased()
        
        if week <= 12 {
            return intensity == "low" ? 8 : 3
        }
        
        if week >= 28 {
            if activity.activityId.localizedCaseInsensitiveContains("yoga") {
                return 8
            }
            return intensity == "low" ? 6 : 2
        }
        
        return intensity == "moderate" ? 7 : 4
    }
    
    private func deterministicRoutineOrderValue(for activity: ActivityDefinition, type: RoutineType, on date: Date) -> Int {
        let weekday = istCalendar.component(.weekday, from: date)
        let weekComponent = istCalendar.component(.weekOfYear, from: date)
        let conditionKey = userProfile.medicalConditions.map(\.rawValue).sorted().joined(separator: "|")
        let seed = [
            activity.activityId,
            type.rawValue,
            "\(weekday)",
            "\(weekComponent)",
            "\(userProfile.gestationalWeek)",
            "\(userProfile.trimester.rawValue)",
            userProfile.activityLevel.rawValue,
            conditionKey
        ].joined(separator: "#")
        
        return stableHash(seed) % 11
    }
    
    private func stableHash(_ value: String) -> Int {
        value.unicodeScalars.reduce(7) { partial, scalar in
            ((partial * 31) + Int(scalar.value)) & 0x7fffffff
        }
    }
    
    //COUNT
    
    private func dynamicCount(for type: RoutineType) -> Int {
        
        switch (type, userProfile.activityLevel) {
            
        case (.walking, .low): return 4
        case (.walking, .moderate): return 6
        case (.walking, .high): return 8
            
        case (.exercise, .low): return 5
        case (.exercise, .moderate): return 7
        case (.exercise, .high): return 9
            
        case (.yoga, .low): return 4
        case (.yoga, .moderate): return 6
        case (.yoga, .high): return 8
        }
    }
    
    //BUILD
    
    private func buildRoutineItems(from activities: [ActivityDefinition], type: RoutineType) -> [RoutineItem] {
        
        activities.map { activity in
            
            RoutineItem(
                activityId: activity.activityId,
                routineType: type,
                title: activity.metadata.title,
                
                video: activity.media.video,
                image: activity.media.image,
                
                durationSeconds: activity.prescription.durationMinutes * 60,
                distanceMeters: activity.prescription.recommendedDistanceMeters,
                sets: activity.prescription.sets,
                reps: activity.prescription.reps,
                difficulty: activity.intensity.intensityLevel,
                
                description: activity.metadata.description,
                
                benefits: activity.content.benefits,
                instructions: activity.content.instructions,
                safetyTips: activity.content.safetyTips,
                
                status: .pending
            )
        }
    }
    
    func mapDifficulty(_ value: String?) -> DifficultyLevel {
        
        switch value?.lowercased() {
        case "low": return .beginner
        case "moderate": return .intermediate
        case "high": return .advanced
        default: return .beginner
        }
    }
    
    //PROGRESS
    
    func loadProgress(for item: RoutineItem, date: Date) -> RoutineItemProgress {
        let record = progressEntry(activityId: item.activityId, on: date)?.record
        
        return RoutineItemProgress(
            activityId: item.activityId,
            date: date,
            elapsedSeconds: record?.durationSeconds ?? 0,
            heartRateAverage: record?.avgHeartRate,
            caloriesBurned: nil,
            distanceCovered: record?.distanceMeters,
            repetitionsCompleted: item.reps,
            status: record?.status ?? .pending
        )
    }
    
    func saveProgress(
        for item: RoutineItem,
        elapsedSeconds: Int?,
        status: RoutineItemStatus,
        date: Date
    ) {
        let existingEntry = progressEntry(activityId: item.activityId, on: date)
        let key = existingEntry?.key ?? progressKey(activityId: item.activityId, date: date)
        
        var record = existingEntry?.record ?? ActivityExecutionRecord(
            activityId: item.activityId,
            date: date,
            firestoreWeek: nil,
            startTime: Date(),
            endTime: nil,
            status: .pending,
            durationSeconds: nil,
            distanceMeters: nil,
            activeEnergyKcal: nil,
            avgHeartRate: nil,
            avgSpO2: nil,
            steps: nil,
            reps: item.reps,
            sets: item.sets,
            feedback: nil
        )
        
        // Time tracking
        if record.startTime == nil {
            record.startTime = Date()
        }
        
        if status == .completed {
            record.endTime = Date()
        }
        
        // Duration (from old system)
        if let elapsed = elapsedSeconds {
            record.durationSeconds = elapsed
        }
        
        // Distance
        if let distance = item.distanceMeters {
            record.distanceMeters = Double(distance)
        }
        
        record.reps = item.reps
        record.sets = item.sets
        
        // Status update
        record.status = status
        
        // Save
        if let week = progressWeek(for: record.date) {
            record.firestoreWeek = week
        }
        
        // Save
        progressStore[key] = record
        removeProgressIndexEntry(for: key)
        if let week = record.firestoreWeek ?? progressWeek(for: record.date) {
            progressWeekIndex[week, default: [:]][dayKey(record.date), default: [:]][key] = record
        }
        notifyProgressChanged()
        
        saveProgressToFirestore(record: record, item: item, documentKey: key)
        
        // Rotation update (only when completed)
        if status == .completed {
            rotationHistory.append(
                ActivityRotationRecord(
                    activityId: item.activityId,
                    lastPerformedDate: date
                )
            )
        }
    }
    
    func markItemCompleted(_ item: inout RoutineItem, date: Date) {
        item.status = .completed
        saveProgress(for: item, elapsedSeconds: item.durationSeconds, status: .completed, date: date)
    }
    
    func markItemSkipped(_ item: inout RoutineItem, date: Date) {
        item.status = .skipped
        saveProgress(for: item, elapsedSeconds: nil, status: .skipped, date: date)
    }
    
    //UTIL
    
    private func debug(_ stage: String, _ count: Int) {
        print("\(stage): \(count)")
    }
    
    //PROFILE UPDATE (AUTO REGEN)
    
    func updateUserProfile(_ profile: UserProfile) {
        
        let oldProfile = userProfile
        self.userProfile = profile
        refreshProgressIndexesAfterProfileUpdate()
        
        if hasSignificantChange(old: oldProfile, new: profile) {
            invalidateTodayButKeepProgress()
        }
    }
    
    private func invalidateTodayButKeepProgress() {
        let key = dayKey(Date())
        
        dailyRoutineStore[key] = dailyRoutineStore[key] ?? [:]
    }
    
    private func getRoutineItemsWithoutCache(for type: RoutineType, date: Date) -> [RoutineItem] {
        
        let newItems = generateRoutineItems(for: type, date: date)
        
        return newItems.map { item -> RoutineItem in
            var updatedItem = item
            let progress = loadProgress(for: item, date: date)
            updatedItem.status = progress.status
            return updatedItem
        }
    }
    
    private func hasSignificantChange(old: UserProfile, new: UserProfile) -> Bool {
        return old.age != new.age || old.trimester != new.trimester || old.activityLevel != new.activityLevel || old.medicalConditions != new.medicalConditions
    }
    
    private func invalidateToday() {
        let key = dayKey(Date())
        dailyRoutineStore.removeValue(forKey: key)
    }
}

//Progress
extension DataController {
    
    private func saveProgressToFirestore(
        record: ActivityExecutionRecord,
        item: RoutineItem? = nil,
        feedback: UserFeedback? = nil,
        documentKey: String? = nil
    ) {
        
        guard let userId = currentUserId else { return }
        
        let key = documentKey
            ?? progressEntry(activityId: record.activityId, on: record.date)?.key
            ?? progressKey(activityId: record.activityId, date: record.date)
        guard let writePayload = progressWeekWritePayload(
            record: record,
            item: item,
            feedback: feedback,
            documentKey: key
        ) else { return }

        db.collection("users")
            .document(userId)
            .collection("progress_weeks")
            .document(writePayload.documentId)
            .setData(writePayload.data, merge: true) { error in
                if let error = error {
                    print("Progress Firestore save error:", error)
                } else {
                    print("Progress saved to Firestore")
                }
            }
    }
    
    private func startProgressListener() {
        
        progressListener?.remove()
        
        guard let userId = currentUserId else {
            progressStore.removeAll()
            progressWeekIndex.removeAll()
            userFeedback.removeAll()
            notifyProgressChanged()
            return
        }
        
        progressListener = db.collection("users")
            .document(userId)
            .collection("progress_weeks")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Progress Firestore listener error:", error)
                    return
                }
                
                guard let docs = snapshot?.documents else { return }
                
                let restored = self.restoreProgressRecords(fromWeekDocuments: docs)
                var feedbackLookup: [UUID: UserFeedback] = [:]

                for record in restored.values {
                    if let feedback = record.feedback {
                        feedbackLookup[feedback.id] = feedback
                    }
                }

                self.replaceProgressState(restored: restored, feedbackLookup: feedbackLookup)
                print("Progress synced from Firestore:", restored.count)
            }
    }
    
    func loadProgressFromFirestore(completion: @escaping () -> Void) {
        
        guard let userId = currentUserId else {
            completion()
            return
        }
        
        db.collection("users")
            .document(userId)
            .collection("progress_weeks")
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else {
                    completion()
                    return
                }
                
                if let error = error {
                    print("Progress Firestore load error:", error)
                    completion()
                    return
                }

                let docs = snapshot?.documents ?? []
                let restored = self.restoreProgressRecords(fromWeekDocuments: docs)
                var feedbackLookup: [UUID: UserFeedback] = [:]

                restored.values.forEach { record in
                    if let feedback = record.feedback {
                        feedbackLookup[feedback.id] = feedback
                    }
                }

                self.replaceProgressState(restored: restored, feedbackLookup: feedbackLookup)
                print("Progress loaded from Firestore:", restored.count)
                completion()
            }
    }
    
    private func firestoreData(for record: ActivityExecutionRecord, item: RoutineItem? = nil, feedback: UserFeedback? = nil) -> [String: Any] {
        let distance = record.distanceMeters ?? Double(item?.distanceMeters ?? 0)
        let stats: [String: Any] = [
            "steps": record.steps ?? 0,
            "distance": distance,
            "calories": record.activeEnergyKcal ?? 0,
            "reps": record.reps ?? item?.reps ?? 0,
            "sets": record.sets ?? item?.sets ?? 0
        ]
        let vitals: [String: Any] = [
            "heartRate": record.avgHeartRate ?? 0,
            "spo2": record.avgSpO2 ?? 0
        ]

        var data: [String: Any] = [
            "activityId": record.activityId,
            "date": Timestamp(date: record.date),
            "status": record.status.rawValue,
            "duration": record.durationSeconds ?? 0,
            "distance": distance,
            "stats": stats,
            "vitals": vitals
        ]
        
        if let startTime = record.startTime {
            data["startTime"] = Timestamp(date: startTime)
        }
        
        if let endTime = record.endTime {
            data["endTime"] = Timestamp(date: endTime)
        }
        
        if let item = item {
            data["reps"] = item.reps ?? 0
            data["sets"] = item.sets ?? 0
        }
        
        if let reps = record.reps {
            data["reps"] = reps
        }
        
        if let sets = record.sets {
            data["sets"] = sets
        }
        
        if let feedback = feedback {
            data["feedback"] = firestoreData(for: feedback)
        }
        
        return data
    }
    
    private func firestoreData(for feedback: UserFeedback) -> [String: Any] {
        [
            "id": feedback.id.uuidString,
            "activityId": feedback.activityId,
            "difficulty": feedback.difficulty.rawValue,
            "fatigue": feedback.fatigue.rawValue,
            "note": feedback.note ?? "",
            "createdAt": Timestamp(date: feedback.createdAt)
        ]
    }
    
    private func progressRecord(from data: [String: Any], fallbackWeek: Int? = nil) -> ActivityExecutionRecord? {
        
        guard let activityId = data["activityId"] as? String else { return nil }
        
        let stats = data["stats"] as? [String: Any]
        let vitals = data["vitals"] as? [String: Any]
        let inferredStatus = inferredStatusForRestoredRecord(data: data, stats: stats, vitals: vitals)
        
        return ActivityExecutionRecord(
            activityId: activityId,
            date: (data["date"] as? Timestamp)?.dateValue() ?? Date(),
            firestoreWeek: intValue(data["week"]) ?? fallbackWeek,
            startTime: (data["startTime"] as? Timestamp)?.dateValue(),
            endTime: (data["endTime"] as? Timestamp)?.dateValue(),
            status: inferredStatus,
            durationSeconds: intValue(data["duration"]),
            distanceMeters: doubleValue(data["distance"]) ?? doubleValue(stats?["distance"]),
            activeEnergyKcal: doubleValue(stats?["calories"]),
            avgHeartRate: intValue(vitals?["heartRate"]),
            avgSpO2: doubleValue(vitals?["spo2"]),
            steps: intValue(stats?["steps"]),
            reps: intValue(data["reps"]) ?? intValue(stats?["reps"]),
            sets: intValue(data["sets"]) ?? intValue(stats?["sets"]),
            feedback: feedback(from: data["feedback"])
        )
    }

    private func inferredStatusForRestoredRecord(
        data: [String: Any],
        stats: [String: Any]?,
        vitals: [String: Any]?
    ) -> RoutineItemStatus {
        if let rawStatus = data["status"] as? String,
           let status = RoutineItemStatus(rawValue: rawStatus) {
            return status
        }

        let hasMeaningfulValue =
            (intValue(data["duration"]) ?? 0) > 0
            || (intValue(data["reps"]) ?? intValue(stats?["reps"]) ?? 0) > 0
            || (intValue(data["sets"]) ?? intValue(stats?["sets"]) ?? 0) > 0
            || (intValue(stats?["steps"]) ?? 0) > 0
            || (doubleValue(data["distance"]) ?? doubleValue(stats?["distance"]) ?? 0) > 0
            || (doubleValue(stats?["calories"]) ?? 0) > 0
            || (intValue(vitals?["heartRate"]) ?? 0) > 0
            || data["startTime"] != nil
            || data["endTime"] != nil
            || data["feedback"] != nil

        return hasMeaningfulValue ? .completed : .pending
    }
    
    private func saveProgressStatsToFirestore(
        activityId: String,
        date: Date,
        steps: Int?,
        distance: Double?,
        heartRate: Int?
    ) {
        
        guard let userId = currentUserId else { return }
        
        let key = latestProgressKey(activityId: activityId, date: date)
            ?? progressEntry(activityId: activityId, on: date)?.key
            ?? progressKey(activityId: activityId, date: date)

        var record = progressEntry(activityId: activityId, on: date)?.record ?? ActivityExecutionRecord(
            activityId: activityId,
            date: date,
            firestoreWeek: nil,
            startTime: nil,
            endTime: nil,
            status: .inProgress,
            durationSeconds: nil,
            distanceMeters: nil,
            activeEnergyKcal: nil,
            avgHeartRate: nil,
            avgSpO2: nil,
            steps: nil,
            reps: nil,
            sets: nil,
            feedback: nil
        )

        if let steps { record.steps = steps }
        if let distance { record.distanceMeters = distance }
        if let heartRate { record.avgHeartRate = heartRate }

        guard let writePayload = progressWeekWritePayload(
            record: record,
            documentKey: key
        ) else { return }

        db.collection("users")
            .document(userId)
            .collection("progress_weeks")
            .document(writePayload.documentId)
            .setData(writePayload.data, merge: true)
    }
    
    private func latestProgressKey(activityId: String, date: Date) -> String? {
        progressStore
            .filter { _, record in
                record.activityId == activityId && dayKey(record.date) == dayKey(date)
            }
            .sorted { lhs, rhs in lhs.value.date > rhs.value.date }
            .first?
            .key
    }
    
    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
    
    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
    
    func getAllProgress() -> [ActivityExecutionRecord] {
        return Array(progressStore.values)
    }

    func getProgress(for activityId: String) -> [ActivityExecutionRecord] {
        return progressStore.values.filter { $0.activityId == activityId }
    }
    
    func loadScheduleFromDisk() {
        print("Schedule disk load disabled; use Firestore")
    }
    
    func saveScheduleToDisk() {
        print("Schedule disk save disabled; use Firestore")
    }
    
    func updateSessionProgress(
        activityId: String,
        date: Date,
        steps: Int?,
        distance: Double?,
        heartRate: Int?
    ) {
        
        guard var schedule = activitySchedule else { return }
        
        let key = Self.formatter.string(from: date)
        
        for i in 0..<schedule.insights.count {
            for j in 0..<schedule.insights[i].weeks.count {
                for k in 0..<schedule.insights[i].weeks[j].days.count {
                    
                    if schedule.insights[i].weeks[j].days[k].dayKey == key {
                        
                        for s in 0..<schedule.insights[i].weeks[j].days[k].sessions.count {
                            
                            var session = schedule.insights[i].weeks[j].days[k].sessions[s]
                            
                            if session.id.contains(activityId) {
                                
                                // Update stats
                                session.stats = session.stats.map { metric in
                                    
                                    var updated = metric
                                    
                                    switch metric.title.lowercased() {
                                        
                                    case "steps":
                                        if let steps = steps {
                                            updated.value = "\(steps)"
                                        }
                                        
                                    case "distance":
                                        if let distance = distance {
                                            updated.value = String(format: "%.2f", distance)
                                        }
                                        
                                    default:
                                        break
                                    }
                                    
                                    return updated
                                }
                                
                                // Update vitals
                                if var vitals = session.vitals {
                                    vitals = vitals.map { metric in
                                        
                                        var updated = metric
                                        
                                        if metric.title.lowercased() == "heart rate",
                                           let hr = heartRate {
                                            updated.value = "\(hr)"
                                        }
                                        
                                        return updated
                                    }
                                    
                                    session.vitals = vitals
                                }
                                
                                // Save back
                                schedule.insights[i].weeks[j].days[k].sessions[s] = session
                            }
                        }
                    }
                }
            }
        }
        
        self.activitySchedule = schedule
        saveScheduleToFirestore()
        saveProgressStatsToFirestore(
            activityId: activityId,
            date: date,
            steps: steps,
            distance: distance,
            heartRate: heartRate
        )
    }
    
    
    func saveScheduleToFirestore() {
        
        guard let userId = currentUserId,
              let schedule = activitySchedule else { return }
        
        do {
            let data = try JSONEncoder().encode(schedule)
            let json = try JSONSerialization.jsonObject(with: data)
            
            db.collection("users")
                .document(userId)
                .setData(["schedule": json], merge: true)
            
            print(" Firestore saved")
            
        } catch {
            print(" Firestore error:", error)
        }
    }
    
    func loadScheduleFromFirestore(completion: @escaping () -> Void) {
        
        guard let userId = currentUserId else {
            completion()
            return
        }
        
        db.collection("users")
            .document(userId)
            .getDocument { snapshot, error in
                
                if let data = snapshot?.data()?["schedule"] {
                    
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: data)
                        let decoded = try JSONDecoder().decode(ActivitySchedule.self, from: jsonData)
                        
                        self.activitySchedule = decoded
                        
                        print(" Firestore loaded")
                    } catch {
                        print(" Decode error:", error)
                    }
                }
                
                completion()
            }
    }
    
    func stopActivity(activityId: String, completion: @escaping () -> Void) {
        
        guard activeActivityId == activityId else {
            completion()
            return
        }
        
        let end = Date()
        
        fetchTodayVitals { [weak self] vitals in
            
            //  NEW SYSTEM UPDATE
            self?.updateSessionProgress(
                activityId: activityId,
                date: end,
                steps: vitals.steps,
                distance: vitals.distanceMeters,
                heartRate: vitals.avgHeartRate
            )
            
            //  optional firestore sync
            self?.saveScheduleToFirestore()
            
            self?.activeActivityId = nil
            
            completion()
        }
    }
    
}

//LOADER

enum ActivityLoader {
    
    static func loadActivities() -> [ActivityDefinition] {
        
        let files = [
            "walking_activities_meaningful",
            "exercise_activities_mapped",
            "yoga_activities_medical_mapped"
        ]
        
        return files.flatMap { file in
            
            guard let url = Bundle.main.url(forResource: file, withExtension: "json") else {
                print("Missing:", file)
                return [ActivityDefinition]()
            }
            
            do {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode([ActivityDefinition].self, from: data)
                print("Loaded \(decoded.count) from \(file)")
                return decoded
            } catch {
                print("Decode error:", error)
                return []
            }
        }
    }
    
}

//Profile
extension DataController {
    
    func loadAppContent(id: String) -> AppContent? {
        
        let fileName: String
        let jsonKey: String
        
        switch id {
        case "about_blooma":
            fileName = "about_blooma"
            jsonKey = "about_blooma"
            
        case "data_sources":
            fileName = "data_sources"
            jsonKey = "data_sources"
            
        case "research_insights":
            fileName = "research_insights"
            jsonKey = "research_insights"
            
        case "legal_compliance":
            fileName = "legal_compliance"
            jsonKey = "privacy_policy"
            
        default:
            return nil
        }
        
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            print(" File not found:", fileName)
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            
            let decodedDict = try JSONDecoder().decode([String: AppContent].self, from: data)
            
            guard let content = decodedDict[jsonKey] else {
                print(" Key not found in JSON:", jsonKey)
                return nil
            }
            
            print(" Loaded:", content.title)
            print(" Sections:", content.sections.count)
            
            return content
            
        } catch {
            print(" Decode error:", error)
            return nil
        }
    }
    
}

//Firebase
extension DataController {
    
    func saveProfileToFirestore() {
        guard let userId = currentUserId else { return }
        
        var userDetails: [String: Any] = [
            "name": userProfile.name,
            "userName": userProfile.userName.lowercased(),
            "email": userProfile.email?.lowercased() ?? "",
            "password": userProfile.password,
            "age": userProfile.age,
            "week": userProfile.gestationalWeek,
            "gestationalDay": userProfile.gestationalDay,
            "trimester": userProfile.trimester.rawValue,
            "activityLevel": userProfile.activityLevel.rawValue,
            "hasAppleWatch": userProfile.hasAppleWatch,
            "medicalConditions": userProfile.medicalConditions.map { $0.rawValue }
        ]
        
        if let lmpDate = userProfile.lmpDate {
            userDetails["lmpDate"] = lmpDate
        }
        
        if let eddDate = userProfile.eddDate {
            userDetails["eddDate"] = eddDate
        }
        
        db.collection("users").document(userId).setData([
            "userDetails": userDetails,
            "schemaVersion": 2,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    func loadProfileFromFirestore(completion: @escaping (UserProfile?) -> Void) {
        
        guard let userId = currentUserId else {
            completion(nil)
            return
        }
        
        db.collection("users").document(userId).getDocument { snapshot, error in
            
            if let error = error {
                print("Firestore load error:", error)
                completion(nil)
                return
            }
            
            guard let rawData = snapshot?.data() else {
                completion(nil)
                return
            }

            let data = (rawData["userDetails"] as? [String: Any]) ?? rawData
            
            let trimester: Trimester

            if let intValue = data["trimester"] as? Int {
                trimester = Trimester(rawValue: intValue) ?? .first
            } else if let stringValue = data["trimester"] as? String {
                switch stringValue.lowercased() {
                case "first": trimester = .first
                case "second": trimester = .second
                case "third": trimester = .third
                default: trimester = .first
                }
            } else {
                trimester = .first
            }
            
            let medicalConditions: [MedicalCondition]

            if let rawArray = data["medicalConditions"] as? [String] {
                medicalConditions = rawArray.compactMap { MedicalCondition(rawValue: $0) }
            } else {
                medicalConditions = []
            }

            let profile = UserProfile(
                userId: UUID(uuidString: userId) ?? UUID(),
                profileImageData: nil,
                name: data["name"] as? String ?? "",
                email: data["email"] as? String,
                userName: data["userName"] as? String ?? "",
                password: data["password"] as? String ?? "",
                age: data["age"] as? Int ?? 0,
                lmpDate: self.dateValue(from: data["lmpDate"]),
                eddDate: self.dateValue(from: data["eddDate"]),
                gestationalWeek: data["week"] as? Int ?? 1,
                gestationalDay: data["gestationalDay"] as? Int ?? 0,
                trimester: trimester,
                medicalConditions: medicalConditions,
                activityLevel: ActivityLevel(rawValue: data["activityLevel"] as? String ?? "low") ?? .low,
                hasAppleWatch: data["hasAppleWatch"] as? Bool ?? false
            )
            
            self.userProfile = profile
            self.refreshPregnancyProgressIfNeeded()
            self.refreshProgressIndexesAfterProfileUpdate()
            completion(self.userProfile)
        }
    }
    
    fileprivate func dateValue(from value: Any?) -> Date? {
        if let date = value as? Date {
            return date
        }
        
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }
        
        if let interval = value as? TimeInterval {
            return Date(timeIntervalSince1970: interval)
        }
        
        if let string = value as? String {
            return ISO8601DateFormatter().date(from: string)
        }
        
        return nil
    }
}

extension DataController {
    
    func saveUserFeedback(activityId: String, difficulty: DifficultyLevel, fatigue: FatigueLevel, note: String?) {
        
        let feedback = UserFeedback(
            id: UUID(),
            activityId: activityId,
            difficulty: difficulty,
            fatigue: fatigue,
            note: note,
            createdAt: Date()
        )
        
        userFeedback.append(feedback)
        userFeedback.sort { $0.createdAt > $1.createdAt }
        if let key = latestProgressKey(activityId: feedback.activityId, date: feedback.createdAt),
           var record = progressStore[key] {
            record.feedback = feedback
            progressStore[key] = record
            if let week = gestationalWeek(for: record.date) {
                progressWeekIndex[week, default: [:]][dayKey(record.date), default: [:]][key] = record
            }
        }
        notifyProgressChanged()
        saveFeedbackToFirestore(feedback)
    }
    
    func hasFeedback(for activityId: String) -> Bool {
        return userFeedback.contains {
            $0.activityId == activityId
        }
    }

    func shouldPromptForFeedback(for activityId: String, on date: Date) -> Bool {
        let feedbackForActivity = userFeedback
            .filter { $0.activityId == activityId }
            .sorted { $0.createdAt > $1.createdAt }

        guard let latestFeedback = feedbackForActivity.first else {
            return true
        }

        if istCalendar.isDate(latestFeedback.createdAt, inSameDayAs: date) {
            return false
        }

        let daysSinceLastFeedback = istCalendar.dateComponents([.day], from: latestFeedback.createdAt, to: date).day ?? 0
        if daysSinceLastFeedback >= 7 {
            return true
        }

        let completedCount = progressStore.values
            .filter { $0.activityId == activityId && $0.status == .completed }
            .count

        return completedCount > 0 && completedCount.isMultiple(of: 3)
    }
    
    private func saveFeedbackToFirestore(_ feedback: UserFeedback) {
        
        guard let userId = currentUserId else { return }
        
        let key = latestProgressKey(activityId: feedback.activityId, date: feedback.createdAt)
            ?? progressEntry(activityId: feedback.activityId, on: feedback.createdAt)?.key
            ?? progressKey(activityId: feedback.activityId, date: feedback.createdAt)

        var record = progressEntry(activityId: feedback.activityId, on: feedback.createdAt)?.record ?? ActivityExecutionRecord(
            activityId: feedback.activityId,
            date: feedback.createdAt,
            firestoreWeek: nil,
            startTime: nil,
            endTime: nil,
            status: .completed,
            durationSeconds: nil,
            distanceMeters: nil,
            activeEnergyKcal: nil,
            avgHeartRate: nil,
            avgSpO2: nil,
            steps: nil,
            reps: nil,
            sets: nil,
            feedback: nil
        )
        record.feedback = feedback

        guard let writePayload = progressWeekWritePayload(
            record: record,
            feedback: feedback,
            documentKey: key
        ) else { return }

        db.collection("users")
            .document(userId)
            .collection("progress_weeks")
            .document(writePayload.documentId)
            .setData(writePayload.data, merge: true) { error in
                if let error = error {
                    print("Feedback Firestore save error:", error)
                } else {
                    print("Feedback saved to Firestore")
                }
            }
    }
    
}

extension DataController {
    
    func insightHealthItemsForCurrentWeek() -> [HealthItem] {
        insightHealthItems(for: max(1, min(userProfile.gestationalWeek, 40)))
    }

    func insightHealthItems(for gestationalWeek: Int) -> [HealthItem] {
        let preferredWeek = max(1, min(gestationalWeek, 40))

        return ActivityType.allCases.map { activity in
            // NEW: If the current profile week has no progress yet, show the
            // latest Firestore week that actually has saved records.
            let displayWeek = preferredInsightWeek(for: activity, preferredWeek: preferredWeek)
            let dates = insightDates(for: displayWeek)
            let dayLabels = dates.map { Self.graphDayLabelFormatter.string(from: $0) }
            let chartValues = dates.map { date in
                graphMetricValue(for: activity, sessions: liveSessions(for: activity, on: date, preferredWeek: displayWeek))
            }
            let weeklySessions = dates.flatMap { liveSessions(for: activity, on: $0, preferredWeek: displayWeek) }
            let progressSummary = insightProgressSummary(
                for: activity,
                sessions: weeklySessions,
                week: displayWeek
            )
            
            return HealthItem(
                title: activity.title,
                progress: progressSummary.progressText,
                subtitle: progressSummary.subtitle,
                motivation: MotivationText.text(
                    activity: progressSummary.motivationType,
                    completed: progressSummary.completed,
                    target: progressSummary.target
                ),
                chartValues: chartValues,
                chartLabels: dayLabels
            )
        }
    }
    
    private func insightProgressSummary(
        for activity: ActivityType,
        sessions: [InsightSession],
        week: Int
    ) -> (progressText: String, subtitle: String, completed: Double, target: Double, motivationType: HealthActivityType) {
        switch activity {
        case .walking:
            let steps = totalMetricValue(named: "Steps", in: sessions)
            return (
                progressText: "\(Int(steps.rounded())) steps",
                subtitle: steps > 0 ? "Week \(week) walking total" : "No walking data in week \(week)",
                completed: steps,
                target: 8000,
                motivationType: .walking
            )
        case .exercise:
            let reps = totalMetricValue(named: "Reps", in: sessions)
            if reps > 0 {
                return (
                    progressText: "\(Int(reps.rounded())) reps",
                    subtitle: "Week \(week) exercise total",
                    completed: reps,
                    target: 40,
                    motivationType: .exercise
                )
            }
            
            let minutes = totalMetricValue(named: "Duration", in: sessions)
            if minutes > 0 {
                return (
                    progressText: "\(Int(minutes.rounded())) min",
                    subtitle: "Week \(week) exercise total",
                    completed: minutes,
                    target: 30,
                    motivationType: .exercise
                )
            }
            
            let sessionCount = Double(sessions.count)
            return (
                progressText: "\(Int(sessionCount.rounded())) sessions",
                subtitle: sessionCount > 0 ? "Week \(week) exercise count" : "No exercise data in week \(week)",
                completed: sessionCount,
                target: 30,
                motivationType: .exercise
            )
        case .yoga:
            let minutes = totalMetricValue(named: "Duration", in: sessions)
            if minutes > 0 {
                return (
                    progressText: "\(Int(minutes.rounded())) min",
                    subtitle: "Week \(week) yoga total",
                    completed: minutes,
                    target: 20,
                    motivationType: .yoga
                )
            }
            
            let sessionCount = Double(sessions.count)
            return (
                progressText: "\(Int(sessionCount.rounded())) sessions",
                subtitle: sessionCount > 0 ? "Week \(week) yoga count" : "No yoga data in week \(week)",
                completed: sessionCount,
                target: 2,
                motivationType: .yoga
            )
        }
    }
    
    private func totalMetricValue(named title: String, in sessions: [InsightSession]) -> Double {
        sessions.reduce(0.0) { partial, session in
            partial + metricValue(in: session.stats, titled: title)
        }
    }
    
    func loadInsightsResponse() -> InsightsResponse? {
        let url =
            Bundle.main.url(forResource: "footerInsights", withExtension: "json")
            ?? Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil)?
                .first(where: { $0.lastPathComponent == "footerInsights.json" })
        
        guard let url else {
            print("footerInsights.json not found")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(InsightsResponse.self, from: data)
        } catch {
            print("Failed to decode footerInsights.json:", error)
            return nil
        }
    }
    
    func activityWeekProgressSnapshot(for activity: ActivityType, gestationalWeek: Int) -> ActivityWeekProgressSnapshot? {
        let displayWeek = preferredInsightWeek(for: activity, preferredWeek: gestationalWeek)
        let dates = insightDates(for: displayWeek)
        guard !dates.isEmpty else { return nil }
        
        let days = dates.map { date -> InsightDay in
            let sessions = liveSessions(for: activity, on: date, preferredWeek: displayWeek)
            return InsightDay(
                dayKey: dayKey(date),
                dayLabel: Self.graphDayLabelFormatter.string(from: date),
                dateDisplay: Self.insightDateFormatter.string(from: date),
                sessions: sessions
            )
        }
        
        let values = days.map { day in
            graphMetricValue(for: activity, sessions: day.sessions)
        }
        
        let hasSessions = days.contains { !$0.sessions.isEmpty }
        
        guard hasSessions || values.contains(where: { $0 > 0 }) else {
            return nil
        }
        
        let total = values.reduce(0, +)
        let activeDays = max(values.filter { $0 > 0 }.count, 1)
        let average = total / Double(activeDays)
        let metricTitle = graphMetricTitle(for: activity)
        let displayValue = graphDisplayValue(for: activity, averageValue: average)
        
        return ActivityWeekProgressSnapshot(
            graphSummary: InsightGraphSummary(
                title: activity.title,
                metricTitle: metricTitle,
                displayValue: displayValue,
                dayLabels: dates.map { Self.graphDayLabelFormatter.string(from: $0) },
                dayValues: values
            ),
            days: days
        )
    }
    
    func enrichedInsightSession(
        from session: InsightSession?,
        activityType: String,
        dateText: String
    ) -> InsightSession? {
        guard let session else { return nil }
        guard let date = Self.dayKeyFormatter.date(from: dateText) else { return session }
        
        if let exactMatch = liveSession(activityId: session.id, activityType: activityType, on: date) {
            return exactMatch
        }
        
        return session
    }
    
    func feedbackForInsightSession(
        sessionId: String?,
        activityType: String,
        dateText: String
    ) -> UserFeedback? {
        let selectedDate = Self.dayKeyFormatter.date(from: dateText)
        let exactCandidates = candidateActivityIds(for: sessionId, activityType: activityType)
        let matchingFeedback = userFeedback.filter { feedback in
            guard exactCandidates.contains(feedback.activityId) || matchesActivityType(feedback.activityId, activityType: activityType) else {
                return false
            }
            
            guard let selectedDate else { return true }
            return istCalendar.isDate(feedback.createdAt, inSameDayAs: selectedDate)
        }
        
        return matchingFeedback.sorted { $0.createdAt > $1.createdAt }.first
            ?? userFeedback
                .filter { exactCandidates.contains($0.activityId) || matchesActivityType($0.activityId, activityType: activityType) }
                .sorted { $0.createdAt > $1.createdAt }
                .first
    }
    
    private func datesForGestationalWeek(_ gestationalWeek: Int) -> [Date] {
        let safeWeek = max(1, gestationalWeek)
        let baseLMP = pregnancyReferenceLMP()
        guard let startDate = istCalendar.date(byAdding: .day, value: (safeWeek - 1) * 7, to: baseLMP) else {
            return []
        }
        
        return (0..<7).compactMap { offset in
            istCalendar.date(byAdding: .day, value: offset, to: startDate)
        }
    }

    // NEW: Prefer real saved Firestore day keys for Insights rendering. This
    // avoids rebuilding week charts from a shifted pregnancy timeline when the
    // stored week/day data already exists in progress_weeks/Wxx.
    private func insightDates(for gestationalWeek: Int) -> [Date] {
        let generatedDates = datesForGestationalWeek(gestationalWeek)
        let storedDates = weekRecords(for: gestationalWeek)
            .keys
            .compactMap { Self.dayKeyFormatter.date(from: $0) }
            .sorted()

        guard !generatedDates.isEmpty else { return storedDates }
        guard !storedDates.isEmpty else { return generatedDates }

        var mergedByDayKey: [String: Date] = [:]
        generatedDates.forEach { mergedByDayKey[dayKey($0)] = $0 }
        storedDates.forEach { mergedByDayKey[dayKey($0)] = $0 }

        return mergedByDayKey.values.sorted()
    }
    
    private func pregnancyReferenceLMP() -> Date {
        if let lmp = userProfile.lmpDate {
            return istCalendar.startOfDay(for: lmp)
        }
        
        let estimated = PregnancyDateCalculation.estimatedLMP(
            fromWeek: userProfile.gestationalWeek,
            day: userProfile.gestationalDay,
            calendar: istCalendar,
            today: Date()
        )
        return istCalendar.startOfDay(for: estimated)
    }
    
    private func liveSessions(for activity: ActivityType, on date: Date, preferredWeek: Int? = nil) -> [InsightSession] {
        let week = preferredWeek ?? gestationalWeek(for: date) ?? userProfile.gestationalWeek
        let dayRecords = weekRecords(for: week)[dayKey(date)] ?? [:]
        let records = Array(dayRecords.values)

        return records
            .filter { record in
                matchesActivityType(record.activityId, activityType: activity.rawValue)
                    && record.status != .pending
            }
            .sorted { lhs, rhs in
                (lhs.endTime ?? lhs.date) > (rhs.endTime ?? rhs.date)
            }
            .map(makeInsightSession(from:))
    }

    func homeWeeklyProgressSnapshot() -> HomeWeeklyProgressSnapshot {
        let displayWeek = preferredHomeProgressWeek()
        let dates = insightDates(for: displayWeek)

        let activityConfigs: [(routineType: RoutineType, activityType: ActivityType, category: String, imageName: String)] = [
            (.walking, .walking, "MOVEMENT", "walk"),
            (.exercise, .exercise, "STRENGTH", "excercise"),
            (.yoga, .yoga, "MINDFULNESS", "yoga")
        ]

        var chartValues: [RoutineType: [Double]] = [:]

        let activities = activityConfigs.map { config -> HomeWeeklyProgressActivity in
            let sessions = dates.flatMap { liveSessions(for: config.activityType, on: $0, preferredWeek: displayWeek) }
            let values = dates.map { date in
                graphMetricValue(
                    for: config.activityType,
                    sessions: liveSessions(for: config.activityType, on: date, preferredWeek: displayWeek)
                )
            }
            chartValues[config.routineType] = values

            let summary = homeWeeklyActivitySummary(for: config.activityType, sessions: sessions)
            return HomeWeeklyProgressActivity(
                routineType: config.routineType,
                category: config.category,
                name: config.activityType.title,
                value: summary.value,
                unit: summary.unit,
                goal: summary.goal,
                goalUnit: summary.goalUnit,
                progress: summary.progress,
                color: config.routineType.accentColor,
                imageName: config.imageName
            )
        }

        let totalProgress = activities.reduce(0.0) { $0 + $1.progress }
        let overallPercent = activities.isEmpty
            ? 0
            : Int(((totalProgress / Double(activities.count)) * 100).rounded())
        let hasAnySavedProgress = activities.contains { $0.value > 0 }
        let motivation = hasAnySavedProgress
            ? "Showing your saved progress from week \(displayWeek)."
            : getMotivationMessage()

        return HomeWeeklyProgressSnapshot(
            displayWeek: displayWeek,
            overallPercent: overallPercent,
            motivation: motivation,
            dayLabels: dates.map { Self.graphDayLabelFormatter.string(from: $0) },
            chartValues: chartValues,
            activities: activities
        )
    }
    
    private func liveSession(activityId: String, activityType: String, on date: Date) -> InsightSession? {
        if let exactRecord = progressStore.values
            .filter({ istCalendar.isDate($0.date, inSameDayAs: date) && $0.activityId == activityId })
            .sorted(by: { ($0.endTime ?? $0.date) > ($1.endTime ?? $1.date) })
            .first {
            return makeInsightSession(from: exactRecord)
        }
        
        return progressStore.values
            .filter {
                istCalendar.isDate($0.date, inSameDayAs: date)
                    && matchesActivityType($0.activityId, activityType: activityType)
            }
            .sorted(by: { ($0.endTime ?? $0.date) > ($1.endTime ?? $1.date) })
            .first
            .map(makeInsightSession(from:))
    }
    
    private func makeInsightSession(from record: ActivityExecutionRecord) -> InsightSession {
        let activityType = activityType(for: record.activityId)
        return InsightSession(
            id: record.activityId,
            sessionTitle: title(for: record.activityId),
            time: sessionTimeText(for: record),
            stats: sessionStats(for: record, activityType: activityType),
            vitals: sessionVitals(for: record)
        )
    }
    
    private func graphMetricValue(for activity: ActivityType, sessions: [InsightSession]) -> Double {
        switch activity {
        case .walking:
            let steps = sessions.reduce(0) { partial, session in
                partial + metricValue(in: session.stats, titled: "Steps")
            }
            if steps > 0 {
                return steps
            }
            
            let distance = sessions.reduce(0) { partial, session in
                partial + metricValue(in: session.stats, titled: "Distance")
            }
            if distance > 0 {
                return distance
            }
            
            return Double(sessions.count)
        case .exercise, .yoga:
            let metricTotal = sessions.reduce(0) { partial, session in
                let duration = metricValue(in: session.stats, titled: "Duration")
                let reps = metricValue(in: session.stats, titled: "Reps")
                return partial + max(duration, reps)
            }
            if metricTotal > 0 {
                return metricTotal
            }
            
            return Double(sessions.count)
        }
    }
    
    private func graphMetricTitle(for activity: ActivityType) -> String {
        switch activity {
        case .walking:
            return "Average Steps"
        case .exercise:
            return "Average Active Minutes"
        case .yoga:
            return "Average Practice Minutes"
        }
    }
    
    private func graphDisplayValue(for activity: ActivityType, averageValue: Double) -> String {
        switch activity {
        case .walking:
            return "\(Int(averageValue.rounded())) steps"
        case .exercise, .yoga:
            return "\(Int(averageValue.rounded())) min"
        }
    }
    
    private func sessionStats(for record: ActivityExecutionRecord, activityType: ActivityType) -> [SessionMetric] {
        var metrics: [SessionMetric] = []
        
        if let durationSeconds = record.durationSeconds, durationSeconds > 0 {
            metrics.append(SessionMetric(title: "Duration", value: "\(max(1, durationSeconds / 60))", unit: "min"))
        }
        
        if activityType == .walking {
            if let distance = record.distanceMeters, distance > 0 {
                metrics.append(SessionMetric(title: "Distance", value: formatted(distance / 1000.0), unit: "km"))
            }
            if let steps = record.steps, steps > 0 {
                metrics.append(SessionMetric(title: "Steps", value: "\(steps)", unit: "steps"))
            }
        } else {
            if let reps = record.reps, reps > 0 {
                metrics.append(SessionMetric(title: "Reps", value: "\(reps)", unit: "reps"))
            }
            if let sets = record.sets, sets > 0 {
                metrics.append(SessionMetric(title: "Sets", value: "\(sets)", unit: "sets"))
            }
        }
        
        if let calories = record.activeEnergyKcal, calories > 0 {
            metrics.append(SessionMetric(title: "Calories", value: "\(Int(calories.rounded()))", unit: "kcal"))
        }
        
        if metrics.isEmpty {
            metrics.append(SessionMetric(title: "Progress", value: record.status == .completed ? "100" : "0", unit: "%"))
        }
        
        return metrics
    }
    
    private func sessionVitals(for record: ActivityExecutionRecord) -> [SessionMetric]? {
        var vitals: [SessionMetric] = []
        
        if let heartRate = record.avgHeartRate, heartRate > 0 {
            vitals.append(SessionMetric(title: "Heart Rate", value: "\(heartRate)", unit: "bpm"))
            vitals.append(SessionMetric(title: "Peak Heart Rate", value: "\(heartRate)", unit: "bpm"))
        }
        
        if let spo2 = record.avgSpO2, spo2 > 0 {
            vitals.append(SessionMetric(title: "Respiratory Rate", value: formatted(spo2), unit: "%"))
            vitals.append(SessionMetric(title: "Peak Respiratory Rate", value: formatted(spo2), unit: "%"))
        }
        
        return vitals.isEmpty ? nil : vitals
    }
    
    private func sessionTimeText(for record: ActivityExecutionRecord) -> String {
        if let startTime = record.startTime, let endTime = record.endTime {
            return "\(Self.insightTimeFormatter.string(from: startTime)) - \(Self.insightTimeFormatter.string(from: endTime))"
        }
        
        if let sessionTime = record.startTime ?? record.endTime {
            return Self.insightTimeFormatter.string(from: sessionTime)
        }
        
        return "--"
    }
    
    private func formatDuration(_ durationSeconds: Int) -> String {
        let minutes = max(0, durationSeconds / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
        }
        return "\(max(1, minutes)) min"
    }
    
    private func metricValue(in metrics: [SessionMetric], titled title: String) -> Double {
        Double(metrics.first(where: { $0.title.lowercased() == title.lowercased() })?.value ?? "") ?? 0
    }
    
    private func title(for activityId: String) -> String {
        allActivities.first(where: { $0.activityId == activityId })?.metadata.title
            ?? activityId.replacingOccurrences(of: "_", with: " ").capitalized
    }
    
    private func activityType(for activityId: String) -> ActivityType {
        switch routineType(for: activityId) {
        case .walking:
            return .walking
        case .exercise:
            return .exercise
        case .yoga:
            return .yoga
        }
    }

    private func routineType(for activityId: String) -> RoutineType {
        let normalized = activityId.lowercased()

        if normalized.hasPrefix("walk_") || normalized.contains("walk") {
            return .walking
        }
        if normalized.hasPrefix("yoga_") || normalized.contains("yoga") {
            return .yoga
        }
        if normalized.hasPrefix("ex_") || normalized.contains("exercise") {
            return .exercise
        }

        if let matched = allActivities.first(where: { $0.activityId.caseInsensitiveCompare(activityId) == .orderedSame }) {
            let matchedId = matched.activityId.lowercased()
            if matchedId.hasPrefix("walk_") || matchedId.contains("walk") {
                return .walking
            }
            if matchedId.hasPrefix("yoga_") || matchedId.contains("yoga") {
                return .yoga
            }
        }

        return .exercise
    }
    
    private func matchesActivityType(_ activityId: String, activityType activityTypeValue: String) -> Bool {
        routineType(for: activityId).rawValue == activityTypeValue.lowercased()
    }
    
    func latestGestationalWeekWithProgress(for activity: ActivityType) -> Int? {
        progressWeekIndex.keys.sorted().reversed().first { week in
            weekRecords(for: week).values.contains { dayRecords in
                dayRecords.values.contains { record in
                    record.status != .pending
                        && matchesActivityType(record.activityId, activityType: activity.rawValue)
                }
            }
        }
    }

    // NEW: Resolve the best week to show in Insights. Prefer the requested
    // week when it has activity data, otherwise fall back to the latest saved
    // Firestore week for that activity so the user sees real progress.
    func preferredInsightWeek(for activity: ActivityType, preferredWeek: Int) -> Int {
        let safePreferredWeek = max(1, min(preferredWeek, 40))
        let preferredHasProgress = weekRecords(for: safePreferredWeek).values.contains { dayRecords in
            dayRecords.values.contains { record in
                record.status != .pending
                    && matchesActivityType(record.activityId, activityType: activity.rawValue)
            }
        }

        if preferredHasProgress {
            return safePreferredWeek
        }

        return latestGestationalWeekWithProgress(for: activity) ?? safePreferredWeek
    }

    func preferredHomeProgressWeek() -> Int {
        let currentWeek = max(1, min(userProfile.gestationalWeek, 40))
        let hasCurrentWeekProgress = weekRecords(for: currentWeek).values.contains { dayRecords in
            dayRecords.values.contains { $0.status != .pending }
        }

        if hasCurrentWeekProgress {
            return currentWeek
        }

        return latestGestationalWeekWithAnyProgress() ?? currentWeek
    }

    private func latestGestationalWeekWithAnyProgress() -> Int? {
        progressWeekIndex.keys.sorted().reversed().first { week in
            weekRecords(for: week).values.contains { dayRecords in
                dayRecords.values.contains { $0.status != .pending }
            }
        }
    }

    private func homeWeeklyActivitySummary(
        for activity: ActivityType,
        sessions: [InsightSession]
    ) -> (value: Double, unit: String, goal: Double, goalUnit: String, progress: Double) {
        switch activity {
        case .walking:
            let steps = totalMetricValue(named: "Steps", in: sessions)
            let goal = 8000.0
            return (
                value: steps,
                unit: "steps",
                goal: goal,
                goalUnit: "steps",
                progress: min(max(steps / goal, 0), 1)
            )
        case .exercise:
            let reps = totalMetricValue(named: "Reps", in: sessions)
            if reps > 0 {
                let goal = 300.0
                return (
                    value: reps,
                    unit: "reps",
                    goal: goal,
                    goalUnit: "reps",
                    progress: min(max(reps / goal, 0), 1)
                )
            }

            let minutes = totalMetricValue(named: "Duration", in: sessions)
            if minutes > 0 {
                let goal = 30.0
                return (
                    value: minutes,
                    unit: "min",
                    goal: goal,
                    goalUnit: "min",
                    progress: min(max(minutes / goal, 0), 1)
                )
            }

            let sessionCount = Double(sessions.count)
            let goal = 7.0
            return (
                value: sessionCount,
                unit: "sessions",
                goal: goal,
                goalUnit: "sessions",
                progress: min(max(sessionCount / goal, 0), 1)
            )
        case .yoga:
            let minutes = totalMetricValue(named: "Duration", in: sessions)
            if minutes > 0 {
                let goal = 20.0
                return (
                    value: minutes,
                    unit: "min",
                    goal: goal,
                    goalUnit: "min",
                    progress: min(max(minutes / goal, 0), 1)
                )
            }

            let sessionCount = Double(sessions.count)
            let goal = 2.0
            return (
                value: sessionCount,
                unit: "sessions",
                goal: goal,
                goalUnit: "sessions",
                progress: min(max(sessionCount / goal, 0), 1)
            )
        }
    }
    
    private func gestationalWeek(for date: Date) -> Int? {
        let startDate = istCalendar.startOfDay(for: pregnancyReferenceLMP())
        let normalizedDate = istCalendar.startOfDay(for: date)
        let dayOffset = istCalendar.dateComponents([.day], from: startDate, to: normalizedDate).day ?? 0
        guard dayOffset >= 0 else { return nil }
        return min(max((dayOffset / 7) + 1, 1), 40)
    }
    
    private func candidateActivityIds(for sessionId: String?, activityType activityTypeValue: String) -> Set<String> {
        var ids = Set<String>()
        if let sessionId, !sessionId.isEmpty {
            ids.insert(sessionId)
        }
        allActivities
            .filter { matchesActivityType($0.activityId, activityType: activityTypeValue) }
            .forEach { ids.insert($0.activityId) }
        return ids
    }
    
    private func formatted(_ value: Double) -> String {
        if value == floor(value) {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
    
    private func feedback(from value: Any?) -> UserFeedback? {
        guard let payload = value as? [String: Any],
              let idString = payload["id"] as? String,
              let id = UUID(uuidString: idString),
              let activityId = payload["activityId"] as? String,
              let difficultyRaw = payload["difficulty"] as? String,
              let fatigueRaw = payload["fatigue"] as? String,
              let difficulty = DifficultyLevel(rawValue: difficultyRaw),
              let fatigue = FatigueLevel(rawValue: fatigueRaw) else {
            return nil
        }
        
        return UserFeedback(
            id: id,
            activityId: activityId,
            difficulty: difficulty,
            fatigue: fatigue,
            note: (payload["note"] as? String)?.nilIfEmpty,
            createdAt: (payload["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
    
    private func notifyProgressChanged() {
        NotificationCenter.default.post(name: Self.progressDidChangeNotification, object: self)
    }
}

extension DataController {
    
    func changePassword(old: String, new: String, confirm: String) -> (Bool, String) {
        
        if old != userProfile.password {
            return (false, "Old password is incorrect")
        }
        
        if new != confirm {
            return (false, "New passwords do not match")
        }
        
        if new.count < 6 {
            return (false, "Password must be at least 6 characters")
        }
        
        userProfile.password = new
        saveProfileToFirestore()
        
        return (true, "Password updated successfully")
    }
    
    func updateUserName(name: String) {
        userProfile.name = name
        guard currentUserId != nil else { return }
        saveProfileToFirestore()
    }
    
    func updateUserCredentials(username: String, password: String) {
        
        userProfile.userName = username
        userProfile.password = password
        
        guard let userId = currentUserId else { return }
        saveProfileToFirestore()
    }
    
    func updateUserAge(_ age: Int) {
        userProfile.age = age
        guard let userId = currentUserId else { return }
        saveProfileToFirestore()
    }
    
    func updateGestationalWeek(_ week: Int, _ currentTrimester: Trimester) {
        let lmpDate = PregnancyDateCalculation.estimatedLMP(fromWeek: week, day: 0, calendar: istCalendar)
        let calculation = PregnancyDateCalculation.fromLMP(lmpDate)
        
        userProfile.lmpDate = calculation.lmpDate
        userProfile.eddDate = calculation.eddDate
        userProfile.gestationalWeek = week
        userProfile.gestationalDay = 0
        userProfile.trimester = currentTrimester
        resetPregnancyProgressDayAnchor()
        guard let userId = currentUserId else { return }
        saveProfileToFirestore()
    }
    
    func updatePregnancyDates(lmpDate: Date, eddDate: Date, gestationalWeek: Int, gestationalDay: Int, trimester: Trimester) {
        userProfile.lmpDate = lmpDate
        userProfile.eddDate = eddDate
        userProfile.gestationalWeek = gestationalWeek
        userProfile.gestationalDay = gestationalDay
        userProfile.trimester = trimester
        resetPregnancyProgressDayAnchor()
        guard let userId = currentUserId else { return }
        saveProfileToFirestore()
    }
    
    func updateMedicalCondition(_ condition: [MedicalCondition]) {
        userProfile.medicalConditions = condition
        guard let userId = currentUserId else { return }
        saveProfileToFirestore()
    }
    
    func updateActivityLevel(_ level : ActivityLevel) {
        userProfile.activityLevel = level
        guard let userId = currentUserId else { return }
        saveProfileToFirestore()
    }
    
    func updateHasAppleWatch(_ watchStatus: Bool) {
        userProfile.hasAppleWatch = watchStatus
        guard let userId = currentUserId else { return }
        saveProfileToFirestore()
    }
    
    func updateProfileImage(_ image: UIImage) {
        userProfile.profileImageData = image.jpegData(compressionQuality: 0.8)
        guard let userId = currentUserId else { return }
        saveProfileToFirestore()
    }
    
}

extension DataController {

    // NEW: Support both legacy top-level auth fields and the current
    // `userDetails.*` Firestore schema used by the app.
    private func normalizedUserDocumentData(from rawData: [String: Any]) -> [String: Any] {
        (rawData["userDetails"] as? [String: Any]) ?? rawData
    }

    // NEW: Username/email login was only checking top-level Firestore fields,
    // so accounts saved under `userDetails.userName` / `userDetails.email`
    // were incorrectly reported as missing.
    private func fetchUserDocument(
        field: String,
        identifier: String,
        completion: @escaping (QueryDocumentSnapshot?) -> Void
    ) {
        let candidateFields = [field, "userDetails.\(field)"]
        fetchUserDocument(in: candidateFields, identifier: identifier, index: 0, completion: completion)
    }

    private func fetchUserDocument(
        in candidateFields: [String],
        identifier: String,
        index: Int,
        completion: @escaping (QueryDocumentSnapshot?) -> Void
    ) {
        guard candidateFields.indices.contains(index) else {
            completion(nil)
            return
        }

        db.collection("users")
            .whereField(candidateFields[index], isEqualTo: identifier)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("User lookup error:", error)
                    completion(nil)
                    return
                }

                if let doc = snapshot?.documents.first {
                    completion(doc)
                    return
                }

                self?.fetchUserDocument(
                    in: candidateFields,
                    identifier: identifier,
                    index: index + 1,
                    completion: completion
                )
            }
    }
    
    func checkUserExists(username: String, completion: @escaping (Bool, [String: Any]?) -> Void) {
        fetchUserDocument(field: "userName", identifier: username.lowercased()) { doc in
            guard let doc else {
                completion(false, nil)
                return
            }

            completion(true, self.normalizedUserDocumentData(from: doc.data()))
        }
    }
    
    
    func loginWithUsername(
        credentials: LoginCredentials,
        completion: @escaping (Result<UserProfile, LoginError>, AuthState) -> Void
    ) {
        
        let identifier: String
        let field: String

        if let email = credentials.email, !email.isEmpty {
            identifier = email.lowercased()
            field = "email"
        } else if let username = credentials.username, !username.isEmpty {
            identifier = username.lowercased()
            field = "userName"
        } else {
            completion(.failure(.unknown), .existingUser)
            return
        }
        
        fetchUserDocument(field: field, identifier: identifier) { doc in
                guard let doc else {
                    DispatchQueue.main.async {
                        completion(.failure(.userNotFound), .existingUser)
                    }
                    return
                }
                
                let userId = doc.documentID
                let data = self.normalizedUserDocumentData(from: doc.data())
                
                let storedPassword = data["password"] as? String ?? ""
                
                if storedPassword != credentials.password {
                    completion(.failure(.wrongPassword), .existingUser)
                    return
                }
                
                // SAVE SESSION
                self.currentUserId = userId
                UserDefaults.standard.set(userId, forKey: "userId")
                UserDefaults.standard.set(true, forKey: "isLoggedIn") // 🔥 FIX
                UserDefaults.standard.set("username", forKey: "loginType")

                let profile = UserProfile(
                    userId: UUID(),
                    profileImageData: nil,
                    name: data["name"] as? String ?? "",
                    email: data["email"] as? String,
                    userName: identifier,
                    password: storedPassword,
                    age: data["age"] as? Int ?? 0,
                    lmpDate: self.dateValue(from: data["lmpDate"]),
                    eddDate: self.dateValue(from: data["eddDate"]),
                    gestationalWeek: data["week"] as? Int ?? 1,
                    gestationalDay: data["gestationalDay"] as? Int ?? 0,
                    trimester: Trimester(rawValue: data["trimester"] as? Int ?? 1) ?? .first,
                    medicalConditions: [],
                    activityLevel: ActivityLevel(rawValue: data["activityLevel"] as? String ?? "low") ?? .low,
                    hasAppleWatch: data["hasAppleWatch"] as? Bool ?? false
                )
                
                self.userProfile = profile
                self.refreshProgressIndexesAfterProfileUpdate()

                self.loadProgressFromFirestore {
                    DispatchQueue.main.async {
                        completion(.success(profile), .existingUser)
                    }
                }
            }
    }
}

extension DataController {
    
    func signInWithGoogle(from viewController: UIViewController, completion: @escaping (Result<UserProfile, Error>, AuthState) -> Void) {
        
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            completion(.failure(NSError(domain: "GoogleAuth", code: -1)), .existingUser)
            return
        }
        
        let config = GIDConfiguration(clientID: clientID)
        
        GIDSignIn.sharedInstance.configuration = config
        
        GIDSignIn.sharedInstance.signIn(withPresenting: viewController) { result, error in
            
            if let error = error {
                completion(.failure(error), .existingUser)
                return
            }
            
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                completion(.failure(NSError(domain: "GoogleAuth", code: -2)), .existingUser)
                return
            }
            
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )
            
            Auth.auth().signIn(with: credential) { authResult, error in
                
                if let error = error {
                    completion(.failure(error), .existingUser)
                    return
                }
                
                guard let firebaseUser = authResult?.user else {
                    let error = NSError(domain: "FirebaseAuth", code: -3, userInfo: [NSLocalizedDescriptionKey: "User not found after login"])
                    
                    completion(.failure(error), .existingUser)
                    return
                }

                let userId = firebaseUser.uid
                
                self.currentUserId = userId

                self.loadProfileFromFirestore { profile in
                    
                    DispatchQueue.main.async {
                        
                        UserDefaults.standard.set(true, forKey: "isLoggedIn")
                        UserDefaults.standard.set("google", forKey: "loginType")
                        UserDefaults.standard.set(userId, forKey: "userId")

                        if let existingProfile = profile {
                            
                            self.userProfile = existingProfile
                            self.loadProgressFromFirestore {
                                completion(.success(existingProfile), .existingUser)
                            }
                            
                        } else {
                            
                            let profile = self.createUserProfile(from: firebaseUser)
                            self.userProfile = profile
                            
                            self.saveProfileToFirestore()
                            
                            completion(.success(profile), .newUser)
                        }
                    }
                }
            }
        }
    }
    
    func signInAsGuest() -> UserProfile {
        setupGuestRegistrationDate()
        
        let profile = UserProfile(
            userId: UUID(),
            profileImageData: nil,
            name: "Guest",
            email: nil,
            userName: "Mom",
            password: "",
            age: 25,
            lmpDate: nil,
            eddDate: nil,
            gestationalWeek: 1,
            gestationalDay: 0,
            trimester: .first,
            medicalConditions: [],
            activityLevel: .low,
            hasAppleWatch: false
        )
        
        self.userProfile = profile
        
        return profile
    }
    
    func logout() {
        do {
            try Auth.auth().signOut()
        } catch {
            print("Logout error:", error)
        }
        
        self.currentUserId = nil
        
        UserDefaults.standard.set(false, forKey: "isLoggedIn")
        UserDefaults.standard.removeObject(forKey: "loginType")
        UserDefaults.standard.removeObject(forKey: "userId")
    }
    
    private func createUserProfile(from user: User) -> UserProfile {
        
        return UserProfile(
            userId: UUID(),
            profileImageData: nil,
            name: user.displayName ?? "",
            email: user.email?.lowercased(),
            userName: (user.email ?? "").lowercased(),
            password: "",
            age: 0,
            lmpDate: nil,
            eddDate: nil,
            gestationalWeek: 1,
            gestationalDay: 0,
            trimester: .first,
            medicalConditions: [],
            activityLevel: .low,
            hasAppleWatch: false
        )
    }
}

extension DataController {
    
    var onboardingGreetings: [String] {
        [
            "You’re in a safe space 🤍",
            "Let’s take this one step at a time",
            "Your body is doing something incredible",
            "We’re here to support you, always",
            "Gentle care for a beautiful journey",
            "Every pregnancy is unique — just like you",
            "Small steps, thoughtful care",
            "This journey deserves patience and love"
        ]
    }
    
    func onboardingGreeting(at index: Int) -> String {
        let messages = onboardingGreetings
        guard !messages.isEmpty else { return "" }
        return messages[index % messages.count]
    }
    
    func dynamicFootnote(routineType: RoutineType, completedItems: Int, totalItems: Int, rotationSeed: Int) -> [String] {
        routineType.footnotes(for: routineType, bucket: progressBucket(completed: completedItems, total: totalItems))
    }
    
    func progressBucket(completed: Int, total: Int) -> ProgressBucket {

        guard total > 0 else { return .notStarted }

        let p = Float(completed) / Float(total)

        switch p {

        case 0:
            return .notStarted

        case 0..<0.4:
            return .started

        case 0.4..<0.8:
            return .midway

        case 0.8..<1:
            return .almostDone

        default:
            return .completed
        }
    }
    
}

//Home
extension DataController {
    
    func getWatchVitals() -> [WatchVitalViewModel] {
        let vitals = latestHealthVitals
        let heartRate = vitals?.avgHeartRate ?? 0
        let spo2 = Int(vitals?.avgSpO2?.rounded() ?? 0)
        let sleepHours = 7
        let sleepMinutes = 0
        let todaySteps = vitals?.steps ?? 0
        
        return [
            WatchVitalViewModel(
                icon: "heart.fill",
                title: "Heart Rate",
                value: heartRate > 0 ? "\(heartRate) bpm" : "-- bpm",
                tint: .systemRed
            ),
            WatchVitalViewModel(
                icon: "lungs.fill",
                title: "SpO₂",
                value: spo2 > 0 ? "\(spo2)%" : "--%",
                tint: .systemBlue
            ),
            WatchVitalViewModel(
                icon: "bed.double.fill",
                title: "Sleep",
                value: "\(sleepHours)h \(sleepMinutes)m",
                tint: .systemPurple
            ),
            WatchVitalViewModel(
                icon: "figure.walk",
                title: "Steps",
                value: todaySteps > 0 ? "\(todaySteps.formatted())" : "--",
                tint: .systemGreen
            )
        ]
    }
    
    func getGreetingMessage() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let userName = userProfile.name
        
        if hour < 12 {
            return "Good Morning, \(userName)!"
        } else if hour < 17 {
            return "Good Afternoon, \(userName)!"
        } else {
            return "Good Evening, \(userName)!"
        }
    }
    
    func getVitalsSubtitle() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        
        if userProfile.trimester == .first {
            return hour < 12 ? "Rest is important in early pregnancy." : "Your vitals look stable today."
        } else if userProfile.trimester == .second {
            return hour < 12 ? "Your energy levels are at their peak." : "Stay hydrated and keep moving."
        } else {
            return hour < 12 ? "Take it easy, you're doing great." : "Rest when you need to."
        }
    }
    
    func getDayItems() -> [DayItem] {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        
        let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]
        
        return dayLabels.enumerated().map { index, label in
            let adjustedIndex = (index + 1) % 7
            return DayItem(title: label, isSelected: adjustedIndex == weekday - 1)
        }
    }
}


extension DataController {
    
    
    func loadInsightsFromJSON() -> [InsightResponse] {
        
        guard let url = Bundle.main.url(forResource: "insights", withExtension: "json") else {
            print("json not found")
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([InsightResponse].self, from: data)
            print("Decoded weeks count:", decoded.count)
            return decoded
        } catch {
            print("Decoding error:", error)
            return []
        }
    }
    
    
    
    func getCategoriesForCurrentWeek() -> [Category] {
        
        let allWeeks = loadInsightsFromJSON()
        let currentWeek = userProfile.gestationalWeek
        
        let matchingWeeks = allWeeks.filter { $0.week == currentWeek }
        
        let mergedCategories = matchingWeeks.flatMap { $0.categories }
        
        print("Categories for week \(currentWeek):", mergedCategories.count)
        
        return mergedCategories
    }
    
    
    func getInsightCardsForCurrentWeek() -> [Insights] {
        
        let categories = getCategoriesForCurrentWeek()
        
        return categories.compactMap { category in
            
            guard let firstItem = category.items.first else { return nil }
            
            return Insights(
                image: UIImage(named: category.heroImage)
                    ?? UIImage(systemName: "sparkles")!,
                title: category.title,
                description: firstItem.shortDescription,
                points: "+25 pts"
            )
        }
    }
    
    
    func getCategoryById(_ id: String) -> Category? {
        return getCategoriesForCurrentWeek()
            .first(where: { $0.id == id })
    }
    
    
    func getDetailForCategory(id: String) -> (title: String, body: String)? {
        
        guard let category = getCategoryById(id),
              let firstItem = category.items.first else {
            return nil
        }
        
        return (
            title: firstItem.title,
            body: firstItem.detailDescription
        )
    }
}
    
//Home
extension DataController {

    func loadInsightDetail(section: String, week: Int) -> InsightDetail? {

        // Try exact week first
        let exactFile = "\(section)_week_\(week)"
        if let url = Bundle.main.url(forResource: exactFile, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(InsightDetail.self, from: data) {
            return decoded
        }

        // Fallback to week 1 if current week doesn't exist yet
        let fallbackFile = "\(section)_week_1"
        guard let url = Bundle.main.url(forResource: fallbackFile, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(InsightDetail.self, from: data)
        else {
            print("❌ Could not load \(fallbackFile).json")
            return nil
        }

        print("⚠️ \(exactFile).json not found, using week 1 fallback")
        return decoded
    }
}

extension DataController {

    private var istCalendarForProgress: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    func saveRegistrationDate() {
        guard UserDefaults.standard.object(forKey: "registrationDate") == nil else { return }
        let today = istCalendarForProgress.startOfDay(for: Date())
        UserDefaults.standard.set(today, forKey: "registrationDate")
    }

    func getRegistrationDate() -> Date {
        if let saved = UserDefaults.standard.object(forKey: "registrationDate") as? Date {
            return saved
        }
        let today = istCalendarForProgress.startOfDay(for: Date())
        UserDefaults.standard.set(today, forKey: "registrationDate")
        return today
    }

    func getWeekDayLabels() -> [String] {
        let cal = istCalendarForProgress
        let today = cal.startOfDay(for: Date())
        let reg = cal.startOfDay(for: getRegistrationDate())
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")!

        guard let daysSinceReg = cal.dateComponents([.day], from: reg, to: today).day else {
            return Array(repeating: "", count: 6) + ["Today"]
        }

        var labels: [String] = []

        for slot in 0..<7 {
            if slot < 6 {
                let offsetFromReg = slot
                if offsetFromReg > daysSinceReg {
                    labels.append("")
                } else if offsetFromReg == daysSinceReg {
                    labels.append("Today")
                } else {
                    guard let day = cal.date(byAdding: .day, value: offsetFromReg, to: reg) else {
                        labels.append("")
                        continue
                    }
                    labels.append(formatter.string(from: day))
                }
            } else {
                if daysSinceReg >= 6 {
                    labels.append("Today")
                } else {
                    labels.append("")
                }
            }
        }

        return labels
    }

    func getWeekDayKeys() -> [String] {
        let cal = istCalendarForProgress
        let today = cal.startOfDay(for: Date())
        let reg = cal.startOfDay(for: getRegistrationDate())

        guard let daysSinceReg = cal.dateComponents([.day], from: reg, to: today).day else {
            return Array(repeating: "", count: 7)
        }

        var keys: [String] = []

        for slot in 0..<7 {
            if slot < 6 {
                let offsetFromReg = slot
                if offsetFromReg > daysSinceReg {
                    keys.append("")
                } else {
                    guard let day = cal.date(byAdding: .day, value: offsetFromReg, to: reg) else {
                        keys.append("")
                        continue
                    }
                    keys.append(dayKey(day))
                }
            } else {
                if daysSinceReg >= 6 {
                    keys.append(dayKey(today))
                } else {
                    keys.append("")
                }
            }
        }

        return keys
    }

    private func getRealChartData(for routineType: RoutineType) -> [Double] {
        let keys = getWeekDayKeys()
        return keys.map { key -> Double in
            guard !key.isEmpty else { return -1 }
            
            let completed = progressStore.values.filter {
                dayKey($0.date) == key && $0.status == .completed
            }
            
            guard !completed.isEmpty else { return 0 }
            
            switch routineType {
            case .walking:
                return Double(completed.count)
                
            case .exercise, .yoga:
                let durations = completed.compactMap { $0.durationSeconds }
                return durations.isEmpty ? 0 : Double(durations.reduce(0, +)) / 60.0
            }
        }
    }

    private func getGuestChartData(for routineType: RoutineType) -> [Double] {
        let cal = istCalendarForProgress
        let today = cal.startOfDay(for: Date())
        let reg = cal.startOfDay(for: getRegistrationDate())
        
        guard let daysSinceReg = cal.dateComponents([.day], from: reg, to: today).day else {
            return Array(repeating: -1, count: 7)
        }
        
        let seeds: [RoutineType: [Double]] = [
            .walking:  [3, 5, 2, 6, 4, 5, 3],
            .exercise: [18, 22, 15, 25, 20, 23, 19],
            .yoga:     [20, 25, 18, 28, 22, 26, 21]
        ]
        
        let base = seeds[routineType] ?? Array(repeating: 0, count: 7)
        var result: [Double] = []
        
        for slot in 0..<7 {
            if slot < 6 {
                if slot > daysSinceReg {
                    result.append(-1)
                } else if slot == daysSinceReg {
                    result.append(base[6])
                } else {
                    result.append(base[slot])
                }
            } else {
                result.append(daysSinceReg >= 6 ? base[6] : -1)
            }
        }
        
        return result
    }

    func getChartValues(for routineType: RoutineType) -> [Double] {
        return currentUserId == nil
            ? getGuestChartData(for: routineType)
            : getRealChartData(for: routineType)
    }

    func getCurrentStreak() -> Int {
        let cal = istCalendarForProgress
        let today = cal.startOfDay(for: Date())
        var streak = 0
        var checkDate = today

        while true {
            let key = dayKey(checkDate)
            let dayRecords = progressStore.values.filter { dayKey($0.date) == key }
            let hasActivity = dayRecords.contains { $0.status == .completed }

            if checkDate == today {
                if hasActivity { streak += 1 }
            } else {
                guard hasActivity else { break }
                streak += 1
            }

            guard let previous = cal.date(byAdding: .day, value: -1, to: checkDate) else { break }
            let reg = cal.startOfDay(for: getRegistrationDate())
            if previous < reg { break }
            checkDate = previous
        }

        UserDefaults.standard.set(streak, forKey: "currentStreak")
        return streak
    }

    func getLongestStreak() -> Int {
        let cal = istCalendarForProgress
        let reg = cal.startOfDay(for: getRegistrationDate())
        let today = cal.startOfDay(for: Date())

        guard let totalDays = cal.dateComponents([.day], from: reg, to: today).day else { return 0 }

        var longest = 0
        var current = 0

        for offset in 0...totalDays {
            guard let date = cal.date(byAdding: .day, value: offset, to: reg) else { continue }
            let key = dayKey(date)
            let hasActivity = progressStore.values.contains {
                dayKey($0.date) == key && $0.status == .completed
            }
            if hasActivity {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }

        return longest
    }

    func getOverallCompletionPercent(for date: Date) -> Int {
        let types = RoutineType.allCases
        var totalItems = 0
        var handled = 0

        for type in types {
            let items = getRoutineItems(for: type, date: date)
            totalItems += items.count
            handled += items.filter {
                let p = loadProgress(for: $0, date: date)
                return p.status == .completed || p.status == .skipped
            }.count
        }

        guard totalItems > 0 else { return 0 }
        return Int((Double(handled) / Double(totalItems)) * 100)
    }

    func getMotivationMessage() -> String {
        let isGuest = currentUserId == nil
        
        if isGuest {
            return getGuestMotivation()
        } else {
            return getRealMotivation()
        }
    }
    
    private func getGuestMotivation() -> String {
        guard let url = Bundle.main.url(forResource: "footerInsights", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(InsightsResponse.self, from: data) else {
            return "A calm evening routine helps you and baby sleep better."
        }
        let week = userProfile.gestationalWeek
        let weekStr = "week_\(week)"
        let all = decoded.insights.flatMap { insight in
            insight.weeks.filter { $0.week == weekStr }.flatMap { weekData in
                weekData.days.flatMap { $0.sessions.map { $0.sessionTitle } }
            }
        }
        return all.randomElement() ?? "A calm evening routine helps you and baby sleep better."
    }

    private func getRealMotivation() -> String {
        let trimester = userProfile.trimester
        let hour = Calendar.current.component(.hour, from: Date())
        
        let messages: [Trimester: [String]] = [
            .first: [
                "Small steps today build strength for tomorrow.",
                "Rest when you need to, move when you can.",
                "Your body is doing incredible work right now.",
                "Gentle movement supports you and baby both.",
                "Every little effort counts — you're doing great."
            ],
            .second: [
                "Your energy is building — keep the momentum.",
                "Stay hydrated and keep moving, mama.",
                "You're halfway there — celebrate every session.",
                "Consistency now makes the third trimester easier.",
                "Baby feels your movement — keep it up!"
            ],
            .third: [
                "Take it one breath, one step at a time.",
                "Rest is just as important as movement now.",
                "You're in the home stretch — be proud.",
                "Listen to your body, it knows what it needs.",
                "Almost there — every session is a gift to baby."
            ]
        ]
        
        let pool = messages[trimester] ?? messages[.first]!
        
        if hour < 12 {
            return pool.first ?? "You're doing amazing."
        } else if hour < 17 {
            return pool[safe: 1] ?? pool.randomElement() ?? "Keep going!"
        } else {
            return pool.last ?? "Rest well tonight."
        }
    }
    
    func setupGuestRegistrationDate() {
        let cal = istCalendarForProgress
        let today = cal.startOfDay(for: Date())
        guard let sixDaysAgo = cal.date(byAdding: .day, value: -6, to: today) else { return }
        UserDefaults.standard.set(sixDaysAgo, forKey: "registrationDate")
    }
    
    //for most recent item
    func getMostRecentlyActiveItem(for type: RoutineType, date: Date) -> (item: RoutineItem, progress: RoutineItemProgress)? {
        let items = getRoutineItems(for: type, date: date)
        
        // First priority: currently in progress (pending with elapsed > 0)
        let inProgress = items
            .compactMap { item -> (RoutineItem, RoutineItemProgress)? in
                let p = loadProgress(for: item, date: date)
                guard p.status == .pending && p.elapsedSeconds > 0 else { return nil }
                return (item, p)
            }
            .sorted { $0.1.elapsedSeconds > $1.1.elapsedSeconds }
            .first
        
        if let inProgress = inProgress { return inProgress }
        
        // Second priority: first pending (not yet started)
        if let pending = items.first(where: {
            loadProgress(for: $0, date: date).status == .pending
        }) {
            return (pending, loadProgress(for: pending, date: date))
        }
        
        return nil
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension DataController {
    // Debug helper: keep this seeder for local/demo verification of the week/day
    // Firestore structure. It intentionally writes valid progress into progress_weeks.
    func loadDummyProgressDataUntilCurrentDay(completion: (() -> Void)? = nil) {
        guard progressStore.isEmpty else {
            completion?()
            return
        }

        guard let userId = currentUserId else {
            let seed = makeDummyProgressSeedUntilCurrentDay()
            replaceProgressState(restored: seed.records, feedbackLookup: seed.feedbackLookup)
            completion?()
            return
        }

        db.collection("users")
            .document(userId)
            .collection("progress_weeks")
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else {
                    completion?()
                    return
                }

                if let error = error {
                    print("Dummy seed preflight Firestore error:", error)
                    let seed = self.makeDummyProgressSeedUntilCurrentDay()
                    self.replaceProgressState(restored: seed.records, feedbackLookup: seed.feedbackLookup)
                    completion?()
                    return
                }

                let docs = snapshot?.documents ?? []
                if !docs.isEmpty {
                    let restored = self.restoreProgressRecords(fromWeekDocuments: docs)
                    var feedbackLookup: [UUID: UserFeedback] = [:]
                    restored.values.forEach { record in
                        if let feedback = record.feedback {
                            feedbackLookup[feedback.id] = feedback
                        }
                    }
                    self.replaceProgressState(restored: restored, feedbackLookup: feedbackLookup)
                    completion?()
                    return
                }

                let seed = self.makeDummyProgressSeedUntilCurrentDay()
                self.saveProfileToFirestore()
                self.persistSeedProgressToFirestore(records: seed.records) { success in
                    if success {
                        self.replaceProgressState(restored: seed.records, feedbackLookup: seed.feedbackLookup)
                    } else {
                        self.replaceProgressState(restored: seed.records, feedbackLookup: seed.feedbackLookup)
                    }
                    completion?()
                }
            }
    }

    private func makeDummyProgressSeedUntilCurrentDay() -> (
        records: [String: ActivityExecutionRecord],
        feedbackLookup: [UUID: UserFeedback]
    ) {
        let calendar = istCalendar
        let today = calendar.startOfDay(for: Date())
        let currentWeek = max(1, min(userProfile.gestationalWeek, 40))
        let currentDayIndex = max(0, min(userProfile.gestationalDay, 6))
        var seeded: [String: ActivityExecutionRecord] = [:]
        var seededFeedback: [UUID: UserFeedback] = [:]

        for week in 1...currentWeek {
            let dates = datesForGestationalWeek(week)
            let lastDayIndex = week == currentWeek ? min(currentDayIndex, max(0, dates.count - 1)) : max(0, dates.count - 1)
            guard !dates.isEmpty else { continue }

            for dayIndex in 0...lastDayIndex {
                let date = calendar.startOfDay(for: min(dates[dayIndex], today))
                let types = ActivityType.allCases.shuffled()

                for activityType in types {
                    let sessionCount = Int.random(in: 0...2)
                    guard sessionCount > 0 else { continue }

                    let candidates = allActivities.filter {
                        self.activityType(for: $0.activityId) == activityType
                    }
                    guard !candidates.isEmpty else { continue }

                    for sessionIndex in 0..<sessionCount {
                        let definition = candidates.randomElement() ?? candidates[0]
                        guard let record = dummyProgressRecord(
                            activity: definition,
                            activityType: activityType,
                            date: date,
                            sessionIndex: sessionIndex
                        ) else { continue }

                        let key = progressKey(activityId: record.activityId, date: record.date)
                        seeded[key] = record

                        if let feedback = record.feedback {
                            seededFeedback[feedback.id] = feedback
                        }
                    }
                }
            }
        }

        return (records: seeded, feedbackLookup: seededFeedback)
    }

    private func persistSeedProgressToFirestore(
        records: [String: ActivityExecutionRecord],
        completion: @escaping (Bool) -> Void
    ) {
        guard let userId = currentUserId else {
            completion(false)
            return
        }

        var payloadsByWeek: [String: [String: Any]] = [:]

        for (documentKey, record) in records {
            guard let writePayload = progressWeekWritePayload(
                record: record,
                feedback: record.feedback,
                documentKey: documentKey
            ) else { continue }

            var merged = payloadsByWeek[writePayload.documentId] ?? [:]
            for (field, value) in writePayload.data {
                merged[field] = value
            }
            payloadsByWeek[writePayload.documentId] = merged
        }

        let batch = db.batch()
        for (documentId, payload) in payloadsByWeek {
            let ref = db.collection("users")
                .document(userId)
                .collection("progress_weeks")
                .document(documentId)
            batch.setData(payload, forDocument: ref, merge: true)
        }

        batch.commit { error in
            if let error = error {
                print("Dummy seed Firestore write error:", error)
                completion(false)
            } else {
                print("Dummy seed Firestore write success:", records.count)
                completion(true)
            }
        }
    }

    private func dummyProgressRecord(
        activity: ActivityDefinition,
        activityType: ActivityType,
        date: Date,
        sessionIndex: Int
    ) -> ActivityExecutionRecord? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let sessionOffsetMinutes = 360 + (sessionIndex * 150) + Int.random(in: 0...40)
        let startTime = istCalendar.date(byAdding: .minute, value: sessionOffsetMinutes, to: date) ?? date
        let durationMinutes: Int
        let distanceMeters: Double
        let steps: Int
        let reps: Int
        let sets: Int

        switch activityType {
        case .walking:
            durationMinutes = Int.random(in: 18...42)
            distanceMeters = Double(Int.random(in: 900...3600))
            steps = Int.random(in: 1200...6200)
            reps = 0
            sets = 0
        case .exercise:
            durationMinutes = Int.random(in: 12...35)
            distanceMeters = 0
            steps = Int.random(in: 200...1800)
            reps = Int.random(in: 10...40)
            sets = Int.random(in: 1...4)
        case .yoga:
            durationMinutes = Int.random(in: 15...40)
            distanceMeters = 0
            steps = Int.random(in: 100...900)
            reps = Int.random(in: 4...18)
            sets = Int.random(in: 1...3)
        }

        let endTime = istCalendar.date(byAdding: .minute, value: durationMinutes, to: startTime) ?? startTime
        let calories = Double(Int.random(in: 45...220))
        let heartRate = Int.random(in: 88...138)
        let spo2 = Double(Int.random(in: 94...99))
        let shouldAddFeedback = Int.random(in: 0...4) == 0

        var json: [String: Any] = [
            "activityId": activity.activityId,
            "date": isoFormatter.string(from: date),
            "startTime": isoFormatter.string(from: startTime),
            "endTime": isoFormatter.string(from: endTime),
            "status": RoutineItemStatus.completed.rawValue,
            "duration": durationMinutes * 60,
            "distance": distanceMeters,
            "reps": reps,
            "sets": sets,
            "stats": [
                "steps": steps,
                "distance": distanceMeters,
                "calories": calories,
                "reps": reps,
                "sets": sets
            ],
            "vitals": [
                "heartRate": heartRate,
                "spo2": spo2
            ]
        ]

        if shouldAddFeedback {
            json["feedback"] = [
                "id": UUID().uuidString,
                "activityId": activity.activityId,
                "difficulty": [DifficultyLevel.beginner, .intermediate, .advanced].randomElement()?.rawValue ?? DifficultyLevel.beginner.rawValue,
                "fatigue": [FatigueLevel.none, .low, .moderate].randomElement()?.rawValue ?? FatigueLevel.low.rawValue,
                "note": ["Felt good", "Nice session", "Comfortable pace", "Good energy"].randomElement() ?? "Good energy",
                "createdAt": isoFormatter.string(from: endTime)
            ]
        }

        guard JSONSerialization.isValidJSONObject(json),
              let data = try? JSONSerialization.data(withJSONObject: json),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return dummyProgressRecord(fromJSON: decoded)
    }

    private func dummyProgressRecord(fromJSON payload: [String: Any]) -> ActivityExecutionRecord? {
        guard let activityId = payload["activityId"] as? String,
              let dateString = payload["date"] as? String,
              let date = ISO8601DateFormatter().date(from: dateString) else {
            return nil
        }

        let stats = payload["stats"] as? [String: Any]
        let vitals = payload["vitals"] as? [String: Any]
        let startTime = ISO8601DateFormatter().date(from: payload["startTime"] as? String ?? "")
        let endTime = ISO8601DateFormatter().date(from: payload["endTime"] as? String ?? "")
        let feedback = dummyFeedback(fromJSON: payload["feedback"] as? [String: Any])

        return ActivityExecutionRecord(
            activityId: activityId,
            date: date,
            firestoreWeek: intValue(payload["week"]),
            startTime: startTime,
            endTime: endTime,
            status: RoutineItemStatus(rawValue: payload["status"] as? String ?? "") ?? .completed,
            durationSeconds: intValue(payload["duration"]),
            distanceMeters: doubleValue(payload["distance"]) ?? doubleValue(stats?["distance"]),
            activeEnergyKcal: doubleValue(stats?["calories"]),
            avgHeartRate: intValue(vitals?["heartRate"]),
            avgSpO2: doubleValue(vitals?["spo2"]),
            steps: intValue(stats?["steps"]),
            reps: intValue(payload["reps"]) ?? intValue(stats?["reps"]),
            sets: intValue(payload["sets"]) ?? intValue(stats?["sets"]),
            feedback: feedback
        )
    }

    private func dummyFeedback(fromJSON payload: [String: Any]?) -> UserFeedback? {
        guard let payload,
              let idString = payload["id"] as? String,
              let id = UUID(uuidString: idString),
              let activityId = payload["activityId"] as? String,
              let difficultyRaw = payload["difficulty"] as? String,
              let fatigueRaw = payload["fatigue"] as? String,
              let difficulty = DifficultyLevel(rawValue: difficultyRaw),
              let fatigue = FatigueLevel(rawValue: fatigueRaw),
              let createdAtString = payload["createdAt"] as? String,
              let createdAt = ISO8601DateFormatter().date(from: createdAtString) else {
            return nil
        }

        return UserFeedback(
            id: id,
            activityId: activityId,
            difficulty: difficulty,
            fatigue: fatigue,
            note: payload["note"] as? String,
            createdAt: createdAt
        )
    }
}

//Insights
private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

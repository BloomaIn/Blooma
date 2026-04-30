//
//  Model.swift
//  prenatalPregnancy
//
//  Created by GEU on 30/01/26.
//

import Foundation
import UIKit

//Login
enum LoginType: String {
    case google
    case apple
    case guest
}

struct LoginCredentials {
    var username: String?
    var email: String?
    var password: String
}

enum AuthState {
    case newUser
    case existingUser
}

enum LoginError: LocalizedError {
    case userNotFound
    case wrongPassword
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .userNotFound:
            return "User not found"
        case .wrongPassword:
            return "Incorrect password"
        case .unknown:
            return "Something went wrong"
        }
    }
}

struct UserProfile: Codable, Identifiable {
    let userId: UUID
    var profileImageData: Data?
    var name: String
    var email: String?
    var userName: String
    var password: String
    var age: Int
    var lmpDate: Date?
    var eddDate: Date?
    var gestationalWeek: Int
    var gestationalDay: Int
    var trimester: Trimester
    var medicalConditions: [MedicalCondition]
    var activityLevel: ActivityLevel
    var hasAppleWatch: Bool
    
    var id: UUID { userId }
}

enum Trimester: Int, Codable {
    case first = 1
    case second = 2
    case third = 3
    
    var displayTitle: String {
        switch self {
        case .first: return "First Trimester"
        case .second: return "Second Trimester"
        case .third: return "Third Trimester"
        }
    }
}

struct PregnancyDateCalculation {
    let lmpDate: Date
    let eddDate: Date
    let gestationalWeek: Int
    let gestationalDay: Int
    let trimester: Trimester
    
    var gestationalDisplay: String {
        "Week \(gestationalWeek) + \(gestationalDay) day\(gestationalDay == 1 ? "" : "s")"
    }
    
    static let pregnancyLengthInDays = 280
    
    static func fromLMP(_ date: Date, calendar: Calendar = .current, today: Date = Date()) -> PregnancyDateCalculation {
        let normalizedLMP = calendar.startOfDay(for: date)
        let normalizedToday = calendar.startOfDay(for: today)
        let totalDays = max(0, calendar.dateComponents([.day], from: normalizedLMP, to: normalizedToday).day ?? 0)
        let week = max(1, min(42, (totalDays / 7) + 1))
        let day = totalDays % 7
        let eddDate = calendar.date(byAdding: .day, value: pregnancyLengthInDays, to: normalizedLMP) ?? normalizedLMP
        
        return PregnancyDateCalculation(
            lmpDate: normalizedLMP,
            eddDate: eddDate,
            gestationalWeek: week,
            gestationalDay: day,
            trimester: trimester(for: week)
        )
    }
    
    static func fromEDD(_ date: Date, calendar: Calendar = .current, today: Date = Date()) -> PregnancyDateCalculation {
        let normalizedEDD = calendar.startOfDay(for: date)
        let lmpDate = calendar.date(byAdding: .day, value: -pregnancyLengthInDays, to: normalizedEDD) ?? normalizedEDD
        return fromLMP(lmpDate, calendar: calendar, today: today)
    }
    
    static func trimester(for week: Int) -> Trimester {
        switch week {
        case 1...12:
            return .first
        case 13...27:
            return .second
        default:
            return .third
        }
    }
    
    static func estimatedLMP(fromWeek week: Int, day: Int, calendar: Calendar = .current, today: Date = Date()) -> Date {
        let totalDays = max(0, ((max(1, week) - 1) * 7) + max(0, day))
        return calendar.date(byAdding: .day, value: -totalDays, to: calendar.startOfDay(for: today)) ?? today
    }
}

enum ActivityLevel: String, Codable, CaseIterable {
    case low
    case moderate
    case high
    
    var displayName: String {
        switch self {
        case .low: return "Gentle"
        case .moderate: return "Balanced"
        case .high: return "Active"
        }
    }
}

enum MedicalCondition: String, Codable, CaseIterable {
    case none
    case anemia
    case hypertension
    case diabetes
    case thyroid
    case obesity
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .anemia: return "Anemia"
        case .hypertension: return "Hypertension"
        case .diabetes: return "Diabetes"
        case .thyroid: return "Thyroid"
        case .obesity: return "Obesity"
        }
    }
}

enum RoutineType: String, Codable, CaseIterable {
    case walking
    case exercise
    case yoga
}

enum RoutineItemStatus: String, Codable {
    case pending
    case inProgress
    case completed
    case skipped
}

struct ActivityDefinition: Codable, Identifiable {
    
    let activityId: String
    let metadata: Metadata
    let content: Content
    let media: Media
    let prescription: Prescription
    let intensity: Intensity
    let medicalSafety: MedicalSafety
    let userCapabilityRequirement: Capability
    
    var id: String { activityId }
    
    struct Metadata: Codable {
        let title: String
        let description: String
    }
    
    struct Content: Codable {
        let benefits: [String]
        let instructions: [String]
        let safetyTips: [String]
    }
    
    struct Media: Codable {
        let video: String
        let image: String
    }
    
    struct Prescription: Codable {
        let trimester: [String]
        let sets: Int?
        let reps: Int?
        let durationMinutes: Int
        let recommendedDistanceMeters: Int?
    }
    
    struct Intensity: Codable {
        let intensityLevel: String
    }
    
    struct MedicalSafety: Codable {
        let medicalConditions: [String]
        let contraindications: [String]
    }
    
    struct Capability: Codable {
        let allowedActivityLevels: [String]
    }
}

struct RoutineItem: Identifiable {
    let id = UUID()
    
    
    let activityId: String
    let routineType: RoutineType
    let title: String
    
    let video: String
    let image: String
    
    let durationSeconds: Int
    let distanceMeters: Int?
    let sets: Int?
    let reps: Int?
    let difficulty: String?
    
    let description: String
    let benefits: [String]
    let instructions: [String]
    let safetyTips: [String]
    
    var status: RoutineItemStatus
}

struct RoutineSession: Identifiable {
    let id = UUID()
    let routineType: RoutineType
    let totalItems: Int
    let totalDuration: Int
}

struct ActivityExecutionRecord: Codable {
    
    let activityId: String
    let date: Date
    // NEW: Preserve the Firestore progress_weeks document week so Insights can
    // render the exact saved week even if the local profile dates change later.
    var firestoreWeek: Int?
    
    var startTime: Date?
    var endTime: Date?
    var status: RoutineItemStatus
    
    var durationSeconds: Int?
    var distanceMeters: Double?
    var activeEnergyKcal: Double?
    
    // Watch (optional)
    var avgHeartRate: Int?
    var avgSpO2: Double?
    var steps: Int?
    var reps: Int?
    var sets: Int?
    var feedback: UserFeedback?
}

struct ActivityRotationRecord: Codable {
    let activityId: String
    let lastPerformedDate: Date
}

struct RoutineItemStatusCount {
    let completed: Int
    let skipped: Int
    let pending: Int
    let total: Int
}

enum ProgressBucket {
    case notStarted
    case started
    case midway
    case almostDone
    case completed
}

enum RoutineSection: Int, CaseIterable {
    case recommended
    case routine
}

struct UserFeedback: Codable {
    
    let id: UUID
    let activityId: String
    let difficulty: DifficultyLevel
    let fatigue: FatigueLevel
    let note: String?
    let createdAt: Date
    
}

enum DifficultyLevel: String, Codable, CaseIterable {
    case beginner
    case intermediate
    case advanced

    var displayText: String {
        switch self {
        case .beginner:
            return "Beginner"
        case .intermediate:
            return "Intermediate"
        case .advanced:
            return "Advanced"
        }
    }
}

enum FatigueLevel: String, Codable, CaseIterable {
    case none
    case low
    case moderate
    case high

    var displayText: String {
        switch self {
        case .none:
            return "None"
        case .low:
            return "Low"
        case .moderate:
            return "Moderate"
        case .high:
            return "High"
        }
    }
}

enum Section: Int, CaseIterable {
    case header
    case difficulty
    case fatigue
    case notes
}

enum RoutineControlMode {
    case start
    case continueExercise
    case pause
    case play
    case completed
    case skipped
}

enum DetailSection: Int, CaseIterable {
    case description
    case instructions
    case benefits
    case safety
}

//Progress
struct ActivitySchedule: Codable {
    let scheduleMetadata: ScheduleMetadata
    var insights: [Insight]
}

struct ScheduleMetadata: Codable {
    let planTitle: String
    let startDate: String
    let endDate: String
    let totalDays: Int
    let durationMonths: Int
}


//Filtering
enum RoutineProcessingStep: Int, CaseIterable {
    
    case filteringType
    case applyingTrimester
    case checkingProfile
    case validatingHealth
    case matchingLevel
    case finalizing
    
    var title: String {
        switch self {
        case .filteringType:
            return "Analyzing activities..."
            
        case .applyingTrimester:
            return "Adjusting for your trimester..."
            
        case .checkingProfile:
            return "Reviewing your profile..."
            
        case .validatingHealth:
            return "Ensuring safety..."
            
        case .matchingLevel:
            return "Matching your activity level..."
            
        case .finalizing:
            return "Finalizing your routine..."
        }
    }
    
    var subtitle: String {
        switch self {
        case .filteringType:
            return "Selecting suitable activity types"
            
        case .applyingTrimester:
            return "Filtering based on your current stage"
            
        case .checkingProfile:
            return "Considering your personal details"
            
        case .validatingHealth:
            return "Applying safety guidelines"
            
        case .matchingLevel:
            return "Aligning with your comfort level"
            
        case .finalizing:
            return "Preparing your personalized plan"
        }
    }
}

//Profile
enum ProfileSection: Int, CaseIterable {
    
    case header
    case yourInformation
    case healthActivity
    case devices
    case privacy
    case support
    case about
    
    var title: String {
        switch self {
        case .header:
            return ""
        case .yourInformation:
            return "Your Information"
        case .healthActivity:
            return "Health & Activity"
        case .devices:
            return "Connected Devices"
        case .privacy:
            return "Privacy & Compliance"
        case .support:
            return "Support & Research"
        case .about:
            return "About App"
        }
    }
    
    var rows: [ProfileRow] {
        switch self {
            
        case .header:
            return []
            
        case .yourInformation:
            return [.personalInformation, .pregnancyInformation]
            
        case .healthActivity:
            return [.medicalConditions, .activityStatus]
            
        case .devices:
            return [.appleWatch]
            
        case .privacy:
            return [.legalCompliance, .permissions]
            
        case .support:
            return [.helpSupport, .researchInsights, .dataSources]
            
        case .about:
            return [.aboutBlooma, .credits, .logout]
        }
    }
}

enum ProfileRow {
    
    // Your Information
    case personalInformation
    case pregnancyInformation
    
    // Health
    case medicalConditions
    case activityStatus
    
    // Devices
    case appleWatch
    
    // Privacy
    case legalCompliance
    case permissions
    
    // Support
    case helpSupport
    case researchInsights
    case dataSources
    
    // About
    case aboutBlooma
    case credits
    case logout
    
    var title: String {
        switch self {
        case .personalInformation: return "Personal Information"
        case .pregnancyInformation: return "Pregnancy Information"
        case .medicalConditions: return "Medical Conditions"
        case .activityStatus: return "Activity Status"
        case .appleWatch: return "Apple Watch"
        case .legalCompliance: return "Legal & Compliance"
        case .permissions: return "Permissions"
        case .helpSupport: return "Help & Support"
        case .researchInsights: return "Research & Insights"
        case .dataSources: return "Data Sources"
        case .aboutBlooma: return "About Blooma"
        case .credits: return "Credits & Contributors"
        case .logout: return "Logout"
        }
    }
    
    var icon: String {
        switch self {
        case .personalInformation: return "person.text.rectangle"
        case .pregnancyInformation: return "heart.text.square"
        case .medicalConditions: return "cross.case"
        case .activityStatus: return "figure.run"
        case .appleWatch: return "applewatch"
        case .legalCompliance: return "doc.text"
        case .permissions: return "lock.shield"
        case .helpSupport: return "questionmark.circle"
        case .researchInsights: return "brain.head.profile"
        case .dataSources: return "externaldrive"
        case .aboutBlooma: return "info.circle"
        case .credits: return "person.3.fill"
        case .logout: return "rectangle.portrait.and.arrow.right"
        }
    }
    
    var subtitle: String {
        switch self {
            
        case .personalInformation:
            return "Manage your basic personal details like name and age."
            
        case .pregnancyInformation:
            return "Track your pregnancy progress and trimester details."
            
        case .medicalConditions:
            return "View and update your medical conditions."
            
        case .activityStatus:
            return "Monitor and adjust your daily activity level."
            
        case .appleWatch:
            return "Connect and manage your Apple Watch device."
            
        case .legalCompliance:
            return "View legal terms, policies and compliance details."
            
        case .permissions:
            return "Manage app permissions and privacy controls."
            
        case .helpSupport:
            return "Get help, FAQs and customer support."
            
        case .researchInsights:
            return "Explore research-based pregnancy insights."
            
        case .dataSources:
            return "See where your health data comes from."
            
        case .aboutBlooma:
            return "Learn more about the Blooma app."
            
        case .credits:
            return "Meet the experts, instructors, and contributors behind the app."
            
        case .logout:
            return "Sign out from your account securely."
        }
    }
    
    var contentId: String? {
        switch self {
        case .aboutBlooma:
            return "about_blooma"
            
        case .dataSources:
            return "data_sources"
            
        case .researchInsights:
            return "research_insights"
            
        case .legalCompliance:
            return "legal_compliance"
            
        default:
            return nil
        }
    }
    
    var isEditable: Bool {
        switch self {
        case .personalInformation, .pregnancyInformation, .medicalConditions, .activityStatus, .appleWatch:
            return true
            
        case .logout:
            return false
            
        default:
            return false
        }
    }
    
    var style: Style {
        switch self {
        case .logout:
            return .action
        default:
            return .normal
        }
    }
}

struct ProfileSectionData {
    let section: ProfileSection
    let rows: [ProfileRow]
}

struct ProfileDisplayValue {
    
    static func value(for row: ProfileRow, profile: UserProfile) -> String? {
        
        switch row {
            
        case .personalInformation:
            return profile.name
            
        case .pregnancyInformation:
            return "Week \(profile.gestationalWeek) + \(profile.gestationalDay) days (\(profile.trimester.displayTitle))"
            
        case .medicalConditions:
            return profile.medicalConditions.isEmpty ? "None" : profile.medicalConditions.map { $0.displayName }.joined(separator: ", ")
            
        case .activityStatus:
            return profile.activityLevel.displayName
            
        case .appleWatch:
            return profile.hasAppleWatch ? "Connected" : "Not Connected"
            
        default:
            return nil
        }
    }
}

enum ProfileDetailItem {
    
    case value(title: String, value: String?)
    case description(title: String, subtitle: String, icon: String)
}

enum PickerType {
    case age
    case week
    case lmpDate
    case eddDate
    case activity
}

enum PermissionType {
    case motion
    case camera
    case photo
    case notification
    
    var icon: String {
        switch self {
        case .motion: return "figure.walk"
        case .camera: return "camera"
        case .photo: return "photo.on.rectangle"
        case .notification: return "bell.badge"
        }
    }
    
    var title: String {
        switch self {
        case .motion: return "Motion & Activity"
        case .camera: return "Camera"
        case .photo: return "Photo Library"
        case .notification: return "Notifications"
        }
    }
    
    var description: String {
        switch self {
        case .motion:
            return "Track activity for safe prenatal workouts."
        case .camera:
            return "Capture a photo for your profile when you choose."
        case .photo:
            return "Select images from your device for your profile."
        case .notification:
            return "Receive reminders for daily prenatal activities."
        }
    }
}

struct PermissionItem {
    let type: PermissionType
    
    var icon: String { type.icon }
    var title: String { type.title }
    var description: String { type.description }
    
    static var all: [PermissionItem] {
        return [
            PermissionItem(type: .motion),
            PermissionItem(type: .camera),
            PermissionItem(type: .photo),
            PermissionItem(type: .notification)
        ]
    }
}

enum PermissionStatus {
    case notDetermined
    case denied
    case authorized
}

struct AppContent: Codable {
    let id: String?
    let title: String
    let subtitle: String?
    let sections: [ContentSection]
}

struct ContentSection: Codable {
    let id: String?
    let title: String
    let content: ContentData
}

struct ContentData: Codable {
    let heroTitle: String
    let heroSubtitle: String
    let introBlocks: [IntroBlock]
    let items: [Item]
    
    enum CodingKeys: String, CodingKey {
        case heroTitle = "hero_title"
        case heroSubtitle = "hero_subtitle"
        case introBlocks = "intro_blocks"
        case items
    }
}

struct IntroBlock: Codable {
    let label: String
    let heading: String
    let paragraphs: [String]
}

struct Item: Codable {
    let icon: String
    let title: String
    let description: String
}

//App Color
enum Style {
    case normal
    case action
}

struct AppTheme {
    
    let backgroundGradientStart: UIColor
    let backgroundGradientEnd: UIColor
    
    let glassUltraThin: UIColor
    let glassThin: UIColor
    let glassMedium: UIColor
    let glassStrong: UIColor
    
    let glassBorderLight: UIColor
    let glassBorderStrong: UIColor
    
    let shadowSoft: UIColor
    let shadowMedium: UIColor
    
    let primaryText: UIColor
    let secondaryText: UIColor
    let tertiaryText: UIColor
    
    let accentPrimary: UIColor
    let accentSecondary: UIColor
    
    let buttonGlassBackground: UIColor
    let buttonGlassBorder: UIColor
    let buttonText: UIColor
    
    let inputGlassBackground: UIColor
    let inputGlassBorder: UIColor
    
    let success: UIColor
    let warning: UIColor
    let error: UIColor
    
    let divider: UIColor
    let shimmer: UIColor
}

//Insight
struct InsightsResponse: Codable {
    var insights: [Insight]
}

struct Insight: Codable {
    var activityType: String
    var title: String
    var weeks: [InsightWeek]
}

struct InsightGraphSummary {
    var title: String
    var metricTitle: String
    var displayValue: String
    var dayLabels: [String]
    var dayValues: [Double]
}

struct ActivityWeekProgressSnapshot {
    let graphSummary: InsightGraphSummary
    let days: [InsightDay]
    
    var hasProgress: Bool {
        days.contains { !$0.sessions.isEmpty }
    }
}

struct InsightWeek: Codable {
    var week: String
    var days: [InsightDay]
}

struct InsightStat: Codable {
    var title: String
    var value: String
    var unit: String
}

struct InsightDay: Codable {
    var dayKey: String
    var dayLabel: String
    let dateDisplay: String
    var sessions: [InsightSession]
}

struct InsightSession: Codable {
    var id: String
    var sessionTitle: String
    var time : String
    var stats: [SessionMetric]
    var vitals: [SessionMetric]?
}

struct SessionMetric: Codable {
    var title: String
    var value: String
    var unit: String
}

struct Stat: Codable {
    var title: String
    var value: String
    var unit: String
}

struct Week {
    let title: String
    let isSelected: Bool
}

struct TodayProgress: Codable {

    let totalKcal: Int
    let steps: Int
    let distance: Double
    let stairs: Int
    let timeline: [String:Int]
}

struct WalkingData: Decodable {
    let activities: [String: ActivityData]
}
    
struct ActivityData: Decodable {
    let weeks: [WeekData]
}
    
struct WeekData: Decodable {
    let week: String
    let days: [String: Int]
    
    var averageValue: Int {
        guard !days.isEmpty else { return 0 }
        let total = days.values.reduce(0, +)
        return total / days.count
    }
    
    var sortedDays: [(String, Int)] {
        let order = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return days.sorted {
            (order.firstIndex(of: $0.key) ?? 0) < (order.firstIndex(of: $1.key) ?? 0)
        }
    }
}

enum ActivityType: String, CaseIterable {
    case walking
    case exercise
    case yoga
    
    var title: String {
        switch self {
        case .walking: return "Walking"
        case .exercise: return "Exercise"
        case .yoga: return "Yoga"
        }
    }
    
    var icon: String {
        switch self {
        case .walking: return "figure.walk"
        case .exercise: return "dumbbell.fill"
        case .yoga: return "figure.yoga"
        }
    }
    
    var metricTitle: String {
        switch self {
        case .walking:
            return "Average Steps"
        case .exercise, .yoga:
            return "Average Time"
        }
    }
    
    var unit: String {
        switch self {
        case .walking:
            return "steps"
        case .exercise, .yoga:
            return "min"
        }
    }
    
    var selectedColor: UIColor {
        switch self {
        case .walking:
            return .systemGreen
        case .exercise:
            return .systemPurple
        case .yoga:
            return .systemRed
        }
    }
    
    var normalColor: UIColor {
        return .systemGray4
    }
}

//Home
struct WatchVitalViewModel {
    let icon: String
    let title: String
    let value: String
    let tint: UIColor
}

struct Insights {
    let image: UIImage
    let title: String
    let description: String
    let points: String
}

struct InsightResponse: Codable {
    let week: Int
    let categories: [Category]
}

struct Category: Codable {
    let id: String
    let title: String
    let subtitle: String
    let heroImage: String
    let items: [InsightItem]
}

struct InsightItem: Codable {
    let title: String
    let shortDescription: String
    let detailDescription: String
}

struct DayItem {
    let title: String
    let isSelected: Bool
}

struct DummyMemoryRoot: Codable {
    let weeks: [DummyMemoryWeek]
}

struct DummyMemoryWeek: Codable {
    let week: Int
    let images: [DummyMemoryImage]
}

struct DummyMemoryImage: Codable {
    let id: String
    let fileName: String
}

struct RoutineCardData {
    let routineType: RoutineType
    let firstIncompleteItem: RoutineItem?
    let incompleteCount: Int
    let totalCount: Int
    let progress: RoutineItemProgress?
}

struct RoutineItemProgress: Codable {
    let activityId: String
    let date: Date
    var elapsedSeconds: Int
    var heartRateAverage: Int?
    var caloriesBurned: Double?
    var distanceCovered: Double?
    var repetitionsCompleted: Int?
    var status: RoutineItemStatus
}

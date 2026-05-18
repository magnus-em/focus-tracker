import Foundation
import SwiftUI
import FocusCore

/// iPad-side settings store. UserDefaults-backed. Settings here don't need to
/// sync to Mac via CloudKit — they're per-device preferences. Anything that
/// genuinely needs cross-device sync (problem goals, weekly targets, etc.)
/// can live in a Stored* SwiftData model in FocusCore later.
final class PadSettings: ObservableObject {

    @Published var workMinutes: Double {
        didSet { UserDefaults.standard.set(workMinutes, forKey: "workMinutes") }
    }
    @Published var breakMinutes: Double {
        didSet { UserDefaults.standard.set(breakMinutes, forKey: "shortBreakMinutes") }
    }
    @Published var dailyGoalHours: Int {
        didSet { UserDefaults.standard.set(dailyGoalHours, forKey: "dailyGoalHours") }
    }
    @Published var autoStartBreaks: Bool {
        didSet { UserDefaults.standard.set(autoStartBreaks, forKey: "autoStartBreaks") }
    }
    @Published var autoStartWork: Bool {
        didSet { UserDefaults.standard.set(autoStartWork, forKey: "autoStartWork") }
    }
    @Published var pauseGraceMinutes: Int {
        didSet { UserDefaults.standard.set(pauseGraceMinutes, forKey: "pauseGraceMinutes") }
    }
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published var tags: [String] {
        didSet { UserDefaults.standard.set(tags, forKey: "tags") }
    }
    @Published var problemSources: [String] {
        didSet { UserDefaults.standard.set(problemSources, forKey: "problemSources") }
    }
    @Published var quantGoal: Int {
        didSet { UserDefaults.standard.set(quantGoal, forKey: "quantGoal") }
    }
    @Published var quantWeeklyGoal: Int {
        didSet { UserDefaults.standard.set(quantWeeklyGoal, forKey: "quantWeeklyGoal") }
    }
    @Published var sweGoal: Int {
        didSet { UserDefaults.standard.set(sweGoal, forKey: "sweGoal") }
    }
    @Published var sweWeeklyGoal: Int {
        didSet { UserDefaults.standard.set(sweWeeklyGoal, forKey: "sweWeeklyGoal") }
    }
    @Published var commitmentEnabled: Bool {
        didSet { UserDefaults.standard.set(commitmentEnabled, forKey: "commitmentEnabled") }
    }
    @Published var todayCommitment: String {
        didSet { UserDefaults.standard.set(todayCommitment, forKey: "todayCommitment") }
    }
    @Published var lastCommitmentDateEpoch: Double {
        didSet { UserDefaults.standard.set(lastCommitmentDateEpoch, forKey: "lastCommitmentDateEpoch") }
    }
    @Published var interviewDate: Date? {
        didSet {
            UserDefaults.standard.set(interviewDate?.timeIntervalSince1970 ?? 0, forKey: "interviewDate")
        }
    }
    @Published var cloudKitSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(cloudKitSyncEnabled, forKey: "cloudKitSyncEnabled") }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "workMinutes": 25.0,
            "shortBreakMinutes": 10.0,
            "dailyGoalHours": 4,
            "autoStartBreaks": true,
            "autoStartWork": false,
            "pauseGraceMinutes": 10,
            "soundEnabled": true,
            "tags": ["Quant", "SWE", "AI"],
            "problemSources": ["QuantGuide", "LeetCode"],
            "quantGoal": 0,
            "quantWeeklyGoal": 0,
            "sweGoal": 0,
            "sweWeeklyGoal": 0,
            "commitmentEnabled": true,
            "cloudKitSyncEnabled": true,
        ])
        workMinutes = d.double(forKey: "workMinutes")
        breakMinutes = d.double(forKey: "shortBreakMinutes")
        dailyGoalHours = d.integer(forKey: "dailyGoalHours")
        autoStartBreaks = d.bool(forKey: "autoStartBreaks")
        autoStartWork = d.bool(forKey: "autoStartWork")
        pauseGraceMinutes = d.integer(forKey: "pauseGraceMinutes")
        soundEnabled = d.bool(forKey: "soundEnabled")
        tags = d.stringArray(forKey: "tags") ?? ["Quant", "SWE", "AI"]
        problemSources = d.stringArray(forKey: "problemSources") ?? ["QuantGuide", "LeetCode"]
        quantGoal = d.integer(forKey: "quantGoal")
        quantWeeklyGoal = d.integer(forKey: "quantWeeklyGoal")
        sweGoal = d.integer(forKey: "sweGoal")
        sweWeeklyGoal = d.integer(forKey: "sweWeeklyGoal")
        commitmentEnabled = d.bool(forKey: "commitmentEnabled")
        todayCommitment = d.string(forKey: "todayCommitment") ?? ""
        lastCommitmentDateEpoch = d.double(forKey: "lastCommitmentDateEpoch")
        let epoch = d.double(forKey: "interviewDate")
        interviewDate = epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil
        cloudKitSyncEnabled = d.bool(forKey: "cloudKitSyncEnabled")
        hasCompletedOnboarding = d.bool(forKey: "hasCompletedOnboarding")
    }

    var needsCommitmentToday: Bool {
        guard commitmentEnabled else { return false }
        if lastCommitmentDateEpoch == 0 { return true }
        return !Calendar.current.isDateInToday(Date(timeIntervalSince1970: lastCommitmentDateEpoch))
    }

    func markCommitmentDone(_ text: String) {
        todayCommitment = text
        lastCommitmentDateEpoch = Date().timeIntervalSince1970
    }

    var engineSettings: FocusTimerEngine.Settings {
        .init(
            workMinutes: workMinutes,
            breakMinutes: breakMinutes,
            dailyGoalHours: dailyGoalHours,
            autoStartBreaks: autoStartBreaks,
            autoStartWork: autoStartWork,
            pauseGraceMinutes: pauseGraceMinutes
        )
    }
}

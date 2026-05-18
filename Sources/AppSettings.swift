import Foundation

class AppSettings: ObservableObject {
    @Published var workMinutes: Double {
        didSet { UserDefaults.standard.set(workMinutes, forKey: "workMinutes") }
    }
    @Published var shortBreakMinutes: Double {
        didSet { UserDefaults.standard.set(shortBreakMinutes, forKey: "shortBreakMinutes") }
    }
    @Published var longBreakMinutes: Double {
        didSet { UserDefaults.standard.set(longBreakMinutes, forKey: "longBreakMinutes") }
    }
    @Published var sessionsBeforeLongBreak: Int {
        didSet { UserDefaults.standard.set(sessionsBeforeLongBreak, forKey: "sessionsBeforeLongBreak") }
    }
    @Published var dailyGoal: Int {
        didSet { UserDefaults.standard.set(dailyGoal, forKey: "dailyGoalHours") }
    }
    @Published var autoStartBreaks: Bool {
        didSet { UserDefaults.standard.set(autoStartBreaks, forKey: "autoStartBreaks") }
    }
    @Published var autoStartWork: Bool {
        didSet { UserDefaults.standard.set(autoStartWork, forKey: "autoStartWork") }
    }
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published var siteBlockingEnabled: Bool {
        didSet { UserDefaults.standard.set(siteBlockingEnabled, forKey: "siteBlockingEnabled") }
    }
    @Published var blockDuringBreaks: Bool {
        didSet { UserDefaults.standard.set(blockDuringBreaks, forKey: "blockDuringBreaks") }
    }
    @Published var blockedSites: [String] {
        didSet { UserDefaults.standard.set(blockedSites, forKey: "blockedSites") }
    }
    @Published var tags: [String] {
        didSet { UserDefaults.standard.set(tags, forKey: "tags") }
    }
    /// Minutes a paused work session can sit before auto-saving + ending.
    @Published var pauseGraceMinutes: Int {
        didSet { UserDefaults.standard.set(pauseGraceMinutes, forKey: "pauseGraceMinutes") }
    }
    @Published var autoBreakEnabled: Bool {
        didSet { UserDefaults.standard.set(autoBreakEnabled, forKey: "autoBreakEnabled") }
    }
    @Published var commitmentEnabled: Bool {
        didSet { UserDefaults.standard.set(commitmentEnabled, forKey: "commitmentEnabled") }
    }
    @Published var lastCommitmentDateEpoch: Double {
        didSet { UserDefaults.standard.set(lastCommitmentDateEpoch, forKey: "lastCommitmentDateEpoch") }
    }
    @Published var todayCommitment: String {
        didSet { UserDefaults.standard.set(todayCommitment, forKey: "todayCommitment") }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    var needsCommitmentToday: Bool {
        guard commitmentEnabled else { return false }
        if lastCommitmentDateEpoch == 0 { return true }
        return !Calendar.current.isDateInToday(Date(timeIntervalSince1970: lastCommitmentDateEpoch))
    }

    func markCommitmentDone(text: String) {
        todayCommitment = text
        lastCommitmentDateEpoch = Date().timeIntervalSince1970
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
    @Published var problemSources: [String] {
        didSet { UserDefaults.standard.set(problemSources, forKey: "problemSources") }
    }
    @Published var interviewDate: Date? {
        didSet {
            UserDefaults.standard.set(interviewDate?.timeIntervalSince1970 ?? 0, forKey: "interviewDate")
        }
    }

    init() {
        let d = UserDefaults.standard

        // Existing-user detection: if any prior signal exists, skip onboarding.
        if !d.bool(forKey: "hasCompletedOnboarding") {
            let priorState = (d.stringArray(forKey: "tags")?.isEmpty == false)
                || d.double(forKey: "lastCommitmentDateEpoch") > 0
                || (d.string(forKey: "todayCommitment")?.isEmpty == false)
                || d.double(forKey: "workMinutes") > 0
            if priorState { d.set(true, forKey: "hasCompletedOnboarding") }
        }

        d.register(defaults: [
            "workMinutes": 25.0,
            "shortBreakMinutes": 10.0,
            "longBreakMinutes": 15.0,
            "sessionsBeforeLongBreak": 4,
            "dailyGoalHours": 4,
            "autoStartBreaks": true,
            "autoStartWork": false,
            "soundEnabled": true,
            "siteBlockingEnabled": false,
            "blockDuringBreaks": false,
            "pauseGraceMinutes": 10,
            "autoBreakEnabled": true,
            "commitmentEnabled": true,
            "quantGoal": 0,
            "quantWeeklyGoal": 0,
            "sweGoal": 0,
            "sweWeeklyGoal": 0,
            "problemSources": ["QuantGuide", "LeetCode"],
        ])
        workMinutes = d.double(forKey: "workMinutes")
        shortBreakMinutes = d.double(forKey: "shortBreakMinutes")
        longBreakMinutes = d.double(forKey: "longBreakMinutes")
        sessionsBeforeLongBreak = d.integer(forKey: "sessionsBeforeLongBreak")
        dailyGoal = d.integer(forKey: "dailyGoalHours")
        autoStartBreaks = d.bool(forKey: "autoStartBreaks")
        autoStartWork = d.bool(forKey: "autoStartWork")
        soundEnabled = d.bool(forKey: "soundEnabled")
        siteBlockingEnabled = d.bool(forKey: "siteBlockingEnabled")
        blockDuringBreaks = d.bool(forKey: "blockDuringBreaks")
        blockedSites = d.stringArray(forKey: "blockedSites") ?? []
        tags = d.stringArray(forKey: "tags") ?? []
        pauseGraceMinutes = d.integer(forKey: "pauseGraceMinutes")
        autoBreakEnabled = d.bool(forKey: "autoBreakEnabled")
        commitmentEnabled = d.bool(forKey: "commitmentEnabled")
        lastCommitmentDateEpoch = d.double(forKey: "lastCommitmentDateEpoch")
        todayCommitment = d.string(forKey: "todayCommitment") ?? ""
        quantGoal = d.integer(forKey: "quantGoal")
        quantWeeklyGoal = d.integer(forKey: "quantWeeklyGoal")
        sweGoal = d.integer(forKey: "sweGoal")
        sweWeeklyGoal = d.integer(forKey: "sweWeeklyGoal")
        problemSources = d.stringArray(forKey: "problemSources") ?? ["QuantGuide", "LeetCode"]
        let epoch = d.double(forKey: "interviewDate")
        interviewDate = epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil
        hasCompletedOnboarding = d.bool(forKey: "hasCompletedOnboarding")

        // One-time normalization for legacy "AI/ML" tag.
        if tags.contains("AI/ML") {
            tags = tags.map { $0 == "AI/ML" ? "AI" : $0 }
            d.set(tags, forKey: "tags")
        }
    }
}

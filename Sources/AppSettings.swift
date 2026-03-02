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
        didSet { UserDefaults.standard.set(dailyGoal, forKey: "dailyGoal") }
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

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "workMinutes": 25.0,
            "shortBreakMinutes": 5.0,
            "longBreakMinutes": 15.0,
            "sessionsBeforeLongBreak": 4,
            "dailyGoal": 8,
            "autoStartBreaks": true,
            "autoStartWork": false,
            "soundEnabled": true,
            "siteBlockingEnabled": false,
            "blockDuringBreaks": false,
        ])
        workMinutes = d.double(forKey: "workMinutes")
        shortBreakMinutes = d.double(forKey: "shortBreakMinutes")
        longBreakMinutes = d.double(forKey: "longBreakMinutes")
        sessionsBeforeLongBreak = d.integer(forKey: "sessionsBeforeLongBreak")
        dailyGoal = d.integer(forKey: "dailyGoal")
        autoStartBreaks = d.bool(forKey: "autoStartBreaks")
        autoStartWork = d.bool(forKey: "autoStartWork")
        soundEnabled = d.bool(forKey: "soundEnabled")
        siteBlockingEnabled = d.bool(forKey: "siteBlockingEnabled")
        blockDuringBreaks = d.bool(forKey: "blockDuringBreaks")
        blockedSites = d.stringArray(forKey: "blockedSites") ?? []
    }
}

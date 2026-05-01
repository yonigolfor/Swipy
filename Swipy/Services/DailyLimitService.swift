import Foundation

class DailyLimitService: ObservableObject {
    static let shared = DailyLimitService()

    let dailyLimit = 100
    private let swipesKey = "dailySwipesCount"
    private let dateKey = "dailySwipesDate"

    @Published private(set) var swipesUsedToday: Int = 0

    var remainingSwipes: Int { max(0, dailyLimit - swipesUsedToday) }
    var hasReachedLimit: Bool { swipesUsedToday >= dailyLimit }

    private init() {
        resetIfNewDay()
        swipesUsedToday = UserDefaults.standard.integer(forKey: swipesKey)
    }

    func canSwipe(isPremium: Bool) -> Bool {
        isPremium || !hasReachedLimit
    }

    func recordSwipe() {
        resetIfNewDay()
        swipesUsedToday += 1
        UserDefaults.standard.set(swipesUsedToday, forKey: swipesKey)
    }

#if DEBUG
    func resetDailyCount() {
        swipesUsedToday = 0
        UserDefaults.standard.set(0, forKey: swipesKey)
        UserDefaults.standard.set(Calendar.current.startOfDay(for: Date()), forKey: dateKey)
    }
#endif

    private func resetIfNewDay() {
        let today = Calendar.current.startOfDay(for: Date())
        let saved = UserDefaults.standard.object(forKey: dateKey) as? Date ?? .distantPast
        guard today > saved else { return }
        swipesUsedToday = 0
        UserDefaults.standard.set(0, forKey: swipesKey)
        UserDefaults.standard.set(today, forKey: dateKey)
    }
}

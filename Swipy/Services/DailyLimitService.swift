import Foundation
import UserNotifications

class DailyLimitService: ObservableObject {
    static let shared = DailyLimitService()

    // TODO: tune this once we have retention data — current value is a temporary ceiling
    let dailyLimit = 500
    private let swipesKey      = "dailySwipesCount"
    private let dateKey        = "dailySwipesDate"
    private let bonusKey       = "dailyBonusSwipes"
    private let bonusDateKey   = "dailyBonusSharedDate"

    @Published private(set) var swipesUsedToday: Int = 0
    @Published private(set) var bonusSwipesGranted: Int = 0

    /// True when the user has already shared today — hides the share button.
    var hasSharedToday: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let saved = UserDefaults.standard.object(forKey: bonusDateKey) as? Date ?? .distantPast
        return saved >= today
    }

    private var effectiveLimit: Int { dailyLimit + bonusSwipesGranted }
    var remainingSwipes: Int { max(0, effectiveLimit - swipesUsedToday) }
    var hasReachedLimit: Bool { swipesUsedToday >= effectiveLimit }

    private init() {
        resetIfNewDay()
        swipesUsedToday = UserDefaults.standard.integer(forKey: swipesKey)
        if hasSharedToday {
            bonusSwipesGranted = UserDefaults.standard.integer(forKey: bonusKey)
        }
    }

    func canSwipe(isPremium: Bool) -> Bool {
        isPremium || !hasReachedLimit
    }

    func recordSwipe() {
        resetIfNewDay()
        swipesUsedToday += 1
        UserDefaults.standard.set(swipesUsedToday, forKey: swipesKey)
    }

    /// Grants +50 bonus swipes for today. Safe to call only once per day —
    /// callers should guard with `hasSharedToday` before calling.
    func applyShareBonus() {
        let today = Calendar.current.startOfDay(for: Date())
        bonusSwipesGranted = 50
        UserDefaults.standard.set(bonusSwipesGranted, forKey: bonusKey)
        UserDefaults.standard.set(today, forKey: bonusDateKey)
    }

#if DEBUG
    func resetDailyCount() {
        swipesUsedToday = 0
        bonusSwipesGranted = 0
        UserDefaults.standard.set(0, forKey: swipesKey)
        UserDefaults.standard.set(0, forKey: bonusKey)
        UserDefaults.standard.set(Calendar.current.startOfDay(for: Date()), forKey: dateKey)
        UserDefaults.standard.removeObject(forKey: bonusDateKey)
    }
#endif

    private func resetIfNewDay() {
        let today = Calendar.current.startOfDay(for: Date())
        let saved = UserDefaults.standard.object(forKey: dateKey) as? Date ?? .distantPast
        guard today > saved else { return }
        swipesUsedToday = 0
        bonusSwipesGranted = 0
        UserDefaults.standard.set(0, forKey: swipesKey)
        UserDefaults.standard.set(0, forKey: bonusKey)
        UserDefaults.standard.set(today, forKey: dateKey)
        // Limit has reset — cancel the "you can swipe again" notification if still pending.
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [NotificationManager.swipeLimitResetNotif])
    }
}

# Swipy — Notification System

## קבצים

| קובץ | תפקיד |
|------|-------|
| `Services/NotificationManager.swift` | בונה ושולח את הנוטיפיקציות בפועל ל-UNUserNotificationCenter |
| `Services/NotificationScheduler.swift` | לוגיקת הטריגרים — מחליט מתי ואם לשלוח |
| `Services/NotificationDelegate.swift` | מקבל לחיצות משתמש ומבצע deep linking לטאב הנכון |
| `SwipyApp.swift` | רישום background task + בקשת הרשאות בהפעלה |
| `ContentView.swift` | מאזין ל-`notificationNavigate` ומחליף טאב |

---

## טריגרים

### 1. תזכורת סל מחזור
**מתי:** 24 שעות אחרי שפריטים נמצאים בסל המחזור ולא נמחקו.

**תנאים:**
- `reviewBinIDs` לא ריק (`PersistenceService`)
- מכסת הנוטיפיקציות היומית לא מוצתה (מקסימום 2 ביום) — אם כבר קיימת נוטיפיקציה ממתינה, היא מתעדכנת ללא חיוב מכסה

**עדכון נתונים בזמן אמת:** בכל כניסה לפורגראונד, אם קיימת נוטיפיקציה ממתינה (נוצרה לפחות 24 שעות), היא מוחלפת אוטומטית בנתונים עדכניים (גודל סל נוכחי). אותו מזהה (`reviewBinNotif`) → iOS מחליף אטומית ולא מוסיף. כך גם אם המשתמש מחק חלק מהסל, הנוטיפיקציה מציגה את הנפח הנכון בזמן המסירה.

**פעולות זמינות למשתמש:**
- "נקה עכשיו" → פותח Review Bin (טאב 2)
- "מחק הכל" → פותח Review Bin + פוסט `notificationDeleteAll`

**כשהסל מתרוקן:** הנוטיפיקציה הממתינה מבוטלת אוטומטית.

---

### 2. פרץ צילומים (Photo Burst)
**מתי:** כאשר נצפות 50+ תמונות חדשות מאז הפעם האחרונה שנקבע baseline.

**שני מסלולים:**

#### App פתוחה (Foreground) — Real-time
```
PHPhotoLibraryChangeObserver (PhotoStackViewModel)
    ↓ insertedIndexes.count
NotificationScheduler.checkBurstFromLibraryChange(insertedCount:)
    ↓ currentCount - burstSessionBaseCount >= 50
נוטיפיקציה מתוזמנת לעוד שעה
```
- `burstSessionBaseCount` מאופס בכל כניסה לפורגראונד (`scenePhase == .active`)
- הbaseline מתעדכן אחרי כל גילוי כדי שהבאה יצטרך עוד 50

#### App סגורה (Background) — מאוחר
```
BGAppRefreshTask (iOS מפעיל לפי שיקול דעתו, בד"כ כל 4-8 שעות)
    ↓
checkPhotoBurstTrigger()
    ↓ currentCount - lastKnownPhotoCount >= 50
נוטיפיקציה מתוזמנת לעוד שעה
```

**חשוב — הbaseline מתקדם רק עם שליחה:** `lastKnownPhotoCount` מתעדכן לערך הנוכחי **רק** כשנשלחת נוטיפיקציה. אם ה-diff עדיין מתחת ל-50, הbaseline נשאר על ערכו ה"ישן" — כך ההפרש מצטבר על פני מספר ריצות background עד שחוצה את הסף. בעבר הbaseline התעדכן בכל ריצה וגרם לכך שהפרשים של 30+30 מעולם לא הגיעו ל-50.

**תנאים:**
- לא נשלחה נוטיפיקציה burst ב-24 השעות האחרונות
- מכסת הנוטיפיקציות היומית לא מוצתה

**פעולה זמינה:**
- "בוא נמיין" → פותח Swipe (טאב 1) עם thumbnail של התמונה האחרונה

---

### 3. אבן דרך — כל GB שנחסך
**מתי:** בכל פעם שה-`totalSpaceSavedLifetime` חוצה GB שלם חדש.

**תנאים:**
- `gbSaved > lastMilestoneNotifiedGB` (UserDefaults)
- מכסת הנוטיפיקציות היומית לא מוצתה

**מופעל מ:** `evaluateAndScheduleNotifications()` שרץ:
- בהפעלת האפליקציה (AppDelegate)
- בכל חזרה לפורגראונד (scenePhase)
- ב-background task

---

### 4. ניקוי שבועי
**מתי:** כל יום ראשון בערב בשעה 21:30.

**מנגנון:** `UNCalendarNotificationTrigger` עם `repeats: true` — **מובטח לחלוטין**, לא תלוי ב-background task.

**מתוזמן פעם אחת בלבד** (guard ב-UserDefaults, מפתח `weeklyCleanupScheduledV2`) ואז חוזר על עצמו אוטומטית.

> **שינוי V2:** שינוי ממפתח `weeklyCleanupScheduledV2` מאפשר reschedule חד-פעמי למשתמשים קיימים (ביטול שבת 19:00 → ראשון 21:30).

---

### 5. תזכורת אי-פעילות (72 שעות)
**מתי:** 72 שעות לאחר הכניסה האחרונה לאפליקציה, אם המשתמש לא חזר.

**כותרת:** "60 שניות זה המון זמן! ⏱️"

**גוף:** "כנס ותגלה כמה GB של זבל אתה יכול לפנות מהמכשיר שלך ברגע."

**פעולה זמינה:** "בוא נמיין" (→ מסך סוויפ)

**מנגנון:** `UNTimeIntervalNotificationTrigger(timeInterval: 72*3600, repeats: false)`.  
בכל כניסה לפורגראונד (`scenePhase == .active`) — ההתראה הממתינה מבוטלת ומתוזמנת מחדש. כך השעון מתאפס אוטומטית בכל שימוש.

**לא נספרת** במכסת ה-2 ביום (persistent reminder, לא event-driven trigger).

---

## מכסת נוטיפיקציות יומית

מקסימום **2 נוטיפיקציות ליום** (לא כולל ניקוי שבועי שמתוזמן ישירות ל-UNCalendarTrigger).

המכסה מאופסת חצות בכל יום. ניהול דרך:
- `notifCapCount` — מונה הנוטיפיקציות שנשלחו היום
- `notifCapDate` — יום המדידה הנוכחי

---

## Background Task

**מזהה:** `com.swipy.notificationCheck`

**הרשמה:** ב-`AppDelegate.application(_:didFinishLaunchingWithOptions:)` — **חייב להיות סינכרוני** לפני return.

**תדירות מבוקשת:** כל 6 שעות (`earliestBeginDate`).

**מה iOS עושה בפועל:** מחליט לפי סוללה, רשת, ודפוסי שימוש. לא מובטח. בד"כ רץ לפני שהמשתמש צפוי לפתוח את האפליקציה.

**דרישות Xcode (חובה):**
- Signing & Capabilities → Background Modes:
  - [x] Background fetch
  - [x] Background processing
- Info.plist key: `BGTaskSchedulerPermittedIdentifiers` → `com.swipy.notificationCheck`

---

## Deep Linking

| destination | טאב |
|-------------|-----|
| `"filters"` | 0 — SmartFiltersView |
| `"swipe"` | 1 — SwipeStackView |
| `"reviewBin"` | 2 — ReviewBinView |

הניווט מתבצע דרך `NotificationCenter.default.post(name: .notificationNavigate, object: tab)` שה-ContentView מאזין לו.

---

## זרימה מלאה — App Launch

```
AppDelegate.didFinishLaunching
    ├── registerBackgroundTasks()       ← סינכרוני, חייב לרוץ ראשון
    ├── NotificationDelegate.setupInApp()
    └── requestAuthorization { granted in
            ├── scheduleWeeklyCleanupIfNeeded()
            ├── scheduleBackgroundTask()
            └── evaluateAndScheduleNotifications()
                    ├── checkReviewBinTrigger()
                    ├── checkPhotoBurstTrigger()
                    └── checkMilestoneTrigger()

scenePhase → .active
    ├── resetBurstBaseline()
    └── evaluateAndScheduleNotifications()
```

---

## מגבלות ידועות

| מגבלה | סיבה |
|-------|------|
| Photo burst לא real-time כשהאפליקציה סגורה | iOS לא מאפשר להאזין לגלריה ברקע |
| Background task לא בזמן מדויק | iOS שולט בתזמון לפי ML + סוללה |
| Low Power Mode מבטל background tasks | מגבלת iOS |
| משתמש יכול לכבות ב-Settings → Background App Refresh | מגבלת iOS |

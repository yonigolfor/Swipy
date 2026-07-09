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

## נוסחי טקסט (Copy Variants)

כל סוג נוטיפיקציה (מלבד תזכורת אי-פעילות, שעדיין עם נוסח יחיד) מחזיק 2-3 וריאציות טקסט —
זוגות `title`/`body` נפרדים ב-`Localizable.xcstrings` עם סיומת `.2`, `.3` (למשל
`notif.reviewBin.title.2`). `NotificationManager.randomVariant(_:)` בוחר וריאציה אחת
רנדומלית (`.randomElement()`) בכל קריאה ל-schedule — כך שנוטיפיקציות חוזרות לא מרגישות
זהות פעם אחר פעם. הבחירה קורית בכל שליחה בפועל, לא נשמרת/נזכרת בין נוטיפיקציות.

**הוספת וריאציה נוספת:** להוסיף זוג מפתחות `title.N`/`body.N` חדש ל-`Localizable.xcstrings`
(עם תרגום אנגלי) ולהוסיף אותו למערך ב-`randomVariant([...])` בפונקציית ה-schedule הרלוונטית.

---

## טריגרים

### 1. תזכורת סל מחזור
**מתי:** 8 שעות אחרי שפריטים נמצאים בסל המחזור ולא נמחקו.

**תנאים:**
- `reviewBinIDs` לא ריק (`PersistenceService`)
- מכסת הנוטיפיקציות היומית לא מוצתה (מקסימום 2 ביום) — אם כבר קיימת נוטיפיקציה ממתינה, היא מתעדכנת ללא חיוב מכסה

**עדכון נתונים בזמן אמת:** בכל כניסה לפורגראונד, אם קיימת נוטיפיקציה ממתינה (נוצרה לפחות 8 שעות), היא מוחלפת אוטומטית בנתונים עדכניים (גודל סל נוכחי). אותו מזהה (`reviewBinNotif`) → iOS מחליף אטומית ולא מוסיף. כך גם אם המשתמש מחק חלק מהסל, הנוטיפיקציה מציגה את הנפח הנכון בזמן המסירה.

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
- `burstSessionBaseCount` מאופס בכל כניסה לפורגראונד (`resetBurstBaseline()`, `scenePhase == .active`)
- הbaseline מתעדכן אחרי כל גילוי כדי שהבאה יצטרך עוד 50
- **`resetBurstBaseline()` נוגע רק ב-`burstSessionBaseCount`** — היא לא אמורה לגעת ב-`lastKnownPhotoCount` בכלל (ראו הערה למטה)

#### App סגורה (Background) — מאוחר
```
BGAppRefreshTask (iOS מפעיל לפי שיקול דעתו, בד"כ כל 4-8 שעות)
    ↓
checkPhotoBurstTrigger()
    ↓ currentCount - lastKnownPhotoCount >= 50
נוטיפיקציה מתוזמנת לעוד שעה
```

**חשוב — הbaseline מתקדם רק עם שליחה:** `lastKnownPhotoCount` מתעדכן לערך הנוכחי **רק** כשנשלחת נוטיפיקציה. אם ה-diff עדיין מתחת ל-50, הbaseline נשאר על ערכו ה"ישן" — כך ההפרש מצטבר על פני מספר ריצות background עד שחוצה את הסף.

**באג שחזר וקיבל תיקון סופי:** `resetBurstBaseline()` (המסלול הראשון, foreground) היה **גם** מאפס את `lastKnownPhotoCount` בכל פתיחת אפליקציה — זה בדיוק ה-anti-pattern שהפסקה למעלה מזהירה ממנו, ומשתמש שפותח את האפליקציה מדי פעם מעולם לא היה מצטבר ל-50 לפני שה-baseline מתאפס שוב. `resetBurstBaseline()` נוגע היום **רק** ב-`burstSessionBaseCount` — שני המסלולים בלתי-תלויים לחלוטין.

**Edge case — התקנה חדשה, לפני הרשאה:** ה"first run" guard ב-`checkPhotoBurstTrigger()` (שקובע את ה-baseline הראשוני בפעם שהמפתח לא קיים ב-UserDefaults) עלול לרוץ **לפני** ש-onboarding בכלל מבקש הרשאת גלריה (`evaluateAndScheduleNotifications()` נקרא מ-`scenePhase == .active` כבר בלאנץ' הקר). ללא בדיקת הרשאה, `PHAsset.fetchAssets(...).count` היה מחזיר `0` באותו רגע (לא בגלל ברירת מחדל של UserDefaults — כי אין עדיין גישה לספרייה בפועל), וה-0 הזה היה נשמר לצמיתות כ-baseline. אחרי שהמשתמש מאשר גישה בפועל (נניח לספרייה שלו יש 3000 תמונות), ה-background task הראשון היה מחשב `3000 - 0 = 3000` ושולח נוטיפיקציית "פרץ תמונות" שקרית. הguard כיום דורש `authorizationStatus == .authorized || .limited` לפני ששומר את ה-baseline הראשוני — אם אין הרשאה עדיין, הבדיקה פשוט מדלגת ומנסה שוב בפעם הבאה (foreground או background) עד שיש גישה אמיתית.

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

### 4. מכסת החלקות התחדשה

**מתי:** כשמשתמש חינמי מגיע ל-0 החלקות ביום, ובחצות הלילה (00:01) כשהמכסה מתאפסת.

**תנאים:**
- `DailyLimitService.shared.hasReachedLimit == true`
- `!PremiumManager.shared.isPremium` — פרמיום לא מוגבל, לא צריך התראה
- מתוזמן בסיום כל החלקת keep/delete שגרמה להגיע למגבלה

**טריגר:** `scheduleSwipeLimitResetIfNeeded()` ב-`PhotoStackViewModel` — נקרא מיד אחרי `recordSwipe()` ב-`keepPhoto()` וב-`deletePhoto()`.

**מסירה:** `UNCalendarNotificationTrigger` ל-00:01 ביום המחרת (דקה אחרי האיפוס). לא חוזרת (`repeats: false`).

**ביטול:** `DailyLimitService.resetIfNewDay()` מבטל את ההתראה הממתינה כשהיום מתחדש — safety net למקרה שהמשתמש פתח את האפליקציה לפני חצות.

**לא נספרת** במכסת ה-2 ביום — היא התראה פונקציונלית שהמשתמש יזם (הגיע למגבלה).

**פעולה זמינה:** "בוא נמיין" → פותח Swipe (טאב 1)

---

### 5. ניקוי שבועי
**מתי:** כל יום ראשון בערב בשעה 21:30.

**מנגנון:** `UNCalendarNotificationTrigger` עם `repeats: true` — **מובטח לחלוטין**, לא תלוי ב-background task.

**מתוזמן פעם אחת בלבד** (guard ב-UserDefaults, מפתח `weeklyCleanupScheduledV2`) ואז חוזר על עצמו אוטומטית.

> **שינוי V2:** שינוי ממפתח `weeklyCleanupScheduledV2` מאפשר reschedule חד-פעמי למשתמשים קיימים (ביטול שבת 19:00 → ראשון 21:30).

---

### 6. תזכורת אי-פעילות (30 שעות)
**מתי:** 30 שעות לאחר הכניסה האחרונה לאפליקציה, אם המשתמש לא חזר.

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
    └── NotificationDelegate.setupInApp()

ContentView.onAppear   ← נחיתה במסך הראשי, אחרי onboarding (או משתמש חוזר)
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

**למה לא ב-`didFinishLaunching`:** לבקש הרשאת התראות בהפעלה קרה ראשונה — לפני שהמשתמש בכלל ראה את onboarding — סותר את ה-HIG של Apple (לבקש הרשאה בהקשר, אחרי שהערך של האפליקציה כבר הודגם). `requestAuthorization` הוא idempotent — אם המשתמש כבר החליט (אישר/דחה), iOS לא מציג דיאלוג נוסף, כך שקריאה מ-`ContentView.onAppear` בטוחה גם למשתמשים חוזרים בכל הפעלה.

---

## מגבלות ידועות

| מגבלה | סיבה |
|-------|------|
| Photo burst לא real-time כשהאפליקציה סגורה | iOS לא מאפשר להאזין לגלריה ברקע |
| Background task לא בזמן מדויק | iOS שולט בתזמון לפי ML + סוללה |
| Low Power Mode מבטל background tasks | מגבלת iOS |
| משתמש יכול לכבות ב-Settings → Background App Refresh | מגבלת iOS |

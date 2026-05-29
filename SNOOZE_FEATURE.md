# Snooze Feature — "Later" (Swipe Up)

## מה זה

"Snooze" הוא פעולת ה-swipe-up בסוויפי. המשמעות: "אני לא רוצה להחליט עכשיו — תחזיר לי את התמונה הזאת אחרי כמה החלקות." התמונה עוברת לתור פנימי (`snoozeQueue`) ומוחזרת לראש הסטאק אחרי N החלקות של keep/delete.

---

## זרימה מלאה — שלב אחר שלב

### 1. זיהוי המחווה (`SwipeAction.swift`)

```swift
if offset.height < -80 && abs(offset.width) < 80 → .up → .snooze
```

סף: 80pt למעלה, עם פחות מ-80pt אופקי. האנכי נבדק **לפני** האופקי — סווייפ אלכסוני ימינה/שמאלה מנצח.

### 2. אנימציית הכרטיס (`SwipeStackView.swift`)

הכרטיס עף למעלה: `dragOffset = CGSize(width: translation.width, height: -500)`. אחרי 0.3s `viewModel.performAction(.snooze)` מופעל.

### 3. אינדיקטור ויזואלי (`SwipeIndicator.swift`)

- אמוג'י `🤷‍♂️` + טקסט מתורגם `"swipe.later"`
- רקע: `Color.swipeBlue.gradient` (כחול)
- גודל ושקיפות גדלים לינארית עם המרחק, מקסימום ב-100pt
- מיושר לראש הכרטיס

### 4. הלוגיקה הראשית — `snoozePhoto()` (`PhotoStackViewModel.swift:749`)

```swift
func snoozePhoto() {
    guard let topCard = photoStack.first else { return }
    lastSwipedImage = imageCache.object(forKey: topCard.id as NSString)
    processedAssetIDs.insert(topCard.id)   // מסתיר מ-pagination
    self.lastAction = (topCard, .snooze)
    photoStack.removeFirst()
    OfflineCacheService.shared.evict(for: topCard.id)

    let currentCount = persistence.snoozedPhotos[topCard.id] ?? 0
    let newCount = currentCount + 1
    let offset: Int
    switch newCount {
    case 1:  offset = 50
    case 2:  offset = 150
    default: offset = 500
    }

    persistence.snoozedPhotos[topCard.id] = newCount
    snoozeQueue.append(SnoozedPhoto(item: topCard, swipesRemaining: offset, snoozeCount: newCount))

    hapticService.snooze()
    precacheNextImages()
    loadNextPageIfNeeded()
}
```

---

## Exponential Backoff — כמה swipes עד שהתמונה חוזרת

| מספר ה-snooze לתמונה | swipes עד חזרה |
|----------------------|----------------|
| 1 (ראשון)            | 50             |
| 2 (שני)              | 150            |
| 3+ (שלישי ומעלה)     | 500            |

**חשוב:** הספירה מצטברת ונשמרת ב-UserDefaults. גם אחרי force-quit ופתיחה מחדש — אם התמונה כבר סנוזה 2 פעמים בעבר, הפעם הבאה תהיה 500 swipes.

---

## מבנה הנתונים בזיכרון

```swift
private struct SnoozedPhoto {
    let item: PhotoItem
    var swipesRemaining: Int   // ספירה לאחור
    let snoozeCount: Int       // האיטרציה של snooze זה
}

private var snoozeQueue: [SnoozedPhoto] = []
```

---

## מנגנון החזרה — `decrementSnoozeCounts()` (שורה 1311)

מופעל אחרי **כל keep או delete** (לא אחרי snooze):

```swift
private func decrementSnoozeCounts() {
    guard !snoozeQueue.isEmpty else { return }
    var readyIndices: [Int] = []
    for i in snoozeQueue.indices {
        snoozeQueue[i].swipesRemaining -= 1
        if snoozeQueue[i].swipesRemaining <= 0 { readyIndices.append(i) }
    }
    guard !readyIndices.isEmpty else { return }
    let toInject = readyIndices.map { snoozeQueue[$0].item }
    for i in readyIndices.reversed() { snoozeQueue.remove(at: i) }
    toInject.forEach { processedAssetIDs.remove($0.id) }
    photoStack.insert(contentsOf: toInject, at: 0)
}
```

- כל snooze-swipe של המשתמש **לא** מונה — רק keep ו-delete
- כשפריט מגיע ל-0, הוא מוזרק ל-`photoStack[0]` (ראש הסטאק)
- ה-ID שלו מוסר מ-`processedAssetIDs` כדי שה-pagination לא יסנן אותו שוב

---

## Persistence (`PersistenceService.swift`)

```swift
@AppStorage("snoozedPhotos") private var snoozedPhotosData: Data = Data()

var snoozedPhotos: [String: Int] {
    // [localIdentifier: snoozeCount]
    // מקודד כ-JSON ב-UserDefaults
}
```

- שורד force-quit
- על `init()` של ה-ViewModel: `restoreSnoozedItems()` בונה מחדש את `snoozeQueue` עם `swipesRemaining=0`
- כלומר: **אחרי force-quit כל הפריטים הסנוזים מופיעים מיד** בראש הסטאק בפתיחה הבאה
- `clearSnoozedID()` נקרא כשהמשתמש עושה keep או delete על תמונה שהייתה סנוזה

---

## Flush מיידי — מתי snooze מתעלם מהספירה

בכל אחד מהמצבים הבאים **כל** הפריטים בתור נזרקים מיידית לראש הסטאק ללא המתנה:

| מצב | קוד |
|-----|-----|
| Cold start / filter change | `flushSnoozedToFront()` ב-`resetAndLoad()` |
| Shuffle mode הפעלה/כיבוי | `flushSnoozedToFront()` ב-`activateShuffle()` / `deactivateShuffle()` |
| Offline mode הפעלה/כיבוי | `flushSnoozedToFront()` ב-`activateOfflineMode()` / `deactivateOfflineMode()` |

```swift
private func flushSnoozedToFront() -> [PhotoItem] {
    guard !snoozeQueue.isEmpty else { return [] }
    let items = snoozeQueue.map { $0.item }
    snoozeQueue = []
    items.forEach { processedAssetIDs.remove($0.id) }
    return items
}
```

---

## Undo (Shake)

רק הפעולה **האחרונה** ניתנת לביטול (shake). אם הפעולה האחרונה הייתה snooze:

1. הפריט מוסר מ-`snoozeQueue`
2. `persistence.snoozedPhotos[id]` מוקטן ב-1, או מוסר אם הגיע ל-0
3. הפריט חוזר ל-`photoStack[0]`
4. התמונה השמורה ב-`lastSwipedImage` מוחזרת ל-NSCache — אין flash

---

## מה לא קורה ב-Snooze

- **אין** הוספה ל-Review Bin
- **אין** מחיקה
- **אין** רישום ב-`keptPhotoIDs`
- **אין** עדכון ל-`DailyLimitService` (לא נספר כ-swipe לצורך המכסה היומית)
- **אין** התראה / notification שהתמונה חזרה
- **אין** גבול מקסימלי למספר פעמים שניתן לסנוז את אותה תמונה

---

## דיאגרמת מצבים

```
Swipe Up
    │
    ▼
snoozePhoto()
    ├─ הסר מ-photoStack
    ├─ הוסף ל-processedAssetIDs (מסתיר מ-pagination)
    ├─ שמור snoozeCount ב-UserDefaults (count++)
    ├─ הוסף ל-snoozeQueue עם offset (50 / 150 / 500)
    └─ haptic snooze

user swipes Keep or Delete (×N)
    │
    ▼
decrementSnoozeCounts()
    ├─ swipesRemaining-- לכל פריט בתור
    └─ אם swipesRemaining ≤ 0:
           ├─ הסר מ-snoozeQueue
           ├─ הסר מ-processedAssetIDs
           └─ inject ל-photoStack[0]

הפריט מופיע שוב בראש הסטאק
    ├─ swipe Up שוב → offset = 150 (אם זה הפעם השנייה)
    ├─ swipe Right → keep (+ clearSnoozedID)
    └─ swipe Left  → delete (+ clearSnoozedID)
```

---

## נקודות עיצוב שכדאי לדעת

1. **Offline Cache נמחק בסנוז** — `OfflineCacheService.shared.evict(for: topCard.id)` נקרא ב-`snoozePhoto()`. הכרטיס ייטען מחדש כשיחזור.

2. **מספר סנוזים במקביל** — מותר. כמה תמונות יכולות להיות ב-`snoozeQueue` בו-זמנית, כל אחת עם `swipesRemaining` משלה.

3. **שני פריטים שמגיעים ל-0 באותו swipe** — שניהם מוזרקים ל-`photoStack[0]` באותה קריאה. הסדר ביניהם הוא סדר האינדקסים ב-`snoozeQueue` (FIFO).

4. **Snooze בתוך Shuffle Mode** — עובד. אבל כש-Shuffle מסתיים, `flushSnoozedToFront()` מבטל את הספירה ומחזיר את הכל מיד.

5. **Daily Limit** — `snoozePhoto()` לא קורא ל-`DailyLimitService.shared.recordSwipe()`. משתמשי freemium יכולים לסנוז ללא הגבלה גם כשהגיעו למכסה היומית — רק keep ו-delete חסומים.

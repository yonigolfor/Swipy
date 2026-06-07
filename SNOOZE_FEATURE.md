# Snooze Feature — "Later" (Swipe Up)

## מה זה

"Snooze" הוא פעולת ה-swipe-up בסוויפי. המשמעות: "אני לא רוצה להחליט עכשיו — תחזיר לי את התמונה הזאת אחרי כמה החלקות." התמונה עוברת לתור פנימי (`snoozeQueue`) ומוחדרת ב-index 2 בתחתית הסטאק הנראה כאשר `globalActionCounter` מגיע ל-`stagingMilestone` שלה. משם היא צפה טבעית לראש הסטאק עם כל swipe — ללא pop וללא טלפורט.

---

## Absolute Milestones — הלוגיקה המרכזית

המערכת עובדת עם **שני milestones מוחלטים** לכל פריט:

```
stagingMilestone = globalActionCounter + backoffValue - snoozeStageDepth
targetMilestone  = globalActionCounter + backoffValue
```

- `globalActionCounter` — מונה מונוטוני שגדל ב-1 על כל keep או delete. שמור ב-UserDefaults, לעולם לא יורד.
- `stagingMilestone` — הערך שבו הפריט מוחדר ב-index 2 (תחתית הסטאק הנראה).
- `targetMilestone` — הערך שבו הפריט היה אמור לצוץ בראש הסטאק (נשמר לצורך reference בלבד — בפועל הפריט כבר נמצא בסטאק).
- `snoozeStageDepth = 2` — equals `cardStackSize - 1 = 3 - 1 = 2`.

**למה זה נכון:** שלושת הערכים persisted → הלוגיקה שורדת force-quit, app updates וכל שינוי state.

---

## Exponential Backoff

| מספר הsnooze לפריט | backoffValue | swipes עד הגעה לראש |
|--------------------|-------------|---------------------|
| 1 (ראשון)           | 50          | ~50 keep/delete     |
| 2 (שני)             | 100         | ~100 keep/delete    |
| 3+ (שלישי ומעלה)    | 150         | ~150 keep/delete    |

הספירה מצטברת ב-`SnoozedPhotoRecord.snoozeCount` ב-UserDefaults.

---

## מבנה הנתונים

### In-memory (PhotoStackViewModel)

```swift
private struct SnoozedPhoto {
    let item: PhotoItem
    let targetMilestone: Int   // reference only
    let stagingMilestone: Int  // counter value at which item enters photoStack at index 2
    let snoozeCount: Int
}

/// Insertion depth — SwipeStackView.cardStackSize - 1.
/// Item enters at the bottom of the visible ZStack and reaches index 0
/// after snoozeStageDepth more swipes.
private let snoozeStageDepth = 2

private var snoozeQueue: [SnoozedPhoto] = []
```

### Persisted (PersistenceService)

```swift
struct SnoozedPhotoRecord: Codable {
    let snoozeCount: Int
    let targetMilestone: Int   // reference only
    let stagingMilestone: Int  // absolute counter at which item is inserted at index 2

    // Backward compat: V2 records without stagingMilestone default to targetMilestone - 2
    init(from decoder: Decoder) throws { ... }
}

// [localIdentifier: SnoozedPhotoRecord] — key: "snoozedPhotosV2"
var snoozedPhotos: [String: SnoozedPhotoRecord]

// מונה מונוטוני — key: "globalActionCounter"
var globalActionCounter: Int
```

---

## זרימה — שלב אחר שלב

### Snooze (`snoozePhoto()`)

```
1. processedAssetIDs.insert(topCard.id)   // חסום pagination
2. photoStack.removeFirst()
3. OfflineCacheService.evict(for: id)
4. newCount = (existingRecord?.snoozeCount ?? 0) + 1
5. backoff = 50 / 150 / 500
6. milestone = globalActionCounter + backoff
7. staging  = milestone - snoozeStageDepth        ← חדש
8. persist: SnoozedPhotoRecord(snoozeCount, targetMilestone: milestone, stagingMilestone: staging)
9. snoozeQueue.append(SnoozedPhoto(item, targetMilestone, stagingMilestone, snoozeCount))
10. haptic snooze
```

### Keep / Delete (קריטי — סדר הפעולות)

```
1. processedAssetIDs.insert(topCard.id)
2. photoStack.removeFirst()
3. ... (bin / kept logic) ...
4. persistence.globalActionCounter += 1    ← קודם
5. stageSnoozedItemsIfReady()              ← אחר כך
```

הסדר הכרחי: אם הפוך — פריט שה-stagingMilestone שלו הוא בדיוק counter+1 מחמיץ swipe אחד.

### `stageSnoozedItemsIfReady()` — מנגנון הhחזרה

```swift
private func stageSnoozedItemsIfReady() {
    guard !snoozeQueue.isEmpty else { return }
    let counter = persistence.globalActionCounter
    let readyIndices = snoozeQueue.indices.filter { counter >= snoozeQueue[$0].stagingMilestone }
    guard !readyIndices.isEmpty else { return }
    let toStage = readyIndices.map { snoozeQueue[$0].item }
    for i in readyIndices.reversed() { snoozeQueue.remove(at: i) }
    for item in toStage {
        processedAssetIDs.remove(item.id)
        persistence.clearSnoozedID(item.id)
        photoStack.insert(item, at: min(snoozeStageDepth, photoStack.count))
    }
}
```

נקרא **רק** אחרי keep/delete ואחרי כל בנייה מחדש של photoStack.  
snooze swipes לא מקדמים את המונה ולא מפעילים את הפונקציה.

**ניקוי חלקי בזמן staging:** רק `processedAssetIDs` מתנקה בעת staging, כדי למנוע מ-pagination לשלוף duplicate. רשומת ה-persistence **נשארת** עד שהמשתמש מחליט סופית (keep/delete/undo) — כך `snoozeCount` נשמר לצורך badge ה-×2/×3 ולחישוב backoff נכון ב-snooze הבא.

---

## Persistence — מה שורד force-quit

| ערך | מפתח UserDefaults | נמחק מתי |
|-----|-------------------|----------|
| `globalActionCounter` | `"globalActionCounter"` | לעולם לא |
| `snoozedPhotos` | `"snoozedPhotosV2"` | כשהמשתמש עושה keep / delete / undo |

### אתחול לאחר force-quit (init)

```swift
// 1. Migration מפורמט ישן (חד-פעמי)
persistence.migrateSnoozeDataIfNeeded()

// 2. חסום רק IDs עם snooze פעיל (targetMilestone עדיין לא הגיע)
let counter = persistence.globalActionCounter
let activeSnoozeIDs = Set(persistence.snoozedPhotos
    .filter { counter < $0.value.targetMilestone }.keys)
self.processedAssetIDs = persistence.keptPhotoIDs.union(activeSnoozeIDs)

// 3. בנה snoozeQueue מהpersistence
restoreSnoozedItems()
```

### `restoreSnoozedItems()` — חלוקה לאחר אתחול

- **פריטים בשלים** (`counter >= targetMilestone`): `clearSnoozedID` → יצוצו דרך pagination רגיל (ID לא נחסם)
- **פריטים שstagingMilestone שלהם עבר** (`counter >= stagingMilestone` אך `< targetMilestone`): נכנסים ל-`snoozeQueue` כרגיל; `stageSnoozedItemsIfReady()` יזרוק אותם לindex 2 מיד כשphotoStack יהיה מוכן
- **פריטים פעילים** (`counter < stagingMilestone`): נכנסים ל-`snoozeQueue`, ID נשאר חסום
- **assets שנמחקו מהספרייה**: `clearSnoozedID` + `processedAssetIDs.remove`

---

## Undo (Shake)

```swift
if last.action == .snooze {
    snoozeQueue.removeAll { $0.item.id == item.id }
    persistence.clearSnoozedID(item.id)  // מחיקה מוחלטת — לא decrement
}
```

**חשוב:** `globalActionCounter` **לא יורד** ב-undo. המונה רק עולה.  
**חשוב:** undo של snooze אפשרי רק לפני הswipe הבא — `lastAction` מוחלף בכל keepPhoto/deletePhoto. לכן הפריט לעולם לא יהיה בphotoStack (staged) בזמן undo.  
**חשוב:** `clearSnoozedID` מלא (לא decrement של snoozeCount) — record עם future stagingMilestone היה חוסם את הפריט שוב בעלייה הבאה.

---

## Migration V1 → V2 → V3 (stagingMilestone)

| גרסה | פורמט | מפתח |
|------|--------|------|
| V1 | `[String: Int]` (snoozeCount בלבד) | `"snoozedPhotos"` |
| V2 | `SnoozedPhotoRecord(snoozeCount, targetMilestone)` | `"snoozedPhotosV2"` |
| V3 | `SnoozedPhotoRecord(snoozeCount, targetMilestone, stagingMilestone)` | `"snoozedPhotosV2"` |

**V1→V2:** `targetMilestone = globalActionCounter` → פריטים צצים מיד בהשקה הראשונה לאחר העדכון.  
**V2→V3:** `stagingMilestone` לא קיים בrecords ישנים → `decodeIfPresent` מחזיר `targetMilestone - 2` כdefault → התנהגות זהה לפריטים חדשים.

---

## מה לא קורה ב-Snooze

- **אין** הוספה ל-Review Bin
- **אין** מחיקה
- **אין** רישום ב-`keptPhotoIDs`
- **אין** עדכון ב-`DailyLimitService` (לא נספר כ-swipe לצורך המכסה היומית)
- **אין** התראה כשהפריט חוזר
- **אין** גבול מקסימלי למספר פעמים שניתן לסנוז את אותה תמונה

---

## VictoryView — Escape Hatch לסטאק ריק

כשה-`photoStack` מתרוקן ויש פריטים ב-`snoozeQueue` התואמים לפילטר הפעיל, ה-`VictoryView` מציג CTA ייעודי:

- **כותרת:** "You have X snoozed items" / "יש לך X פריטים שנדחו"
- **כפתור:** "Review Now" / "עבור אליהם" (כתום)

**`pendingSnoozedCount: @Published private(set) Int`** — מספר הפריטים ב-`snoozeQueue` התואמים את `currentFilter`. מתעדכן אחרי כל מוטציה של `snoozeQueue` ואחרי שינוי פילטר.

**`flushSnoozedItemsNow()`** — נקרא בלחיצה על הכפתור. מזריק את כל הפריטים התואמים לפילטר ישירות לסטאק, עוקף את ה-milestone counter. זהה ל-`stageSnoozedItemsIfReady()` אבל ללא תנאי milestone. רשומות ה-persistence **נשארות** (לצורך snoozeCount badge בswipe הבא).

**מצב Offline:** כאשר `isOfflineMode == true`, ה-flush מוגבל לפריטים **הזמינים מקומית בלבד**. `flushableSnoozedItems()` בודק `isLocallyAvailable` ואם לא — `OfflineCacheService.isCached()` (בדיקת `fileExists` בלבד, ללא קריאת נתונים). פריטי iCloud-only נשארים ב-`snoozeQueue` ויופיעו ב-"Review Now" כשהמשתמש יחזור לאונליין. `pendingSnoozedCount` גם הוא מציג רק את הפריטים הנגישים, ולכן הכפתור לעולם לא יטעה את המשתמש לגבי כמות הפריטים שיחזרו.

גם לאחר ה-injection, צינור הטעינה מכבד את offline mode: `startCaching()` ו-`VideoPlayerPool` פועלים עם `isNetworkAccessAllowed = false` — אין ניסיון לגשת לiCloud גם אם הפריט היה נראה "זמין" אך לא לגמרי מקומי.

**למה זה הכרחי:** `globalActionCounter` עולה רק על keep/delete. סטאק ריק = אי-אפשר להחליק = המונה לעולם לא מתקדם = פריט סנוז שהוא האחרון בגלריה תקוע ללא מוצא. ה-CTA פותר את ה-hard deadlock הזה.

---

## דיאגרמת מצבים

```
Swipe Up
    │
    ▼
snoozePhoto()
    ├─ processedAssetIDs.insert(id)
    ├─ staging  = globalActionCounter + backoff - 2
    ├─ milestone = globalActionCounter + backoff
    ├─ persist: SnoozedPhotoRecord(snoozeCount, targetMilestone, stagingMilestone)
    └─ snoozeQueue.append(...)
         └─ updatePendingSnoozedCount()

Path A — Normal (יש עוד פריטים בסטאק)
    │
    ▼
User swipes Keep or Delete (×N until globalActionCounter >= stagingMilestone)
    │
    ▼
persistence.globalActionCounter += 1
stageSnoozedItemsIfReady()
    └─ אם globalActionCounter >= item.stagingMilestone:
           ├─ snoozeQueue.remove(item)
           ├─ processedAssetIDs.remove(item.id)
           └─ photoStack.insert(item, at: min(2, photoStack.count))
                          ↑ index 2 = תחתית הZStack הנראה

Path B — Escape hatch (הסטאק ריק, VictoryView מוצג)
    │
    ▼
User taps "Review Now"
    │
    ▼
flushSnoozedItemsNow()
    ├─ snoozeQueue.removeAll { matchesCurrentFilter }
    ├─ processedAssetIDs.remove(item.id)  ← מבטל חסימת pagination
    └─ photoStack.insert(item, at: min(2, photoStack.count))

הפריט כבר נמצא בסטאק ב-index 2
    │
    ├─ swipe אחד  → עולה ל-index 1
    ├─ שני swipes → עולה ל-index 0 (ראש הסטאק) — ללא pop
    │
    ▼
הפריט בראש הסטאק
    ├─ Swipe Up שוב → backoff = 150/500
    ├─ Swipe Right  → keep
    └─ Swipe Left   → delete
```

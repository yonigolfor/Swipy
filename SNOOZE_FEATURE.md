# Snooze Feature — "Later" (Swipe Up)

## מה זה

"Snooze" הוא פעולת ה-swipe-up בסוויפי. המשמעות: "אני לא רוצה להחליט עכשיו — תחזיר לי את התמונה הזאת אחרי כמה החלקות." התמונה עוברת לתור פנימי (`snoozeQueue`) ומוחזרת לראש הסטאק כאשר `globalActionCounter` מגיע ל-`targetMilestone` שלה.

---

## Absolute Milestone — הלוגיקה המרכזית

במקום ספירה יחסית לאחור (`swipesRemaining--`), המערכת עובדת עם **milestone מוחלט**:

```
targetMilestone = globalActionCounter + backoffValue
```

- `globalActionCounter` — מונה מונוטוני שגדל ב-1 על כל keep או delete. שמור ב-UserDefaults, לעולם לא יורד.
- `targetMilestone` — הערך של `globalActionCounter` שבו הפריט צריך לצוץ מחדש.
- פריט בשל כאשר: `globalActionCounter >= targetMilestone`

**למה זה נכון:** שני הערכים persisted → הloגיקה שורדת force-quit, app updates וכל שינוי state.

---

## Exponential Backoff

| מספר הsnooze לפריט | backoffValue | swipes עד חזרה |
|--------------------|-------------|----------------|
| 1 (ראשון)           | 50          | ~50 keep/delete |
| 2 (שני)             | 150         | ~150 keep/delete |
| 3+ (שלישי ומעלה)    | 500         | ~500 keep/delete |

הספירה מצטברת ב-`SnoozedPhotoRecord.snoozeCount` ב-UserDefaults.

---

## מבנה הנתונים

### In-memory (PhotoStackViewModel)

```swift
private struct SnoozedPhoto {
    let item: PhotoItem
    let targetMilestone: Int  // absolute counter value when this item resurfaces
    let snoozeCount: Int
}

private var snoozeQueue: [SnoozedPhoto] = []
```

### Persisted (PersistenceService)

```swift
struct SnoozedPhotoRecord: Codable {
    let snoozeCount: Int
    let targetMilestone: Int
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
6. milestone = persistence.globalActionCounter + backoff
7. persistence.snoozedPhotos[id] = SnoozedPhotoRecord(snoozeCount: newCount, targetMilestone: milestone)
8. snoozeQueue.append(SnoozedPhoto(item, targetMilestone: milestone, snoozeCount: newCount))
9. haptic snooze
```

### Keep / Delete (קריטי — סדר הפעולות)

```
1. processedAssetIDs.insert(topCard.id)
2. photoStack.removeFirst()
3. ... (bin / kept logic) ...
4. persistence.globalActionCounter += 1    ← קודם
5. checkSnoozeMilestones()                 ← אחר כך
```

הסדר הכרחי: אם הפוך — פריט שה-milestone שלו הוא בדיוק counter+1 מחמיץ swipe אחד.

### checkSnoozeMilestones() — מנגנון החזרה

```swift
private func checkSnoozeMilestones() {
    guard !snoozeQueue.isEmpty else { return }
    let counter = persistence.globalActionCounter
    let readyIndices = snoozeQueue.indices.filter { counter >= snoozeQueue[$0].targetMilestone }
    guard !readyIndices.isEmpty else { return }
    let toInject = readyIndices.map { snoozeQueue[$0].item }
    for i in readyIndices.reversed() { snoozeQueue.remove(at: i) }
    toInject.forEach { processedAssetIDs.remove($0.id) }
    photoStack.insert(contentsOf: toInject, at: 0)
}
```

נקרא **רק** אחרי keep/delete — snooze swipes לא מקדמים את המונה.

---

## Persistence — מה שורד force-quit

| ערך | מפתח UserDefaults | נמחק מתי |
|-----|-------------------|----------|
| `globalActionCounter` | `"globalActionCounter"` | לעולם לא |
| `snoozedPhotos` | `"snoozedPhotosV2"` | כשהמשתמש עושה keep/delete/undo על הפריט |

### אתחול לאחר force-quit (init)

```swift
// 1. Migration מפורמט ישן (חד-פעמי)
persistence.migrateSnoozeDataIfNeeded()

// 2. חסום רק IDs עם snooze פעיל
let counter = persistence.globalActionCounter
let activeSnoozeIDs = Set(persistence.snoozedPhotos
    .filter { counter < $0.value.targetMilestone }.keys)
self.processedAssetIDs = persistence.keptPhotoIDs.union(activeSnoozeIDs)

// 3. בנה snoozeQueue מהpersistence
restoreSnoozedItems()
```

### restoreSnoozedItems() — חלוקה נכונה

- **פריטים בשלים** (`counter >= targetMilestone`): `clearSnoozedID` → יצוצו דרך pagination רגיל
- **פריטים פעילים** (`counter < targetMilestone`): נכנסים ל-`snoozeQueue`
- **assets שנמחקו מהספרייה**: `clearSnoozedID` + `processedAssetIDs.remove`

---

## injectReadySnoozedItems() — שינוי state

נקרא בתחילת כל `resetAndLoad` (החלפת filter, shuffle, offline toggle):

```swift
@discardableResult
private func injectReadySnoozedItems() -> [PhotoItem] {
    guard !snoozeQueue.isEmpty else { return [] }
    let counter = persistence.globalActionCounter
    let ready = snoozeQueue.filter { counter >= $0.targetMilestone }
    guard !ready.isEmpty else { return [] }
    let items = ready.map { $0.item }
    snoozeQueue.removeAll { counter >= $0.targetMilestone }
    items.forEach { processedAssetIDs.remove($0.id) }
    return items
}
```

**ההבדל מהישן (`flushSnoozedToFront`):** רק פריטים שהגיעו ל-milestone שלהם מוזרקים לחזית. פריטים שעדיין בbackoff window נשארים חסומים — החלפת filter/shuffle אינה עוקפת את כוונת המשתמש.

---

## Undo (Shake)

```swift
if last.action == .snooze {
    snoozeQueue.removeAll { $0.item.id == item.id }
    persistence.clearSnoozedID(item.id)  // מחיקה מוחלטת — לא decrement
}
```

**חשוב:** `globalActionCounter` **לא יורד** ב-undo. המונה רק עולה.  
**חשוב:** `clearSnoozedID` מלא (לא decrement של snoozeCount) — record עם future targetMilestone היה חוסם את הפריט שוב בעלייה הבאה.

---

## Migration V1 → V2

פורמט ישן: `[String: Int]` (key: `"snoozedPhotos"`)  
פורמט חדש: `[String: SnoozedPhotoRecord]` (key: `"snoozedPhotosV2"`)

```swift
func migrateSnoozeDataIfNeeded() {
    // קורא legacy key, ממיר לV2 עם targetMilestone = globalActionCounter (מיידי)
    // מנקה legacy key כדי שהmigration לא יחזור על עצמו
}
```

פריטים ישנים מקבלים `targetMilestone = globalActionCounter` → צצים מיד בהשקה הראשונה לאחר העדכון.

---

## מה לא קורה ב-Snooze

- **אין** הוספה ל-Review Bin
- **אין** מחיקה
- **אין** רישום ב-`keptPhotoIDs`
- **אין** עדכון ב-`DailyLimitService` (לא נספר כ-swipe לצורך המכסה היומית)
- **אין** התראה כשהפריט חוזר
- **אין** גבול מקסימלי למספר פעמים שניתן לסנוז את אותה תמונה

---

## דיאגרמת מצבים

```
Swipe Up
    │
    ▼
snoozePhoto()
    ├─ processedAssetIDs.insert(id)
    ├─ milestone = globalActionCounter + backoff(50/150/500)
    ├─ persist: SnoozedPhotoRecord(snoozeCount, targetMilestone)
    └─ snoozeQueue.append(...)

User swipes Keep or Delete
    │
    ▼
persistence.globalActionCounter += 1
checkSnoozeMilestones()
    └─ אם globalActionCounter >= item.targetMilestone:
           ├─ snoozeQueue.remove(item)
           ├─ processedAssetIDs.remove(item.id)
           └─ photoStack.insert(item, at: 0)

הפריט מופיע שוב בראש הסטאק
    ├─ Swipe Up שוב → backoff = 150/500
    ├─ Swipe Right → keep (+ clearSnoozedID)
    └─ Swipe Left  → delete (+ clearSnoozedID)
```

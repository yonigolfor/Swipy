# House Ads — Implementation Plan

## מה אנחנו בונים

כרטיסי פרסומת פנימיים ("House Ads") שמופיעים כל 20 החלקות בחפיסת הקלפים — בדיוק כמו ב-Tinder. הכרטיס נראה ומרגיש כמו כרטיס רגיל, והמשתמש מחליק לכל כיוון כדי לסגור אותו. נשתמש בזה לקידום Premium או cross-promo לאפליקציות אחרות. אין SDK חיצוני — הכל native.

---

## ארכיטקטורה — הגישה הנבחרת

**Enum `StackCard`** במקום `[PhotoItem]` ישירות.

```swift
enum StackCard: Identifiable {
    case photo(PhotoItem)
    case houseAd(HouseAdContent)

    var id: String {
        switch self {
        case .photo(let item): return item.id
        case .houseAd(let ad): return "ad_\(ad.id)"
        }
    }

    // נוחות — מחזיר nil אם זה פרסומת
    var photoItem: PhotoItem? {
        if case .photo(let item) = self { return item }
        return nil
    }
}
```

**למה enum ולא `isAd: Bool` בתוך `PhotoItem`:**
- כפיית טיפוסים — Swift מחייב כל consumer לטפל במקרה הפרסומת
- `HouseAdContent` אין לו `PHAsset`, `fileSize`, `duration` — זה אחר מהותית
- ביצועים — אין בדיקות `if item.isAd` פזורות בקוד

---

## טיפוסי הנתונים החדשים

### `HouseAdContent`

קובץ חדש: `Models/HouseAdContent.swift`

```swift
struct HouseAdContent: Identifiable {
    let id: String
    let imageName: String      // שם ב-Assets.xcassets
    let title: String          // "שדרג ל-Premium"
    let subtitle: String       // "החלקות בלתי מוגבלות + עוד"
    let ctaLabel: String       // "גלה עוד"
    let destination: AdDestination
}

enum AdDestination {
    case premiumUpgrade        // פותח PaywallView
    case externalURL(URL)      // cross-promo לאפליקציה אחרת
}
```

### מאגר הפרסומות

ב-`PhotoStackViewModel`, מוגדר כ-array סטטי — ללא רשת, ללא dependencies:

```swift
private let houseAds: [HouseAdContent] = [
    HouseAdContent(
        id: "premium_unlimited",
        imageName: "ad_premium",
        title: String(localized: "ad.premium.title"),
        subtitle: String(localized: "ad.premium.subtitle"),
        ctaLabel: String(localized: "ad.cta.learn_more"),
        destination: .premiumUpgrade
    ),
    // עוד פרסומות כאן בעתיד
]
private var adRoundRobinIndex = 0
```

---

## שינויי ViewModel

### שינוי מרכזי: `photoStack` → `cardStack`

```swift
// לפני:
@Published var photoStack: [PhotoItem] = []

// אחרי:
@Published var cardStack: [StackCard] = []
```

> **חשוב:** שם חדש (`cardStack`) כי הסמנטיקה השתנתה. `photoStack` רמז על תמונות בלבד.

### Properties שמשתנים

| Property | לפני | אחרי |
|---|---|---|
| `topCard` | `photoStack.first` | `cardStack.first?.photoItem` |
| `remainingCount` | `photoStack.count` | `cardStack.filter { $0.photoItem != nil }.count` |
| `isTopCardAd` | לא קיים | `if case .houseAd = cardStack.first { return true }` |

### מונה הפרסומות

```swift
private var adSwipeCounter = 0   // עולה בכל real swipe (keep/delete/snooze), לא ב-ad dismiss
private let adFrequency = 20     // כל כמה swipes מופיעה פרסומת
```

### `injectAdIfNeeded()` — פונקציה חדשה

נקראת בסוף `keepPhoto()`, `deletePhoto()`, ו-`snoozePhoto()` — לפני `precacheNextImages()`.

```swift
private func injectAdIfNeeded() {
    adSwipeCounter += 1
    guard adSwipeCounter % adFrequency == 0 else { return }

    // בטיחות: לא מזריקים פרסומת אם אין מספיק תמונות סביבה
    let photoCount = cardStack.filter { $0.photoItem != nil }.count
    guard photoCount >= 3 else { return }

    // בטיחות: לא מזריקים אם כבר יש פרסומת בסטאק
    guard !cardStack.contains(where: { if case .houseAd = $0 { return true }; return false }) else { return }

    let ad = houseAds[adRoundRobinIndex % houseAds.count]
    adRoundRobinIndex += 1

    // הזרקה ב-index 2 (תחתית ה-ZStack הנראה) — כמו snooze staging.
    // הכרטיס עולה טבעית לראש אחרי 2 swipes נוספים, ללא pop.
    cardStack.insert(.houseAd(ad), at: min(2, cardStack.count))
}
```

### שינויים בכל ה-methods

#### `keepPhoto()` / `deletePhoto()` / `snoozePhoto()`

כל שלושתם מתחילים עם:
```swift
guard case .photo(let topCard) = cardStack.first else { return }
```
ובסוף (לפני `precacheNextImages()`):
```swift
injectAdIfNeeded()
```

#### `dismissTopAd()` — פונקציה חדשה

```swift
func dismissTopAd() {
    guard case .houseAd = cardStack.first else { return }
    cardStack.removeFirst()
    hapticService.selection()
    precacheNextImages()
    loadNextPageIfNeeded()
    // adSwipeCounter לא עולה — dismiss של פרסומת לא נחשב swipe
}
```

#### `undoLastAction()`

`lastAction` הוא `(item: PhotoItem, action: SwipeAction)` — לא נגע בו. Undo עובד על PhotoItem בלבד, כי אנחנו קוראים `guard let last = lastAction` ו-lastAction נשמר רק ב-keep/delete/snooze שמתחילים עם `guard case .photo`. **אין שינוי נדרש.**

#### `precacheNextImages()` ו-`prepareUpcomingCards()`

```swift
// לפני:
let nextItems = Array(photoStack.prefix(5))

// אחרי:
let nextItems = cardStack.prefix(5).compactMap { $0.photoItem }
```
זה מדלג על פרסומות אוטומטית — אין להן asset.

#### `startBackgroundPrefetch()`

```swift
// לפני:
let items = Array(photoStack.dropFirst().prefix(20)).filter { !$0.isVideo }

// אחרי:
let items = cardStack.dropFirst().prefix(20).compactMap { $0.photoItem }.filter { !$0.isVideo }
```

#### `loadNextPageIfNeeded()`

בדיקת watermark צריכה לספור רק תמונות אמיתיות:
```swift
let photoCount = cardStack.filter { $0.photoItem != nil }.count
guard !isFetchingNextPage, photoCount <= lowWatermark else { return }
```

#### `evictStaleCacheEntries(keeping:)`

```swift
// לפני:
var keepIDs = Set(items.map { $0.id })
if let topID = photoStack.first?.id { keepIDs.insert(topID) }
if let item = photoStack.first(where: { $0.id == id }) { evictedItems.append(item) }

// אחרי:
var keepIDs = Set(items.map { $0.id })
if let topPhotoID = cardStack.first?.photoItem?.id { keepIDs.insert(topPhotoID) }
if let item = cardStack.compactMap({ $0.photoItem }).first(where: { $0.id == id }) {
    evictedItems.append(item)
}
```

#### `stageSnoozedItemsIfReady()`

```swift
// לפני:
photoStack.insert(tagged, at: min(snoozeStageDepth, photoStack.count))

// אחרי:
cardStack.insert(.photo(tagged), at: min(snoozeStageDepth, cardStack.count))
```

#### `resetAndLoad()` / כל מקום שמבצע `photoStack = items`

```swift
// לפני:
self.photoStack = rawItems

// אחרי:
self.cardStack = rawItems.map { .photo($0) }
```

גם `photoStack.append(contentsOf: batch)` הופך ל-`cardStack.append(contentsOf: batch.map { .photo($0) })` בכל מקום (scanLocalUniverse, scanUntilFull, loadNextPageIfNeeded, photoLibraryDidChange).

#### `photoLibraryDidChange()`

```swift
// לפני:
let existingIDs = Set(self.photoStack.map { $0.id })

// אחרי:
let existingIDs = Set(self.cardStack.compactMap { $0.photoItem?.id })
```

#### `restoreLinearStack()`

```swift
// לפני:
return snapshot.filter { !processedAssetIDs.contains($0.id) }

// אחרי:
return snapshot.filter {
    guard case .photo(let item) = $0 else { return false }  // מסנן פרסומות תמיד
    return !processedAssetIDs.contains(item.id)
}
```

#### `scanLocalUniverse()` — seenIDs

```swift
// לפני:
var seenIDs: Set<String> = Set(photoStack.map { $0.id })

// אחרי:
var seenIDs: Set<String> = Set(cardStack.compactMap { $0.photoItem?.id })
```

---

## שינויי SwipeStackView

### ForEach — תמיכה בשני סוגי כרטיסים

```swift
ForEach(
    Array(viewModel.cardStack.prefix(cardStackSize).enumerated()),
    id: \.element.id
) { index, card in
    Group {
        switch card {
        case .photo(let item):
            PhotoCardView(
                item: item,
                isTopCard: index == 0,
                cachedImage: viewModel.imageCache.object(forKey: item.id as NSString)
            )
        case .houseAd(let ad):
            AdCardView(ad: ad)
                .environmentObject(viewModel)
        }
    }
    .frame(width: geometry.size.width - 40, height: geometry.size.height - 40)
    .zIndex(Double(cardStackSize - index))
    .offset(x: index == 0 ? dragOffset.width : 0,
            y: index == 0 ? dragOffset.height : CGFloat(index * 8))
    .scaleEffect(index == 0 ? 1.0 : (1.0 - CGFloat(index) * 0.05))
    .rotationEffect(.degrees(index == 0 ? dragRotation : (card.photoItem?.rotation ?? 0)))
    .opacity(index == 0 ? 1.0 : (1.0 - Double(index) * 0.2))
    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragOffset)
    .gesture(index == 0 ? dragGesture : nil)
    .overlay { if index == 0 { swipeIndicatorOverlay } }
}
```

### dragGesture — טיפול בפרסומת

בתוך `.onEnded`, לפני הקריאה ל-`viewModel.performAction(action)`:

```swift
// אם הקלף העליון הוא פרסומת — כל swipe סוגר אותה, ללא לוגיקת keep/delete/snooze
if viewModel.isTopCardAd {
    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
        switch direction {
        case .left:  dragOffset = CGSize(width: -500, height: value.translation.height)
        case .right: dragOffset = CGSize(width: 500, height: value.translation.height)
        case .up:    dragOffset = CGSize(width: value.translation.width, height: -500)
        case .none:  break
        }
    }
    NotificationCenter.default.post(name: .stopCurrentVideo, object: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        viewModel.dismissTopAd()
        dragOffset = .zero
        dragRotation = 0
    }
    return
}
```

### VictoryView condition

```swift
// לפני:
} else if viewModel.photoStack.isEmpty {

// אחרי:
} else if viewModel.cardStack.isEmpty {
```
(כרטיס פרסומת לבדו לא יגרום ל-VictoryView — הוא גם נמצא ב-cardStack. עם הגנת `photoCount >= 3` בהזרקה, לעולם לא נגיע למצב שרק פרסומת נשארה.)

---

## `AdCardView` — מפרט עיצוב

קובץ חדש: `Views/Main/AdCardView.swift`

**מבנה ויזואלי** — זהה בגודל ובצורה ל-`PhotoCardView`:
- פינות מעוגלות 20pt
- `Color.cardBackground` רקע
- תמונה מ-Assets (fullscreen, fill mode)
- Gradient overlay כהה בחלק התחתון
- Badge "Sponsored" בפינה עליונה שמאלית — capsule קטן, `.ultraThinMaterial` + `Color.swipeBlue.opacity(0.2)`

**תוכן (bottom overlay):**
```
[תמונת פרסומת fullscreen]
────────────────────────
Gradient overlay (שחור → שקוף, מלמטה)

  [כותרת — Bold, 22pt]
  [תת-כותרת — Regular, 14pt, לבן opacity 0.8]

  [כפתור CTA — Capsule, fill: swipeBlue]
    "גלה עוד"
```

**אין:** snooze indicator, file size badge, heart icon, video controls. הכרטיס הוא ad — clean ופשוט.

**Tap על כפתור CTA:**
- `.premiumUpgrade` → `viewModel.shouldShowPaywall = true`
- `.externalURL(url)` → `UIApplication.shared.open(url)`

---

## Localization — מפתחות חדשים

להוסיף ל-`Localizable.xcstrings`:

| מפתח | עברית | אנגלית |
|---|---|---|
| `ad.badge.sponsored` | "ממומן" | "Sponsored" |
| `ad.premium.title` | "הגיע הזמן לשדרג" | "Time to Upgrade" |
| `ad.premium.subtitle` | "החלקות בלתי מוגבלות + כל הפיצ'רים" | "Unlimited swipes + all features" |
| `ad.cta.learn_more` | "גלה עוד" | "Learn More" |

---

## Persistence — מה צריך לשרוד force-quit?

**כלום** — `adSwipeCounter` הוא in-memory בלבד. אם המשתמש סוגר את האפליקציה, הספירה מתאפסת. זה מכוון — פרסומות הן session-level, לא lifetime. אין סיבה לזכור "ראית פרסומת לפני 3 ימים".

---

## ניתוח Edge Cases

| מצב | התנהגות |
|---|---|
| פחות מ-3 תמונות בסטאק | פרסומת לא מוזרקת (guard `photoCount >= 3`) |
| כבר יש פרסומת בסטאק | פרסומת שנייה לא מוזרקת (guard `!contains .houseAd`) |
| Shake (undo) כשהקלף העליון הוא פרסומת | `undoLastAction()` ב-ViewModel כבר מוגן — `lastAction` נשמר רק על `.photo` swipes, אז undo ישחזר את הפוטו שלפני הפרסומת |
| Snooze על פרסומת | מטופל ב-`isTopCardAd` check ב-gesture — treated כ-dismiss |
| Shuffle — פרסומת בסנאפשוט | `restoreLinearStack()` מסנן `.houseAd` תמיד |
| Offline mode | פרסומות מוזרקות גם ב-offline — אין dependency על רשת |
| Blurry / Burst filter | פרסומות מוזרקות רק ב-.all filter? לא בהכרח — `injectAdIfNeeded()` אגנוסטי ל-filter. שיקול לעתיד: filter by `currentFilter == .all` |
| Daily limit exhausted | הפרסומת לא בודקת DailyLimitService — dismissal תמיד חופשי |
| VictoryView | מוצגת כש-`cardStack.isEmpty` — פרסומת בודדת לא תגרום לזה הודות לגנרד |

---

## רשימת קבצים לשינוי

### קבצים חדשים (ליצור)
- `Models/HouseAdContent.swift` — הטיפוס החדש + `AdDestination`
- `Models/StackCard.swift` — ה-enum + `Identifiable` conformance
- `Views/Main/AdCardView.swift` — כרטיס הפרסומת

### קבצים קיימים לעדכון
- `ViewModels/PhotoStackViewModel.swift` — עיקר השינויים (ראה רשימה למעלה)
- `Views/Main/SwipeStackView.swift` — ForEach + dragGesture + VictoryView condition
- `Swipy/Localizable.xcstrings` — 4 מפתחות חדשים
- `Assets.xcassets` — תמונות פרסומות
- `CLAUDE.md` — עדכון File Structure

### קבצים שלא צריכים שינוי
- `PhotoCardView.swift` — לא נוגע ב-cardStack
- `ReviewBinView.swift` / `ReviewBinViewModel.swift` — עובד עם `reviewBin: [PhotoItem]`
- `PersistenceService.swift` — לא מחזיק את הסטאק
- כל ה-Services — אגנוסטים לסטאק

---

## סדר יישום מומלץ

1. **`StackCard.swift` + `HouseAdContent.swift`** — הטיפוסים החדשים (אין תלויות)
2. **`PhotoStackViewModel.swift`** — שינוי מרכזי. קומפיל אחרי כל שלב.
3. **`AdCardView.swift`** — UI בלבד, ViewModel כבר מוכן
4. **`SwipeStackView.swift`** — ForEach + gesture
5. **`Localizable.xcstrings` + Assets** — תוכן
6. **בדיקה ידנית:** keep 20 פעמים → פרסומת מופיעה → swipe → נעלמת. Undo לפני ואחרי. Shuffle. Offline.

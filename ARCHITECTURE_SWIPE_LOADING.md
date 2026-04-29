# Swipy — Swipe Stack: Loading Architecture & UX Analysis

## 1. הבעיה המדויקת — למה נטענת מחדש בחזרה לטאב

### הגורם הישיר

`SwipeStackView.onAppear` קורא `viewModel.refreshPhotos()` **בכל פעם** שהמשתמש חוזר לטאב:

```swift
// SwipeStackView.swift:139
.onAppear {
    viewModel.refreshPhotos()
}
```

`refreshPhotos()` קורא ל-`resetAndLoad()` שעושה **full reset**:

```swift
// PhotoStackViewModel.swift:255–260
private func resetAndLoad(filter: FilterCategory) {
    isLoading = true
    fetchCursor = 0           // ← מאפס את הסמן
    isFetchingNextPage = false
    // ... ומשמיד את photoStack כולו ובונה מחדש
}
```

כתוצאה מכך:

1. `photoStack` מתאפס ל-`[]` ואז מתאכלס מחדש מהספרייה
2. SwiftUI מזהה שה-`id`-ים ב-`ForEach` השתנו (סדר שונה / אובייקטים חדשים) → כל `PhotoCardView` נהרס ונבנה מחדש
3. כל `PhotoCardView` חדש מתחיל עם `@State private var image: UIImage? = nil` → מיידית קורא ל-`loadImage()` → מציג `ProgressView` עד שהתמונה חוזרת

### למה זה גלוי גם אם PHCachingImageManager מחזיק cache?

`PHCachingImageManager` אכן שומר את הפיקסלים בזיכרון/דיסק, אך:
- `loadImage` תמיד עושה קריאה async ל-`requestImage`
- התוצאה חוזרת ב-callback, לא סינכרונית
- בינתיים `isLoading = true` → `ProgressView` מוצג
- ב-`highQualityFormat` deliveryMode עלול להגיע קודם thumbnal ואז תמונה מלאה (שתי קריאות callback)

### למה VideoPlayerPool לא עוזר?

`onDisappear` של SwipeStackView קורא `VideoPlayerPool.shared.drainAll()` via `pauseVideoPool()` (בפועל רק `pauseAll()`, לא drain) — אבל `warmUp` שנקרא ב-`resetAndLoad` מבקש מחדש `PHImageManager.requestPlayerItem` לכל וידאו, וגם זה async ולוקח זמן.

---

## 2. Data Flow — מהגלריה למסך

```
PHPhotoLibrary
      │
      ▼
PhotoLibraryService.fetchAllPhotos()
  → PHFetchResult<PHAsset>  (lazy index, O(1) בגישה לפי אינדקס)
      │
      ▼
PhotoLibraryService.fetchPageOfAssets(for:startIndex:pageSize:excluding:)
  → [PhotoItem]  (wrapper קל עם asset + metadata)
      │
      ▼
PhotoStackViewModel.photoStack: [PhotoItem]
  (array בזיכרון, מנוהל דרך @Published)
      │
      ▼
SwipeStackView  —  ForEach(photoStack.prefix(3))
      │
      ▼
PhotoCardView (per item)
  ├── תמונה:  PhotoLibraryService.loadImage → PHCachingImageManager → UIImage → @State image
  └── וידאו:  VideoPlayerPool.player(for:) → AVPlayer → @State player
```

---

## 3. מבנה ה-Stack הנוכחי

### כמה קלפים מוצגים

```swift
// SwipeStackView.swift:25
private let cardStackSize = 3
```

ב-`ZStack` מוצגים תמיד **3 קלפים** בלבד (prefix(3) מ-`photoStack`):
- `index 0` = הקלף הראשי (top card) — אינטראקטיבי, מציג תמונה/וידאו מלאים
- `index 1` = קלף אחורי ראשון — `scaleEffect(0.95)`, `opacity(0.8)`, `y offset: +8px`
- `index 2` = קלף אחורי שני — `scaleEffect(0.90)`, `opacity(0.6)`, `y offset: +16px`

### גדלי דפים ו-Pagination

| שלב | גודל |
|-----|------|
| Initial page size (ברירת מחדל) | **50 items** |
| Initial page size (blurry/burst) | 200 / 500 items |
| Next page size | **30 items** |
| Low watermark (trigger לטעינה הבאה) | **12 items** |
| Image pre-cache (startCaching) | **10 items** בטעינה ראשונית |
| Image pre-cache (after swipe) | **5 items** (precacheNextImages) |

### VideoPlayerPool

| פרמטר | ערך |
|--------|-----|
| maxPoolSize | **3 players** |
| deliveryMode | `.fastFormat` (מהיר, לא הכי איכותי) |
| warmUp נקרא עם | 5 assets הבאים |
| eviction | כל asset שלא ב-5 הבאים מוסר |

---

## 4. Caching הנוכחי — מה קיים

### Image Caching (PHCachingImageManager)
- **קיים** — `PhotoLibraryService` משתמש ב-`PHCachingImageManager` (לא הרגיל)
- `startCaching` נקרא ל-10 פריטים ראשונים ואחרי כל swipe ל-5 הבאים
- **הבעיה**: ה-cache נשמר ב-`PhotoLibraryService.shared` (singleton) ולא מאופס בין מעברי טאבים
- עם זאת, `resetAndLoad` מחדש את ה-`photoStack` → כל `PhotoCardView` נהרס → `image` מתאפס → `loadImage()` רץ שוב (גם אם PHCachingImageManager מחזיק את הפיקסלים)

### Video Caching (VideoPlayerPool)
- **קיים** — singleton עם 3 players מוכנים מראש
- `warmUp` נקרא אחרי כל swipe עם 5 ה-assets הבאים
- `onDisappear` של SwipeStackView קורא `pauseAll()` — **לא drain**, players נשמרים
- **הבעיה**: `resetAndLoad` קורא שוב `warmUp` → אבל כי pool עדיין מחזיק את ה-players הישנים ולא נוצר מחדש — זה בסדר. הבעיה היא הצד של ה-View: `PhotoCardView` חדש מתחיל עם `player = nil` → `loadVideoPlayer()` רץ → pool hit צריך לקרות, אבל אם ה-asset ID השתנה (כי `photoStack` נבנה מחדש) — pool miss.

---

## 5. Swipe Flow מלא

```
משתמש מושך קלף
        │
        ▼
DragGesture.onEnded
  → animate card off screen (±500px, 0.4s spring)
  → DispatchQueue.main.asyncAfter(0.3s):
      │
      ├── viewModel.performAction(action)
      │     └── keepPhoto() / deletePhoto() / starPhoto()
      │           ├── processedAssetIDs.insert(id)
      │           ├── photoStack.removeFirst()
      │           ├── precacheNextImages()  ← cache top-5 images + warmUp top-5 videos
      │           └── loadNextPageIfNeeded()  ← if stack.count ≤ 12
      │
      └── dragOffset = .zero  (ללא animation → קלף הבא "קופץ" למקום)
```

---

## 6. בעיות UX הנוכחיות

### בעיה 1 — Tab Switch Re-Load (הבעיה הדווחת)
**מה קורה**: כל חזרה לטאב Swipe מפעילה `refreshPhotos()` → full reset → loading spinner על הקלף הראשון.

**למה**: `SwipeStackView.onAppear` קורא `refreshPhotos()` ללא תנאי. SwiftUI מפעיל `onAppear` בכל פעם שהView נכנס למסך, כולל מעבר טאבים.

**הפתרון הנדרש**: `onAppear` צריך להיות idempotent — לא לרוץ אם ה-stack כבר מאוכלס ולא השתנה כלום בספרייה. ה-`PHPhotoLibraryChangeObserver` כבר מוגדר ויטפל בשינויים אמיתיים.

### בעיה 2 — PhotoCardView State Loss
`@State private var image: UIImage?` הוא state **מקומי** לכל instance של `PhotoCardView`. כאשר ה-`photoStack` נבנה מחדש ו-SwiftUI מחדש את ה-ForEach, הstate מתאפס — גם אם הפיקסלים נמצאים ב-PHCachingImageManager.

**הפתרון הנדרש**: Cache ב-ViewModel ברמת `[assetID: UIImage]` כך שכאשר `PhotoCardView` נוצר מחדש, הוא מקבל את התמונה מיידית.

### בעיה 3 — VideoPlayerPool Eviction vs. Tab Switch
`onDisappear` קורא `pauseAll()` — זה טוב. אבל `resetAndLoad` קורא `warmUp` עם 5 assets חדשים, וה-eviction logic מסיר players שלא ב-5 הבאים. אם ה-pool עדיין מחזיק את הוידאו הראשון — זה יהיה pool hit מהיר. אם לא — slow path עם `requestPlayerItem`.

---

## 7. מה צריך לשמור (נדרש לשינויים עתידיים)

| מה | מצב נוכחי | מצב רצוי |
|----|-----------|-----------|
| `onAppear` refresh | תמיד | רק אם ספרייה השתנתה |
| Image cache | PHCachingImageManager בלבד | + ViewModel-level `[id: UIImage]` cache |
| Video pool | 3 players, evict on tab leave? | שמור pool בין מעברי טאבים |
| Stack rebuild | כל tab switch | רק אחרי library change |
| `isLoading` spinner | כל refresh | רק טעינה ראשונה אמיתית |

---

## 8. סיכום הזרימה בעיה ← פתרון

```
[משתמש עובר לטאב אחר]
        │
        ▼
SwipeStackView.onDisappear
  → pauseAll() ✓
  → stopCurrentVideo notification ✓

[משתמש חוזר לטאב Swipe]
        │
        ▼
SwipeStackView.onAppear
  → refreshPhotos()  ← BUG: זה מאפס הכל
        │
        ▼
resetAndLoad()
  → photoStack = []  ← כל הקלפים נהרסים
  → isLoading = true ← spinner מוצג
  → fetchPageOfAssets()  ← fetch חדש (גם אם לא צריך)
  → photoStack = [50 items]
        │
        ▼
ForEach renders 3 × PhotoCardView (new instances)
  → image = nil  ← state חדש
  → loadImage() רץ שוב
  → ProgressView מוצג עד שהתמונה חוזרת (גם אם cached)
```

**הפתרון הקצר**: הסר את `refreshPhotos()` מ-`onAppear` — החלף בבדיקה: "האם `photoStack` ריק ולא בטעינה?" בלבד. השינויים האמיתיים בספרייה כבר מטופלים ע"י `PHPhotoLibraryChangeObserver`.

# Swipy — Swipe Stack: Loading Architecture

## 1. Data Flow — מהגלריה למסך

```
PHPhotoLibrary
      │
      ▼
PhotoLibraryService.fetchAllPhotos()
  → PHFetchResult<PHAsset>  (lazy index, O(1) per access)
      │
      ▼
PhotoLibraryService.fetchPageOfAssets(for:startIndex:pageSize:excluding:)
  → [PhotoItem]  (lightweight wrapper: asset + metadata only)
      │
      ▼
PhotoStackViewModel.photoStack: [PhotoItem]
  (@Published array, full app session lifetime)
      │
      ▼
SwipeStackView — ForEach(photoStack.prefix(3))
      │
      ├── imageCache.object(forKey: item.id)  ← synchronous cache lookup
      │
      ▼
PhotoCardView(item:, isTopCard:, cachedImage:)
  ├── תמונה:  cachedImage != nil → מוצג מיידית (zero async round-trip)
  │           cachedImage == nil → Thumbnail Gate (ראה סעיף 7)
  └── וידאו:  loadVideoThumbnail() → placeholder מיידי
              VideoPlayerPool.player(for:) → AVPlayer (pre-warmed)
              pool miss → PHImageManager.requestPlayerItem → slow path
```

---

## 2. מבנה ה-Stack

### קלפים מוצגים
```swift
private let cardStackSize = 3
```
תמיד **3 קלפים** ב-ZStack (prefix(3) מ-`photoStack`):

| index | תיאור | עיצוב |
|-------|--------|-------|
| 0 | top card — אינטראקטיבי | scale 1.0, opacity 1.0, y=0 |
| 1 | קלף אחורי ראשון | scale 0.95, opacity 0.8, y=+8pt |
| 2 | קלף אחורי שני | scale 0.90, opacity 0.6, y=+16pt |

### Pagination

| פרמטר | ערך |
|--------|-----|
| Initial page (ברירת מחדל) | 50 items |
| Initial page (blurry) | 200 items |
| Initial page (burst) | 500 items — נדרש ל-VNFeaturePrint chain analysis |
| Next page | 30 items |
| Low watermark (trigger לדף הבא) | 12 items |

---

## 3. Image Cache — NSCache (app-level)

### למה נדרש
`PHCachingImageManager.requestImage` הוא **תמיד async**, גם כשהפיקסלים cached בזיכרון iOS. אין path סינכרוני. ה-NSCache ב-ViewModel מאפשר לגשת לתמונה **בזמן init של PhotoCardView**, לפני כל render.

### הגדרות
```swift
cache.countLimit = 8          // top-5 stack + early-precache buffer + 1 undo slot
cache.totalCostLimit = 8 MB   // ~8 תמונות בגודל קלף
```
`cacheTargetSize` = רוחב המסך פחות 40pt × 65% גובה מסך (גודל הקלף בפועל)

### מחזור חיים של entry

```
precacheNextImages() נקרא אחרי כל swipe (וגם בטעינה ראשונית)
        │
        ├── startCaching() → רמז ל-PHCachingImageManager
        ├── VideoPlayerPool.warmUp() → מכין AVPlayers לוידאו
        └── loadImage() עבור top-5 images → מכניס ל-NSCache + מסמן loadedImageIDs
                │
                ▼
        evictStaleCacheEntries()
          → מסיר keys שאינם ב-top-5 ואינם lastAction.item
          → Index-0 immunity: photoStack.first לעולם לא מוסר בזמן drag
```

### Eviction Policy
**נשמר ב-cache בכל נקודה:**
- top-5 פריטים ב-`photoStack`
- הפריט האחרון שנעשה עליו swipe (`lastSwipedImage`) — לצורך shake-to-undo
- הקלף שב-index 0 (top card) — protected מ-eviction גם אם נקראת precache בזמן drag

**מוסר מ-cache:**
- כל פריט שאינו ב-top-5 ואינו ה-undo item

### Synchronous Handshake
```
SwipeStackView:
  imageCache.object(forKey: item.id)  →  cachedImage: UIImage?
        │
        ▼
PhotoCardView.init(cachedImage:)
  _image    = State(initialValue: cachedImage)
  _isLoading = State(initialValue: cachedImage == nil)
        │
        ▼
onAppear:
  image != nil → דילוג (cache hit: אפס round-trips)
  image == nil → Thumbnail Gate: שתי קריאות מקבילות (ראה סעיף 7)
```

### loadedImageIDs — Observable Readiness
```swift
@Published var loadedImageIDs: Set<String>
```
כל פעם שתמונה נכנסת ל-NSCache ה-ID שלה מסומן ב-set הזה.  
מאפשר לviews לצפות מתי קלף "מוכן" בלי לבצע cache lookup סינכרוני.  
מנוקה ב-`resetAndLoad` (שינוי פילטר) ומעודכן ב-eviction.

---

## 4. Early Precache — prepareUpcomingCards()

מנגנון חדש שמפחית מסכים שחורים בהחלקה מהירה.

```
DragGesture.onChanged (offset > 80pt, פעם אחת per gesture)
  → viewModel.prepareUpcomingCards()
        │
        ├── photoStack.dropFirst().prefix(5)  ← דולג על index 0 (עוזב)
        ├── startCaching() עבור index 1-5
        ├── VideoPlayerPool.warmUp(protectedID: topCard.localIdentifier)
        │     └── top card מוגן מ-eviction כל עוד הgesture לא הסתיים
        └── loadImage() עבור index 1-5 → NSCache + loadedImageIDs
```

**מה זה נותן**: מהרגע שהמשתמש חוצה 80pt ועד שהswipe מסתיים (~200-400ms), כל הקלפים הבאים נטענים ל-NSCache. כשהקלף החדש מגיע למסך — `cachedImage != nil` ואין flash.

**Video Pool Protection**: `warmUp(protectedID:)` מבטיח שה-AVPlayer של הקלף הנוכחי לא יפונה בזמן שהמשתמש עדיין מחזיק אותו. ללא ההגנה הזו, `replaceCurrentItem(nil)` היה גורם לוידאו להיהפך לשחור גם אם המשתמש מחזיר את הקלף למרכז.

---

## 5. Video Pre-warming — VideoPlayerPool

| פרמטר | ערך |
|--------|-----|
| maxPoolSize | 3 players |
| deliveryMode | `.fastFormat` |
| warmUp נקרא עם | 5 assets הבאים (אחרי כל swipe ובזמן drag) |
| eviction | assets שאינם ב-5 הבאים מוסרים — למעט protectedID |

**Fast path**: `VideoPlayerPool.shared.player(for: asset)` → מחזיר `AVPlayer` מוכן  
**Slow path**: pool miss → `PHImageManager.requestPlayerItem` → async load  
**Re-sync**: `resumeTopCardVideo` notification → `PhotoCardView` מחדש play אם player נעצר בטעות בזמן drag שבוטל

---

## 6. Swipe Flow

```
DragGesture.onChanged (offset > 80pt — פעם אחת)
  → prepareUpcomingCards()   ← Early warm-up (ראה סעיף 4)

DragGesture.onEnded (swipe מושלם)
  → animate card off-screen (±500pt, 0.4s spring)
  → DispatchQueue.main.asyncAfter(0.3s):
      ├── lastSwipedImage = imageCache[topCard.id]   ← שומר לundo
      ├── viewModel.performAction()
      │     ├── processedAssetIDs.insert(id)
      │     ├── photoStack.removeFirst()
      │     ├── precacheNextImages()                  ← cache + pool + eviction
      │     └── loadNextPageIfNeeded()                ← אם stack ≤ 12
      └── dragOffset = .zero

DragGesture.onEnded (swipe בוטל — חזר למרכז)
  → resetCardPosition()
  → post(.resumeTopCardVideo)   ← re-sync video אם נעצר
```

**Undo (shake)**:
```
undoLastAction()
  → imageCache.setObject(lastSwipedImage)   ← מחזיר תמונה ל-cache
  → loadedImageIDs.insert(item.id)          ← מסמן כ-ready
  → photoStack.insert(item, at: 0)          ← קלף מופיע מיידית ללא flash
```

---

## 7. Thumbnail Gate — Cache Miss Path

כשקלף לא נמצא ב-NSCache (`cachedImage == nil`), `PhotoCardView.loadImage()` מפעיל **שתי קריאות מקבילות ונפרדות**:

```
Pass 1: loadThumbnail()
  deliveryMode = .fastFormat
  isNetworkAccessAllowed = false
  targetSize = 300×400 pt
  → callback < 50ms (תמיד מקומי, לעולם לא iCloud)
  → thumbnailImage = thumb   ← מוצג מיידית כ-base layer

Pass 2: loadImage()
  deliveryMode = .highQualityFormat
  isNetworkAccessAllowed = true
  targetSize = 600×800 pt
  → callback כשהתמונה המלאה מוכנה (ממתין בסבלנות ל-iCloud)
  → אם thumbnailImage != nil → withAnimation(.easeIn(0.18)) { image = fullRes }
  → אם thumbnailImage == nil → image = fullRes (ללא אנימציה — asset מקומי מהיר)
  → asyncAfter(0.35s): thumbnailImage = nil  ← פינוי זיכרון
```

**מה זה מבטיח**:
- **אף פעם לא קלף שחור** — thumbnail מקומי תמיד מוכן לפני render
- **ללא פשרות באיכות** — Pass 2 עם `.highQualityFormat` מחכה לגרסה המלאה
- **iCloud slow path** — thumbnail נשאר כל עוד ההורדה לא הסתיימה; אם נכשלת, thumbnail נשאר לצמיתות

**אינדיקטור טעינה לתמונה**: אם Pass 2 לא הסתיים אחרי **1000ms**, מופיע spinner עדין מעל ה-thumbnail. נעלם ברגע שה-full-res מגיע. מיושם עם task handle שמבוטל ב-`onDisappear` — אין race condition אם הכרטיסייה נסגרת לפני סיום ה-debounce.

**וידאו**: `loadVideoThumbnail()` נקרא ב-`onAppear` במקביל ל-`loadVideoPlayer()`.  
`isVideoPlayerReady` מופעל 50ms אחרי שה-AVPlayer מוקצה (מאפשר ל-AVLayer לרנדר frame ראשון).  
Thumbnail נעלם עם `animation(.easeIn(0.2))` ו-`thumbnailImage = nil` אחרי 300ms נוספים.

**אינדיקטורי טעינה לוידאו** (שלושה מצבים):
- **Initial load** — אחרי **450ms** ללא `isVideoPlayerReady`, מופיע spinner מעל ה-thumbnail
- **Buffering stall** — KVO על `AVPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate`; spinner מופיע מעל הפריים הקפוא. Change-detection guard מונע רינדור מיותר על כל שינוי status
- **Error** — KVO על `AVPlayerItem.status == .failed`; אייקון `exclamationmark.triangle.fill` מוצג

כל ה-task handles מבוטלים ב-`onDisappear`; ה-KVO observers מתאפסים ב-`onChange(of: player)`.

---

## 8. Tab Switch

```swift
// SwipeStackView.onAppear
if viewModel.photoStack.isEmpty && !viewModel.isLoading {
    viewModel.refreshPhotos()
}
```

| תרחיש | טיפול |
|--------|-------|
| מעבר טאב חזרה ל-Swipe | stack קיים → לא נוגע בו |
| בחירת קטגוריה מ-SmartFilters | `loadPhotos(filter:)` נקרא לפני המעבר → onAppear לא מבטל |
| גלריה השתנתה (limited access וכו') | `PHPhotoLibraryChangeObserver` מטפל |
| הפעלה ראשונה / stack ריק | `refreshPhotos()` רץ |

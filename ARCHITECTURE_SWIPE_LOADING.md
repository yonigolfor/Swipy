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
  │           cachedImage == nil → PhotoLibraryService.loadImage → UIImage → cache
  └── וידאו:  VideoPlayerPool.player(for:) → AVPlayer (pre-warmed)
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
| Initial page (burst) | 500 items |
| Next page | 30 items |
| Low watermark (trigger לדף הבא) | 12 items |

---

## 3. Image Cache — NSCache (app-level)

### למה נדרש
`PHCachingImageManager.requestImage` הוא **תמיד async**, גם כשהפיקסלים cached בזיכרון iOS. אין path סינכרוני. ה-NSCache ב-ViewModel מאפשר לגשת לתמונה **בזמן init של PhotoCardView**, לפני כל render.

### הגדרות
```swift
cache.countLimit = 6          // top-5 + 1 undo slot
cache.totalCostLimit = 6 MB   // ~6 תמונות בגודל קלף
```
`cacheTargetSize` = רוחב המסך פחות 40pt × 65% גובה מסך (גודל הקלף בפועל)

### מחזור חיים של entry

```
precacheNextImages() נקרא אחרי כל swipe
        │
        ├── startCaching() → רמז ל-PHCachingImageManager
        ├── VideoPlayerPool.warmUp() → מכין AVPlayers לוידאו
        └── loadImage() עבור top-3 images → מכניס ל-NSCache
                │
                ▼
        evictStaleCacheEntries()
          → מסיר keys שאינם ב-top-5 ואינם lastAction.item
```

### Eviction Policy
**נשמר ב-cache בכל נקודה:**
- top-5 פריטים ב-`photoStack`
- הפריט האחרון שנעשה עליו swipe (`lastSwipedImage`) — לצורך shake-to-undo

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
  image == nil → loadImage()   // cache miss: טוען async
  image != nil → דילוג         // cache hit: אפס round-trips
```

---

## 4. Video Pre-warming — VideoPlayerPool

| פרמטר | ערך |
|--------|-----|
| maxPoolSize | 3 players |
| deliveryMode | `.fastFormat` |
| warmUp נקרא עם | 5 assets הבאים (אחרי כל swipe) |
| eviction | assets שאינם ב-5 הבאים מוסרים |

**Fast path**: `VideoPlayerPool.shared.player(for: asset)` → מחזיר `AVPlayer` מוכן לניגון  
**Slow path**: pool miss → `PHImageManager.requestPlayerItem` → async load

---

## 5. Swipe Flow

```
DragGesture.onEnded
  → animate card off-screen (±500pt, 0.4s spring)
  → DispatchQueue.main.asyncAfter(0.3s):
      ├── lastSwipedImage = imageCache[topCard.id]   ← שומר לundo
      ├── viewModel.performAction()
      │     ├── processedAssetIDs.insert(id)
      │     ├── photoStack.removeFirst()
      │     ├── precacheNextImages()                  ← cache + pool + eviction
      │     └── loadNextPageIfNeeded()                ← אם stack ≤ 12
      └── dragOffset = .zero
```

**Undo (shake)**:
```
undoLastAction()
  → imageCache.setObject(lastSwipedImage)   ← מחזיר תמונה ל-cache
  → photoStack.insert(item, at: 0)          ← קלף מופיע מיידית ללא flash
```

---

## 6. Tab Switch — מצב נוכחי (אחרי תיקון)

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

---

## 7. מה לא cached (ידוע)

- **וידאו ב-init**: `isLoading=true` עד ש-`loadVideoPlayer()` רץ ב-`onAppear`. pool hit מהיר מאוד אבל לא אפס. לא נפתר עדיין.
- **תמונות בטעינה ראשונית**: `precacheNextImages()` רץ רק אחרי שהstack נטען. 10 הפריטים הראשונים מקבלים `startCaching` אבל לא NSCache proactive fill — רק הפריטים שנכנסים אחרי swipe.

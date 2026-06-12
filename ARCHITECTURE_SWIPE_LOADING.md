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

### loadedScoreIDs — Score Readiness
```swift
@Published var loadedScoreIDs: Set<String>
```
מסמן אילו קלפים כבר קיבלו ציון אסתטי ב-`AestheticScoringService.scoreCache`.  
`SwipeStackView` קורא `cachedScore(for: item.id)` רק כשה-ID ב-set הזה — מונע חישוב סינכרוני מתוך ה-render.  
מנוקה ב-`resetAndLoad` ומנוקה per-item ב-eviction.

---

## 3a. Aesthetic Scoring Pipeline

### UserAestheticPersona
`AestheticScoringService` סורק עד 200 Favorites של המשתמש ובונה פרסונה:

| שדה | תיאור |
|-----|--------|
| `topCategories` | ממוצע confidence של VNClassifyImageRequest לכל קטגוריה |
| `avgSharpnessVariance` | ממוצע Laplacian (CIEdges) variance — baseline חדות |
| `avgColorTemperature` | 0=קר, 1=חמים (CIAreaAverage) |
| `facePresenceRate` | אחוז תמונות עם people/portrait/selfie |
| `livePhotoRate` / `hdrRate` | העדפת סוג מדיה |

הפרסונה נשמרת ב-`UserDefaults` (key: `"userAestheticPersona_v1"`) ולא נבנית מחדש בהפעלות הבאות.

### ציון 1–10
```
sharpness match   30%  (CIEdges variance / persona baseline)
color temp match  20%  (1 − |delta| × 2.5)
media type match  10%  (Live/HDR alignment)
scene match       40%  (VNClassifyImageRequest overlap עם topCategories)
```
נוסחה: `max(1, min(10, Int(raw × 9) + 1))`

### זרימת הציון
```
resetAndLoad()
  → Task.detached: analyzeFavorites() [DispatchQueue.global — חוסם GCD, לא cooperative pool]
        → buildPersonaBlocking(): PHImageManager + VNClassify על 299×299 thumbs
        → שמירה ל-UserDefaults
        → MainActor: scoreCachedCardsIfNeeded()  ← catches cards already in NSCache

precacheNextImages() / prepareUpcomingCards()
  → loadImage completion → Task @MainActor → scheduleScore(item:image:)
        → DispatchQueue.global: score(for:image:)  ← VNClassify חוסם; חייב GCD
              → computeScore(): resize 299×299 → CIEdges + CIAreaAverage + VNClassify
              → DispatchQueue.main: loadedScoreIDs.insert(id)
                    → SwipeStackView re-render → PhotoCardView מקבל aestheticScore != nil
                          → badge מופיע עם .animation(.easeIn, value: aestheticScore != nil)
```

### כללים קריטיים
- **`VNClassifyImageRequest.perform` חוסם את ה-cooperative thread pool** — חייב לרוץ על `DispatchQueue.global`, לא `Task.detached`.
- **Resize ל-299×299 לפני כל חישוב** — ללא resize, Vision על 1080p לוקח 10+ שניות.
- **`withAnimation` אסור על `loadedScoreIDs.insert`** — הtransaction מדמם לstack ומגרום לקלפים להגיע מהכיוון הלא נכון. השתמש ב-`.animation(_:value:)` על ה-VStack של הbadge בלבד.
- **`CILaplacian` הוא macOS-only** — השתמש ב-`CIEdges` על iOS.

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
**Slow path**: pool miss → `isVideoPlayerReady = false` (reset gate) → `PHImageManager.requestPlayerItem` → async load  
**Re-sync**: `resumeTopCardVideo` notification → `PhotoCardView` מחדש play אם player נעצר בטעות בזמן drag שבוטל

### Pool Lifecycle — מחזור חיים של ה-pool

Pool entries **אינם** מתפנים ב-`onDisappear` של `PhotoCardView`. הpool מנהל את עצמו:

| גורם | מנגנון |
|------|---------|
| swipe רגיל | `warmUp()` stale eviction — אוטומטי |
| `emptyTrash` | `drainAll()` מפורש לפני מחיקה מה-PHPhotoLibrary |
| מעבר טאב | `pauseAll()` בלבד — players **נשארים בpool** |
| חזרה לטאב | pool hit מיידי; `rewarmVideoPool()` מכין קלפים עתידיים |

### PlayerUIView — isReadyForDisplay KVO

ה-KVO observer מוגדר על `playerLayer` (תמיד אותו instance, לא על `AVPlayer`). הוא נשאר פעיל לאחר החלפת player.

ב-`player.didSet`:
1. `hasCalledReadyCallback = false` — מאפשר ל-callback לירות שוב לplayer חדש
2. `playerLayer.player = player` — מעדכן את הlayer
3. אם `playerLayer.isReadyForDisplay == true` כבר (pool hit, אותו player) → callback יורה **מיידית** (KVO לא יורה כי הערך לא השתנה)
4. אם `isReadyForDisplay == false` (player חדש) → KVO יירה כשהlayer יגיע ל-`true` ✓

## 5a. Audio Session — AudioSessionManager

`AudioSessionManager.shared` מנהל את `AVAudioSession` כך שסרטון מושתק לא יפסיק מוזיקת רקע (Spotify, Podcasts וכד׳).

| מצב | Category | Options | תוצאה |
|-----|----------|---------|-------|
| וידאו מושתק | `.playback` | `.mixWithOthers` | מוזיקת רקע ממשיכה |
| וידאו עם קול | `.playback` | `[]` | מוזיקת רקע נעצרת |
| כל הוידאו נעצר | deactivate | `.notifyOthersOnDeactivation` | מוזיקת רקע חוזרת |

**`configure(muted:)`** נקרא ב-4 מקומות ב-`PhotoCardView`:
- `onChange(of: isTopCard)` כשהקלף הופך ל-top
- `loadVideoPlayer()` — direct load path (pool miss)
- `activatePlayer()` — pooled path
- mute toggle

**`deactivate()`** נקרא **רק** ב-`pauseVideoPool()` (מעבר טאב) — לא על כל swipe, כדי למנוע blip שמיעתי בין קלפים עוקבים.

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
} else {
    viewModel.rewarmVideoPool()  // fast no-op במעבר רגיל; חיוני אחרי emptyTrash
}

// SwipeStackView.onDisappear
NotificationCenter.default.post(name: .stopCurrentVideo, object: nil)
viewModel.pauseVideoPool()  // pause בלבד — pool נשאר חם
```

### עקרון: Pool חם בין טאבים

`PhotoCardView.onDisappear` **לא** קורא `release()` ו**לא** מאפס `isVideoPlayerReady`.  
שני הדברים נשמרים כדי שהוידאו יחזור מיידית ללא טעינה מחדש:

```
מעבר טאב:
  onDisappear → stopPlayer() (pause + seek 0) + pauseAll()
  pool: players נשארים, רק מושהים

חזרה לטאב:
  onAppear → loadVideoPlayer()
    → pool hit ✓ (instant, no I/O)
    → activatePlayer() → play()
    → isVideoPlayerReady כבר true → וידאו מוצג מיידית
```

### isVideoPlayerReady — מתי מתאפס

| מצב | isVideoPlayerReady |
|-----|--------------------|
| `onDisappear` (tab switch) | **לא מתאפס** — שומר על instant resume |
| pool hit (fast path) | לא נגע — נשאר true |
| pool miss / slow path | **מתאפס ל-false** לפני PHImageManager request |

### תרחישים

| תרחיש | טיפול |
|--------|-------|
| מעבר טאב חזרה ל-Swipe | pool hit → וידאו ממשיך מיידית |
| חזרה אחרי `emptyTrash` | pool ריק (drainAll) → `rewarmVideoPool()` → pool miss → slow path + reset gate |
| memory pressure פינה את הpool | pool miss → slow path, `isVideoPlayerReady = false` מציג loading state |
| בחירת קטגוריה מ-SmartFilters | `loadPhotos(filter:)` נקרא לפני המעבר → `onAppear` מרענן |
| גלריה השתנתה | `PHPhotoLibraryChangeObserver` מטפל |
| הפעלה ראשונה / stack ריק | `refreshPhotos()` רץ |

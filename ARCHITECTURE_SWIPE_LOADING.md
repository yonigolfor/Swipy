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
      ├── viewModel.image(for: item.id)           ← photoService.cachedImage() — synchronous
      ├── viewModel.finalImageIDs.contains(id)    ← is this the final version?
      │
      ▼
PhotoCardView(item:, isTopCard:, cachedImage:, isCachedImageFinal:)
  ├── תמונה:  isCachedImageFinal && cachedImage != nil → מוצג מיידית, ללא reload וללא spinner
  │           cachedImage != nil, !isCachedImageFinal → demote לthumbnailImage; requestCardImage רץ מאחורה
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

### גודל קלף — 9:16 Constrained

גודל הקלף מחושב פעם אחת ב-`GeometryReader` של `SwipeStackView`:

```swift
let cardW = min(geometry.size.width - 40, geometry.size.height * 9.0 / 16.0)
let cardH = cardW * 16.0 / 9.0
```

הלוגיקה: מוצא את **הקלף הגדול ביותר** בפרופורציה 9:16 שמתאים לשטח הזמין.
- רוחב מגביל (מסך גדול): `cardW = width - 40`, `cardH = cardW × 16/9`
- גובה מגביל (מסך קצר): `cardH = availableHeight`, `cardW = cardH × 9/16`

**תצוגת תמונה ב-`imageContentView`**: כל תמונה — portrait וlandscape — מקבלת אותה טיפול:
- שכבה 1 (רקע): `.scaledToFill()` + `blur(25)` + `scaleEffect(1.1)` + `clipped()` — ממלא את כל הקלף
- שכבה 2 (תמונה ראשית): `.scaledToFit()` — מציג את התמונה המלאה ללא חיתוך

תמונות 3:4 (iPhone portrait הרגיל) יקבלו פסי blur קטנים למעלה/למטה.
תמונות 9:16 (landscape video ratio) ימלאו את הקלף ב-pixel-perfect ללא margins.

### Pagination

| פרמטר | ערך |
|--------|-----|
| Initial page (ברירת מחדל) | 50 items |
| Initial page (blurry) | 200 items |
| Initial page (burst) | 500 items — נדרש ל-VNFeaturePrint chain analysis |
| Next page | 30 items |
| Low watermark (trigger לדף הבא) | 12 items |

---

## 3. Image Cache — NSCache (service-level)

### למה נדרש
`PHCachingImageManager.requestImage` הוא **תמיד async**, גם כשהפיקסלים cached בזיכרון iOS. אין path סינכרוני. ה-NSCache מאפשר לגשת לתמונה **בזמן init של PhotoCardView**, לפני כל render.

### מיקום
ה-cache נמצא ב-`PhotoLibraryService` (לא ב-ViewModel) — שומר על ViewModel stateless לגבי pixels ומונע memory pressure כפול.

### הגדרות
```swift
cache.countLimit = 10         // top-8 stack + 1 undo slot + 1 safety (30 offline — see setOfflineCacheLimit)
// totalCostLimit: לא מוגדר — iOS מנהל eviction אוטומטית לפי memory pressure
```
`cardTargetSize` = `(screenWidth − 40) × screenScale` × `(screenHeight × 0.65) × screenScale`
כפל ב-`UIScreen.main.scale` (2× / 3×) מבטיח שPHImageManager מחזיר pixels ברזולוציית retina.

### מחזור חיים של entry

```
precacheNextImages() נקרא אחרי כל swipe (וגם בטעינה ראשונית)
        │
        ├── startCaching() → רמז ל-PHCachingImageManager (top-20, ראה warmUpCache)
        ├── VideoPlayerPool.warmUp() → מכין AVPlayers לוידאו
        └── loadImage() עבור top-8 images → מכניס ל-NSCache + מסמן loadedImageIDs
                │
                ▼
        evictStaleCacheEntries()
          → מסיר keys שאינם ב-top-8 ואינם lastAction.item
          → Index-0 immunity: photoStack.first לעולם לא מוסר בזמן drag
```

### Eviction Policy
**נשמר ב-cache בכל נקודה:**
- top-8 פריטים ב-`photoStack`
- הפריט האחרון שנעשה עליו swipe (`lastSwipedImage`) — לצורך shake-to-undo
- הקלף שב-index 0 (top card) — protected מ-eviction גם אם נקראת precache בזמן drag

**מוסר מ-cache:**
- כל פריט שאינו ב-top-8 ואינו ה-undo item

### Synchronous Handshake
```
SwipeStackView:
  viewModel.image(for: item.id)              →  cachedImage: UIImage?
  viewModel.finalImageIDs.contains(item.id)  →  isCachedImageFinal: Bool
        │
        ▼
PhotoCardView.init(cachedImage:, isCachedImageFinal:)
  _image    = State(initialValue: cachedImage)
  _isLoading = State(initialValue: cachedImage == nil)
        │
        ▼
onAppear:
  isCachedImageFinal && image != nil → isLoading = false מיידית, ללא reload, ללא spinner
  !isCachedImageFinal && image != nil → demote לthumbnailImage; requestCardImage מאחורה
  image == nil → Thumbnail Gate: שתי קריאות מקבילות (ראה סעיף 7)
```

### loadedImageIDs — Observable Readiness
```swift
@Published var loadedImageIDs: Set<String>
```
כל פעם שתמונה נכנסת ל-NSCache ה-ID שלה מסומן ב-set הזה.  
מאפשר לviews לצפות מתי קלף "מוכן" בלי לבצע cache lookup סינכרוני.  
מנוקה ב-`resetAndLoad` (שינוי פילטר), ב-`activateOfflineMode()`, ומעודכן ב-eviction.

### finalImageIDs — Delivery Finality
```swift
@Published var finalImageIDs: Set<String>
```
מסמן אילו קלפים קיבלו את הגרסה הסופית של התמונה — לא יגיעו יותר callbacks.  
- **Online**: מוכנס כש-`isDegraded == false` (full-res אושר).  
- **Offline**: מוכנס על כל callback לא-nil (`.fastFormat` מספק תוצאה אחת סופית).  
`PhotoCardView` משתמש ב-`isCachedImageFinal` כדי לדלג על ה-reload dance וה-spinner לגמרי.  
מנוקה ב-`resetAndLoad`, ב-`activateOfflineMode()`, ומנוקה per-item ב-eviction.

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
| `featurePrintCentroid` | ממוצע element-wise של וקטורי `VNGenerateImageFeaturePrintRequest` (512 floats) |
| `avgSharpnessVariance` | ממוצע grayscale CIEdges variance — baseline חדות |
| `avgColorTemperature` | 0=קר, 1=חמים (CIAreaAverage) |
| `livePhotoRate` / `hdrRate` | העדפת סוג מדיה |

הפרסונה נשמרת ב-`UserDefaults` (key: `"userAestheticPersona_v2"`) ולא נבנית מחדש בהפעלות הבאות.

### ציון 1–10
```
feature print sim  50%  (L2 distance מהcentroid, normalized: max(0, 1 − dist/8))
sharpness match    25%  (CIEdges variance / persona baseline)
color temp match   15%  (1 − |delta| × 2.5)
media type match   10%  (Live/HDR alignment)
```
נוסחה: `max(1, min(10, Int(raw × 9) + 1))`

`featurePrintCentroid` הוא הממוצע הפרספטואלי של ה-Favorites — תמונות שנראות קרוב לדפוסים שהמשתמש אהב מקבלות ציון גבוה, גם כשהן שייכות לאותה קטגוריה סמנטית.

### זרימת הציון
```
resetAndLoad()
  → Task.detached: analyzeFavorites() [DispatchQueue.global — חוסם GCD, לא cooperative pool]
        → buildPersonaBlocking(): PHImageManager + VNFeaturePrint + CIEdges על 299×299 thumbs
        → שמירה ל-UserDefaults
        → MainActor: scoreCachedCardsIfNeeded()  ← catches cards already in NSCache

precacheNextImages() / prepareUpcomingCards()
  → loadImage completion → Task @MainActor → scheduleScore(item:image:)
        → DispatchQueue.global: score(for:image:)  ← VNFeaturePrint חוסם; חייב GCD
              → computeScore(): resize 299×299 → CIEdges + CIAreaAverage + VNFeaturePrint
              → DispatchQueue.main: loadedScoreIDs.insert(id)
                    → SwipeStackView re-render → PhotoCardView מקבל aestheticScore != nil
                          → badge מושבת כרגע (מסומן בהערה ב-PhotoCardView)
                          → להחזרה: בטל הערה ל-scoreBadgeView block ב-imageContentView
```

### Blur Gate — שתי שכבות הגנה

ציון תמונה מטושטשת יורד ללא תלות בדמיון לfavorites.

**`BlurDetector.sharpnessVariance`:** ממיר ל-grayscale (`CIPhotoEffectMono`) לפני `CIEdges` —
מונע inflation של variance מקצות צבע בתמונות מטושטשות.

סף 600 מכויל מנתונים אמיתיים: תמונות מטושטשות הניבו var=290–580, חדות var=622+.

```
Tier 1 (hard): variance < 600  →  sharpnessFactor = variance / 600
  var=290 (מאוד מטושטש): gate≈0.51
  var=440 (מטושטש):      gate≈0.75
  var=580 (גבולי):       gate≈0.97

Tier 2 (soft): variance ≥ 600  →  sharpnessFactor = variance / max(avgSharpnessVariance, 600)
  Self-calibrating: אם המשתמש אוהב תמונות מטושטשות → avgSharpnessVariance נמוך → עונש קטן

Fallback: variance = ∞ (CIEdges נכשל)  →  raw ×= 0.6

נוסחת עונש: raw *= (0.05 + 0.95 × sharpnessFactor)
  sharpnessFactor=0: raw ×= 0.05 → ציון max 1
  sharpnessFactor=1: raw ×= 1.0  → אין עונש
```

לכיול: grep ל-`[BlurCalib]` ב-Xcode Console — כל קלף מדפיס var, bucket (VERY-BLURRY/BLURRY/borderline/sharp), gate, ו-finalScore.

### כללים קריטיים
- **`VNGenerateImageFeaturePrintRequest.perform` חוסם את ה-cooperative thread pool** — חייב לרוץ על `DispatchQueue.global`, לא `Task.detached`.
- **Resize ל-299×299 לפני כל חישוב** — ללא resize, Vision על 1080p לוקח 10+ שניות.
- **`withAnimation` אסור על `loadedScoreIDs.insert`** — הtransaction מדמם לstack ומגרום לקלפים להגיע מהכיוון הלא נכון. השתמש ב-`.animation(_:value:)` על ה-VStack של הbadge בלבד.
- **`CILaplacian` הוא macOS-only** — השתמש ב-`CIEdges` על iOS.
- **`obs.data` הוא property מסוג `Data`**, לא method — גישה ישירה לbytes של ה-feature print ללא `copyingDataInto`.

---

## 4. Early Precache — prepareUpcomingCards()

מנגנון חדש שמפחית מסכים שחורים בהחלקה מהירה.

```
DragGesture.onChanged (offset > 30pt, פעם אחת per gesture)
  → viewModel.prepareUpcomingCards()
        │
        ├── photoStack.dropFirst().prefix(8)  ← דולג על index 0 (עוזב)
        ├── startCaching() עבור index 1-8
        ├── VideoPlayerPool.warmUp(protectedID: topCard.localIdentifier)
        │     └── top card מוגן מ-eviction כל עוד הgesture לא הסתיים
        └── loadImage() עבור index 1-8 → NSCache + loadedImageIDs
```

**מה זה נותן**: מהרגע שהמשתמש חוצה 30pt ועד שהswipe מסתיים (~200-400ms), כל הקלפים הבאים נטענים ל-NSCache. כשהקלף החדש מגיע למסך — `cachedImage != nil` ו-`isCachedImageFinal == true` → ללא flash, ללא spinner.

**Video Pool Protection**: `warmUp(protectedID:)` מבטיח שה-AVPlayer של הקלף הנוכחי לא יפונה בזמן שהמשתמש עדיין מחזיק אותו. ללא ההגנה הזו, `replaceCurrentItem(nil)` היה גורם לוידאו להיהפך לשחור גם אם המשתמש מחזיר את הקלף למרכז.

---

## 5. Video Pre-warming — VideoPlayerPool

| פרמטר | ערך |
|--------|-----|
| maxPoolSize | 5 players — top card + 2 back cards + 2-video true look-ahead |
| maxConcurrentLoads | 2 — `PHImageManager.requestPlayerItem` calls בו-זמנית, השאר נכנסים ל-`pendingLoadQueue` |
| deliveryMode | `.fastFormat` |
| warmUp נקרא עם | חלון רחב (~15 assets, לא רק 5) — כדי שתמיד יהיו מועמדים נוספים למלא slots שהתפנו על פני כמה קריאות; קריאה בודדת עדיין פועלת רק על 5 הוידאו הראשונים בחלון |
| eviction | assets שאינם בחלון הנוכחי מוסרים — למעט protectedID |
| preferredForwardBufferDuration | 2.0s ל-players ב-pool שטרם נצפים; מתאפס ל-automatic (0) ב-`PhotoCardView.activatePlayer()` לפני `play()` |

**Fast path**: `VideoPlayerPool.shared.player(for: asset)` → מחזיר `AVPlayer` מוכן  
**Slow path**: pool miss → `isVideoPlayerReady = false` (reset gate) → `PHImageManager.requestPlayerItem` → async load  
**Re-sync**: `resumeTopCardVideo` notification → `PhotoCardView` מחדש play אם player נעצר בטעות בזמן drag שבוטל

### Bounded-Concurrency Load Queue

`enqueue()` → אם `activeLoadIDs.count < maxConcurrentLoads` מתחיל טעינה מיידית (`startLoad`), אחרת נכנס ל-`pendingLoadQueue`. כל סיום טעינה (`finishLoad`) קורא ל-`startNextQueuedLoad()` כדי לרוקן את התור בהדרגה — לעולם לא יותר מ-2 בקשות `PHImageManager` בו-זמנית.

`evict()` מבטל גם את ה-`PHImageRequestID` בפועל (`PHImageManager.cancelImageRequest`), לא רק את ה-`Task` העוטף — אבל ביטול Task אינו מבטיח שהקריאה הבסיסית ל-PHImageManager שכבר ירתה בפועל תיפסק. `loadGeneration` (מונה per-asset) מגן על `finishLoad` מפני תוצאה "ישנה" שמגיעה אחרי שאותו asset פונה ונכנס מחדש (למשל swipe ואז shake-undo מהיר) — רק completion שהmarker שלו תואם לגנרציה הנוכחית מתקבל.

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
DragGesture.onChanged (offset > 30pt — פעם אחת)
  → prepareUpcomingCards()   ← Early warm-up (ראה סעיף 4)

DragGesture.onEnded (swipe מושלם)
  → swipedItem = viewModel.topCard   ← נתפס מיד, לפני האנימציה/העיכוב
  → viewModel.beginSwipe(swipedItem, action)   ← סינכרוני, ראה "Pending Swipe" למטה
  → animate card off-screen (±500pt, 0.4s spring)
  → DispatchQueue.main.asyncAfter(0.3s):
      ├── viewModel.finalizeSwipe(swipedItem, action)  ← false אם בוטל תוך כדי טיסה, ראה למטה
      │     └── (אם true) performAction → keepPhoto/deletePhoto/snoozePhoto:
      │           ├── lastSwipedImage = imageCache[swipedItem.id]   ← שומר לundo
      │           ├── photoStack.remove(at: index of swipedItem.id) ← לא removeFirst()!
      │           │     (מוצא לפי id, לא לפי מיקום — ראה הערה למטה)
      │           ├── processedAssetIDs.insert(id)
      │           ├── precacheNextImages()                  ← cache + pool + eviction
      │           └── loadNextPageIfNeeded()                ← אם stack ≤ 15
      └── (אם finalizeSwipe החזיר true) dragOffset = .zero
```

**קריטי — race עם undo:** `swipedItem` נתפס ב-`onEnded` (סינכרוני), *לפני* ה-0.3s delay,
ומועבר במפורש ל-`beginSwipe`/`finalizeSwipe`. `keepPhoto`/`deletePhoto`/`snoozePhoto` מסירים
אותו לפי **התאמת `id`**, לא `photoStack.first`/`removeFirst()`. הסיבה: אם המשתמש מנער לביטול
(undo) בדיוק בתוך אותם 0.3 שניות — `undoLastAction()` עלול להכניס פריט קודם בחזרה
לראש הערימה (`insert(at: 0)`) *לפני* שהעיכוב הזה מסתיים. בלי הקישור המפורש ל-item,
הפעולה הממתינה הייתה נופלת על מי שנמצא כרגע בראש (הפריט שהוחזר ע"י undo) במקום על
הקלף שבאמת swipe-קו.

**Pending Swipe — סגירת חלון המירוץ עם ה-Undo button/shake (300ms):**
`lastAction`/`canUndo` היו מתעדכנים רק בתוך `keepPhoto`/`deletePhoto`/`snoozePhoto` —
כלומר רק אחרי ה-0.3s delay. במשך אותם 300ms, אם המשתמש לחץ Undo או ניער — הפעולה
הייתה מכוונת עדיין לswipe ה*קודם*, לא לזה שכרגע רואים עף מהמסך; והswipe החדש היה
ממשיך ומתבצע במלואו (הפריט עדיין נמחק/נשמר) בלי שהמשתמש שם לב.
התיקון: `beginSwipe(item, action)` נקרא **סינכרונית** ב-`onEnded`, לפני ה-delay —
מסמן `pendingSwipe`/`pendingSwipeIDs` ומעדכן `lastAction` (וכך `canUndo`) מיידית.
`undoLastAction()` בודק `pendingSwipe` ראשון: אם הswipe עדיין pending, שום דבר לא
מוטט עדיין (הפריט מעולם לא הוסר מ-`photoStack`) — הביטול הוא רק ניקוי הflag,
בלי `insert(at:)` ובלי שחזור cache. ה-`finalizeSwipe` שקורה 0.3s לאחר מכן בודק אם
ה-id עדיין ב-`pendingSwipeIDs` — אם לא (בוטל), הוא no-op ומחזיר `false`, וה-View
מדלג על איפוס `dragOffset`/הצגת particle explosion/ספירת shake-hint, כדי לא לפגוע
באנימציית הנחיתה של ה-undo שכבר רצה.
```

DragGesture.onEnded (swipe בוטל — חזר למרכז)
  → resetCardPosition()
  → post(.resumeTopCardVideo)   ← re-sync video אם נעצר
```

**Undo (shake)**:
```
SwipeStackView.performUndo()
  → guard !isDragging, !isPinching else return         ← שייק תוך כדי גרירה/pinch חי מתעלם,
                                                          לא חוטף dragOffset/dragRotation/pinchScale/pinchOffset
  → action = viewModel.undoLastAction()   ← מחזיר את הפעולה שבוטלה (keep/delete/snooze)
  │     ├── photoService.cacheImage(lastSwipedImage)  ← מחזיר תמונה ל-cache
  │     ├── loadedImageIDs.insert(item.id)            ← מסמן כ-ready
  │     ├── finalImageIDs.insert(item.id)             ← קלף ה-undo הוא תמיד סופי (full-res)
  │     └── photoStack.insert(item, at: 0)            ← קלף מופיע מיידית ללא flash ולא spinner
  → isUndoAnimating = true, undoGeneration += 1        ← חוסם dragGesture וגם מנתק את pinchGesture
                                                          (`index == 0 && !isUndoAnimating ? pinchGesture : nil`)
                                                          עד הנחיתה; generation נלכד ב-let מקומי
  → dragOffset/dragRotation = off-screen, בכיוון ובזווית של ה-swipe שבוטל
        (keep→ימין +25°, delete→שמאל -25°, snooze→למעלה 0°)
        קלף חדש בערימה לא מונפש בהופעתו הראשונה — אז זה מצטייר מיידית, בלי הבהוב
  → DispatchQueue.main.asyncAfter(0.03s):              ← מאפשר לפריים הזה להיכתב
      withAnimation(spring 0.45/0.75, completionCriteria: .logicallyComplete):
        dragOffset/dragRotation → 0                    ← קפיצה underdamped, "נחיתה" בחפיסה
      completion: if undoGeneration == generation { isUndoAnimating = false }
  → DispatchQueue.main.asyncAfter(1.0s):
        if undoGeneration == generation { isUndoAnimating = false }
        ← רשת ביטחון idempotent + generation-gated — משחררת את הגרירה גם אם
          ה-completion לעיל לא נורה (למשל האפליקציה עברה לרקע), אבל לעולם לא
          מאפסת isUndoAnimating ששייך לסבב undo מאוחר יותר (שייק כפול מהיר)
```

---

## 7. Thumbnail Gate — Image Loading Path

`PhotoCardView.onAppear` מחליט אם לטעון מחדש לפי `isCachedImageFinal`:

```
onAppear (תמונה):

  נתיב מהיר (isCachedImageFinal && image != nil):
    isLoading = false   ← תמונה סופית כבר זמינה, מוצגת מיידית
    אין reload, אין spinner

  נתיב רגיל (!isCachedImageFinal):
    אם image != nil:
      thumbnailImage = image   ← demote לplaceholder (אולי degraded)
      image = nil
    Task: diskCache.retrieveAsync() || loadImage()
    imageSpinnerTask: spinner אחרי 1000ms אם image עדיין nil

  נתיב offline+unavailable (isCachedImageFinal && image == nil):
    Task: loadImage()   ← ניסיון נוסף
    אין spinner         ← asset לא זמין, אין טעם לחכות

loadImage() — שתי קריאות מקבילות:

  Pass 1: loadThumbnail()
    deliveryMode = .fastFormat, isNetworkAccessAllowed = false
    targetSize = 300×400 pt
    → דולג אם thumbnailImage כבר קיים (ה-demoted placeholder עדיף)
    → אחרת: thumbnailImage = thumb (< 50ms, תמיד מקומי)

  Pass 2: loadImage()
    deliveryMode = .highQualityFormat, isNetworkAccessAllowed = !isOfflineMode
    targetSize = cardTargetSize (retina-pixel dimensions)
    → ממתין לגרסה המלאה (iCloud כולל, בonline mode)
    → אם thumbnailImage != nil → withAnimation(.easeIn(0.18)) { image = fullRes }
    → אם thumbnailImage == nil → image = fullRes (ללא אנימציה — asset מהיר)
    → asyncAfter(0.35s): thumbnailImage = nil
```

**מה זה מבטיח**:
- **אפס spinner בonline mode** — `requestCardImage` מספק `.opportunistic`; כשה-full-res מגיע (`isDegraded=false`) הViewModel מסמן `finalImageIDs` והקלף הבא מוצג מיידית
- **אפס spinner בoffline mode** — `requestCardImage` משתמש ב-`.fastFormat`; callback תמיד `isDegraded=false`; ה-View יודע שאין upgrade שיגיע
- **אף פעם לא קלף שחור** — placeholder (מcache או thumbnail) מוצג מיידית
- **fastFormat fallback protection** — תמונה degraded שהגיעה לcache מוחלפת כשה-full-res מגיע; toggle של `loadedImageIDs` גורם ל-SwiftUI לרנדר מחדש

**אינדיקטור טעינה לתמונה**: אם Pass 2 לא הסתיים אחרי **1000ms** (ורק כש-`!isCachedImageFinal`), מופיע spinner עדין מעל ה-placeholder. task handle מבוטל ב-`onDisappear` — אין race condition.

**וידאו**: `loadVideoThumbnail()` נקרא ב-`onAppear` במקביל ל-`loadVideoPlayer()`.  
`isVideoPlayerReady` מופעל 50ms אחרי שה-AVPlayer מוקצה (מאפשר ל-AVLayer לרנדר frame ראשון).  
Thumbnail נעלם עם `animation(.easeIn(0.2))` ו-`thumbnailImage = nil` אחרי 300ms נוספים.

**אינדיקטורי טעינה לוידאו** (שלושה מצבים):
- **Initial load** — אחרי **450ms** ללא `isVideoPlayerReady`, מופיע spinner מעל ה-thumbnail
- **Buffering stall** — KVO על `AVPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate`; spinner מופיע מעל הפריים הקפוא. Change-detection guard מונע רינדור מיותר על כל שינוי status
- **Error** — KVO על `AVPlayerItem.status == .failed`; אייקון `exclamationmark.triangle.fill` מוצג

כל ה-task handles מבוטלים ב-`onDisappear`; ה-KVO observers מתאפסים ב-`onChange(of: player)`; ה-`AVPlayerItemDidPlayToEndTime` block-observer נשמר ב-`videoEndObserver` ומוסר ב-`onDisappear`.

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

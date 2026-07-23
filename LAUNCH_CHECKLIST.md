# Swipy — Launch Checklist (App Store + Marketing)

**איך להשתמש בקובץ הזה:** זהו מסמך עבודה חי. סמנו `[x]` על כל סעיף שהושלם. בכל סשן חדש עם Claude — פשוט הפנו לקובץ הזה ("תמשיך איתי מה-LAUNCH_CHECKLIST") והעבודה תמשיך מהנקודה המדויקת שבה עצרתם.

**עדכון אחרון:** 2026-07-23
**שלב נוכחי:** שלב 0 — הכנה לפני הגשה (TestFlight ✅ הושלם, פידבק נקי)

---

## שלב 0 — הכנה לפני הגשה ל-App Store

- [ ] להחליף את כתובת המייל האישית (`yonitestgolfor@gmail.com`) בדפי `docs/privacy-policy.html` ו-`docs/terms-of-use.html` לכתובת ייעודית לאפליקציה
- [ ] להדביק את ה-Privacy Policy URL (`https://swipy-app.netlify.app/privacy-policy.html`) בשדה App Privacy ב-App Store Connect
- [ ] (רשות, מומלץ) מעבר קצר של עו"ד/רו"ח על סעיף Limitation of Liability ב-Terms
- [x] להכין Screenshots — סעיפים 1–5 (עדיפות עליונה) צולמו והועלו בהצלחה ל-App Store Connect; פירוט מלא בתת-סעיף "Screenshots — אילו פיצ'רים להדגיש" למטה
- [ ] להכין App Preview video (אופציונלי אך מומלץ — מעלה המרה בדף האפליקציה)
- [ ] למלא Name / Subtitle / Keywords / Promotional Text / Description ב-App Store Connect — הכל כבר מנוסח ב-`MARKETING.md` §9
- [ ] Age Rating questionnaire
- [ ] Support URL
- [ ] לוודא שכל ה-Subscription disclosures (משך, מחיר, חידוש אוטומטי, לינק למסמכים) מופיעים ב-Description לפי Guideline 3.1.2

### Screenshots — פיצ'רים + כתוביות overlay (סדר מומלץ)

הראשונים ב-3 מכריעים — הם מה שנראה בדף האפליקציה לפני שמישהו גולל. סדר בנוי כסיפור: hook → תועלת → אמון → דיפרנציאציה → סגירה.

- [x] **1. מסך Swipe כללי** (בוצע) — ה-hero shot
  - EN: **"Swipe your gallery clean"** / sub: *"Keep, delete, or snooze — in seconds"*
  - HE: **"מנקים את הגלריה בסוויפ אחד"** / sub: *"שומרים, מוחקים או דוחים — תוך שניות"*

- [x] **2. Smart Filters** (בוצע) — מסך `SmartFiltersView` עם 6 הקטגוריות והספירות. ה-USP הכי חזק — "האפליקציה מוצאת את הזבל בשבילך"
  - EN: **"Swipy finds the junk for you"** / sub: *"Screenshots, blurry shots, duplicates, big videos — all auto-detected"*
  - HE: **"Swipy מוצא את הזבל בשבילכם"** / sub: *"צילומי מסך, תמונות מטושטשות, כפילויות, סרטונים כבדים — הכל אוטומטי"*

- [ ] **3. SessionSavingsBar** — ה-counter של MB/GB עולה בזמן אמת, ה-lava-star
  - EN: **"Watch your storage come back"** / sub: *"Every swipe frees up real space"*
  - HE: **"תראו את המקום מתפנה בזמן אמת"** / sub: *"כל סוויפ משחרר עוד מקום"*

- [x] **4. Review Bin** (בוצע) — רשת פריטים לפני מחיקה סופית — טיפול בהתנגדות המרכזית (פחד למחוק בטעות)
  - EN: **"Nothing is deleted until you say so"** / sub: *"Every photo waits safely in your Review Bin"*
  - HE: **"שום דבר לא נמחק עד שאתם מאשרים"** / sub: *"כל תמונה מחכה בבטחה בסל המיחזור"*

- [x] **5. Privacy / On-device** (בוצע) — גרפיקה שיווקית ייעודית (לא צילום מסך אמיתי): רקע במיתוג האפליקציה + אייקון מנעול/מכשיר. מרגיע לקוחות שחוששים מהעלאת תמונות רגישות לענן
  - EN: **"100% on your device. Always."** / sub: *"No cloud upload. No account. No server — ever."*
  - HE: **"100% על המכשיר שלכם. תמיד."** / sub: *"בלי העלאה לענן. בלי חשבון. בלי שרת — אף פעם."*

- [x] **6. Shuffle** (בוצע) — פיצ'ר דיפרנציאציה
  - EN: **"Mix it up with Shuffle"** / sub: *"Jump around your gallery, your way"*
  - HE: **"מערבבים את הסדר עם Shuffle"** / sub: *"עוברים בין תקופות בגלריה כרצונכם"*

- [ ] **7. Snooze ("Later")** — סוויפ למעלה דוחה החלטה
  - EN: **"Can't decide? Swipe up for later"** / sub: *"Snoozed photos come back when you're ready"*
  - HE: **"לא בטוחים? סוויפו למעלה לדחות"** / sub: *"התמונות הדחויות חוזרות כשתהיו מוכנים"*

- [ ] **8. Aesthetic Score badge** — קלף עם ציון (1–10), מדגיש את ה-AI/Vision
  - EN: **"Swipy learns your best shots"** / sub: *"Smart scoring highlights your favorites automatically"*
  - HE: **"Swipy לומד להכיר את התמונות הכי טובות שלכם"** / sub: *"ניקוד חכם מסמן את המומלצות"*

- [ ] **9. (אופציונלי) Lifetime Savings / Milestone** — שיא רגשי, סוגר עם תחושת ניצחון
  - EN: **"3.2 GB freed. And counting."** / sub: *"See your total space saved, forever"*
  - HE: **"3.2 ג'יגה התפנו. וממשיך."** / sub: *"המקום שחסכתם, לתמיד"*

**הערות טכניות:**
- גדלים נדרשים: **6.9"** (iPhone 16 Pro Max) חובה, **13"** iPad חובה (כי `TARGETED_DEVICE_FAMILY = "1,2"` — אפליקציה universal) — למרות ש-iPad נעול ל-Portrait בלבד (`UIRequiresFullScreen`), עדיין צריך צילומי מסך iPad תקינים
- אם אין זמן לצלם את כל ה-9 — עדיפות מוחלטת לסעיפים 1–5 (הם מה שמופיע בלי גלילה ומניע את ההורדה, כולל שכבת האמון של Review Bin + Privacy יחד) — **הושלם והועלה ל-App Store Connect**; סעיפים 3, 7, 8, 9 נותרו אופציונליים
- כל הכתוביות מנוסחות דו-לשוני (EN/HE) — לבחור לפי locale ההגשה; כדאי localize את ה-screenshots בפועל אם ההגשה כוללת גם עברית וגם אנגלית ב-App Store Connect

## שלב 0.5 — TestFlight (הושלם)

- [x] Build ראשון ל-TestFlight
- [x] סבב טסטרים ראשוני — 6–7 משתמשים פעילים
- [x] פידבק נקי נכון ל-2026-07-21 — אין קראשים/באגים פתוחים
- [x] החלטה: לא להרחיב את מעגל הטסטרים — ממשיכים ישירות לשלב 0/1

## שלב 0.6 — אנליטיקס (להתקין *לפני* ההשקה — אי אפשר למדוד רטרואקטיבית)

**החלטה:** נשארים **Native-Only** — בלי RevenueCat/Mixpanel/שום 3rd-party SDK, כדי לשמור על הבטחת "100% on-device" במלואה.
- [x] D7 Retention / Conversion / Revenue — App Store Connect Analytics (StoreKit 2 כבר נותן את זה native, בלי קוד נוסף)
- [x] שימוש מוצרי פנימי (swipe counts, Smart Filter usage וכו') — `AnalyticsService.swift` חדש: ספירה מקומית ב-`PersistenceService` + `os_signpost` ל-rollup דרך MetricKit (גלוי ב-Xcode Organizer → Metrics אחרי שהאפליקציה חיה ומשתמשים מאשרים שיתוף אנליטיקס)
- [x] מסך Debug לצפייה בספירות המקומיות בזמן פיתוח/TestFlight — `AnalyticsDebugView.swift` (`#if DEBUG`, long-press על "Device" ב-Smart Filters)
- [ ] Referral Rate — אין כלי native למדידה מדויקת בלי שרת/SDK; להישאר עם מעקב ידני/הערכה גסה בשלב זה

## שלב 1 — הגשה ל-Review

- [ ] להגיש Build ל-App Review
- [ ] **חשוב:** לבחור שחרור **ידני** (לא אוטומטי) ב-App Store Connect — כדי לתאם את ה-go-live בדיוק עם Product Hunt / התוכן של יום 1
- [ ] לשקול שימוש ב-**Pre-Order** (עד 180 יום מראש, מתקין אוטומטית ביום השחרור) כדי לצבור הורדות "בקנה" לפני היום הרשמי
- [ ] ביום ההגשה עצמו — למלא את טופס "Promote your app" ב-developer.apple.com (טיוטת הפיץ' מוכנה ב-`MARKETING.md` §9, מועמדות "New Apps We Love")

## שלב 2 — עבודה מקבילה בזמן ההמתנה ל-Review

- [ ] לצלם/להפיק מראש את תוכן ימים 1, 3, 5 מהלו"ז ב-`MARKETING.md` §3 (POV Swipe ASMR, Before/After, Day in the Life)
- [ ] לפתוח/לחמם חשבונות TikTok + Instagram — לפרסם תוכן ניש ראשוני בלי CTA של "תורידו עכשיו" (אלגוריתם מעדיף חשבון עם היסטוריה על פני חשבון קר)
- [ ] להתחיל ליצור קשר ראשוני עם 20 ה-micro-KOLs (לא לחכות ל-Week 2 בפועל — לתגובה לוקח זמן). Brief מוכן ב-`MARKETING.md` §4
- [ ] להכין את רשימת ה-Subreddits / קבוצות Facebook ל-seeding (`MARKETING.md` §6, Week 1)
- [ ] להכין את דף ה-Product Hunt (טקסט, תמונות, GIF/וידאו) מראש

## שלב 3 — יום ה-Launch

- [ ] לשחרר את הגרסה ידנית (מתואם עם השאר)
- [ ] Product Hunt launch — יום שני, 00:01 PST
- [ ] Reddit + Facebook Groups seeding
- [ ] פרסום תוכן יום 1 (POV Swipe ASMR)

## שלב 4 — לו"ז 30 הימים

מפורט במלואו ב-`MARKETING.md` §3 (טבלת יום/פורמט/תוכן/פלטפורמה). קישורי המשך:

- [ ] שבוע 1: Seeding ללא תשלום (`MARKETING.md` §6)
- [ ] שבוע 2: Micro-KOL outreach בפועל (DM + הצעת Premium lifetime)
- [ ] שבוע 3: Paid Boost ($50–100 על הסרטון האורגני החזק ביותר)
- [ ] שבוע 4: PR Micro-burst (Geektime / The Marker Weekend + עריכת App Store)
- [ ] יום 30: Milestone post + Giveaway

## שלב 5 — מדידה

לעקוב אחרי הטבלה ב-`MARKETING.md` §7 (הורדות, D7 Retention, Referral Rate, TikTok views, GB saved/user, Review Score) — נדרש שהאנליטיקס משלב 0.6 יהיה חי לפני ה-launch.

---

## קבצים קשורים
- `MARKETING.md` — התוכן השיווקי המלא (hooks, קהלי יעד, KOLs, ASO metadata)
- `HOUSE_ADS.md` — פרסומות פנימיות בתוך חפיסת הקלפים (מוניטיזציה, לא שיווק חיצוני) — לא קשור ישירות ל-launch אבל רלוונטי אם רוצים למנף Premium promotion לפני ה-launch

# App Store listing — draft

Everything here is a draft to edit, not a decision. The name in particular is
mine, not yours.

## Name and subtitle

`Daybook` is a placeholder. Check availability before committing: the App Store
enforces uniqueness on the name, and "Daybook" is a real English word that
several apps already use.

| Field | Limit | English | Hebrew |
|---|---|---|---|
| Name | 30 | `Daybook` | `Daybook` |
| Subtitle | 30 | `Your day, without opening it` | `היום שלך, בלי לפתוח` |

Alternative subtitles, if the first reads as too clever:

- `The day on your lock screen` / `היום במסך הנעילה`
- `Tasks that come to you` / `משימות שמגיעות אליך`

## Promotional text (170, editable without review)

**EN** — Move every app to page two. Daybook takes the first home page and
keeps today in front of you, so the day happens whether or not you remember to
check.

**HE** — העבירו את כל האפליקציות לעמוד השני. Daybook לוקח את עמוד הבית הראשון
ושומר את היום מול העיניים, כך שהיום קורה בין אם נזכרתם לבדוק ובין אם לא.

## Description

### English

Most task apps wait for you to open them. Daybook does the opposite: it puts
the day on the screens you already look at, and you only go in to write things
down.

**A widget that owns the first page.** Move your apps to page two. What you see
after unlocking is today — everything on it, with a circle beside each thing you
can tap to tick off. The tap works without opening the app.

**A card on the lock screen.** The thing you should be doing now, in large
letters, with the next few beneath it and a Done button that works without
unlocking.

**Alerts as loud as the thing deserves.** A note to yourself gets a quiet
notification. A deadline gets more insistent as it approaches. A wake-up gets a
real alarm that rings through silent mode. You choose the volume per item, and
quiet hours silence everything you have not marked as important enough to
ignore them.

**Twelve kinds of thing, and none of them are hardcoded.** Events, tasks,
deadlines, recurring chores, routines that show one step at a time, habits with
a weekly quota that nudge only when you fall behind, timers you start yourself,
place reminders, things you are waiting on someone else for, and things you
might do someday. Pick the closest one and change whatever you like — the kinds
are just starting points, and every setting is editable on every item.

**Everything stays on your phone.** No account. No analytics. Nothing leaves the
device.

In Hebrew and English, right to left included.

### Hebrew

רוב אפליקציות המשימות מחכות שתפתחו אותן. Daybook עושה את ההפך: הוא שם את היום
על המסכים שאתם ממילא מסתכלים בהם, ונכנסים אליו רק כדי לרשום דברים.

**ווידג׳ט שמחזיק את העמוד הראשון.** העבירו את האפליקציות לעמוד השני. מה שרואים
אחרי פתיחת הנעילה זה היום — הכול עליו, עם עיגול ליד כל דבר שאפשר להקיש עליו
כדי לסמן שבוצע. ההקשה עובדת בלי לפתוח את האפליקציה.

**כרטיס במסך הנעילה.** הדבר שצריך לעשות עכשיו, באותיות גדולות, עם הבאים בתור
מתחתיו וכפתור "בוצע" שעובד בלי לפתוח את הנעילה.

**התראות חזקות כמו שמגיע לדבר.** פתק לעצמכם מקבל התראה שקטה. דדליין נעשה נחרץ
יותר ככל שמתקרבים. השכמה מקבלת שעון מעורר אמיתי שמצלצל גם במצב שקט. אתם בוחרים
את עוצמת הקול לכל פריט, ושעות השקט משתיקות כל מה שלא סימנתם כחשוב מספיק כדי
להתעלם מהן.

**שנים־עשר סוגים, ואף אחד מהם לא קבוע מראש.** אירועים, משימות, דדליינים, מטלות
חוזרות, שגרות שמציגות שלב אחד בכל פעם, הרגלים עם מכסה שבועית שמזכירים רק כשנשארים
מאחור, טיימרים שאתם מתחילים, תזכורות לפי מקום, דברים שאתם ממתינים להם ממישהו
אחר, ודברים שאולי תעשו מתישהו. בוחרים את הקרוב ביותר ומשנים מה שרוצים — הסוגים
הם רק נקודת התחלה, וכל הגדרה ניתנת לעריכה בכל פריט.

**הכול נשאר בטלפון.** בלי חשבון. בלי אנליטיקס. שום דבר לא עוזב את המכשיר.

בעברית ובאנגלית, כולל ימין לשמאל.

## Keywords (100 characters, comma separated, no spaces)

**EN**
```
widget,lockscreen,routine,habit,reminder,alarm,checklist,agenda,planner,recurring,timer,todo
```
(92 characters. Do not repeat the app name or subtitle words — Apple already
indexes those, so repeating them wastes the budget.)

**HE**
```
ווידגט,מסךנעילה,שגרה,הרגל,תזכורת,שעוןמעורר,יומן,מתכנן,משימות,טיימר,רשימה
```

## Screenshot plan

Six per device size. Required sizes are 6.9" and 6.5"; everything else is
derived. Shoot on a device, not the simulator — Live Activities and alarms do
not render correctly in one.

| # | Screen | Caption (EN) | Caption (HE) |
|---|---|---|---|
| 1 | Home screen, both widgets, apps gone | `Give it the first page` | `תנו לו את העמוד הראשון` |
| 2 | Lock screen with the Live Activity | `Done, without unlocking` | `בוצע, בלי לפתוח נעילה` |
| 3 | Today, mid-morning, mixed states | `The whole day, grouped by what needs you` | `כל היום, מקובץ לפי מה שדורש אתכם` |
| 4 | Preset picker | `Twelve starting points, none of them fixed` | `שנים־עשר נקודות פתיחה, אף אחת לא קבועה` |
| 5 | Editor, Advanced open | `Change anything about anything` | `לשנות כל דבר בכל פריט` |
| 6 | Weekly review | `Where the things you hid from yourself come back` | `לאן חוזרים הדברים שהסתרתם מעצמכם` |

Shoot 3, 4, 5 and 6 in Hebrew for the Hebrew listing rather than reusing the
English ones — the RTL layout is a selling point and a reviewer will notice.

Seed a realistic day first. An empty app screenshots badly, and a fake-looking
one screenshots worse.

## App Review notes

Put this in the review notes field, because two features cannot be exercised
without it:

> The wake-up item uses AlarmKit and needs a physical device to ring; it will
> not sound in the simulator.
>
> Place reminders need Location set to Always. To test: create an item, choose
> "Place reminder", tap the map to drop a pin near your location, and set the
> radius to 100m.
>
> The lock screen card appears once an item is due within its lead time. To see
> it immediately, create an item due in two minutes with the lock screen
> surface enabled.
>
> No account is required. The app is fully functional offline.

## Category and rating

- Primary category: **Productivity**
- Secondary: **Utilities**
- Age rating: **4+** — no user-generated content is shared, no web views, no
  purchases.

## Before you submit

Name availability, the contact email in the privacy policy, a hosted privacy
policy URL, and the real app icon. All four are on the checklist.

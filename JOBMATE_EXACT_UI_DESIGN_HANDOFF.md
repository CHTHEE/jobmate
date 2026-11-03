# JobMate Exact UI Design Handoff

> Visual reproduction reference for Flutter Web and Android, derived from the current React/Vite/Tailwind prototype source.
>
> **Scope:** reproduce the existing UI. This document does not redesign JobMate, define a backend, or replace the functional Flutter/Supabase implementation.

## 0. Reading rules and evidence levels

This document uses the following labels consistently:

- **SOURCE EXACT** — literal CSS/JSX/SVG value, or a deterministic Tailwind utility value in the installed Tailwind CSS v4 implementation.
- **CLASS-DERIVED** — exact class name exists in source and is converted to its normal CSS value. It is exact for the current Tailwind v4 build, but is not a separately hard-coded design token.
- **CONTENT-DRIVEN** — width or height is intentionally determined by text, viewport, content, flex/grid, or intrinsic sizing; no fixed measurement should be invented.
- **INFERRED / RECOMMENDATION** — Flutter implementation advice, not an existing source fact.
- **MOCK/SIMULATED** — visual state exists, but timers/local state/static data imitate the behavior.
- **NOT DESIGNED** — no corresponding UI was found.
- **NEEDS CONFIRMATION / UNKNOWN** — source does not determine the answer.

The 36 px preview switcher in `src/App.tsx` is a **development artifact**, not product UI. Its product previews start at `top: 36px`; do not reproduce the switcher in production Flutter.

---

# 1. Project visual overview

JobMate uses a restrained employment-platform visual language: a Slate 50 app canvas, white cards and chrome, one-pixel Slate 200 borders, teal brand actions, compact rounded controls, dense metadata, and soft semantic status backgrounds. Most product pages are centered columns rather than edge-to-edge dashboards. Serif display headings provide contrast while Outfit carries almost all interface copy and DM Mono is reserved for numbers, IDs, times, percentages, coordinates, and scores.

## 1.1 Color tokens

### Literal project tokens — SOURCE EXACT

| Role | Token/value | Current use |
|---|---:|---|
| Canvas | `#f8fafc` | Literal `body` background; app shell separately uses the `slate-50` class |
| Default text | `#0f172a` | Literal `body` text; strongest headings separately use the `slate-900` class |
| Brand 50 | `#f0fdfa` | selected nav, secondary actions, soft panels |
| Brand 100 | `#ccfbf1` | avatars, active fills, AI ring track |
| Brand 200 | `#99f6e4` | soft borders/rings |
| Brand 300 | `#5eead4` | hover borders |
| Brand 400 | `#2dd4bf` | focus border / bright accent |
| Brand 500 | `#14b8a6` | charts, bars, progress |
| Brand 600 | `#0d9488` | primary action, logo, active icon |
| Brand 700 | `#0f766e` | primary hover, selected text, auth brand panel |
| Brand 800 | `#115e59` | primary active |
| Brand 900 | `#134e4a` | deepest brand |
| Scrollbar thumb | `#cbd5e1` | `.scroll-thin` only |
| White | `#ffffff` | cards, inputs, dialogs, shell chrome |
| Logo secondary on dark | `rgba(255,255,255,0.75)` | “Mate” wordmark segment |
| Drawer/modal overlay | Slate 900 at 40%, 50%, or 60% | backdrop depends on module |

### Tailwind utility palette — SOURCE CLASS NAMES, not literal project hex

The source uses the utility families below but does not declare their hexadecimal values in project code. Tailwind v4's installed default palette is represented internally with color functions rather than these project-authored hex tokens. To avoid fabricating source hex values, this table records the exact classes only. In Flutter, resolve the current build's computed colors during manual capture or deliberately pin an approved conversion.

| Family | Exact source shades used |
|---|---|
| Slate | `slate-50`, `100`, `200`, `300`, `400`, `500`, `600`, `700`, `800`, `900` |
| Green | `green-50`, `100`, `200`, `300`, `400`, `500`, `600`, `700`, `800` |
| Red | `red-50`, `100`, `200`, `300`, `400`, `500`, `600`, `700`, `800` |
| Amber | `amber-50`, `100`, `200`, `300`, `400`, `500`, `600`, `700`, `800` |
| Blue | `blue-50`, `100`, `200`, `300`, `400`, `500`, `600`, `700`, `800` |
| Purple | `purple-50`, `100`, `200`, `500`, `600`, `700` |
| Orange | `orange-50`, `200`, `300`, `400`, `500`, `600`, `700` |
| Indigo | `indigo-50`, `100`, `200`, `700` |
| Rose/Pink | `rose-100`, `rose-700`, `pink-50`, `pink-700` |

Literal semantic/map colors that **are** present in TSX include Green `#22c55e`, Red `#ef4444` and `#f87171`, Amber `#f59e0b`, Blue `#3b82f6`/`#93c5fd`, Purple `#7c3aed`/`#c4b5fd`, Orange `#f97316`/`#fed7aa`, Pink `#ec4899`/`#fbcfe8`, and Brand `#0d9488`/`#99f6e4`. These literals belong to rings, evaluation ratings, and WorkMap job-type pins; they do not prove every Tailwind utility with the same family/shade renders from a project-authored hex token.

### Semantic assignment

| State | Surface / content / border |
|---|---|
| Primary action | Brand 600 / white; hover Brand 700; active Brand 800 |
| Secondary/selected | Brand 50 / Brand 700; selected icon Brand 600 |
| Neutral card | White / Slate 900–500 / Slate 200 |
| Hover card | White / unchanged / Brand 300 plus `shadow-sm` |
| Success/verified/accepted | Green 50 / Green 700 / Green 200; stronger action Green 500–600 |
| Warning/reviewing | Amber 50 / Amber 700 / Amber 200 |
| Error/destructive | Red 50 or Red 500 / Red 700 or white / Red 200–400 |
| Information/pending/open | Blue 50 / Blue 700 / Blue 200 |
| Disabled | same base colors at 50% opacity; cursor not-allowed on web |
| Focus | 2 px Brand 500 ring; inputs also Brand 400 border; shared buttons add 1 px ring offset |
| Dialog | White surface, Slate 900/40–60 overlay, `shadow-xl` or `shadow-2xl` |
| Chat outgoing | Brand-toned bubble with white text; incoming uses Slate surfaces/text |

**UNKNOWN:** there is no explicit dark theme. Do not infer one.

## 1.2 Radius, borders, elevation, and spacing

### Radius — CLASS-DERIVED

| Utility | CSS radius | Typical use |
|---|---:|---|
| `rounded` | 4 px | compact labels |
| `rounded-md` | 6 px | small controls |
| `rounded-lg` | 8 px | buttons, inputs, nav items, icon wells |
| `rounded-xl` | 12 px | cards, search, primary panels |
| `rounded-2xl` | 16 px | feature cards/dialogs |
| `rounded-full` | 9999 px | avatars, pills, status badges, progress tracks |
| Mobile `rounded-t-2xl` | 16 px top corners | bottom sheets |

Borders are normally **1 px** (`border`) in Slate 200 or Slate 300. Ring badges/focus use **1 px** or **2 px** respectively. No custom border width scale was found.

### Shadows — CLASS-DERIVED Tailwind v4 presets

| Utility | CSS shadow |
|---|---|
| `shadow-sm` | `0 1px 3px 0 rgb(0 0 0 / 0.10), 0 1px 2px -1px rgb(0 0 0 / 0.10)` |
| `shadow` | `0 1px 3px 0 rgb(0 0 0 / 0.10), 0 1px 2px -1px rgb(0 0 0 / 0.10)`; current compiled CSS makes it equivalent to `shadow-sm` |
| `shadow-md` | `0 4px 6px -1px rgb(0 0 0 / 0.10), 0 2px 4px -2px rgb(0 0 0 / 0.10)` |
| `shadow-lg` | `0 10px 15px -3px rgb(0 0 0 / 0.10), 0 4px 6px -4px rgb(0 0 0 / 0.10)` |
| `shadow-xl` | `0 20px 25px -5px rgb(0 0 0 / 0.10), 0 8px 10px -6px rgb(0 0 0 / 0.10)` |
| `shadow-2xl` | `0 25px 50px -12px rgb(0 0 0 / 0.25)` |

Cards generally have a border and no resting shadow. `shadow-sm` appears on primary buttons and card hover. Large overlay panels use `shadow-xl`/`shadow-2xl`.

### Spacing scale used heavily — CLASS-DERIVED

| Utility step | px | Primary use |
|---:|---:|---|
| 0.5 | 2 | micro gaps and offsets |
| 1 | 4 | label gaps, tiny margins |
| 1.5 | 6 | compact chips, input-label spacing |
| 2 | 8 | common gaps, button vertical padding |
| 2.5 | 10 | input/button padding, nav row vertical padding |
| 3 | 12 | card gaps, compact padding |
| 3.5 | 14 | input horizontal padding |
| 4 | 16 | default card padding, main mobile horizontal padding |
| 5 | 20 | larger card/dialog padding |
| 6 | 24 | page mobile vertical padding, larger dialogs |
| 8 | 32 | desktop page vertical padding |
| 10 | 40 | auth side panel padding |
| 12 | 48 | empty-state icon/large space |
| 14 | 56 | app top bar and XL avatar |
| 16 | 64 | occasional feature icon |
| 24 | 96 | mobile shell bottom padding |

Default page stacks use 16, 20, or 24 px vertical gaps (`space-y-4/5/6`). Grid gaps are usually 8, 12, or 16 px. Do not normalize all pages to one gap; preserve the source per screen.

## 1.3 Dimensions and responsive breakpoints

| Item | Exact source behavior |
|---|---|
| Preview artifact | 36 px fixed bar; product is offset by 36 px (`top-9`, `pt-9`) |
| Desktop sidebar | 240 px (`w-60`), visible at `md` ≥768 px |
| Mobile drawer | 256 px (`w-64`), top 36 px to viewport bottom |
| Top bar | 56 px (`h-14`), sticky at `top:36px` in preview |
| Main page padding | 16 px horizontal/24 px vertical base; 24 px horizontal/32 px vertical at `md` |
| Mobile product bottom clearance | 96 px; desktop 32 px |
| Mobile bottom nav | CONTENT-DRIVEN: 8 px top + icon/label + 12 px bottom + safe area; no fixed total height |
| Standard content column | 672 px (`max-w-2xl`) |
| Employer dashboards/map | 768 px (`max-w-3xl`) |
| Admin common | 896 px (`max-w-4xl`) |
| Admin dispute detail | 1024 px (`max-w-5xl`) |
| Auth form | 384 px (`max-w-sm`) |
| Auth brand panel | 420 px, visible at `lg` ≥1024 px |
| Dialog common | 384 px (`max-w-sm`), 448 px (`sm:max-w-md`), 512 px (`sm:max-w-lg`) |
| Report sheet | 794 px max width, 1123 px minimum height |
| Chat | `calc(100vh - 126px)`; conversation rail 288 px at `md`, 320 px at `lg` |
| Nearby map | 360 px height |
| Employer location map | 320 px height |

Breakpoints actually used: base `<640`; `sm` 640; `md` 768; `lg` 1024. No product-specific `xl` layout was found.

## 1.4 Icons and graphics

- `lucide-react` supplies nearly all UI icons. Source usually sets icons to 12, 14, 16, 18, 20, 24, or 28 px via width/height utilities.
- Lucide defaults to a 24×24 viewBox, `currentColor`, round caps/joins, and 2 px stroke unless a source component overrides it. Chat empty-state icon explicitly uses 1.5 stroke.
- Icons are normally leading, vertically centered, and `flex-shrink-0`; button icon slot is 16×16 px.
- Stars use Amber 400 fill and text. Do not substitute emoji.

---

# 2. Exact typography

## 2.1 Font wiring — SOURCE EXACT

`src/index.css` imports from Google Fonts:

- **DM Serif Display**: regular 400 and italic 400; CSS variable `--font-display`.
- **Outfit**: 300, 400, 500, 600, 700; CSS variable `--font-sans`; body default.
- **DM Mono**: 400 and 500; CSS variable `--font-mono`.

Some source requests `font-semibold`/600 or `font-bold`/700 while using DM Mono, although only 400 and 500 are imported. Browsers may synthesize those heavier weights. **Flutter recommendation:** either permit synthesized weights to match the browser or verify screenshots before mapping both to DM Mono 500; do not silently replace the family.

## 2.2 Type scale — CLASS-DERIVED

| Source class | Size / normal line height | Use |
|---|---:|---|
| `text-[9px]` | 9 px / normal unless overridden | tiny badges and AI metadata |
| `text-[10px]` | 10 px / normal | bottom navigation, eyebrow labels, timestamps |
| `text-[11px]` | 11 px / normal | chat context and compact chips |
| `text-xs` | 12 px / 16 px | metadata, status, helper/error text, table labels |
| `text-sm` | 14 px / 20 px | body, fields, buttons, nav labels |
| `text-base` | 16 px / 24 px | shell title, section heading, prominent values |
| `text-lg` | 18 px / 28 px | dialog success title, select headings |
| `text-xl` | 20 px / 28 px | page/subview title |
| `text-2xl` | 24 px / 32 px | dashboard greeting and major numeric stats |
| `text-3xl` | 30 px / 36 px | auth marketing heading |
| `text-5xl` | 48 px / Tailwind normal | isolated report/display value |

Explicit modifiers: `leading-none` = 1; `leading-tight` = 1.25; `leading-snug` = 1.375; `leading-relaxed` = 1.625; `leading-5` = 20 px. `tracking-tight` = −0.025em; `tracking-wide` = 0.025em; `tracking-wider` = 0.05em; `tracking-widest` = 0.1em.

## 2.3 Usage matrix

| UI role | Actual family and treatment |
|---|---|
| Major page title/greeting | DM Serif Display; usually 20 or 24 px, 700 requested, Slate 900, tight line height where set |
| Auth marketing headline | DM Serif Display 30 px, requested 700, white, snug |
| Section headings | Mix: display headings use DM Serif Display 20 px; shared `SectionHeader` remains Outfit 16 px/600 |
| Shell/top-bar title | Outfit 16 px/600 |
| Sidebar and bottom-nav label | Outfit 14 px/500; bottom nav 10 px/500 |
| Card heading | Outfit 14 px/600, except module headings explicitly use DM Serif Display |
| Body/supporting text | Outfit 12–14 px, Slate 500–700, often relaxed |
| Button label | Outfit 12 or 14 px/500 |
| Field label/input | Outfit 14 px/500 label; 14 px/400 input |
| Badge/chip | Outfit 10–12 px/500–700 |
| Numeric stat | DM Mono, usually 20 or 24 px, requested 700 |
| Times/IDs/percent/coordinates | DM Mono 10–16 px, requested 500–700 |
| Tables | Outfit 12–14 px; time/ID/value cells switch to DM Mono |
| Dialog title | DM Serif Display 16–18 px where explicitly styled; some generic dialogs use Outfit bold |

### Flutter reproduction guidance

Load the three exact Google families. Set `ThemeData.fontFamily` to Outfit. Define separate named styles rather than changing the whole Material type scale: `displayPage` (DM Serif Display 24/32), `displaySection` (DM Serif Display 20/28), `shellTitle` (Outfit 16/24, 600), `body` (Outfit 14/20), `meta` (Outfit 12/16), `micro` (Outfit 10), and `numeric` variants based on DM Mono. Set explicit heights only where source does; arbitrary 9/10/11 px text otherwise uses browser-normal line-height and should be visually calibrated.

---

# 3. Application shell

## 3.1 Shared shell structure

`src/components/Layout.tsx` owns the logo and `AppShell`.

### Desktop (`md` and above)

- Fixed left sidebar, 240 px wide, from below the 36 px preview artifact to viewport bottom; white background and 1 px Slate 200 right border.
- Logo row uses 20 px horizontal/16 px vertical padding, a 32 px mark, 10 px gap, and Outfit 16 px bold wordmark; 1 px Slate 100 bottom border.
- Navigation area: 12 px horizontal/16 px vertical padding, 2 px vertical spacing. Every item is full width with 12 px horizontal, 10 px vertical padding, 8 px radius, 14 px/500 label, and 18 px icon slot (`w-4.5`). Height is CONTENT-DRIVEN, approximately 40 px from padding + line box; do not declare an invented fixed height.
- Active item: Brand 50 fill, Brand 700 text, Brand 600 icon. Inactive: Slate 600 text/Slate 400 icon; hover Slate 50/Slate 900.
- Footer profile row mirrors navigation padding, contains 32 px brand avatar, 14 px name, 12 px subtitle, and 16 px chevron.
- Main content receives 240 px left padding. Top bar is sticky, 56 px high, white with Slate 200 bottom border, 24 px horizontal padding. The desktop page title is 16 px/600. Notification and 32 px avatar/profile appear right.
- Page body is centered within each screen's own max width; shell itself does not impose a global max width.

### Mobile (`<md`)

- No permanent sidebar. Top bar has 16 px horizontal padding and a 24 px menu button icon in a compact padded target. The JobMate mark is 28 px; name is 14 px bold.
- Drawer is 256 px wide with Slate 900 at 40% backdrop and `shadow-xl`. It reuses desktop sidebar content; close icon is visible only here.
- Non-admin roles get a fixed five-item bottom nav. Only the first five role nav items are shown. The active item has Brand 600 icon/text and a centered 24×2 px teal indicator at top. Each icon is 20 px and label 10 px. Profile/company can therefore be absent from bottom navigation and remains available through shell/profile affordances.
- Admin has no bottom nav; mobile navigation is drawer-only.
- Page padding is 16 px horizontal/24 px vertical. Non-admin main content reserves 96 px at bottom.

## 3.2 Role shells

### Job Seeker

Navigation order: Home, Jobs, My Applications, Work, Messages, Profile. Jobs contains Browse Jobs / For You / Nearby tabs. Work contains Attendance / Evaluations tabs. The first five appear in mobile bottom nav; Profile is not a sixth bottom item.

### Employer

Navigation order: Dashboard, Job Posts, Applications, Workers, Messages, Company Profile. Job Posts contains Job Posts / Job Location. Workers contains Workers / Attendance / Payment Handling. Company Profile contains Profile / Evaluations / Reputation. The first five appear in mobile bottom nav.

### Administrator

Navigation: Dashboard, Users, Job Posts, Disputes, Reports. Same sidebar/top bar, `isAdmin=true`, no mobile bottom navigation. Admin content expands to 896 or 1024 px on complex views.

## 3.3 Common responsive composition

- Two/four statistic grids: two columns base, four at `md`; 12 px gaps.
- Forms: one column base; selected groups become two columns at `sm`; create-job choices use 2 columns base/3 at `sm`.
- Dialogs: edge-aligned bottom sheet on mobile, centered panel at `sm`; top corners 16 px mobile, all corners 16 px desktop.
- Tables frequently become stacked cards rather than horizontal scrolling; exact behavior is component-specific.
- Long pages use viewport scrolling. Chat creates an internal bounded scroll region. Admin dispute side actions become a sticky right column only at `lg`.

---

# 4. Job Seeker screen specifications

Unless stated otherwise, Job Seeker screens sit in the shared shell, use a 672 px centered column, 16/24/32 px page spacing, white 12 px-radius cards with 1 px Slate 200 borders, and stack to one column on mobile. There are no independent URL routes; screens are local section/tab/subview states.

## JS-01 — Home Dashboard

- **Type/source:** section, `HomeSection`, `src/views/JobSeekerView.tsx`; `max-w-2xl`, `space-y-6`.
- **Order:** DM Serif 24 px greeting and support copy; profile-completion card with 75% DM Mono figure and 8 px progress track; 2×2-to-4-column summary stats; teal AI-match feature banner; recommended job cards; recent applications; trust/skills block.
- **Desktop/mobile:** content width is unchanged; stat columns increase at `md`. Cards reflow internally rather than scaling to fixed heights.
- **States:** static populated dashboard only. Loading/error/empty dashboard states are **NOT DESIGNED**. Navigation actions are local.
- **Details:** values/scores use DM Mono; progress widths are inline percentages; use Slate 50 canvas, not pure white page background.

## JS-02 — Browse Jobs

- **Type/source:** tab root `JobSearchView`, `src/views/jobseeker/JobsView.tsx`; `max-w-2xl`, `space-y-4`.
- **Order:** DM Serif 20 px “Find Jobs”; 12 px-radius search; filter trigger/panel; category/type/location chips; sort row; stacked `JobSearchCard`s.
- **Cards:** 16 px padding, 12 px radius, Slate 200 border; title/company, save icon, type/location/pay, date. Hover teal border/shadow on web.
- **Responsive:** filter controls wrap; filter chip area can scroll vertically with 96 px max height. No desktop split filter rail.
- **States:** source includes no-results empty treatment after filters. Salary range has state but no visible control. Network loading/error are **NOT DESIGNED**.

## JS-03 — Job Details

- **Type/source:** local subview, not route; `JobDetailsView`, `JobsView.tsx`; `max-w-2xl`.
- **Layout:** back control; white detail card with 20 px DM Serif title, company/type/location/salary metadata, status badge; section dividers for description, requirements, skills, company verification and employer trust bars; sticky behavior is **NOT DESIGNED**.
- **Actions:** Apply Now is the dominant teal button; share is visual/placeholder. Applied state changes call-to-action treatment.
- **Mobile:** same order, actions stack/wrap based on available width. No alternative mobile detail design.

## JS-04 — Apply to Job

- **Type/source:** modal/bottom sheet, not route; `ApplyModal`, `JobsView.tsx`.
- **Frame:** fixed full-screen z-index 300, mobile bottom aligned and desktop centered at `sm`; white full width, 448 px max at `sm`, 16 px top-only radius mobile/all-corner desktop, `shadow-2xl`.
- **Content:** job summary, optional 14 px note textarea, profile-sharing information panel, secondary cancel and primary submit. Success uses a large semantic icon and 18 px DM Serif heading.
- **States:** submitting/success are MOCK/SIMULATED. Error state **NOT DESIGNED**.

## JS-05 — AI Recommendations / For You

- **Type/source:** tab view, `AIRecommendationsView`, `src/views/jobseeker/AIRecommendationsView.tsx`; `max-w-2xl`, `space-y-5`.
- **Order:** 20 px DM Serif title + explanatory copy; AI transparency panel; filter/sort controls; stacked recommendation cards.
- **Card visual:** large circular match ring (default 64 px), score in DM Mono; threshold colors: ≥90 Green 500/Green 100 track, ≥75 Brand 600/Brand 100, ≥60 Amber 500/Amber 100, below 60 Red 400/Red 100. Sections distinguish matched skills, skill gaps, why suggested, and employer reputation.
- **Responsive/states:** dense rows wrap and actions stack as needed. Static recommendations and local filters; retrieval loading/error/empty are **NOT DESIGNED**. “View Job” is placeholder.

## JS-06 — Recommendation Application

- **Type/source:** modal/sheet `ApplyModal`, `AIRecommendationsView.tsx`; 448 px max desktop.
- **Visual:** same overlay geometry as JS-04, with match summary/ring context, optional note, AI disclaimer, and teal submit action.
- **States:** simulated submit/success. No backend error or duplicate-application design.

## JS-07 — Nearby Jobs

- **Type/source:** tab view `JobSeekerMapView`, `src/views/shared/LocationModule.tsx`; `max-w-3xl`, compact 12 px vertical gaps.
- **Controls:** title, location search/current-location button, radius selector (2/5/10/25/50 km), job-type chips, map/list segmented toggle.
- **Map:** 360 px high, 16 px radius, Slate 200 border, `shadow-sm`, literal beige `#f0ece0` map. Inline 800×520 WorkMap contains parks, water, streets and labels, radius circle, user pin, six static job pins, popover, legend and zoom controls.
- **List mode:** stacked `JobListCard`s. Desktop does not create a side-by-side map/list split.
- **States:** local filter empty state exists. Current location, zoom, map provider and geolocation are placeholders/MOCK. Mobile controls stack at base; become a row at `sm`.

## JS-08 — Nearby Job Details

- **Type/source:** local subview `JobDetailLocationView`, `LocationModule.tsx`; not route.
- **Visual:** back header, job identity/status, three summary metrics (salary/distance/rating), address/location sections, miniature illustrative map, action row.
- **Responsive:** 672 px centered stack. No desktop side rail.
- **Limitations:** navigation and Apply actions are placeholders; directions/provider/error/location-denied views are **NOT DESIGNED**.

## JS-09 — My Applications

- **Type/source:** section `MyApplicationsView`, `src/views/jobseeker/MyApplicationsView.tsx`; 672 px, 20 px stack gaps.
- **Order:** 20 px DM Serif title; summary statistic cards; search; All/Active/Completed tabs; application cards.
- **Cards:** white/Slate 200/12 px radius, 16 px padding; job/company, `StatusBadge`, metadata/timeline preview, contextual offer/detail/withdraw controls.
- **States:** tab empty state is designed. No loading/error. Mobile wraps card actions.

## JS-10 — Application Details

- **Type/source:** modal/sheet `ApplicationDetailModal`; not standalone route.
- **Frame:** 448 px max, max height 85vh, overflow-y auto, mobile bottom sheet.
- **Content:** job header/status, application ID in DM Mono, vertical timeline, details and offer actions, withdraw control where permitted.
- **Limitations:** Accept/Decline are visually present but placeholders.

## JS-11 — Withdraw Confirmation

- **Type/source:** confirmation dialog `WithdrawConfirmDialog`; not route.
- **Frame:** centered 384 px max, white 16 px radius, `shadow-xl`, 24 px padding over dark overlay.
- **Visual:** warning/destructive icon, title, job/company copy, neutral keep action and red withdraw action.
- **State:** local mutation to Withdrawn; no server failure design.

## JS-12 — Attendance Today

- **Type/source:** Today tab within `AttendanceModule`, `src/views/jobseeker/AttendanceView.tsx`; 672 px, 16 px gaps.
- **Order:** 20 px DM Serif heading and Attendance/Evidence/History sub-tabs; active assignment card; live clock/location verification card; primary check-in/out action; elapsed and status tiles after action.
- **Visual details:** timestamps and elapsed values use DM Mono; Green denotes checked-in/verified, Brand denotes checked-out/action; location verification is a soft semantic panel.
- **States:** idle, locating, verified, checked in, checked out are MOCK/SIMULATED timers. Permission denied, GPS error, offline and real geofence states are **NOT DESIGNED**.

## JS-13 — Check-in/out Confirmation

- **Type/source:** `ConfirmActionDialog`; overlay, not route.
- **Frame:** 384 px max, 16 px radius, `shadow-xl`, 20 px padding; bottom-position-aware outer padding on mobile.
- **Content:** action title, exact time/location in compact rows, consent/info copy, cancel and semantic confirm.
- **State:** local confirmation only.

## JS-14 — Work Evidence

- **Type/source:** Evidence tab `EvidenceForm`, `AttendanceView.tsx`.
- **Layout:** assignment context; bordered upload/drop target; local image/file chips and removal; required description textarea; disclaimer; full-width teal submit.
- **States:** blank, selected files, submitting, submitted success are designed/local. Upload progress, file rejection and server error are **NOT DESIGNED**. Previews use `URL.createObjectURL`.

## JS-15 — Attendance History

- **Type/source:** History tab `AttendanceHistory`.
- **Layout:** All/Completed/Issues filter chips and stacked `HistoryCard`s with date/job, check-in/out, hours, evidence/status, and Details affordance.
- **States:** filtered empty state exists. Details is placeholder; no detail view or loading/error.

## JS-16 — Pending Evaluations

- **Type/source:** shared `JobSeekerEvaluationModule`, `src/views/shared/EvaluationModule.tsx`; 672 px/16 px gaps.
- **Order:** 20 px DM Serif title; bidirectional-visibility notice; Pending/History tabs; pending cards with employer/job, due date and Start Evaluation.
- **States:** empty pending illustration/copy exists. Data is static/local.

## JS-17 — Evaluate Employer

- **Type/source:** local form subview `EvalForm`; not route.
- **Layout:** back header, 18 px DM Serif title, progress label and bar, six separate 12 px-radius criterion cards, rating picker, optional 300-character feedback, submit action.
- **Rating visual:** five numbered colored circular choices: 1 Red 500, 2 Orange 500, 3 Amber 500, 4 Brand 500, 5 Green 500; selected choice receives matching ring/light label.
- **Responsive:** one-column cards on both platforms. Validation appears inline when criteria are incomplete.

## JS-18 — Evaluation Submitted

- **Type/source:** full local confirmation subview `ConfirmationScreen`.
- **Visual:** centered success icon, 20 px DM Serif heading, average/rating summary with DM Mono values, visibility explanation card, primary View Evaluation History.
- **State:** local success only; no submission error.

## JS-19 — Evaluation History

- **Type/source:** History tab `HistoryTab`.
- **Layout:** Given/Received controls, two average statistic tiles, stacked history cards with score, date, role direction and details/report actions.
- **States:** history empty state exists. Values use DM Mono; score badges use semantic thresholds.

## JS-20 — Evaluation Details

- **Type/source:** `HistoryDetailModal`, not route; mobile sheet/desktop modal, 448 px max, 85vh scrolling.
- **Content:** identity/job/date metadata, overall score, six criterion bars, feedback, and report action only when permitted.

## JS-21 — Report Evaluation

- **Type/source:** `ReportModal`, not route; 384 px max confirmation-style panel.
- **Visual:** required preset reason controls, optional details, warning panel, destructive/primary submission and local success treatment.
- **States:** MOCK/SIMULATED. Three-day review copy has no designed admin SLA flow.

## JS-22 — Messages

- **Type/source:** `JobSeekerChatModule`, `src/views/shared/ChatModule.tsx`.
- **Frame:** bordered white 12 px-radius container, negative page horizontal margins; height `calc(100vh - 126px)`.
- **Desktop:** 288 px conversation rail at `md`, 320 px at `lg`; border-right; chat detail flexes. Empty right pane is Slate 50 with 28 px/1.5-stroke icon. List has title/search/conversations. Chat has participant/job header, scrollable grouped messages, quick replies and composer.
- **Mobile:** list is full width. Selecting a conversation hides list and shows full chat with back control. Job context chip can hide below `sm`. Bubble max width 72% base/60% at `sm`; corners vary by sender/group continuity.
- **States:** unread/online/sent/delivered/read and attachments are local simulations. Send failure/offline/upload progress are **NOT DESIGNED**.

## JS-23 — Profile

- **Type/source:** `ProfileViewMode`, `JobSeekerView.tsx`; local profile subview.
- **Order:** identity hero with XL 56 px initials avatar, verification/availability badges and Edit; bio/contact; skills/category chips; resume; reputation/trust card; achievements; rows to Reputation, Payments and Settings.
- **Visual:** 672 px column, 20 px stack, white bordered cards. Metrics/scores use DM Mono and trust ring.
- **States:** populated profile only. Missing-avatar uses initials, not photo asset.

## JS-24 — Edit Profile

- **Type/source:** `ProfileEditForm`; local subview, not route.
- **Layout:** back header, avatar/photo placeholder, stacked labeled fields; 250-character bio counter; location/availability; skills chips/input; category grid; resume upload/removal; Save.
- **Responsive:** category controls become two columns at `sm`; otherwise one column. Save success is local. Upload errors/progress are **NOT DESIGNED**.

## JS-25 — Reputation

- **Type/source:** `JobSeekerReputationPage` + `JobSeekerReputationView`, `src/views/shared/ReputationProfile.tsx`.
- **Order:** back/title; own-profile notice; TrustScoreCard; 2×2 to 4-column performance stats; score-factor progress bars; criterion ratings; work history; attendance summary; evaluations; disclaimer.
- **Visual:** 672 px column, 16 px gaps; numeric values DM Mono; teal/green/amber/red bar thresholds; stars Amber 400.
- **States:** static read-only. Formula/history/loading/error are **NOT DESIGNED**.

## JS-26 — Payments

- **Type/source:** `JobSeekerPaymentModule`, `src/views/shared/PaymentModule.tsx`.
- **Layout:** 20 px DM Serif title; platform-does-not-process-payments disclaimer; Pending/History tabs; pending confirmation cards; history summary/filter/list; details, confirm-receipt and report-issue overlays.
- **Dialogs:** 448–512 px max, mobile bottom sheets, max height 90vh for details. Amount/reference/date use DM Mono. Proof files are chips, not media gallery.
- **States:** local confirm/report success. Overdue exists as a type but is not demonstrated. Gateway/processing UI is **NOT DESIGNED**.

---

# 5. Employer screen specifications

Employer screens inherit the shared shell. Standard detail lists are 672 px; dashboard/posting/attendance pages expand to 768 px. All are local React state rather than URL routes.

## EMP-01 — Employer Dashboard

- **Source/layout:** `DashboardSection`, `src/views/EmployerView.tsx`; 768 px, 24 px stack.
- **Order:** 24 px DM Serif greeting; 2×2/4-column metric cards; quick-action feature row; active post cards; recent applicant cards; worker-performance summary.
- **Responsive/states:** metric grid becomes four columns at `md`; other rows wrap/stack. Populated static state only; loading/error/empty dashboard are **NOT DESIGNED**.

## EMP-02 — Job Posting Dashboard

- **Source/layout:** `PostingsDashboard`, `src/views/employer/JobPostings.tsx`; 768 px, 20 px stack.
- **Header:** 20 px DM Serif “Job Postings,” supporting text, teal Post Job button.
- **Order:** three/four status summary tiles with DM Mono 20 px values; search/filter/status tabs; stacked posting cards.
- **Posting card:** white, 12 px radius, Slate 200 border, 16–20 px padding; title/status/ID/date, type/location/pay, applicants/views metrics, and contextual Edit/Applicants/Publish/Close controls. Use intrinsic height; no fixed card height.
- **Responsive:** compact action labels may wrap; summary cards remain a grid; mobile is not a reduced-information redesign.
- **States/limits:** filtered empty state exists. Publish is no-op; Close confirmation does not persist. This is the primary fidelity reference for the existing Flutter posting dashboard.

## EMP-03 — Create Job

- **Source/layout:** `CreateJobForm`, `JobPostings.tsx`; 672 px, 20 px stack.
- **Header:** back control and 20 px DM Serif title. Form is five white 12 px-radius/Slate 200 sections with `FormSection` title/icon and 16 px padding.
- **Order:** basic job information; compensation; schedule/location; description/AI generation; requirements/skills. Choice grids use two columns base and three at `sm`; paired fields become two columns where coded.
- **Fields:** 14 px labels/inputs, 8–12 px radius, Slate 300 border, Brand 500 2 px focus ring. Required marks are Red 500. Skills are pills.
- **Actions:** Save Draft secondary/outline, Preview, Publish primary; bottom action group wraps/stacks on narrow widths.
- **States/limits:** AI button shows simulated loading then fixed text. Required labels are visual but validation is incomplete. Save/publish navigation is local/no-op in places.

## EMP-04 — Edit Job

- **Source/layout:** same `CreateJobForm` and exact visual structure as EMP-03, title/content change by `mode="edit"`.
- **Important fidelity rule:** do not create a separate edit visual language. Preserve section order, field geometry, chips, AI panel and bottom actions exactly. Only some source fields are prepopulated; this is a mock-data limitation, not a styling cue.

## EMP-05 — Job Preview

- **Source/type:** preview modal inside `CreateJobForm`; not a route.
- **Frame:** white 512 px max, 16 px radius, `shadow-2xl`, max 80vh, scrollable.
- **Content:** public-style title/company/status, pay/location/schedule, description, requirements and skills, footer with close/edit and visually disabled/nonfunctional Apply context.
- **Responsive:** modal uses available width with outer margin; content remains one column.

## EMP-06 — Job Location Picker

- **Source/layout:** `EmployerLocationPicker`, `LocationModule.tsx`; 672 px/20 px stack.
- **Visual:** back/title, required address input and local autocomplete panel, 320 px illustrative WorkMap, draggable teal marker/crosshair guides, coordinate display in DM Mono, confirm/update button and success toast/panel.
- **States:** geocoding uses `Math.random()` and percentages mislabeled as coordinates; current map is MOCK/SIMULATED. Provider, address error and permission states are **NOT DESIGNED**.

## EMP-07 — Applicant Management

- **Source/layout:** `ApplicantManagementView`/`AllApplicantsModule`, `JobPostings.tsx`; 768 px.
- **Order:** back/title or global heading; job filter; six pipeline count tiles (3 columns base/6 at `md`); search/sort; stage tabs; applicant detail cards.
- **Cards:** avatar, status, name/job, trust/rating/skills/applied metadata and stage-action menu. White/Slate 200/12 px geometry.
- **States:** filtered empty state exists. Local status changes only.

## EMP-08 — Applicant Profile

- **Source/type:** `ApplicantProfileModal`, not route; mobile bottom sheet/desktop 512 px modal, max 85vh.
- **Content:** avatar/name/status, trust score, ratings/work summary, skills, cover note and pipeline action. Sections are bordered/divided rather than a second page shell.

## EMP-09 — Reject Applicant

- **Source/type:** nested rejection confirmation in applicant flow; not route.
- **Visual:** destructive red icon/copy, optional internal note textarea, Cancel and Confirm Rejection. Compact 384–448 px overlay treatment.
- **State:** local only; no server error.

## EMP-10 — Workers

- **Source/layout:** `WorkersSection`, `EmployerView.tsx`; 672 px/20 px.
- **Order:** 20 px DM Serif title; three summary metrics with DM Mono values; worker cards with avatar, assignment/status, trust, completed gigs and View Reputation.
- **Responsive:** stack/list on all sizes; metrics wrap into grid.

## EMP-11 — Worker Reputation

- **Source/type:** `ReputationModal`, `ReputationProfile.tsx`; not route.
- **Frame:** full-width mobile bottom sheet; 672 px max at `sm`, 90vh, flex column, `shadow-2xl`.
- **Content:** scrollable Job Seeker reputation profile identical to JS-25 visual grammar. Close header remains fixed within modal.

## EMP-12 — Attendance Review

- **Source/layout:** `AttendanceReviewModule`, `src/views/employer/AttendanceReview.tsx`; 768 px/20 px.
- **Order:** title; four summary tiles; pending-review banner; search + 208 px job filter at `sm` + status filters; worker attendance cards.
- **Cards:** identity/status, job/date, check-in/out/hours/evidence summary and Verify/Flag/View actions. Values use DM Mono.
- **States:** filter empty state exists. Local verify/flag; no retrieval loading/error.

## EMP-13 — Attendance Details

- **Source/type:** `WorkerDetailModal`, bottom sheet/512 px modal, max 90vh.
- **Content:** worker header and status; detail-cell grid; trust/evidence/note cards; verification/flag actions. Evidence View and absent controls are placeholders.

## EMP-14 — Flag Work

- **Source/type:** `FlagDialog`, compact 384 px modal.
- **Visual:** warning icon, preset reason select/custom text, explanatory copy, cancel and red submit. Required state is inline.
- **State:** local status mutation.

## EMP-15 — Record Payment

- **Source/layout:** Record tab `RecordPaymentForm`, `PaymentModule.tsx`; 672 px.
- **Order:** disclaimer; completed-job selector; auto-filled worker card; amount/date; method cards/select; optional reference, proof and note; primary record action.
- **Visual:** amount/date/reference values use DM Mono; proof upload appears as bordered field/chip. One column mobile, paired fields can become two columns at `sm`.

## EMP-16 — Payment Recorded

- **Source/type:** success subview inside `RecordPaymentForm`, not route.
- **Visual:** centered green confirmation, 18 px DM Serif title, summary card with DM Mono amount/reference, View History primary and Record Another secondary.

## EMP-17 — Payment History

- **Source/layout:** History tab in `EmployerPaymentModule`.
- **Order:** 2×2/4-column summary, search/status filter row, payment cards/list, detail modal. Status colors and proof chips match JS-26.
- **States:** filter empty state; static/local data. Export and processing are not present.

## EMP-18 — Messages

- **Source:** `EmployerChatModule`, `ChatModule.tsx`.
- **Visual/responsive:** identical shell and breakpoints to JS-22 with employer conversation data. Preserve 288/320 px rail and mobile list-to-conversation replacement.

## EMP-19 — Company Profile

- **Source/layout:** `CompanyViewMode`, `EmployerView.tsx`; 672 px/20 px.
- **Order:** brand-gradient/identity hero with initials/logo and SSM verification; company description/contact; statistics; reputation/trust; Edit and Settings actions; tabs around Profile/Evaluations/Reputation are handled by parent.
- **States:** verified sample only. Pending/rejected/expired company verification is **NOT DESIGNED**.

## EMP-20 — Edit Company

- **Source/layout:** `CompanyEditForm`; 672 px/20 px.
- **Fields:** logo placeholder, company name/description, industry, company size, website, location, contact name/email, verification read-only panel; save action and local success.
- **Responsive:** selected fields form two columns at `sm`; otherwise one. Upload/progress/error states **NOT DESIGNED**.

## EMP-21 — Evaluations

- **Source:** `EmployerEvaluationModule`, `EvaluationModule.tsx`.
- **Visual:** same screen family as JS-16–21, but criterion copy evaluates workers. Pending/history/form/confirmation/detail/report are local subviews and modals, not separate employer IDs.
- **Fidelity:** preserve colored 1–5 picker, criterion cards, progress and average tiles exactly.

## EMP-22 — Company Reputation

- **Source:** `EmployerReputationPage`/`EmployerReputationView`, `ReputationProfile.tsx`.
- **Visual:** same 672 px reputation structure as JS-25, with employer-specific factors, payment/job accuracy/satisfaction/response/disputes, completed jobs and received evaluations.
- **States:** static read-only; scoring formula/loading/error **NOT DESIGNED**.

---

# 6. Administrator and report screens

Admin inherits the shared shell but has no mobile bottom nav. Common lists are 896 px; dispute detail is 1024 px.

## ADM-01 — Platform Dashboard

- **Source/layout:** `DashboardSection`, `src/views/AdminView.tsx`; `max-w-4xl`, 24 px gaps.
- **Order:** 24 px DM Serif heading; 2×2/4 metric grid; two-column user breakdown/system health at `md`; activity feed; open-dispute list.
- **Visual:** numeric values in DM Mono; progress bars 8 px; compact feed timestamps 10 px. Mobile collapses grids to one/two columns.
- **States:** static populated only.

## ADM-02 — User Management

- **Source/layout:** `UsersSection`; 896 px/20 px.
- **Order:** 20 px DM Serif title; search plus role/status filters and Export CSV; stacked responsive user rows/cards.
- **Row:** avatar/identity, role/status badges, trust score in DM Mono, joined date and profile/action buttons. Mobile wraps metadata/actions; no horizontal table requirement.
- **States:** filtered empty state. CSV is placeholder; no loading/error.

## ADM-03 — Account/Profile Details

- **Source/type:** `UserProfileModal`, not route; full-width mobile bottom sheet and 512 px desktop modal.
- **Content:** avatar/identity/status, contact and account metadata, 2×2 statistics, then restrict/suspend/reactivate actions. 16 px top radius mobile/all corners desktop.

## ADM-04 — User Action Confirmation

- **Source/type:** `UserActionModal`; 384 px centered, 16 px radius, `shadow-2xl`, 20 px padding.
- **Visual:** action-specific semantic icon/title/copy, impact warning, Cancel and destructive/primary confirm.
- **State:** local mutation only.

## ADM-05 — Job Moderation

- **Source/layout:** admin `JobPostsSection`; 896 px/20 px.
- **Order:** title; status tabs; search/filter; stacked job moderation cards showing company, status, reports, posting metadata and View/Approve/Remove controls.
- **Responsive:** cards wrap actions; filter label hides below `sm`. No separate mobile table.
- **States:** filtered empty. View/Approve placeholders.

## ADM-06 — Remove-post Confirmation

- **Source/type:** overlay, not route; 384 px max, 16 px radius, `shadow-2xl`, 20 px padding.
- **Visual:** destructive icon, 16 px DM Serif title, irreversible copy, Cancel and red Remove Posting.
- **State:** local Removed status.

## ADM-07 — Disputes

- **Source/layout:** `DisputesSection`; 896 px/20 px.
- **Order:** title/status filters; dispute cards with DM Mono ID pill, priority dot, category/status, parties, job/date, summary and Review Case.
- **Cards:** internal party/metadata grid becomes two columns at `sm`; mobile stacks.
- **States:** filtered empty; local data only.

## ADM-08 — Dispute Details

- **Source/layout:** `DisputeDetailView`; 1024 px/16 px.
- **Desktop:** three-column grid at `lg`: two-column-width main evidence/case content and one-column sticky action rail (`top:16px`).
- **Mobile/tablet:** single column in source order.
- **Main:** back/ID/status header; parties; description; evidence; expandable related attendance/payment/evaluation records; protected message thread with audit warning.
- **Rail:** case summary, admin remarks, Request Information, Resolve and Reject controls.
- **Visual:** white 12 px cards, Slate 200 borders, 16 px gaps; accordions and evidence use compact 12–14 px text; IDs/times DM Mono.
- **States:** accordion and protected-thread reveal are designed. Evidence file viewer is placeholder.

## ADM-09 — Request Information

- **Source/type:** `RequestInfoModal`; full-width mobile bottom sheet/512 px centered modal.
- **Content:** party selector, required details textarea, contextual notice, submit and local success.
- **Limitation:** copy says Pending Info, but source does not update dispute state.

## ADM-10 — Resolve Dispute

- **Source/type:** `ResolveModal`; same 512 px responsive frame.
- **Content:** outcome radio cards, required explanation, effect notice, Cancel/Resolve; success state.
- **State:** local status → Resolved.

## ADM-11 — Reject Dispute

- **Source/type:** `RejectModal`; same 512 px responsive frame.
- **Content:** rejection reason, optional notes, warning, Cancel/Reject; success state.
- **State:** local status → Rejected.

## ADM-12 — Reports / Analytics

- **Source/layout:** `ReportsSection`; 768 px/24 px.
- **Order:** 20 px DM Serif title + CSV/PDF controls; 2×2/4 stats; registration bar chart; top-employer ranked rows with 6 px progress bars (120 px max).
- **Visual:** chart bars Brand 500, hover Brand 600, rounded tops; ranks and values DM Mono.
- **Limits:** exports are placeholders. Empty/loading/error/chart tooltip design beyond native title is **NOT DESIGNED**.

## RPT-01 / RPT-ATTENDANCE — Attendance & Work Completion Report

- **Accurate identity:** the source component is `AttendanceReport`; it is a static attendance report demo selected through the development preview switcher. `RPT-01` is the inventory ID; `RPT-ATTENDANCE` is a descriptive alias, not a second screen.
- **Source/layout:** `src/views/reports/AttendanceReport.tsx`; Slate 200 outer canvas with 32 px vertical/16 px horizontal padding; white sheet max 794 px, minimum 1123 px, centered, `shadow-md`.
- **Content:** 36 px JobMate mark; report ID in DM Mono; 24 px DM Serif report title; job/schedule table; attendance table; check-in/out locations and coordinates; work evidence/verification; assignment metadata; summary/disclaimer/footer.
- **Print:** action row is hidden; page background becomes white, padding and shadow removed. Print/PDF button calls `window.print()`.
- **Responsive:** the A4-like sheet does not become a different mobile report; narrow viewports compress/overflow according to table content. A dedicated mobile report is **NOT DESIGNED**.

---

# 7. Authentication and account screens

## Shared authentication composition

`src/views/AuthView.tsx` has exactly four states: `login | register | forgot | forgot-sent`.

- Root minimum height is `calc(100vh - 36px)` in the preview.
- At `lg` (1024 px), a 420 px Brand 700 panel appears left with 40 px padding, logo, 30 px DM Serif marketing heading, supporting text, three statistics and decorative translucent patterns. It is hidden below `lg`.
- Right area centers a 384 px form with 20 px horizontal/40 px vertical padding. Mobile adds a logo block with 32 px mark and 32 px bottom margin.
- Form titles are DM Serif 24 px/32 px; support is Outfit 14 px Slate 500. Inputs are 14 px, 8 px radius, Slate 300 border, 10 px vertical/14 px horizontal padding and Brand focus ring.

## AUTH-01 — Login

- Email/password fields, visibility toggle, forgot link, full-width teal Sign In, divider, Register link and demo quick-login cards/buttons.
- Empty validation is inline red; loading is timeout-based MOCK/SIMULATED.
- Role selection is inferred from email substring (`employer`, `admin`) and is MOCK/SIMULATED, not a visual role-picker requirement.
- No social login or persistent session UI.

## AUTH-02 — Registration

- Job Seeker/Employer selection cards sit above fields. Selected card uses teal border/fill; unselected uses white/Slate.
- Fields: name/contact name, email, phone, employer Company Name, password, confirmation, strength meter and terms checkbox; button and back/login link.
- Strength bars use Red/Amber/Green progression.
- **Source limitation:** Employer Company Name is displayed but bound to `value=""` and no-op `onChange`; visually reproduce the field, but the functional Flutter version may bind it correctly without changing appearance.
- Registration/loading is simulated. No Admin registration.

## AUTH-03 — Forgot Password

- Back link, 24 px DM Serif heading, supporting copy, email, full-width Send Reset Link; disabled while empty and simulated loading.
- No reset-password/new-password form exists.

## AUTH-04 — Reset Link Sent

- Centered success icon, 20 px DM Serif title, email/copy, resend link and Back to Login. Resend has no handler.

## Account settings shared layout

`src/views/AccountSettings.tsx` is a 672 px column. It has local sections rather than routes. Main settings uses identity summary and grouped white cards/list rows; detail sections use a back header, fields and full-width/row actions.

## ACC-01 — Account Settings Home

- Identity/account card; Personal Information, Change Password, Notification Settings rows; Security/Privacy/legal rows; sign-out and red delete-account actions; app version `1.0.0` in DM Mono.
- 2FA and profile visibility are placeholders and their destination screens are **NOT DESIGNED**.

## ACC-02 — Personal Information

- Back header; name/email/phone fields in white card; amber email-verification warning; teal Save Changes; local success message.
- The warning is not an email-verification flow.

## ACC-03 — Change Password

- Current/new/confirm fields with eye controls; strength meter and requirement list; full-width save; inline validation and local success.
- Exact password reset by emailed token is **NOT DESIGNED**.

## ACC-04 — Notification Settings

- Back header and grouped activity/email/SMS rows. Each row has title/support copy and a custom toggle: pill track with circular thumb, Slate off and Brand on.
- Local state only. Device permission prompts are **NOT DESIGNED**.

## ACC-05 — Sign Out Confirmation

- `ConfirmDialog`: dark overlay, centered 384 px white 16 px-radius panel, `shadow-xl`, 24 px padding; title/copy and Cancel/Sign Out.
- Parent logout callback is a no-op.

## ACC-06 — Delete Account Confirmation

- Same geometry as ACC-05, destructive red emphasis and permanent-deletion warning; Cancel/Delete. Delete closes only.

### Authentication/account states explicitly absent

Email verification page, OTP, new/reset-password page, social login, admin registration, 2FA setup, account-security history and profile-visibility configuration are **NOT DESIGNED**. Do not derive their appearance from unrelated dialogs.

---

# 8. Reusable component catalog

The source contains **35 identifiable reusable visual components/patterns**: 15 exported shared UI primitives and 20 shell/module-local reusable patterns. This count treats `Skeleton` and `CardSkeleton` separately.

## 8.1 Exported shared primitives (`src/components/UI.tsx`)

| # | Component | Exact visual contract | Use / Flutter recommendation |
|---:|---|---|---|
| 1 | `StatusBadge` | 12 px/500, 8×2 px padding, full pill, 1 px semantic ring | One `StatusPill` widget with status map |
| 2 | `Button` | 8 px radius; sm 12×6 px/12 px text; md 16×8/14; lg 20×10/14; 16 px icon; focus ring; 50% disabled | One variant/size button widget |
| 3 | `Input` | 8 px radius, 1 px border; 14 px; 10×14 px padding; icon at left 12 px, 16 px size; 2 px focus ring | Shared field decorator |
| 4 | `SearchBar` | 12 px radius; 10 px vertical; 36 px left content inset; 16 px search icon | Shared search field |
| 5 | `Avatar` | 28/36/44/56 px; full circle; 12/14/16 px initials; deterministic color by first char | Initial avatar; preserve stable palette |
| 6 | `TrustScoreRing` | default 80 px; radius 36% of size; stroke 10% of size; Slate 200 track; threshold color; DM Mono score 22% of size | Custom painter, not generic progress indicator |
| 7 | `StatCard` | white/12 px/1 px; 16 px padding, 20 at `md`; 40 px icon well; DM Mono 24 px value | Reuse on dashboards/summaries |
| 8 | `JobCard` | white/12 px/1 px; 16 px; teal hover border/shadow; status/location/pay/date composition | Shared compact job tile where source uses it |
| 9 | `ApplicantCard` | white/12 px/1 px; 16 px; 36 px avatar; skill pills; trust star | Shared compact applicant tile |
| 10 | `SectionHeader` | 16 px/600 title, optional 14 px teal action, 16 px bottom margin | Reusable section title row |
| 11 | `EmptyState` | centered, 48 px Slate 100 icon circle, 48 px vertical padding, max 320 px support | Shared known empty state only |
| 12 | `ErrorState` | centered, 48 px Red 50 icon circle, 40 px vertical padding | Do not add to screens without source state unless product requires it |
| 13 | `Skeleton` | Slate 200, 4 px radius, pulse | Loading primitive |
| 14 | `CardSkeleton` | white/12 px/1 px/16 px, avatar and text skeleton composition | Card loading primitive |
| 15 | `NotificationItem` | 16×12 px padding, unread Brand 50 at 40%, 8 px dot, 14/12/10 px text | Notification list row; no dedicated screen currently |

## 8.2 Shell and module-local reusable patterns

| # | Pattern / source | Visual purpose and exact behavior | Primary screens |
|---:|---|---|---|
| 16 | `JobMateMark`/`Wordmark`, `Layout.tsx` | 32 viewBox mark; teal rounded square; white briefcase; 1.5 px teal interior strokes | Auth, shell, report |
| 17 | Sidebar nav item, `Layout.tsx` | 12×10 px padding, 8 px radius, 18 px icon, 14 px/500 | All shell screens |
| 18 | Mobile bottom nav item, `Layout.tsx` | 20 px icon, 10 px label, 24×2 active bar | JS/EMP shell |
| 19 | Tab/segmented row, module files | Compact 12–14 px labels, teal selected treatment, Slate border/background variants | Jobs, work, evaluations, payments |
| 20 | Filter chip/control | Pill or 8–12 px rounded button, semantic selected fill, wrapping | Browse, AI, map, lists |
| 21 | Responsive modal/sheet frame | z 300, Slate overlay, bottom mobile/center `sm`, 16 px radius, `shadow-2xl` | Most details/forms |
| 22 | Profile identity card | 56 px avatar/logo, badges, title/body/action | JS-23, EMP-19, modals |
| 23 | `RatingPicker` | five numbered colored controls + label/ring | JS-17, EMP-21 |
| 24 | `CriterionCard`/score bar | 12 px card, 16 px padding, 6 px/full progress track | Evaluations/reputation |
| 25 | Attendance card/detail cell | white card, compact time grid, status/evidence actions; DM Mono values | JS-12–15, EMP-12–14 |
| 26 | Payment card/status badge/proof chip | amount emphasis, semantic status, compact document chip | JS-26, EMP-15–17 |
| 27 | Chat bubble/attachment bubble | sender-specific fill/corners, max 72%/60%, grouped spacing, receipt icon | JS-22, EMP-18 |
| 28 | WorkMap/map marker/popup | fixed illustrative SVG, absolute pins, type color strip and popup | JS-07–08, EMP-06 |
| 29 | Posting card | job/status/metrics/actions in bordered 12 px card | EMP-02 |
| 30 | Applicant pipeline card | profile/trust/skills/stage action and six-count grid | EMP-07–09 |
| 31 | Reputation section group | trust hero, factor bars, stars, history and disclaimer | JS-25, EMP-11/22 |
| 32 | Admin/list row card | responsive row-to-stack metadata and actions | ADM-02/05/07 |
| 33 | Toggle, `AccountSettings.tsx` | compact Slate/Brand pill track with white circular thumb | ACC-04 |
| 34 | `FormSection`, `JobPostings.tsx` | bordered white 12 px card, icon/title header and grouped fields | EMP-03/04 |
| 35 | Report sheet/table | 794×min-1123 white print sheet, compact bordered tables | RPT-01 |

**Recommendation:** implement items 1–21 as foundational Flutter widgets first, then module-local patterns 22–35. This is a Flutter reuse recommendation, not a claim that every pattern is exported from the React source.

---

# 9. Screen-by-screen implementation matrix

Measurements below name the dominant exact constraint; card heights remain CONTENT-DRIVEN unless explicitly fixed.

| ID | Role/name | Pattern and key measurement | Source | Desktop behavior | Mobile behavior | Suggested Flutter visual equivalent |
|---|---|---|---|---|---|---|
| AUTH-01 | All / Login | 384 px form; 420 px side panel at `lg` | `AuthView.tsx` | Split at 1024 | Centered single form | Constrained auth form + optional side panel |
| AUTH-02 | JS/EMP / Register | Same auth frame; account cards/forms | `AuthView.tsx` | Split | Single column; paired fields wrap | Same scaffold, segmented role cards |
| AUTH-03 | All / Forgot | 384 px form | `AuthView.tsx` | Split | Single form | Auth scaffold |
| AUTH-04 | All / Link sent | 384 px confirmation | `AuthView.tsx` | Split | Centered confirmation | Auth success panel |
| ACC-01 | JS/EMP / Settings | 672 px grouped list | `AccountSettings.tsx` | Centered | Same stack | Settings section list |
| ACC-02 | JS/EMP / Personal info | 672 px form | `AccountSettings.tsx` | Centered | One column | Shared form card |
| ACC-03 | JS/EMP / Password | 672 px form | `AccountSettings.tsx` | Centered | One column | Secure fields + strength widget |
| ACC-04 | JS/EMP / Notifications | 672 px grouped toggles | `AccountSettings.tsx` | Centered | Same stack | Switch rows with custom colors |
| ACC-05 | JS/EMP / Sign out | 384 px dialog | `AccountSettings.tsx` | Centered | Centered | Alert dialog matching source |
| ACC-06 | JS/EMP / Delete | 384 px destructive dialog | `AccountSettings.tsx` | Centered | Centered | Destructive alert dialog |
| JS-01 | JS / Home | 672 px; 2→4 stat grid | `JobSeekerView.tsx` | 4 stats at 768 | 2 stats | Centered scroll column |
| JS-02 | JS / Browse | 672 px cards/filter | `JobsView.tsx` | Same column | Controls wrap | Search/filter stack |
| JS-03 | JS / Job detail | 672 px detail | `JobsView.tsx` | Same column | Actions wrap | Detail scroll view |
| JS-04 | JS / Apply | 448 px sheet/modal | `JobsView.tsx` | Centered | Bottom sheet | Responsive dialog shell |
| JS-05 | JS / For You | 672 px; 64 px match ring | `AIRecommendationsView.tsx` | Same column | Card sections wrap | Custom ring + recommendation card |
| JS-06 | JS / AI apply | 448 px sheet/modal | `AIRecommendationsView.tsx` | Centered | Bottom sheet | Responsive dialog shell |
| JS-07 | JS / Nearby | 768 px; map 360 px | `LocationModule.tsx` | Centered map/list mode | Controls stack | Custom-painted/static map surface |
| JS-08 | JS / Nearby detail | 672 px | `LocationModule.tsx` | Same column | Same stack | Detail scroll view |
| JS-09 | JS / Applications | 672 px | `MyApplicationsView.tsx` | Centered | Cards/actions wrap | Tabbed card list |
| JS-10 | JS / App detail | 448 px, 85vh | `MyApplicationsView.tsx` | Center modal | Bottom sheet | Scrollable responsive dialog |
| JS-11 | JS / Withdraw | 384 px | `MyApplicationsView.tsx` | Center | Center | Alert dialog |
| JS-12 | JS / Attendance | 672 px | `AttendanceView.tsx` | Centered | Same stack | Stateful attendance card visuals |
| JS-13 | JS / Attendance confirm | 384 px | `AttendanceView.tsx` | Center | Center/bottom padded | Alert dialog |
| JS-14 | JS / Evidence | 672 px | `AttendanceView.tsx` | Centered | Same stack | Upload form visual |
| JS-15 | JS / History | 672 px | `AttendanceView.tsx` | Centered | Same list | Filtered card list |
| JS-16 | JS / Pending evaluations | 672 px | `EvaluationModule.tsx` | Centered | Same stack | Tabbed list |
| JS-17 | JS / Evaluate | 672 px criterion cards | `EvaluationModule.tsx` | Centered | Same one-column form | Rating form widgets |
| JS-18 | JS / Submitted | 672 px confirmation | `EvaluationModule.tsx` | Centered | Same | Success state page |
| JS-19 | JS / Eval history | 672 px | `EvaluationModule.tsx` | Centered | Cards wrap | Tabbed card list |
| JS-20 | JS / Eval detail | 448 px, 85vh | `EvaluationModule.tsx` | Center | Bottom sheet | Responsive dialog |
| JS-21 | JS / Report eval | 384 px | `EvaluationModule.tsx` | Center | Center | Alert/form dialog |
| JS-22 | JS / Messages | viewport−126; rail 288/320 | `ChatModule.tsx` | Two pane | List or conversation | LayoutBuilder master/detail |
| JS-23 | JS / Profile | 672 px, 56 px avatar | `JobSeekerView.tsx` | Centered | Same stack | Profile scroll view |
| JS-24 | JS / Edit profile | 672 px | `JobSeekerView.tsx` | Some 2-column fields | One column | Shared form sections |
| JS-25 | JS / Reputation | 672 px; 2→4 stats | `ReputationProfile.tsx` | 4 metrics | 2 metrics | Reputation composition |
| JS-26 | JS / Payments | 672 px; dialogs 448–512 | `PaymentModule.tsx` | Centered + modal | Stack + bottom sheets | Tabbed list/dialog shell |
| EMP-01 | EMP / Dashboard | 768 px; 2→4 stats | `EmployerView.tsx` | 4 stats | 2 stats | Centered dashboard column |
| EMP-02 | EMP / Job postings | 768 px | `JobPostings.tsx` | Full card actions | Wrap actions | Posting list widget |
| EMP-03 | EMP / Create job | 672 px grouped form | `JobPostings.tsx` | 2/3-column field groups | 1/2-column groups | FormSection widgets |
| EMP-04 | EMP / Edit job | Same as EMP-03 | `JobPostings.tsx` | Same | Same | Reuse exact create form visuals |
| EMP-05 | EMP / Preview | 512 px, 80vh | `JobPostings.tsx` | Center modal | Width-constrained modal | Scrollable dialog |
| EMP-06 | EMP / Location picker | 672 px; map 320 px | `LocationModule.tsx` | Centered | Same stack | Custom map surface |
| EMP-07 | EMP / Applicants | 768 px; 3→6 count grid | `JobPostings.tsx` | 6 counts | 3 counts | Pipeline card list |
| EMP-08 | EMP / Applicant profile | 512 px, 85vh | `JobPostings.tsx` | Center | Bottom sheet | Responsive dialog |
| EMP-09 | EMP / Reject | ~384–448 px | `JobPostings.tsx` | Center | Center/sheet | Destructive form dialog |
| EMP-10 | EMP / Workers | 672 px | `EmployerView.tsx` | Centered | Same list | Worker card list |
| EMP-11 | EMP / Worker reputation | 672 px, 90vh | `ReputationProfile.tsx` | Center | Bottom sheet | Large responsive dialog |
| EMP-12 | EMP / Attendance review | 768 px; filter 208 px at `sm` | `AttendanceReview.tsx` | Horizontal filters | Stacked filters | Review card list |
| EMP-13 | EMP / Attendance detail | 512 px, 90vh | `AttendanceReview.tsx` | Center | Bottom sheet | Responsive dialog |
| EMP-14 | EMP / Flag | 384 px | `AttendanceReview.tsx` | Center | Center | Destructive dialog |
| EMP-15 | EMP / Record payment | 672 px | `PaymentModule.tsx` | Paired fields | One column | Form sections |
| EMP-16 | EMP / Payment success | 672 px | `PaymentModule.tsx` | Centered | Same | Success subview |
| EMP-17 | EMP / Payment history | 672 px; 2→4 stats | `PaymentModule.tsx` | 4 stats | 2 stats | Summary + list |
| EMP-18 | EMP / Messages | viewport−126; 288/320 rail | `ChatModule.tsx` | Two pane | Master/detail replacement | Shared chat widget |
| EMP-19 | EMP / Company profile | 672 px | `EmployerView.tsx` | Centered | Same stack | Company profile scroll view |
| EMP-20 | EMP / Edit company | 672 px | `EmployerView.tsx` | Some 2-column fields | One column | Shared form sections |
| EMP-21 | EMP / Evaluations | 672 px + responsive modals | `EvaluationModule.tsx` | Centered | Same/bottom sheets | Shared evaluation widgets |
| EMP-22 | EMP / Reputation | 672 px | `ReputationProfile.tsx` | 4 metrics | 2 metrics | Shared reputation widgets |
| ADM-01 | ADM / Dashboard | 896 px; 2→4 metrics | `AdminView.tsx` | 2-column detail panels | Stack | Admin dashboard column |
| ADM-02 | ADM / Users | 896 px | `AdminView.tsx` | Row cards | Wrapped card rows | Responsive list card |
| ADM-03 | ADM / User profile | 512 px | `AdminView.tsx` | Center | Bottom sheet | Responsive dialog |
| ADM-04 | ADM / User action | 384 px | `AdminView.tsx` | Center | Center | Alert dialog |
| ADM-05 | ADM / Jobs | 896 px | `AdminView.tsx` | Row cards | Wrapped cards | Moderation list |
| ADM-06 | ADM / Remove post | 384 px | `AdminView.tsx` | Center | Center | Alert dialog |
| ADM-07 | ADM / Disputes | 896 px | `AdminView.tsx` | 2-column inner metadata | Stacked metadata | Dispute cards |
| ADM-08 | ADM / Dispute detail | 1024 px; 2+1 at `lg` | `AdminView.tsx` | Sticky side rail | One column | Responsive grid/column |
| ADM-09 | ADM / Request info | 512 px | `AdminView.tsx` | Center | Bottom sheet | Responsive form dialog |
| ADM-10 | ADM / Resolve | 512 px | `AdminView.tsx` | Center | Bottom sheet | Responsive form dialog |
| ADM-11 | ADM / Reject | 512 px | `AdminView.tsx` | Center | Bottom sheet | Responsive form dialog |
| ADM-12 | ADM / Reports | 768 px | `AdminView.tsx` | 4 stats/chart | 2 stats/stack | Custom chart + rows |
| RPT-01 | Report / Attendance | 794×min 1123 px | `AttendanceReport.tsx` | A4-like sheet | Same sheet compressed | Fixed report canvas/print layout |

---

# 10. Assets and recreation guidance

| Asset | Source fact | Export/recreate guidance |
|---|---|---|
| JobMate logo mark | Inline SVG in `Layout.tsx`; repeated inline in `AttendanceReport.tsx`. 32×32 viewBox, Brand 600 rounded square, white briefcase, 1.5 px strokes. | Recreate as Flutter `CustomPainter`/SVG asset from source geometry. There is no standalone logo file to export. |
| JobMate wordmark | Live text: Outfit bold “Job”; “Mate” teal or 75% white. | Recreate as rich text plus mark; do not rasterize. |
| Lucide icons | `lucide-react` imports throughout. | Use a Flutter Lucide package with matching icon names/stroke, or export exact SVG paths if package glyphs differ. No icon sprite is present. |
| WorkMap | Inline SVG-like React composition in `LocationModule.tsx`, 800×520 coordinates and literal colors. | Recreate with `CustomPainter`/SVG based on source. It is not an external map asset and cannot be “exported” from a Make file as a bitmap. |
| Map pins/popovers | HTML/CSS + inline colors/position percentages. | Recreate as Flutter overlays; preserve job-type palette and pin tails. |
| Avatars | Initials in deterministic colored circles; no profile photos bundled. | Recreate algorithmically. Do not invent photos. |
| Company/logo placeholders | Initials/gradient blocks; no external company-logo files identified. | Recreate with initials/gradient. |
| Background decoration | Auth translucent circles/blocks and gradients are CSS elements, not image files. | Recreate as positioned Flutter shapes/gradients. |
| Stars/progress/rings | Lucide stars, CSS bars, SVG circles. | Recreate as vector/icon/custom paint. |
| Static assets directory | No required product photography or image asset set was identified in inspected source. | Nothing to export. Evidence previews are local user-selected object URLs, not shipped assets. |

---

# 11. Visual reference capture plan

## 11.1 Automatic screenshot status

No screenshots were automatically generated. The available Figma screenshot tool supports Figma Design, FigJam and Slides URLs, but explicitly does not support Figma Make `/make/` files. No browser viewport screenshot capability was available in this run. Therefore this document does not claim visual screenshot verification.

## 11.2 Manual capture recommendations — not source measurements

Recommended comparison viewports:

- Desktop: **1440×900** (capture recommendation).
- Mobile Android-like: **390×844** (capture recommendation).
- Optional breakpoint checks: 640, 768 and 1024 px wide, matching actual source breakpoints.
- Hide/crop the 36 px development preview bar when evaluating product chrome, or clearly mark it as non-product.

### Priority manual checklist

1. Job Seeker Home — populated dashboard, 1440 and 390.
2. Employer Dashboard — populated dashboard, both sizes.
3. Admin Dashboard — both sizes, including mobile drawer.
4. Employer Job Posting Dashboard — status tiles, each posting status, card actions.
5. Create Job — top, every form section, action footer, AI generating/generated states.
6. Edit Job — prefilled state and exact parity with Create.
7. Job Preview — desktop centered and mobile-width modal.
8. Job Seeker Profile and Edit Profile.
9. Employer Company Profile and Edit Company.
10. Browse Jobs — filters collapsed/expanded, card hover at desktop, empty result.
11. Job Details and Apply modal/success.
12. My Applications — all tabs, detail modal and withdraw confirmation.
13. AI Recommendations — high/medium/low ring thresholds and apply modal.
14. Attendance — locating, checked-in, checked-out, confirmation, evidence, history.
15. Chat — list, selected conversation, incoming/outgoing groups, attachment, mobile master/detail transition.
16. Nearby Jobs — map, pin popup, list, detail; Employer location picker separately.
17. Evaluations — pending, criterion form, submitted, history, detail, report.
18. Reputation — Job Seeker, Worker modal, Company.
19. Payments — Job Seeker pending/history/detail/confirm/report and Employer record/success/history.
20. Admin Users — filters, profile modal, action confirmation.
21. Admin Disputes — list, detail collapsed/expanded, protected messages, all three workflow modals.
22. Admin Job Moderation and remove confirmation.
23. Admin Reports.
24. Authentication — all four states; Register for both account types; desktop and mobile.
25. Account Settings — home, three detail sections and both confirmations.
26. Static attendance report — screen and print preview.

For each capture, record viewport, state, active tab, scroll position, and whether pointer hover/focus is active. Use side-by-side pixel comparison only after Google Fonts finish loading.

---

# FLUTTER VISUAL REPRODUCTION GUIDE

## ThemeData and token architecture

Create one immutable visual token layer mirroring source names: Brand 50–900, Slate 50–900, semantic families, radii 4/6/8/12/16/full, one-pixel borders, and Tailwind shadow presets. Use Outfit as `ThemeData.fontFamily`; define explicit DM Serif Display and DM Mono styles. Avoid default Material 3 surface tint, elevation, field padding, and 48 px minimum controls where those alter the source appearance; wrap controls with exact constraints while retaining adequate semantic/tap behavior invisibly where possible.

A practical theme mapping follows. Brand, body, logo and inline-SVG hex values below are source literals. For Tailwind default-palette classes, extract the current compiled/computed color instead of treating a familiar legacy hex conversion as source truth.

- `scaffoldBackgroundColor`: `#f8fafc`.
- Primary: `#0d9488`; hover: `#0f766e`; pressed: `#115e59`.
- Default card/dialog surface: `#ffffff`.
- Strong text/body default: source literal `#0f172a`; secondary body, muted and subtle text use the exact classes `slate-700`, `slate-600`, `slate-500` and `slate-400`.
- Default card border uses `slate-200`; stronger input border uses `slate-300`. `#e2e8f0` is a source literal for the trust-ring track and `#cbd5e1` is a source literal for the thin scrollbar, but the utility classes must still be resolved from the installed build.
- Focus: 2 px `#14b8a6` and field border `#2dd4bf`.

## Responsive shell

Drive the shell from the exact 768 px breakpoint. At ≥768 px, reserve a fixed 240 px sidebar and keep the 56 px top bar. Below it, use the 56 px mobile top bar, 256 px drawer and non-admin five-item bottom nav. Do not include the 36 px Figma Make preview bar. Respect safe-area padding below the bottom nav while keeping source content spacing visually equivalent.

Use width constraints per screen, not one application-wide maximum: 672 px standard, 768 px dashboard/map/reporting, 896 px admin lists, 1024 px dispute detail. Center each constraint after shell padding. At 1024 px, create the admin 2+1 dispute grid and auth 420 px brand panel.

## Cards, tables, filters and forms

- Build a base card with white surface, 12 px radius, 1 px Slate 200 border and 16 px padding; opt into 20 px only where source says `p-5`/`md:p-5`.
- Keep card heights intrinsic. Dynamic Supabase text should wrap in the same hierarchy; use ellipsis only where source uses truncation.
- Implement status chips from one semantic map. Do not convert every chip to brand teal.
- Forms use 14 px Outfit, 8 px radius, 1 px Slate 300 border and 10 px vertical/14 px horizontal padding. Focus is a 2 px teal ring. Errors add Red 400 border/ring and 12 px Red 600 text.
- Preserve grouped form sections for EMP-03/04. Avoid a long ungrouped Material form.
- Admin “tables” are mostly responsive card rows. Do not force a desktop `DataTable` if it changes borders, row heights, typography or mobile stacking.
- Filters wrap at content width; at `sm` some rows become horizontal. Match selected fills, not just selected text.

## Mobile layout and overlays

At base width, preserve one-column order and source spacing. A responsive dialog should become a bottom sheet only for source frames that use `items-end` and `rounded-t-2xl`; compact confirmations that are centered in source should remain centered. Use 16 px top/all-corner radius and match 384/448/512/672 px max widths. Respect 85/90vh scrolling limits and keep close/title regions visually stable.

For chat, implement true master/detail replacement below 768 px and two panes above it. For nearby jobs, retain map/list mode rather than creating a desktop split view. For the report, keep the fixed sheet model rather than inventing a mobile report.

## Dynamic Supabase data without visual drift

- Keep skeleton, empty, populated and error widgets at stable positions. Only use source-designed empty/error visuals; product-required new states should be marked as additions during implementation review.
- Constrain unpredictable names, job titles, IDs, amounts and message text with the same wrap/truncate rules. Test longest realistic values and text scaling.
- Preserve DM Mono for changing numeric data so digit widths and alignment match.
- Keep cards content-driven rather than fixing heights from sample data.
- When lists paginate or stream, retain 12–16 px item gaps and avoid Material default dividers unless source has borders/dividers.
- Remote images should fall back to the source initials avatar, not a new generic silhouette.

## Reusable Flutter widgets

Recommended foundation: `JobMateMark`, `JobMateWordmark`, `JobMateShell`, `SidebarNavItem`, `BottomNavItem`, `JmButton`, `JmTextField`, `JmSearchField`, `StatusPill`, `InitialAvatar`, `TrustScoreRing`, `StatCard`, `JobCard`, `ApplicantCard`, `SectionHeader`, `EmptyState`, `ErrorState`, `CardSkeleton`, `ResponsiveSheet`, `FilterChip`, and `SegmentedTabs`. Then add module components for posting sections/cards, rating picker, attendance records, payment cards/proof chips, chat bubbles, WorkMap, and reputation sections.

Keep widget APIs visual-first but data-agnostic. Existing Flutter/Supabase actions should be passed as callbacks; the visual widgets should not reproduce React timers or mock state.

## Screen-specific fidelity risks

- **EMP-02–05:** highest priority. Reuse the exact 768/672 px constraints, grouped card sections, 2/3-column choice grids, status summaries, posting card hierarchy and 512 px preview rather than adapting Flutter defaults.
- **Typography:** DM Serif headings and DM Mono values create much of the identity. Outfit everywhere will look materially different.
- **Chat:** pane width, viewport-relative height, bubble width/corners and mobile replacement are defining.
- **Maps:** WorkMap is an illustration, not a live provider. If the functional Flutter app uses a real map, reproduce control/pin/popup styling on top while acknowledging the basemap itself cannot pixel-match the illustration.
- **Reputation/match rings:** use custom painting with source stroke proportions and thresholds.
- **Dialogs:** source mixes bottom sheets and centered alerts; do not unify them indiscriminately.
- **Report:** use a fixed print layout and explicit page/print testing.

## Verification and report

- **Generated file:** `JOBMATE_EXACT_UI_DESIGN_HANDOFF.md`.
- **Screens/subviews documented:** **71** total — 4 AUTH, 6 ACC, 26 Job Seeker, 22 Employer, 12 Administrator, and 1 static report.
- **Reusable components/patterns identified:** **35** — 15 exported shared UI primitives plus 20 shell/module-local reusable patterns.
- **Exact measurements:** shell (240 px sidebar, 256 px drawer, 56 px top bar), auth (420/384 px), shared max widths (672/768/896/1024 px), dialogs (384/448/512/672 px and 80/85/90vh variants), chat (`100vh−126px`, 288/320 px rail), maps (360/320 px), report (794×min 1123 px), logo geometry, shared primitives, breakpoints, spacing/radius/type utilities and source inline values.
- **Class-derived measurements:** all screens use exact Tailwind classes for padding, gaps, typography, borders, colors, radius and responsive changes. Their conversion is exact for this Tailwind v4 project, but many card/control heights are intentionally CONTENT-DRIVEN.
- **Inferred-only dimensions:** none are presented as source exact. Approximate tap heights, rendered multiline heights, font rasterization, modal content height and safe-area-added bottom-nav height require runtime measurement/manual screenshots.
- **Manual screenshots required:** all visual comparisons; priority is the 26-item checklist in section 11, especially Job Seeker Home, all role dashboards, EMP-02–05, profiles, browse/applications/AI/attendance/chat/nearby/evaluation/reputation/payment, Admin Users/Disputes, auth/account, and report print preview.
- **Missing/ambiguous:** no dark mode; no exact live-map provider visual; no real photos; no designed network/offline/permission states for most modules; no email verification/OTP/reset-password/admin registration; no real verification lifecycle; several no-op actions; content-driven heights; browser font synthesis for bold DM Mono; backend-driven long-content edge cases.
- **Source files actually inspected:** `src/App.tsx`, `src/index.css`, `src/components/Layout.tsx`, `src/components/UI.tsx`, `src/views/AuthView.tsx`, `src/views/AccountSettings.tsx`, `src/views/JobSeekerView.tsx`, `src/views/EmployerView.tsx`, `src/views/AdminView.tsx`, `src/views/jobseeker/JobsView.tsx`, `AIRecommendationsView.tsx`, `MyApplicationsView.tsx`, `AttendanceView.tsx`, `src/views/employer/JobPostings.tsx`, `AttendanceReview.tsx`, `src/views/shared/ChatModule.tsx`, `EvaluationModule.tsx`, `LocationModule.tsx`, `PaymentModule.tsx`, `ReputationProfile.tsx`, `src/views/reports/AttendanceReport.tsx`, plus `JOBMATE_FIGMA_UI_SPEC.md` for ID reconciliation.
- **Unavailable verification:** automated Make screenshots/browser viewport captures were unavailable; no screenshots are claimed. No live backend, map provider, Supabase, network behavior or device-specific Android font rasterization was verified.
- **Executed verification:** `pnpm build` completed successfully with Vite 8.0.3 (1,810 modules transformed). Vite emitted a non-failing warning that the JavaScript chunk exceeds 500 kB; this documentation-only change does not alter that bundle.
- **Formatting:** no Markdown formatter was run; repository guidance identifies `oxfmt` but does not confirm Markdown-safe invocation or prescribe it for documentation.

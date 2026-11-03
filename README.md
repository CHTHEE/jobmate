# JobMate

## 1. Project Overview

JobMate is a Final Year Project (FYP): an AI-assisted recruitment and workforce management platform developed collaboratively with Flutter and Dart for **Web and Android**. Supabase provides authentication, database access, storage and Edge Functions. Gemini integration is intended to run through a Supabase Edge Function, keeping AI credentials off the client.

### Implemented in this checkout

- Authentication flows for sign-in, registration, email verification and password recovery/change.
- Role-aware dashboards, personal profiles, document submission, company onboarding and company verification submission/history.
- Administrator invitation/access, permissions, user management and company review screens; notifications with read tracking.
- Employer job listing/filtering, creation, preview, draft saving, publication, published-job editing and closing. Closed jobs are not editable.
- AI formatting client integration: invokes `format-job-description`, validates responses, keeps generated sections editable and displays recoverable errors.

These are codebase capabilities, not confirmation that every workflow works against the deployed backend. The formatting Edge Function source is **absent from this checkout**; its deployment and Gemini configuration require team confirmation.

### Planned features

Modules 2–10 now have explicitly labeled demo UI environments for the screens
described below; these are not completed backend integrations. Phase 4 adds
evaluations, reputation fixtures, external-payment records and an admin UI
sandbox. Module 1 retains real account/verification flows with new settings and
separate presentation previews. Employer Job Posting remains connected to the
existing Supabase workflow. Other platform folders exist, but the project targets
Web and Android.

### Structure and routing

| Location | Purpose |
| --- | --- |
| `lib/main.dart` | Startup, environment loading, Supabase initialization, GoRouter and app theme |
| `lib/shared/navigation/app_routes.dart` | Central route paths |
| `lib/shared/widgets/` | Workspace shell, responsive layout, authentication styling, startup/loading UI and native back helpers |
| `lib/features/` | `auth`, `home`, `profile`, `company`, `jobs`, `admin`, `notifications` |
| `lib/features/jobs/` | Forms/list/preview, repository, validation and AI response/error handling |
| `supabase/migrations/` | Employer registration and administrator/company-review migrations; not a complete backend bootstrap |
| `supabase/functions/admin-invitations/index.ts` | Checked-in administrator access-check Edge Function implementation |
| `test/` | Startup, authentication UI, workspace, jobs and company-review tests |
| `web/`, `android/` | Target platform projects |

The app uses `MaterialApp.router` with `go_router`, authentication redirects and an auth-state refresh listener. Job routes include `/job-postings`, `/job-postings/create` and `/job-postings/:jobId/edit`; the list reads a `status` query parameter. Preserve this routing system. Authentication email state is transient in-memory state rather than URL data, so not every in-progress flow survives refresh.

## 2. Project Setup

### Prerequisites

- Flutter SDK with bundled Dart satisfying `^3.13.5`, as declared in `pubspec.yaml`.
- Chrome for the Web command below.
- Android SDK/toolchain and an emulator or connected device for Android.
- Access to the team's existing Supabase project and public client configuration. The app depends on existing tables, RPCs, storage buckets, policies and deployed functions; this checkout is not a standalone backend provisioning guide.

From the project root:

```sh
flutter doctor
flutter pub get
```

### Environment configuration

Copy `.env.example` to `.env` unless a local `.env` already exists. In PowerShell, use `Copy-Item .env.example .env`. Populate only the existing variables using the team's project:

```dotenv
SUPABASE_URL=https://YOUR_PROJECT.supabase.co
SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

`flutter_dotenv` loads `.env` at startup, and `pubspec.yaml` bundles it as an asset. Its contents are visible to client users: **only public client configuration belongs here**. Startup reports missing or empty configuration. `.gitignore` excludes `.env` and local variants while retaining `.env.example`.

Gemini API keys must remain server-side in **Supabase Edge Function Secrets**. Never put them, service-role keys or private credentials in Flutter assets, Dart code, browser requests or documentation. The formatting function's secret names and deployment procedure cannot be confirmed from this checkout; do not invent them or create a replacement Supabase project.

### Run Flutter Web

```sh
flutter run -d chrome
```

### Run Flutter Android

Start an emulator or connect a device, then find its ID and run:

```sh
flutter devices
flutter run -d <android-device-id>
```

Replace the placeholder with the actual device ID. Current startup uses `.env`, not `--dart-define`.

## 3. Web vs Android UI/UX Requirements

These are mandatory development conventions, not a claim that every existing screen already satisfies them.

### General principles

- Share business logic, validation, authentication and the Supabase backend across platforms. Keep branding, terminology, colors and functionality consistent.
- Use `kIsWeb` for actual platform behavior; use responsive layout constraints for screen-size adaptation. A narrow screen does not mean Android; a wide screen does not mean Web.
- Reuse `LayoutBuilder`, `ResponsiveLayout`, `ResponsiveContent` and existing workspace patterns where appropriate. Shared responsive breakpoints are 600 and 1024 logical pixels; `AppWorkspace` switches between sidebar and drawer at 1024.
- Avoid horizontal overflow and inaccessible controls.

### Web requirements

- Use responsive desktop-friendly layouts with suitable maximum content widths. Prefer sidebar, navigation rail or existing desktop navigation where appropriate.
- Do not stretch mobile-style full-width forms across large desktop screens. Size forms and dialogs appropriately for desktop.
- Avoid redundant top-left AppBar back arrows when clear in-app navigation exists. Provide Cancel, Back to Job Postings, breadcrumbs or sidebar navigation as appropriate. Never rely exclusively on browser Back.
- Preserve browser Back, Forward, refresh and direct URL navigation through the existing router. Verify authentication and route-state behavior rather than assuming every flow survives refresh.
- Protect unsaved changes when leaving forms where feasible, including browser navigation where supported.
- Support mouse, keyboard, Tab navigation, visible focus indicators and appropriate hover states. Mobile-only interactions must not be the only way to access a feature.

### Android requirements

- Use touch-friendly layouts, comfortably sized targets and mobile-appropriate dialogs, spacing and navigation.
- Keep contextual AppBar back arrows on pushed detail, create and edit screens where appropriate. Respect Android system Back.
- Use scrollable forms that remain usable when the keyboard opens. Respect SafeArea and system insets.
- Do not rely on hover-dependent controls. Protect unsaved changes when navigating back.

### Back navigation rule

Web should hide redundant AppBar back arrows where existing desktop navigation provides a clear alternative. Android should retain contextual AppBar navigation on pushed screens. Never remove the only practical way to leave a screen.

Web sidebar destinations, including Personal Profile, Company Profile and My Job Postings, must not show redundant top-left AppBar back arrows. `AppWorkspace` disables inferred leading controls on Web and explicitly retains the navigation menu at narrow widths. Directly opened pages can use the sidebar or drawer to reach Dashboard. Native platforms retain Flutter's existing inferred leading behavior; explicit form back actions and unsaved-change guards remain in effect.

Inspect `main.dart`, `AppRoutes`, `AppWorkspace`, `MobileBackAction` and the affected screen before changing navigation. Reuse GoRouter and safe navigation patterns. Never call `Navigator.pop` blindly on a potentially initial or directly opened route: check whether it can pop and provide a safe route fallback where needed. The job form already has a list-route fallback after saving when it cannot return to the originating list.

Check unsaved-change handling before changing back navigation. The job form confirms before discarding changes through its back action, workspace navigation or GoRouter route exit, including router-supported browser Back. Saving and AI formatting block navigation. Browser refresh, tab closing and leaving the site are not covered by this route guard. The form hides the Web back arrow, retains native back navigation, and provides Back to Job Postings plus an expandable example description.

### Phase 1 UI foundation

`lib/shared/theme/jobmate_theme.dart` owns the shared teal/neutral palette and
Material input, button, card and dialog defaults. `AuthStyle` layers the existing
authentication typography and full-width primary actions over these defaults;
`AppWorkspace` reuses that layer and the existing responsive padding helper.
Buttons have a 48 logical-pixel minimum target; cards/controls use 12 px corners
and dialogs use 16 px corners. Existing feature overrides remain supported.

The audit found reusable `AuthField`, `AuthWordmark`, `WorkspaceCard`,
`WorkspaceStatus`, `WorkspaceInfo`, `LoadingOverlay`, `ResponsiveContent` and
job preview/confirmation patterns. These remain in use rather than adding a
parallel component library. The existing GoRouter sidebar/drawer navigation,
mobile profile entries and job dirty-form guards remain unchanged.

`JOBMATE_FIGMA_UI_SPEC.md` is a visual reference only. Flutter retains its
600/1024 breakpoints rather than adopting the prototype's 768 px sidebar switch.
Outfit, DM Serif Display and DM Mono are not bundled in this checkout; existing
font requests use available platform fallbacks. Exact font assets, broader
feature heading/stat/error-state consolidation, responsive modal presentation
and remaining module layouts are deferred. No prototype data, simulated
authentication/AI, backend contracts or new modules are introduced by this pass.

Profile/company navigation currently uses existing edit/busy locking; this is
not a general dirty-form guard. Refresh/tab-close protection also remains outside
the existing job route guard. Those limitations need separate scoped work.

## 4. Employer Job Posting Requirements

**Original Description** is the employer's own unstructured input. Employers should include the role's purpose, duties, actual qualifications/experience, location and work arrangement, employment type, salary details, benefits, vacancies and deadline where known. Structured fields must agree with these facts. Missing facts must come from the employer.

- **Format with AI** generates Role Overview, Responsibilities, Requirements and Benefits. The client currently requires at least 30 trimmed characters in Original Description.
- Generated content remains editable. AI formatting must never overwrite Original Description. Replacing existing generated-section content requires confirmation.
- Employers must review and correct AI output before publishing. Never fabricate qualifications, salaries, benefits or other job facts. Manual editing remains available without AI.
- Preserve `draft`, `published` and `closed` workflows, publication validation, company scoping and status checks preventing edits to jobs closed elsewhere.
- Preserve active-employer account checks, owner/employer membership requirements and company-verification checks. Client checks complement backend authorization and RLS; they do not replace them.
- Preserve input during AI errors and allow manual editing/retry. Existing error handling distinguishes expired sessions, denied access, rate limits, temporary service failures, malformed responses and connection errors.
- While AI formatting is pending, a full-page dimmed loading panel keeps the form visible and blocks pointer/keyboard interaction and router-supported Back/navigation. The panel uses actual request state, with a 60-second timeout rather than simulated progress. Success fills the four editable sections; failures/timeouts retain all values and allow retry, and late timed-out responses are ignored. Browser refresh and tab closing remain outside the route guard.

The repository sends `original_description` to `format-job-description`. The client expects a nonempty string `role_overview` and string arrays `responsibilities`, `requirements` and `benefits`. Coordinate backend changes against this existing contract.

### Phase 2 — Module 2 UI and data boundaries

Implemented routes:

| Route | Screen | Data |
| --- | --- | --- |
| `/jobs` | Search/filter/sort and session-saved jobs | Fictional demo catalogue |
| `/jobs/:jobId` | Job details and responsive Apply modal | Demo only |
| `/applications` | My Applications, All/Active/Completed, search/status filters | Shared session demo |
| `/applications/:applicationId` | Application details, timeline, withdraw and offer actions | Shared session demo candidate |
| `/applicants` | Employer pipeline, posting/status filters, search/sort | Fictional candidates only |
| `/applicants/:applicationId` | Applicant details, stage actions, rejection note | Shared session demo |
| `/applicants?posting=<jobId>` | Entry from a real employer posting | Explicit unconnected state; separate demo exploration |

The existing employer list/create/edit/preview/draft/publish/close screens are
reused. Registration/login, company verification/logo access, ownership checks,
job repositories/validation and `format-job-description` are unchanged. The new
route gate reads the existing signed-in `users.role` and `users.status`, requires
an active Job Seeker or Employer as appropriate, and provides loading/error/retry
and Dashboard exits. Existing auth redirects remain in place. This UI gate does
not replace RLS or grant employer access to real applicant records.

**Why Browse Jobs is demo-only:** inspection found no Job Seeker/public job-read
service and no checked-in `job_postings` policies or public projection. The
existing repository is for employer-scoped management and selects full rows.
Reusing that path for public browsing would not establish permission or salary
privacy. No new Supabase job read is attempted. The deployed public-read and
salary-protection rules remain unverified; this is an integration/security review
blocker, not a confirmed deployed vulnerability. If an unauthorized client can
select hidden compensation, UI hiding cannot fix the exposure. Before enabling
real browsing, verify existing grants/RLS and a server-enforced safe projection
that omits hidden salary values. RLS alone does not redact individual columns.

The demo `BrowseJob` display projection keeps existing posting field names and
list formats and excludes `salary_min`, `salary_max` and `salary_period` unless
`salary_visible` is exactly true. Cards/details never render hidden compensation.
Only published sample jobs appear in browsing; expired samples are labeled and
cannot receive applications. Closed/missing direct detail routes show unavailable
states. Company verification and trust scores are not fabricated.

`Module2Repository.session` is one in-memory `ChangeNotifier`, shared by all new
screens. Saved jobs, duplicate checks, stage changes, summary counts and timelines
use that same source. Candidate/Employer pages are two views into a fictional
environment, not relationships between real accounts and jobs. Changes reset on
refresh/restart or sign-out/account change. New applications are attributed to
the explicitly fictional “Demo candidate (you)”; the signed-in profile/resume is
not read, attached or uploaded. Sample resume availability never enables a fake
download. No application success message claims server submission.

Canonical demo statuses are Applied → Shortlisted / Reviewing → Interview →
Offered → Hired. Figma’s Reviewing and Shortlisted map to the single
`ApplicationStage.shortlisted` state. Employers can reject any nonterminal stage;
only the next forward stage is enabled. Job Seekers may withdraw before Offered,
accept an offer as Hired, or decline it as Withdrawn. Hired/Rejected/Withdrawn are
terminal and comprise Completed; all other statuses are Active. Offer acceptance
does not create an assignment. These are UI demo rules, not a deployed API
contract. Internal rejection notes are shown only in the employer demo view;
production privacy still requires server authorization and separate note access.

Navigation retains the existing 1024 px sidebar/drawer switch and adds compact
bottom navigation for Home, Jobs/Posts, Applications and Profile/Company. Both
profiles remain in the drawer. Main Web destinations omit back arrows; detail
pages have explicit return actions and native contextual Back with safe direct
route fallbacks. Apply/rejection forms use a centered desktop dialog or compact
scrollable sheet with keyboard insets, explicit Cancel, discard confirmation and
local note drafts retained if route navigation disposes the modal. Unsubmitted
notes are restored when reopened in the same session; explicit discard clears
them. Refresh/tab close still resets the demo. Actual saving state drives the
application progress UI; no fake network timers are used. Local catalogue/list
reads are synchronous and do not simulate network loading or failures.

Later backend integration needs confirmed application storage and unique
job/candidate constraints, transactional status history and transition rules,
separate employer-only notes, ownership/candidate RLS, resume storage and signed
access, saved-job persistence and offer decisions. Table/service names and schema
must be agreed from the actual backend; prototype proposed entities are not
contracts. Deadline/status/session checks must be enforced server-side at
submission and transitions. Notification/assignment integration belongs to later
scoped work. **No tables, policies, migrations, buckets, Edge Functions, secrets or
Dashboard changes are created or required by this UI demo.**

Focused coverage is in `test/module2_test.dart`: filtering/sorting, salary
projection, status mapping/invalid transitions, duplicates, expiry, cross-role
state/history, reset, access states, responsive pages/modals, internal-note
visibility and direct-route fallback. Run `flutter test test/module2_test.dart
test/workspace_test.dart test/job_postings_test.dart`. Platform acceptance and
live Supabase/AI behavior still require separate verification.

### Phase 3 — Modules 3, 4, 5 and 10

All screens below use **DEMO data only**, except the existing authentication and
active-role check reused from `Module2Gate`. No new Supabase job/profile reads,
mutations, uploads, AI calls, GPS calls, notifications or Realtime subscriptions
are introduced. Existing login, company verification/logo, employer posting and
Gemini formatting paths remain unchanged. No Dashboard steps are required.

| Figma screen | Route / entry | Implemented presentation |
| --- | --- | --- |
| JS-05 | `/recommendations` | For You, transparency banner, deterministic match rings/labels, skill overlap/gaps, explanation, city/type/category/minimum-score filters and score/title sorting |
| JS-06 | Apply on a recommendation | Existing Module 2 responsive Apply form, same saves, application checks and session repository |
| JS-12 | `/attendance` | Sample active assignment, schedule, simulated location check, device clock, elapsed time and check-in/out |
| JS-13 | Check In / Check Out | Explicit confirmation; duplicate/invalid transitions rejected |
| JS-14 | `/attendance/evidence` | Required work description and 1–5 local PNG/JPEG/PDF files, picker, thumbnails/metadata preview, removal, draft retention, validation and demo submission |
| JS-15 | `/attendance/history`, `/attendance/:recordId` | Search/job/status filters, completed/issues states, cards and connected attendance details |
| EMP-12 | `/attendance-review` | Employer summary counts, pending/completed records, job/status filters and search |
| EMP-13 | `/attendance-review/:recordId` | Worker schedule, device timestamps, evidence, note and sample review decision |
| EMP-14 | Flag Work on a pending completed record | Required reason with retained draft and explicit confirmation; Verify requires evidence |
| RPT-01 | `/attendance/:recordId/report`, `/attendance-review/:recordId/report` | Responsive report derived from that same session record, plus a separate printable HTML view on Web |
| JS-22 | `/messages`, `/messages/:conversationId` | Conversation search/unread indicators, job context, grouped messages, local text/attachments and simulated receipts |
| EMP-18 | `/employer-messages`, `/employer-messages/:conversationId` | Employer view of the same fictional conversation history |
| JS-07 | `/nearby-jobs` | Map/list toggle, sample city filter, 2/5/10/25/50 demo km radius, type filter, markers, radius visualization and cards |
| JS-08 | `/nearby-jobs/:jobId` | Fictional workplace address/distance, job facts, demo map and existing Module 2 View Job / Apply navigation |
| EMP-06 | `/job-location-demo` | Standalone address input/sample suggestions, tap/drag marker, keyboard-accessible X/Y sliders and Confirm Location |

New destinations are exposed through each role's existing sidebar/drawer. Compact
bottom navigation and Profile/Company access remain. Main Web destinations omit
inferred back arrows; nested pages have return actions and native contextual Back
with direct-route fallbacks. Chat uses a split view when its available content
width is at least 800 px; narrower layouts show the list or selected thread.
Keyboard-open forms scroll with the existing shell/sheet patterns.

`Phase3Store.session` is one in-memory `ChangeNotifier` for attendance, evidence,
chat and the location sandbox. It resets alongside Module 2 on account changes
and on app restart/refresh. Fictional assignments are independent of real users
and Module 2 hiring decisions; no assignment is created by accepting a demo offer.
Evidence and unsent chat text/files, flag reasons and the address draft survive
in-app navigation for the session. Explicit evidence draft discard confirms
first. Cancel on the flag dialog retains the reason draft. Local file reads show
actual reading state, validate file size/header and expose recoverable errors;
late picker results are ignored after disposal/account reset. Selection is capped
at five files, each at most 5 MiB. Images have local previews; PDFs have metadata
previews rather than an embedded PDF viewer. Files are never uploaded.

The active-role gate supplies loading/error/retry/denied states. Local demo lists
are synchronous rather than imitating a network delay. Empty/filter/unavailable
states are implemented. Attendance uses the device clock, not an authoritative
server timestamp; the 15-minute late grace is a **demo rule**. Simulation of a
location check does not request GPS permission or prove presence. Employer
Verified/Flagged labels are local review decisions and have no legal standing.
Report printing opens a local escaped HTML document with print CSS and the
browser's Print / Save as PDF action; blocked popups can be retried. Native
printing/PDF export is unavailable and labeled accordingly.

Recommendation scoring is deterministic: 70 × matched sample skills / required
sample skills, plus 20 for the sample Shah Alam preference, plus 10 for part-time,
rounded to a whole percentage. Sample skills are communication, willingness to
learn and retail. Requirements are the demo job's skill-like requirements plus a
documented category illustration (retail, Dart/Flutter, customer service or event
setup); this is not an inferred production job-skills contract. Labels consistently
use Excellent ≥90, Strong ≥75, Good ≥60, otherwise Fair. No protected attributes,
real profile, work history or actual AI service is involved. Save and Apply reuse
the Module 2 repository; existing application status mapping remains unchanged.
No company rating/trust score is invented.

Chat is between fictional role personas, not signed-in accounts. Enter sends and
Shift+Enter inserts a newline; an explicit Send button supports touch. Attachment
drafts and sent files stay in memory. Opening a thread marks sample incoming
messages read; a labeled control advances Sent → Delivered → Read for sample
outgoing messages. Every receipt is visibly simulated; there is no actual online
presence or automated fake reply. Search, unread counts and messages share one
source across both role views. No administrator chat interface is added.

Nearby distance is Euclidean distance in a fixed fictional kilometre grid, not
from a user's position. Radius changes update the same markers/list. The location
input filters sample city names; it does not geocode. Remote jobs have no
workplace marker and remain accessible in Browse Jobs. Closed jobs are excluded;
expired jobs are labeled and Module 2 prevents applying. Current GPS location and
directions controls explain that those services are unavailable. The employer
picker uses **DEMO GRID X/Y out of 100**, never fictional geographic degrees.
Its confirmed address/marker are isolated from `job_postings.location`,
`latitude` and `longitude`; it cannot update a real posting.

Figma inconsistencies resolved: percent-based map coordinates are no longer
mislabeled latitude/longitude; placeholder View Job/Evidence/History actions now
open actual local views; the static RPT-01 uses current session records instead
of unrelated identities/dates; recommendation thresholds use one definition;
fake online/GPS/legal-verification claims and reputation scores are omitted.
Real feature logic takes precedence over prototype simulation. Existing fallback
fonts and teal/slate/white Material styling are reused without dependencies.

#### FUTURE BACKEND INTEGRATION — Module 3

Needs agreed logical storage/contracts for recommendation runs, per-job scores,
input snapshots, explanations and skill gaps; candidate-owned access and safe
published-job reads with server-enforced salary privacy. Decide profile/skills
consent, retention, model/provider, versioning, bias evaluation, cost/rate limits
and fallback ranking. A separate authorized server-side recommendation service or
Edge Function may call an approved AI provider. It must not repurpose or change
the working `format-job-description` Gemini contract. No new secrets or endpoints
are configured here; physical table/function names require schema review.

#### FUTURE BACKEND INTEGRATION — Module 4

Needs agreed assignment/shift, attendance event/location, evidence metadata,
verification/flag and report entities. Enforce assigned-worker reads/writes and
owning-employer review with RLS and server-side status transitions, immutable
server timestamps, idempotency and correction/dispute rules. Evidence needs a
private Storage bucket, owner/membership policies, signed URLs, type/size/content
validation, scanning, retention/deletion and upload recovery. Location requires
permission/accuracy/source capture and an agreed geofence/anti-spoofing policy;
device timestamps cannot prove presence. Decide authoritative report generation,
access control and PDF/signature requirements, potentially using an Edge Function.
These are proposed logical needs, not existing schema or legally valid records.

#### FUTURE BACKEND INTEGRATION — Module 5

Needs conversation/participant, message, attachment, receipt and audited-access
entities, server-created job-linked membership, participant-only RLS and Realtime
authorization. Define pagination, retries/idempotency, offline handling, receipt
permissions, presence semantics and notification consent. Attachments need private
Storage with membership checks, signed access, scanning and retention. Any admin
dispute access must be explicitly authorized and audited server-side; a UI warning
alone is insufficient. No admin audit feature, Realtime channel or bucket is
created here. Provider and physical schema decisions remain open.

#### FUTURE BACKEND INTEGRATION — Module 10

Needs approved job-location/preference/geocoding-cache contracts or verified use of
existing posting location fields, owner-only writes, safe public workplace reads
and location privacy/retention policies. Choose/configure Google Maps or another
approved maps, geocoding and directions provider, API restrictions/billing and
error/rate-limit handling. API credentials and any server proxy/Edge Function must
be designed separately. Store genuine latitude/longitude/provider identifiers
only after validating geocoding/manual selection, and calculate distances with
an agreed geographic method. Browser location needs a secure context and consent;
Android foreground approximate/precise permissions require explicit request and
denial handling. No background tracking is implied. No keys, permissions,
Supabase configuration or Dashboard steps are introduced in Phase 3.

Phase 3 tests are in `test/phase3_test.dart`: deterministic scores, attendance and
evidence transitions, flag validation, escaped report HTML, shared chat state,
grid/radius semantics, reset and responsive screen coverage at 320/768/1440 px.
Run with the existing Module 2/workspace/job-posting regression suites. Automated
layout tests do not establish real-device, GPS, live backend or print-dialog
acceptance. Modules 1, 6, 7, 8 and 9 remain outside Phase 3.

Validation snapshot for this Phase 3 pass: all 49 new tests pass, including
320/768/1440 px layouts and role navigation. The full suite has 158 passing tests
and the same two pre-existing failures: the stale registration
`CheckboxListTile` lookup and counter smoke test that omits router startup.
`flutter analyze` reports the existing eight auth/home/profile diagnostics and
none in the Phase 3 code. Formatting and local Web compilation pass. Chrome
runtime tests stalled at startup and were stopped; no Android device is connected.
Native pickers, browser print dialogs, device keyboard/system Back and deployed
Supabase/Gemini acceptance still need manual verification.

### Phase 4 — Account UI, Evaluations, Reputation, Admin and Payments

#### Audit and teammate preservation

The working tree already contained uncommitted Phase 3 screens/navigation/docs
when Phase 4 began; they were retained. Inspection confirmed the actual Phase 3
recommendation, attendance/report, chat and nearby/location-picker files exist.
No teammate auth/profile/company/backend file was replaced with mock logic.

Existing Module 1 UI already covers login, role selection/registration, email
verification, forgot-password OTP, actual password reset/change, personal profile
view/edit/avatar, personal documents/history, company onboarding/logo, review
status/rejection/resubmission history, terms/privacy and sign-out. These are reused
through navigation. Actual profile edits still update only the existing supported
fields. Company editing remains available only during onboarding or rejected-owner
resubmission under the existing `_eligible` rule; verified/pending companies do not
gain new editing rights. KZ's admin dashboard, real user directory RPC, permissions,
invitations and company-review gateway remain intact. Only two navigation tools
were added to that dashboard (UI Sandbox and Account Settings), with formatter-only
changes elsewhere in that file. No real admin metrics were replaced by samples.

#### Screens and routes

| Module / Figma | Route / entry | Real versus demo |
| --- | --- | --- |
| 1 / ACC-01–03 | `/settings`, `/employer-settings`, `/admin-settings` | Real own-account summary/completion and links to existing profile/company/password/terms/privacy flows; confirmed local Supabase sign-out is real |
| 1 / ACC-04 | Notification switches within Job Seeker/Employer Settings | Session-only preference preview, explicitly no real delivery change |
| 1 / ACC-05–06 | Account actions within Settings | Real sign-out confirmation; deletion information/disabled Delete action, no deletion endpoint |
| 1 / JS-24 | `/profile-preview` | Fictional extended profile: display name, bio (250), location, availability, up to ten skills/five categories, optional local PDF resume |
| 1 / EMP-20 | `/company-preview` | Fictional company presentation editor; no real company update or verification badge |
| 6 / JS-16–21 | `/evaluations`, `/evaluations/:assignmentId/rate`, `/evaluations/:assignmentId` | Pending/history, rating form, success, given/received details and report modal; all demo |
| 6 / EMP-21 | `/employer-evaluations` and corresponding detail/rate routes | Same local workflow with worker-specific criteria |
| 7 / JS-25, EMP-22 | `/reputation`, `/employer-reputation` | Illustrative 0–100 score/factor/trend fixtures, visible demo evaluation average and insufficient-data view |
| 8 / existing ADM-01–02 | Existing Dashboard and `/admin-users` | Existing real statistics and read-only account directory remain authoritative |
| 8 / missing ADM-03–04 | `/admin-preview/accounts` | Separate fictional search/filter/detail and restrict/suspend/reactivate confirmation UI |
| 8 / ADM-05–06 | `/admin-preview/jobs` | Fictional job search/filter/detail/removal; no actual publication/moderation |
| 8 / ADM-07–11 | `/admin-preview/disputes`, `/admin-preview/disputes/:disputeId` | Linked demo cases, timeline, information request, resolution/rejection, evidence and internal remarks |
| 8 / ADM-12 | `/admin-preview/reports` | Filtered session analytics and Web printable report; no live analytics/CSV service |
| 8 / additive entry | `/admin-preview` | Demo sandbox overview with explicit links back to real administration |
| 9 / EMP-15–17 | `/employer-payments/record`, `/employer-payments`, `/employer-payments/:paymentId` | External-payment form, local proof, confirmation/success, history and details; all demo |
| 9 / JS-26 | `/payments`, `/payments/:paymentId` | Demo history/pending views, receipt confirmation and payment-issue case linkage |

Sidebar/drawer destinations are role-specific; existing compact bottom navigation
and Profile/Company access remain. Main Web destinations have no inferred back
arrow. Nested screens reuse explicit/native contextual return controls and safe
direct-route fallbacks. Existing forms retain their current navigation protections;
the pre-existing company dirty-form and browser-refresh limitations are not fixed
by this UI phase. The empty Coming Soon panel is hidden now that its three demo
destinations are implemented.

Settings completion derives from the same four real fields as the existing
dashboard: name, auth email, phone and avatar (25% each). No demo field changes
that percentage or real verification. Two-factor authentication, actual notification
delivery and account deletion are explicitly not connected. Real company/profile
edits use the existing pages; the preview editors never prefill or overwrite actual
account/company identities. They are supplementary missing presentation fields,
not replacements for completed teammate screens.

#### Demo state, statuses and authorization

`Phase4Store.session` is a shared in-memory `ChangeNotifier` containing fictional
completed assignments, evaluations, payment records, sample moderation targets,
disputes and local audit notes. It resets on refresh/restart/sign-out/account
change, alongside Phase 2/3. Its sample assignments are independent of real work
and of the separate Phase 3 attendance fixtures. Related Phase 4 screens share IDs
and state: a payment issue marks the payment Disputed and creates a linked case;
an evaluation report creates a linked case. Closing a case never silently changes
payment confirmation or moves funds. The Job Seeker sample view excludes sample
worker B's records; the employer preview can inspect all sample assignments.

Evaluation criteria are exact:

- Job Seeker rates Employer: Communication, Job Description Accuracy,
  Professionalism, Payment Reliability, Work Environment, Respect Towards Workers.
- Employer rates Worker: Communication, Responsibility, Teamwork, Professionalism,
  Adaptability, Punctuality.

All six ratings must be 1–5; optional feedback is capped at 300 characters. Only
completed sample assignments are eligible; repeat submissions are rejected.
Own feedback remains readable; received feedback is hidden until both local
sample parties submit. A clearly named Simulate Counterpart action permits
previewing the reveal without pretending another actual user submitted anything.
Only revealed received evaluations can be reported once. No three-day moderation
SLA is promised. Availability dates are illustrative; production expiry/editing/
anonymity policies still need agreement.

Reputation scores (worker 84/company 90), explanatory indicators and trends are
fixed, explicitly labeled fixtures, not an arbitrary production scoring formula.
They do not recalculate after actions. Only the displayed evaluation average is
derived from revealed local evaluations. The insufficient-data scenario displays
no score; no score is attached to the real account/company.

Payment states: Pending and Overdue may become Confirmed via the sample recipient
action, or Disputed via a required issue reason. Confirmed/Disputed have no further
recipient transition in this preview. Overdue is a seeded scenario, not an
implemented due-date engine. New employer-declared records start Pending. Amounts
use integer cents after validating a positive RM amount with at most two decimal
places, a completed assignment and a valid nonfuture date. Exact local duplicate
records are rejected. Worker/assignment, date, method, reference/note and optional
proof are captured. **JobMate records payments made outside the app: there is no
checkout, card processing, money transfer, wallet or bank verification.**

Dispute states are Open, Investigating, Pending Info, Resolved and Rejected.
Nonterminal cases may be investigated, receive a required information request,
or be resolved/rejected with a selected outcome/reason and explanation. Terminal
cases cannot change again in the preview. Requests now actually change local
status and append timeline entries, correcting the prototype no-op. Remarks are
admin-view-only local data, not proof of secure storage. Account action states
Active/Restricted/Suspended and job Removed are **sample-only**; the actual backend
account-status contract is untouched. All demo mutation confirmations identify
the operation as local; nothing invokes real moderation RPCs.

New Job Seeker/Employer routes reuse the existing signed-in active-role gate.
The admin sandbox and admin settings additionally call the existing deployed
`admin-invitations` `check_access` contract after checking the signed-in
`users.role/status`, require `isAdmin: true`, fail closed, handle denied/expired
access and recheck actor identity after the request. There is no role switch or
demo-login path into administration. This only authorizes access to a fictional
UI preview; existing per-operation real admin/company-review permissions remain
authoritative. Protected conversation access is explicitly unavailable: no RLS
bypass, real private-message query or fabricated secure access audit is added.

Form drafts (including rating selections, notes, payment worker/method/proof and
case party/outcome choices) survive in-app navigation in memory. Discarding the
payment draft confirms first. Resume/proof selection reuses the existing local
file picker, basic header/size checks and previews (one PDF resume; one optional
PNG/JPEG/PDF proof; up to 5 MiB). Nothing uploads. Late file-picker results are
ignored after disposal/account reset. Native pickers/PDF rendering limitations
from Phase 3 remain. Auth/role reads expose loading/error/retry/denied states;
demo lists are synchronous and have filtering/empty/unavailable states rather
than simulated network delays.

#### FUTURE BACKEND INTEGRATION — Module 1

Audit the existing schema before adding logical storage for supported bio,
availability, skills/categories, resume metadata and notification preferences.
Define own-account/company-owner RLS, company verified-edit/re-review rules,
private resume Storage/signed access, retention and deletion handling. Account
deletion requires identity re-verification, employer ownership and legal retention
decisions. MFA and notification providers/permissions need separate approval.
Existing Auth, registration, personal/company verification and storage policies
must remain authoritative; no auth provider/rule changes are made here.

#### FUTURE BACKEND INTEGRATION — Module 6

Needs agreed evaluation request, submission, criterion rating, reveal/visibility
and report entities; assignment-party RLS, verified completion, one-per-party
constraints, server validation and atomic both-sides reveal. Define expiry,
feedback disclosure/anonymity, editing, moderation, appeals and notifications.
Client hiding is not privacy enforcement; unrevealed feedback must be inaccessible
through the API. Link reports transactionally to authorized moderation cases.

#### FUTURE BACKEND INTEGRATION — Module 7

Needs verified assignment/completion/attendance, permitted evaluations, payment
confirmation and dispute outcomes; approved scoring rules, minimum-data thresholds,
formula versions, recalculation cadence, snapshots, explanations and auditability.
Use server-side computation/authorized read projections, privacy rules and an
appeal/correction policy. Removed/unrevealed evaluations and overturned disputes
need defined treatment. No production trust algorithm or score table is created.

#### FUTURE BACKEND INTEGRATION — Module 8

Needs separately authorized account/job moderation capabilities, case/party/
evidence/request/resolution/remark entities and immutable action/access logs.
Enforce admin scopes, object ownership, reason requirements and transactional
state changes with RLS plus server-checked RPCs/services. Internal notes, uploaded
evidence and protected messages require private storage/signed access and explicit
case-scoped permission with server-side audit; an acknowledgement dialog cannot
grant access. Define appeals, notifications, retention, reporting/export services
and financial/evaluation correction policies. Existing company-review/admin
invitation/permission infrastructure must not be weakened or inferred to grant
new production moderation permissions.

#### FUTURE BACKEND INTEGRATION — Module 9

Needs external payment declaration, proof metadata, recipient confirmation,
revision history and dispute-link entities, completed-assignment/party RLS and
server-validated amounts/dates/idempotency/status transitions. Use a private proof
bucket with party-scoped signed access, validation/scanning and retention. Define
overdue/due-date rules, corrections, disputes after confirmation and notification
consent. A dispute resolution must not imply a bank refund or automatic receipt.
No payment gateway or external money-transfer integration is part of JobMate's
payment-record UI. Physical table/policy/bucket/function names must be agreed from
the actual backend, not inferred from the React prototype.

No tables, migrations, SQL, RLS, buckets, Edge Functions, secrets, API providers
or Dashboard configuration are created/changed in Phase 4. Existing Gemini job
formatting and all employer job posting behavior remain unchanged. All new phase
code is additive under `lib/features/phase4/`; tests are in `test/phase4_test.dart`.
Existing real admin directory search/details were not redesigned; missing sample
search/details/moderation controls live in the distinctly named sandbox. Real
extended-profile/company-edit integration, production scores/evaluations/payments/
disputes, CSV export and native report export remain outside this UI pass.

Phase 4 validation: all 76 new tests in `test/phase4_test.dart` pass (exact criteria,
validation/duplicates, visibility, linked cases/statuses, admin denial/retry and
23 screen scenarios at 320/768/1440 px). The full suite has 234 passing tests and
the same two pre-existing failures: stale registration `CheckboxListTile` lookup
and counter smoke test without router initialization. Analysis reports the same
eight auth/home/profile diagnostics and none in new code. Formatting, diff checks
and the local Web build pass. No Android device is connected. Browser/device
interaction, native file pickers, printable popup dialogs, real Supabase sign-out,
live admin access checks and deployed-backend acceptance remain unverified; widget
tests exercise injected account/access fixtures, not actual server authorization.

## Phase 5 — Figma visual redesign and polish

This pass applies the local Figma Markdown specification; original frames and the
referenced BEFORE screenshot were not supplied. It is not a pixel-perfect claim.
The shared theme now uses the teal/slate palette, white bordered surfaces, rounded
controls, compact status badges and clearer heading hierarchy. Outfit, DM Serif
Display and DM Mono are requested with platform fallbacks; these fonts are not
newly bundled or downloaded. Dark teal buttons improve contrast while bright teal
remains the brand accent. New reusable page/profile headings, statistic grids,
brand panels, section headings and compact DEMO notices avoid duplicate layouts.

### Screen inventory coverage

| Figma screens | Phase 5 coverage |
| --- | --- |
| JS-01, EMP-01 | Redesigned welcome, quick actions, activity previews and responsive summaries. Employer posting counts use the existing authorized repository; unavailable counts display an em dash and explanation. Sample applications/work remain separately labeled DEMO. |
| ADM-01 | Redesigned header, management shortcuts and explicitly demo moderation/dispute summaries; existing real overview/access checks retained. |
| EMP-02 | Redesigned real posting dashboard: four derived statistics, search, status filters, richer cards and existing lifecycle actions. |
| EMP-03–04 | Numbered form sections, clearer hierarchy and shared controls; all actual fields, dirty guards, validation and AI callbacks retained. |
| EMP-05 | Professional preview heading/company panel and clearer description sections using the existing form values. |
| JS-23, EMP-19 | New profile/company heroes, responsive information sections and real verification presentation. |
| JS-24, EMP-20, AUTH/ACC | Existing forms/layouts retained; inherit shared typography and controls. Not individually rebuilt. |
| JS-02–22, JS-25–26, EMP-06–09, EMP-12–18, EMP-21–22, ADM-05–12 | Existing screens inherit shared surfaces, badges, typography, demo notices and (where using DemoPage) page headers. No bespoke redesign of every screen is claimed. Existing state/actions remain intact. |
| ADM-02–04 | Existing real admin screens receive global styling; specialized directory/review layouts remain. |
| EMP-10–11, RPT-01 | No dedicated worker directory/profile was added; Workers shortcut opens existing attendance review. Standalone printable report HTML was not redesigned. |

Role landing selection, GoRouter routes and guards remain intact. Desktop
workspace navigation is now grouped in a 240px sidebar. Existing responsive
drawer/bottom navigation, Android contextual Back, safe route fallbacks and Web
main-destination back-arrow rules remain. The existing 1024px sidebar breakpoint
and 64px toolbar are retained rather than forcing prototype dimensions.

### Real functionality, demos and future integration

Supabase authentication, real profiles/company/logo/verification, employer
membership authorization, posting Create/Edit/Preview/Draft/Publish/Close and
salary visibility remain in place. The existing `format-job-description` Edge
Function request, editable AI sections and Original Description are unchanged.
The employer landing page adds only an authorized read through the existing job
repository. No backend contracts, policies, secrets, dependencies or infrastructure
were changed. Existing application, matching, attendance, chat, evaluation,
reputation, payment, location and moderation demo stores remain session-only;
new dashboard previews explicitly identify them. All previous future integration
requirements above still apply; no Supabase Dashboard steps are needed for this pass.

### Validation and remaining work

Formatting and the release Web build pass. Analysis retains the eight existing
auth/home/profile diagnostics. The full suite reports 242 passing tests and two
pre-existing failures (registration CheckboxListTile expectation and counter smoke
test without router initialization). The focused workspace/posting/visual suite
passes 65 tests. Eight new fixture tests render dashboards, posting list/form and
preview at 390px and 1440px, checking layout exceptions and fixture-derived counts.
Ten PNGs are generated under ignored `build/phase5-review/` and were visually
inspected. Tests alias installed Windows fallback fonts for readable screenshots;
these are fixture renders, not live Supabase sessions or exact Figma font matches.

A headless browser attempt captured only the startup loader, so actual browser
runtime verification is inconclusive. No live Supabase/Gemini requests, authenticated
profile/admin browser walkthrough, Android device, browser history/refresh acceptance
or native keyboard/file-picker testing is claimed. Deeper individual module layouts,
bundled design fonts, dedicated worker views and complete visual acceptance against
original Figma frames remain future work. This pass does not claim every screen was
individually redesigned. No commit or push was made.

## Phase 5.1 — Exact handoff matching progress

`JOBMATE_EXACT_UI_DESIGN_HANDOFF.md` is now the primary visual reference;
`JOBMATE_FIGMA_UI_SPEC.md` continues to describe screen/workflow coverage. The
working tree was clean at the start of this pass. Functional implementations and
teammate persistence/authorization code are retained. This section supersedes
Phase 5's measurements and fallback-font limitations where explicitly stated.

### Implemented visual matching

| Area / screen | Updated presentation |
| --- | --- |
| Shared theme | Canvas/text/brand tokens; primary action `#0D9488`, hover `#0F766E`, pressed `#115E59`; white bordered cards without resting shadow; 8px controls, 12px cards, 16px dialogs; 14px body/fields and distinct 20px section/page versus 24px dashboard headings. |
| Fonts | Outfit 300–700, DM Serif Display regular/italic, DM Mono 400/500 bundled in `assets/fonts/`, registered in `pubspec.yaml`. No font package or runtime font requests. Source/licensing notes and OFL licenses included. Heavier serif/mono weights can be synthesized. |
| Workspace shell | 240px sidebar from 768px viewport width, 56px toolbar, 256px mobile drawer, 18px navigation icons, 8px selected item corners, compact Outfit wordmark and pinned account footer. Existing role routes, locks, contextual exits and Android navigation remain. The footer truthfully shows account/role context, not a fabricated person. |
| EMP-02 | Centered 768px list, 20px serif heading, intrinsic Post Job action, four real-derived count cards, existing search/status controls, bordered stacked posting cards and preserved Refresh/Edit/Preview/Publish/Close. Unsupported applicant/view metrics are not fabricated. |
| EMP-03/04 | Centered 672px form with five separate bordered cards: Basic job information, Compensation, Schedule & location, Description & AI formatting, Requirements & benefits. Icon headers, responsive paired fields and salary visibility grouped under compensation. Controllers, field keys, validators, dirty guards, AI progress and callbacks preserved. No fake skills field added. |
| EMP-05 | Preview constrained to 512px and 80% viewport height with scrollable actual content and existing close/return behavior. |
| JS-01 / EMP-01 | 672px / 768px production content columns, 24px greetings and smaller numeric hierarchy. Job Seeker's real profile-completion card precedes demo activity. Existing demo work/applications remain visibly separate from real account/posting data. |
| ADM-01 | 896px content, Slate 50 canvas and 56px toolbar; existing access checks and real overview retained. |
| JS-23/24 | Shared 672px column, 56px real photo/fallback, compact identity/personal details and edit controls. Existing real editing/upload/security logic retained. |
| EMP-19/20 | Shared 672px company layout and saved real logo in the profile header with actual verification state; existing company submission/edit forms inherit bundled fonts and shared fields. |
| Remaining shared pages | Workspace columns default to 672px; employer attendance review uses 768px, admin demo pages 896px. Shared headers/cards/inputs receive the same tokens without changing module state. Chat retains its own split-layout implementation. |

### Remaining fidelity checklist

This is a measured priority-screen matching pass, not a claim that the entire
inventory now exactly matches. Bespoke content order and components still need
individual matching for Browse/Details/Applications, Recommendations, Attendance,
Chat, Evaluations, Reputation, Payments, Nearby/Location and Admin directory/
moderation/disputes/reports/auth/settings. Role dashboards still retain extra real
account/verification cards instead of invented Figma trust/skill metrics; they do
not yet reproduce every recommendation/recent-activity panel. Real profiles lack
some prototype-only bio/skills/resume/reputation fields; no fictional replacements
were introduced. Company registration/resubmission remains the actual workflow.

The shell still places its toolbar across the Scaffold above sidebar/content,
rather than reproducing every sticky React chrome detail. The existing four mobile
destinations are retained; other role destinations remain accessible in the drawer.
Material icons and controls remain instead of adding Lucide dependencies. Android
touch targets are kept usable rather than copying small web-only click targets.
The 36px development switcher is not reproduced. Dedicated worker directory views
and standalone report HTML remain outside this visual pass.

### Functionality and validation

No schema, SQL, RLS, Edge Functions, Gemini model/request contract, secrets,
Storage buckets or package dependencies changed. Font asset registration is the
only `pubspec.yaml` change. Supabase login/role selection, company ownership and
verification, profile updates, actual posting fields/status operations and
Original Description plus four editable AI sections remain authoritative.
All previous demo/backend integration notes remain applicable; no Dashboard steps
are needed. No commit or push was made.

The full test run reports 246 passes and the same two pre-existing failures:
registration's stale CheckboxListTile lookup and the counter smoke test without
router initialization. A subsequent targeted run passes 118 tests across workspace,
posting, Phase 3 and responsive visual scenarios. Analysis retains the eight
pre-existing auth/home/profile diagnostics. Final formatting, whitespace checks
and the release Web build pass. No Android device was connected.

Visual fixture tests now load the bundled fonts and render posting/dashboard/form
screens at 390, 768 and 1440px, with 15 PNGs including previews under ignored
`build/phase51-review/`. They assert widths, toolbar geometry, form sections,
fixture-derived counts and absence of layout exceptions. Images were inspected
against the documented measurements; original Figma screenshots/frames are not
available, so no image-to-image or pixel-perfect comparison is claimed. These are
injected-data Flutter renders, not authenticated browser/server acceptance tests.
The release build was also served locally and real login-page screenshots were
captured and inspected in headless Chrome at 1440px and at a DevTools-emulated
390px viewport (document width also 390px). The first narrow window-only capture
was cropped; it was replaced with the correctly emulated capture. Browser images
are `login-browser-1440.png` and `login-browser-390.png` in the same review folder.
No credentials were entered and no authenticated actions were exercised.
Real Supabase/Gemini operations, native Android hardware, browser history/refresh,
keyboard-open forms and native pickers remain unverified in this pass.

### Files changed in Phase 5.1

- Theme/components: `lib/shared/theme/jobmate_theme.dart`,
  `lib/shared/widgets/app_workspace.dart`, `auth_style.dart`, `design_primitives.dart`.
- Posting UI: `lib/features/jobs/job_postings_page.dart`, `job_form_page.dart`,
  `job_preview.dart`.
- Landing/profile UI: `lib/features/home/home_page.dart`, `dashboard_content.dart`,
  `lib/features/admin/admin_dashboard_page.dart`,
  `lib/features/profile/profile_page.dart`,
  `lib/features/company/create_company_page.dart`.
- Shared demo presentation: `lib/features/demo_work/demo_widgets.dart`.
- Verification: `test/workspace_test.dart`, `test/job_postings_test.dart`,
  `test/phase5_visual_test.dart` (four additional tablet scenarios).
- Assets/documentation: `pubspec.yaml`, five `.ttf` files, three OFL license files,
  `assets/fonts/README.md`, and this README. No dependency additions.

## Phase 5.2 — UI consistency and application integration preparation

The improved Phase 5.1 employer dashboard/posting/form design is preserved. The
existing uncommitted working tree was retained. See [the 71-screen audit](PHASE52_SCREEN_AUDIT.md)
for every AUTH/ACC/JS/EMP/ADM/RPT ID, implementation, role entry, real/demo boundary
and remaining visual differences. Presence of a route is not a completion claim.

### Screens polished / completed

| Module | Phase 5.2 UI work and current boundary |
| --- | --- |
| 1 Account/identity | Existing real login/registration/recovery/profile/company flows preserved. Auth marketing typography now follows 30px display / 14px support copy. Existing real profile/company baseline retained; extended profile/company previews remain explicitly demo. Settings reuse the refined modal/field styles. |
| 2 Jobs/applications | Browse identity cards, responsive filters, job header/actions, three application summary tiles, semantic stage badges, 768px employer pipeline, compact card actions, 448px seeker / 512px employer detail widths, timeline IDs, responsive 448px dialogs and destructive withdrawal/rejection confirmation styling. All seeker catalogue/applications/applicants remain fictional; real posting entry explicitly requires choosing a separate demo pipeline. Employer real postings/counts/AI are unchanged. |
| 3 Recommendations | Existing deterministic matching, filters, match rings, explanations and shared Apply flow retained with refined common fields/modals. No real recommendation AI claim. |
| 4 Attendance/work | Responsive mono-number summaries; attendance/evidence/review/report remain coherent local demos. Added `/workers` directory from the same attendance store and worker-context reputation modal with a truthful insufficient-data state (no invented worker score). Printable A4 demo report styling and 794px report width refined. |
| 5 Communication | White bordered split chat, 288/320px rail sizing where space permits, message/composer padding, mobile single-conversation layout retained. Local sends/attachments/receipts remain labeled simulated. Split mode waits until enough content width remains after the sidebar. |
| 6 Evaluations | Separate bordered criterion panels, colored circular 1–5 choices, mono rating labels. Exact six criteria, 300-character feedback, confirmation/history/visibility behavior preserved. |
| 7 Reputation | Shared 96px score ring and numeric detail for illustrative worker/company dashboards, existing factors/trend/insufficient-data behavior retained. No production scoring added. |
| 8 Administration | Real User Directory now uses the role workspace shell and 896px width; existing reads/permissions/filters/page controls retained. Demo case detail uses a 1024px main/action-and-remarks split on wide layouts and stacks on mobile. Reports use 768px. Protected conversations remain unavailable. |
| 9 External payment records | Existing Record/Success/History/Details/Receipt/Issue flows retain coherent local state; shared summaries/modals/controls refined. No payment gateway, wallet or money transfer. |
| 10 Location | 768px nearby page; 360px illustrative map with parks/roads/water, 180px detail map and 320px employer picker. Simulation labels/coordinates remain explicit; actual posting coordinates are untouched. |

Role navigation includes the new guarded employer Workers destination. The worker
directory uses `Module2Gate(role: 'employer')`; no UI role switching grants access.
Existing GoRouter routes, direct-route safe Back fallbacks, Web main-page arrow
rules, Android contextual Back, form drafts/dirty protection and session resets
remain. No demo repository was converted into a production data service.

### Application Management next

[APPLICATION_MANAGEMENT_INTEGRATION_PLAN.md](APPLICATION_MANAGEMENT_INTEGRATION_PLAN.md)
documents the current screens/models, employer-only real posting reads, missing
public salary-safe read contract, proposed application/history/offer/save/private
note/resume storage, status transitions, ownership/duplicate protection, RLS/privacy
and recommended integration order. All storage structures are proposals. No SQL,
migrations, tables, policies, buckets, Edge Functions, secrets or APIs were created
or changed. All earlier backend integration notes above remain applicable.

UI status: all inventory flows have a corresponding screen/modal/state or explicit
unavailable presentation. This does not mean all production data exists or all
screens are pixel-perfect. Real company editing still follows the existing
registration/resubmission/authorization contract. Production applications remain
blocked on approved public-read, application, privacy and RLS contracts; visual
readiness is not backend readiness.

### Validation and remaining differences

`test/phase52_visual_test.dart` adds 50 render/interaction scenarios: 25 representative
screens at 390px and 1440px using bundled fonts. It checks rendering exceptions and
demo labels, plus worker search/reputation interaction. PNGs are generated under
ignored `build/phase52-review/`. Representative images were visually inspected;
not every conditional state was manually reviewed. Existing module tests cover
additional 320/768/1440px scenarios, filters, role denial, status changes, validation,
draft protection and AI callbacks with injected fixtures.

The full suite reports 296 passing tests and the same two pre-existing failures
(registration CheckboxListTile expectation; router-uninitialized counter smoke test).
The final Module 2 / Phase 4 / Phase 5.2 focused run passes 155 tests. Analysis retains
eight existing auth/home/profile diagnostics, with none newly introduced. Formatting,
whitespace validation and the release Web build pass; no live Supabase/Gemini acceptance,
Android hardware, native picker, keyboard or browser history acceptance is claimed.

The release app's actual login page was captured in headless Chrome at confirmed
1440px and 390px viewports, inspected alongside the fixture samples, with no
horizontal document overflow. These browser captures do not verify authenticated
flows. No original Figma screenshots/frames were available for pixel comparison. Some
prototype-only real-profile metrics are omitted rather than invented. Admin reports
use coherent demo summaries instead of fabricated real registration/ranking data;
case action rail is not sticky. The standalone HTML print sheet uses local system
font fallbacks; the Flutter report uses the bundled design fonts. Detail routes remain routes where needed for
history/direct URLs. Material icons and Android touch targets remain deliberate
Flutter adaptations. Full live role/permission and platform acceptance is still
required. No commit or push was made.

### Files changed in Phase 5.2

- Application UI: `lib/features/applications/{browse_jobs_page,job_details_page,applications_page,module2_widgets}.dart`.
- Shared UI: `lib/features/demo_work/demo_widgets.dart`, `lib/shared/widgets/design_primitives.dart`, `lib/shared/widgets/auth_layout.dart`.
- Work/navigation: new `lib/features/attendance/workers_page.dart`, `lib/features/attendance/attendance_pages.dart`, `lib/shared/navigation/{app_routes,workspace_destinations}.dart`, `lib/main.dart`.
- Other presentation: `lib/features/chat/chat_page.dart`, `lib/features/location/location_pages.dart`, `lib/features/admin/admin_users_page.dart`, `lib/features/phase4/{evaluation_pages,reputation_page,admin_preview_pages}.dart`. Payment pages inherit updated shared summaries and modals.
- Documentation/verification: new `APPLICATION_MANAGEMENT_INTEGRATION_PLAN.md`, `PHASE52_SCREEN_AUDIT.md`, `test/phase52_visual_test.dart`, and this README.
- Prior Phase 5.1 edits/assets remain uncommitted and preserved. No new package dependency.

## 5. Security and Collaboration

- Never commit Gemini API keys, service-role keys, JWTs, credentials or private tokens. Keep Gemini API calls inside the Supabase Edge Function, never directly in Flutter.
- Use the existing Supabase project configuration. Never weaken authentication, authorization, RLS or company-verification checks to make a feature work.
- Inspect shared code and contracts before editing. Do not modify unrelated teammates' modules without explicit instructions. Prefer small changes; when commits are requested, keep them focused and descriptive.
- Ask for approval before destructive database changes, migrations or major architectural changes. Existing migration files do not authorize applying them.
- Document necessary Supabase Dashboard changes separately with their reason and validation steps, without secret values. Do not silently change remote functions, policies, buckets or authentication settings.

## 6. Testing Checklist

Run checks appropriate to the change from the project root:

```sh
flutter analyze
flutter test
```

For focused job changes, use `flutter test test/job_postings_test.dart`. Run other relevant tests and the full suite when warranted. Automated tests do not substitute for browser/device and deployed-backend checks.

- [ ] Analysis and relevant tests; report failures and checks not run.
- [ ] Web desktop and narrow-browser layouts: no overflow, usable forms/dialogs, keyboard/Tab focus and hover behavior.
- [ ] Android layout: touch targets, keyboard-open scrolling, SafeArea and insets.
- [ ] Authentication and role permissions, including denied employer membership/company-verification access.
- [ ] In-app navigation, direct URLs, browser Back/Forward/refresh, Android AppBar/system Back and unsaved changes.
- [ ] Loading, empty, success and error states; repeated actions and session changes where relevant.
- [ ] AI success, editable output, preserved Original Description and replacement confirmation.
- [ ] Temporary AI failure, rate limit, malformed response and session-expiry handling; preserve text and manual editing.

### Details requiring team confirmation

Confirm the deployed `format-job-description` implementation, Gemini configuration, server-side secret names and deployment ownership. Confirm the existing Supabase schema/RPC/storage/policy baseline and authentication settings before attempting a fresh environment; checked-in migrations are partial. Web hosting and its URL behavior require deployment-specific verification. This documentation does not imply live-backend or platform acceptance testing.

### Flutter learning resources

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)
- [Flutter documentation](https://docs.flutter.dev/)

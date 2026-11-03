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

Module 2 browsing and application screens now have an explicit demo environment (see below). AI Recommendations, Attendance, Chat and Location Discovery remain coming soon. Do not describe them as working features. Employer Job Posting remains connected to the existing Supabase workflow. Other platform folders exist, but the project targets Web and Android.

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

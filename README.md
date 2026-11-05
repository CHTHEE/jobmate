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

### Payment Handling update — November 4, 2026

The main Payments routes now use `lib/features/payments/` for the Billplz Sandbox
integration foundation, superseding the older Phase 4 external-payment demo below.
Employer may add a voluntary nonnegative Bonus to the agreed assignment minimum
without worker acceptance. Only Part-time/Temporary accepted, completed and
work-verified assignments without unresolved work-completion disputes are eligible.
Worker and Admin views are read-only; browser redirects never establish success
or worker payout.

See [Payment Handling integration and setup](docs/payment_handling.md) for the
confirmed rules, new API/adapter contract, database invariants and account setup.
Flutter pages and Billplz/domain code are implemented; real AssignmentSource and
durable PaymentStore/FK/RLS/notification integration remain dependent on the
teammate-owned schema. Edge entry points fail closed until wired. No payment
migrations or remote setup were applied. The old demo classes remain for existing
tests; `/employer-payments/record` now redirects to the Sandbox workspace. App pages
show integration pending instead of fictional payment data while disconnected.
The server-only settings loader is now in `supabase/functions/_shared/payments/config.ts`.
Its four new setting names and Dashboard setup steps are documented in the
integration guide. The user reports having the Sandbox Collection and both keys;
values have not been read or verified by the agent. Saving configuration does not
enable the missing Assignment/PaymentStore adapters.
For fixed-port local Payment testing on this Windows machine, use
`flutter run -d chrome --web-hostname localhost --web-port 8765` and set the server
return URL to `http://localhost:8765/#/payments/return`. Port 8080 was denied with
socket error 10013; loopback bind checks for 8765 passed. The ordinary random-port
Web command below remains available for development without a fixed payment return URL.
For manual UI testing before Assignment integration, stop any run on that port and
use `flutter run -d chrome --target test/support/payment_preview.dart --web-hostname localhost --web-port 8765`.
This separate entry point clearly labels fictional records, shares them between
role previews and simulates checkout locally without Supabase/Billplz calls. It
does not enable payment or validate real backend integration; see the guide's
manual walkthrough. The normal lib/main.dart does not import preview fixtures.

### Planned features

Module 4 production worker attendance at `/work-attendance` now supports
confirmed check-in/check-out through the deployed attendance RPCs. Device location
is not collected: both requests send `unavailable` with null coordinates.
The server controls timestamps and eligibility, including the check-in window
from 60 minutes before scheduled start through scheduled end. Actions lock
duplicate submissions and reload authoritative assignments without optimistic
timestamps. Failed responses also refresh before retry; a lost response may have
committed. Existing attendance demos remain separate. This describes the client
implementation; live attendance actions and device acceptance require explicit
testing approval.

Production assignment cards now open read-only evidence metadata at
`/work-attendance/:assignmentId/evidence` for active Job Seekers and
`/work-verification/:assignmentId/evidence` for active Employers. Direct entries
resolve fresh authorized assignment lists; employer company selection comes
from existing company-access checks, never URL parameters. Submitted images can
be previewed and PDFs opened in the browser/PDF app using private, 90-second
signed links after fresh assignment and per-file authorization. No public links
are created. The separate `/attendance/evidence` demo remains unchanged.

Employers can create assignments from Work Verification after selecting an
eligible hired application and explicitly confirming worker, job, company,
MYT schedule and workplace. Fresh complete reads exclude already assigned
applications. Creation uses the existing RPC with transport retries disabled;
uncertain outcomes require fresh assignment reads and remain blocked when
inconclusive. Attempt protection survives dialog/route reopening within the app,
but is not durable across browser refresh/app restart; never restart to retry a
lost response. Concurrent clients still depend on the deployed server constraints.
No migration or live assignment creation was performed during implementation.

Workers can prepare a local evidence draft in a responsive dialog/sheet from
their authorized production evidence viewer. Description and selected files use
the shared draft controller's validation. Submit Evidence remains disabled;
nothing is uploaded or submitted. Closing the form discards its local contents
after confirmation when needed. Account/assignment changes clear the draft.
Employer evidence viewing remains read-only; no new route is introduced.

The approved QA assignment `49f417e6-9645-4433-a1fd-76a99d6c0815` additionally
offers an explicitly armed, supervised real evidence flow from its worker
evidence viewer. Upload and submission require separate confirmations and fresh
eligibility checks. A failed or uncertain action blocks further writes for that
worker's running QA session; read-only reconciliation may establish commitment.
Use only one browser tab/device. Browser refresh or app restart loses this local
gate: stop and investigate manually after any uncertain outcome, never reopen to
retry. Normal production submission stays disabled; no idempotency migration is
required or deployed by this integration.

Authorized employers can open a separate supervised real QA review dialog from
that assignment's evidence viewer while it is pending review. Verify and Request
More Evidence require confirmation and fresh company/evidence checks. One review
dispatch closes further actions for that employer/company's running QA session;
uncertain results require manual investigation, with no automatic retry. Status
and evidence refresh through existing RPCs. Verification history is unavailable
through the deployed API. Ordinary review and demo workflows remain unchanged.
See [pre-commit UI cleanup and release blockers](docs/module4_precommit_ui_review.md)
for completed polish, private-preview behavior and the safety plan for general use.

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

`configureAppNavigation` enables GoRouter's Web imperative-URL compatibility
option for existing pushed detail flows; root menu/tab links use `go`.
This keeps pushed route URLs visible without replacing the router/history API.
It does not make transient OTP state or fictional demo records survive refresh;
live browser Back/Forward and direct-link acceptance remain to be verified.

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

The current acceptance criteria are in [Flutter Web + Android UI/UX standards](docs/flutter_ui_ux_standards.md).
The November 4 platform-navigation update supersedes older Phase 2–5 descriptions
of width-only navigation. See [UI review and verification](docs/ui_ux_review.md)
for this pass's scope, code examples, test coverage and remaining device checks.
The shared shell affects existing workspace screens automatically. Standalone
authentication/security/upload flows remain focused pages with their own safe
return actions; they do not get a second workspace shell.

### General principles

- Share business logic, validation, authentication and the Supabase backend across platforms. Keep branding, terminology, colors and functionality consistent.
- Use `kIsWeb` for actual platform behavior; use responsive layout constraints for screen-size adaptation. A narrow screen does not mean Android; a wide screen does not mean Web.
- Reuse `LayoutBuilder`, `ResponsiveLayout`, `ResponsiveContent` and existing workspace patterns. Width classes start at 600, 840 and 1200 logical pixels. Web's persistent sidebar begins at 840; smaller Web windows use a left drawer. Width never chooses the navigation platform.
- Avoid horizontal overflow and inaccessible controls.

### Web requirements

- Use the shared left sidebar on Web: persistent from 840 logical pixels, an off-canvas left drawer below that. Never render Android bottom navigation on Web. General content can grow to 1280 logical pixels; forms retain their narrower feature-specific limits.
- Job Seeker and Employer workspace pages place the account avatar/menu at the top right of the AppBar, matching the Admin dashboard. Wide layouts show the person's name and role; compact layouts show the avatar and chevron. The menu opens Personal profile, Account settings and Sign out. The Job Seeker's clearly labeled reputation demo is embedded alongside the real personal profile on wide layouts and below it on compact layouts; the existing reputation URL remains available. Employer company reputation remains a separate demo reachable from the account menu. Payments (sandbox) stays in the sidebar/More menu for both roles. Sidebar destinations use expandable categories; the active category opens automatically and Dashboard remains directly available. Admin also reaches Personal profile and Account settings from its top-right menu.
- The Job Seeker dashboard keeps search beside notifications in the top bar, a compact profile-completion checklist, demo applied-company cards, and a future-evaluations placeholder. The checklist disappears when name, email, phone and photo are all present; the Employer's completion progress also disappears at 100%. Demo applications remain clearly labeled and separate from real account data; no evaluation score is shown until that feature exists. On Web and Android, the dashboard search button opens a panel near the top center with a light background dim, without changing the URL; Web notifications open a compact panel at the upper right. The Admin dashboard uses the same Web notification panel. Search history is kept only while that panel is open; it starts empty. Android notifications retain the existing focused page. Direct `/search` and `/notifications` routes remain available. Jobs search uses the demo catalogue; Companies calls `search_public_companies` for verified company name, industry and location only, once the new migration is reviewed and applied; People shows no results until public/private profile controls exist. The company function does not expose documents or private logos.
- Do not stretch mobile-style full-width forms across large desktop screens. Size forms and dialogs appropriately for desktop.
- Avoid redundant top-left AppBar back arrows when clear in-app navigation exists. Provide Cancel, Back to Job Postings, breadcrumbs or sidebar navigation as appropriate. Never rely exclusively on browser Back.
- Preserve browser Back, Forward, refresh and direct URL navigation through the existing router. Verify authentication and route-state behavior rather than assuming every flow survives refresh.
- Protect unsaved changes when leaving forms where feasible, including browser navigation where supported.
- Support mouse, keyboard, Tab navigation, visible focus indicators and appropriate hover states. Mobile-only interactions must not be the only way to access a feature.

### Android requirements

- Use touch-friendly layouts, comfortably sized targets and mobile-appropriate dialogs, spacing and navigation.
- Use the shared bottom NavigationBar at root destinations, including wide tablets. Three primary role destinations, a separate Account avatar and More are shown where the account menu is enabled. Account opens profile and settings; More opens the grouped navigation sheet with Sign out at the bottom. The mobile More sheet omits Dashboard and Job Seeker Search/Browse Jobs; the Job Seeker Jobs tab opens `/jobs`, while the dashboard search icon opens the search panel. Web sidebar entries remain available. Screens that intentionally hide the account menu retain only More. Do not render the Web sidebar/drawer as native primary navigation.
- Root tab switches use GoRouter `go` and `NoTransitionPage` rather than stacking duplicate root pages or sliding the bottom bar. Route selection remains synchronized with the URL; this does not introduce a StatefulShellRoute or preserve every disposed root widget's local filter/scroll state. Existing store-backed drafts are retained. Focused forms/details hide the bar and keep guarded contextual Back with native Material transitions. The bar also hides while the software keyboard is open to preserve form space.
- Keep contextual AppBar back arrows on pushed detail, create and edit screens where appropriate. Respect Android system Back.
- Use scrollable forms that remain usable when the keyboard opens. Respect SafeArea and system insets.
- Do not rely on hover-dependent controls. Protect unsaved changes when navigating back.

### Back navigation rule

Web should hide redundant AppBar back arrows where existing desktop navigation provides a clear alternative. Android should retain contextual AppBar navigation on pushed screens. Never remove the only practical way to leave a screen.

Web sidebar destinations, including Personal Profile, Company Profile and My Job Postings, must not show redundant top-left AppBar back arrows. `AppWorkspace` disables inferred leading controls on both platforms: Web uses its sidebar/menu; native roots use bottom tabs/More, while focused details use explicit contextual Back. Direct routes retain a safe fallback. Existing job/payment guards remain in effect. Company form menu exits now confirm unsaved text, selected files and uncertain submissions; its native Back path also confirms. Browser refresh/tab closing are not guarded.

Standalone Web pages that formerly showed a top-right Dashboard text button now show the JobMate logo in the top-left AppBar as a dashboard link. The Resume page also uses this logo instead of its former top-right My profile action. This logo checks the page's unsaved-input guard before leaving, including a selected PDF. Other specific exits, such as Close policy and Sign in, retain their action; native pages keep contextual Back. General page-reload icons were removed from headers. Contextual text actions such as Check for updates and error Retry remain, along with payment/logo review status refresh controls that check a specific server result.

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
| `/jobs` | Search/filter/sort and session-saved jobs | Supabase `list_published_jobs` RPC |
| `/jobs/:jobId` | Published job details and Apply with optional resume | Supabase browsing and submission RPCs |
| `/applications` | My Applications, All/Active/Completed, search/status filters | Supabase `list_my_job_applications` RPC |
| `/applications/:applicationId` | Application details and chronological status history | Supabase seeker list and history RPCs |
| `/applicants` | Authorized employer posting selector | Existing employer posting RPC |
| `/applicants/:applicationId` | Safe return to applicants | Applicant detail/actions not implemented |
| `/applicants?posting=<jobId>` | Real applicants, search/status filters and sorting | `list_job_applicants(p_job_id)` RPC |

The existing employer list/create/edit/preview/draft/publish/close screens are
reused. Registration/login, company verification/logo access, ownership checks,
job repositories/validation and `format-job-description` are unchanged. The new
route gate reads the existing signed-in `users.role` and `users.status`, requires
an active Job Seeker or Employer as appropriate, and provides loading/error/retry
and Dashboard exits. Existing auth redirects remain in place. This UI gate does
not replace RPC authorization or RLS.

**Real browsing, Phase 1:** Browse Jobs and Job Details now read only through the
existing deployed `list_published_jobs()` RPC for active authenticated Job Seekers.
`PublishedJobsRepository`, in `module2_repository.dart`, isolates this catalogue
and its session-only saved IDs from the unchanged application demo. Both pages
fetch on entry (including direct detail URLs), offer refresh/retry, and show
loading, empty or unavailable states. RPC failures never fall back to sample jobs.
Account changes clear cached jobs/saves and invalidate pending responses.
The existing layouts, routes, search/filter/sort and responsive modals remain.
**Real submission, Phase 2A:** Apply opens `JobApplicationForm`, reusing the
existing responsive modal and `ResumeFile`/`SupabaseResumeGateway` contract.
Resumes load through `list_personal_resumes`; selecting a PDF is optional and
the cover note retains its 1,000-character UI limit. `submit_job_application`
receives the real job ID, optional resume ID and optional trimmed cover note.
Success is shown only after the server returns an application ID. Server errors
are retained, and account changes invalidate selections and pending responses.
Visiting My Resume preserves the note and reopens Apply on return. Cancel/Back
confirms before discarding input; unexpected disposal retains the account-scoped
note until session reset. Browser refresh/tab closing do not retain drafts.
**My Applications, Phase 2B:** the seeker list now calls the existing no-argument
`list_my_job_applications()` RPC. Its exact projection is `application_id`,
`job_id`, `job_title`, `company_name`, nullable `resume_id`/`cover_note`, `status`,
`applied_at`, `updated_at`, and nullable `withdrawn_at`. Cards use the returned
title, company, date and status, with a neutral work icon. No logo, resume
filename, location or salary is inferred. Submitted displays as Applied;
Declined and Withdrawn remain distinct completed statuses. The list preserves
search, status filters, tabs and sorting (applied date then application ID), and
refreshes on entry, explicit refresh and return from its navigation actions.
Loading, error/retry and empty states never fall back to fictional records;
account changes clear cached applications and invalidate pending requests.
**Application details, Phase 2C:** View Application opens the existing detail
route using the real application ID. On entry/direct URL, the page reloads the
owning seeker's application list before calling `list_application_history` with
`p_application_id`. The seven history fields map directly: `history_id`, nullable
`previous_status`, `new_status`, `changed_by`, `changed_by_name`, nullable `note`,
and `changed_at`. The timeline shows only returned events in RPC order, with
status, local date/time, available actor name and note. Initial submissions never
gain inferred future events. Details show the real job/company, applied date,
cover note when present and a resume-attached indicator, without download access.
Details/history reload on entry, explicit refresh and return from View Job or
workspace navigation. Missing ownership, loading, empty history and retry states
are explicit; account switches invalidate both details and history responses.
Back has a safe list fallback for direct URLs. View Job retains the real job ID.
Status changes, withdrawal, offers and resume viewing remain
outside this phase. The submission confirmation now links to the connected list.
**Employer View Applicants, Phase 2D:** My Job Postings now links to the existing
`/applicants?posting=<jobId>` route using View Applicants. Company/job context is
revalidated through the existing employer access checks and posting RPC before
`list_job_applicants` is called. The exact eight-column projection maps
`application_id`, `applicant_id`, `applicant_name`, nullable `resume_id` and
`cover_note`, `status`, `applied_at`, and `updated_at`. Cards show the real name,
status, applied date/time, resume indicator, optional note and application ID.
No contact details, profile images, filenames or download URLs are inferred.
The existing layout retains search, status filters, All/Active/Completed tabs,
summary counts and newest/oldest/name sorting. All eight statuses remain distinct.
View Job reuses the employer preview; Edit Job retains the existing route for
draft/published jobs and is absent for closed jobs. The unfiltered sidebar entry
offers an authorized job selector. Loading/error/retry/empty states never fall
back to sample applicants; refresh rechecks company context, and account/job
changes invalidate pending results. Employer detail URLs now provide a neutral
return state, with no demo actions or records. Employer history, resume downloads,
notification UI and interview scheduling remain outside this phase.
**Employer status updates, Phase 2E:** applicant cards offer only Submitted →
Shortlisted/Rejected, Shortlisted → Interview/Rejected, and Interview →
Offered/Rejected. Offered and all completed statuses have no employer actions.
The existing responsive modal confirms each action and accepts an optional note
of at most 2,000 characters; notes are trimmed and blank notes are sent as null.
`update_job_application_status` receives only `p_application_id`, `p_new_status`
and `p_note`. Repeated submissions are locked, account/company/job context is
checked before submission, and stale responses cannot show success. The client
never changes a card optimistically: it reloads the selected job's applicants
after RPC success or failure, preserving server errors and an unsubmitted note.
If a concurrent transition makes the original action invalid, confirmation is
disabled after refresh. History insertion and applicant notifications remain
entirely server-side. No status update is made against a live test application
by automated tests; they use isolated fakes and a local HTTP server.
**Employer resume viewing, Phase 2F:** cards with a resume offer one View Resume
action. It POSTs the real `application_id` through the authenticated client's
`view-application-resume` Edge Function, validates absolute HTTPS `signed_url`
and positive integral `expires_in` seconds, then opens the PDF automatically.
Web reserves a new tab synchronously during the click and detaches its opener
before awaiting the request; Android uses the existing external PDF/browser
launcher. Only blocked Web opening reveals an Open PDF fallback. Valid links
are retained only in the button's account/application/job context until expiry;
pending tabs and cached links are cleared on context invalidation/disposal.
Failures/timeouts close waiting tabs and expose safe retryable errors without
logging signed URLs or credentials. A 30-second request timeout prevents an
indefinite loading state. The client never calls `get_application_resume_url`
as a URL service or signs applicant Storage objects itself; authorization and
signing stay in the deployed Edge Function. No bucket/policy/function changes
or new dependencies are needed. Browser popup behavior and Android PDF handlers
still require live acceptance checks.
The old `ApplyDemoForm` remains solely for isolated demo/preview fixtures and is
not reachable from real job details. Real submission never creates demo records.
This client change creates no SQL, policies, permissions or deployment changes.

The `BrowseJob` display projection keeps existing posting field names and
list formats and excludes `salary_min`, `salary_max` and `salary_period` unless
`salary_visible` is exactly true. Cards/details never render hidden compensation.
Only rows returned by the published-job RPC appear in browsing; expired jobs are
labeled and Apply is disabled. Hidden or missing salary displays as Not disclosed.
Closed/missing direct detail routes show unavailable states. Company names and
descriptions come from the RPC; verification and trust scores are not fabricated.
Nullable `logo_storage_path` values use authenticated five-minute signed URLs
from the private `jobmate-company-logos` bucket. Browse/detail logo slots retain
their existing dimensions and fallbacks during loading or image/signing errors.
URLs and pending signing requests are cached by path in memory, renewed before
expiry, and cleared on account changes; previous-account results are ignored.
Refreshing jobs retries failed signing requests while preserving valid cached
URLs. Temporary debug-build-only `[JobMate logo]` diagnostics report project host,
RPC path presence, signing errors/status and image HTTP/decode outcomes; they
omit object paths, credentials and signed URLs.

`Module2Repository.session` retains the isolated fixture application demo,
separate from its real `browse` and `myApplications` repositories. Demo duplicate
checks, stage changes, summary counts and timelines use the fictional source;
the seeker list never reads it. Demo changes reset on
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

This older external-record proposal is superseded by the November 4 Sandbox
scope and [current Payment Handling contract](docs/payment_handling.md).

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

## Responsive layout and navigation audit (November 2026)

All routed screen families share the existing responsive containers. A page does
not need to duplicate breakpoints or import the helper when its `AuthLayout`,
`WorkspaceContent` or `DemoPage` already supplies it:

| Screen family | Shared responsive entry |
| --- | --- |
| Login, registration, email verification, password recovery/change, administrator invitation/acceptance | `AuthLayout` |
| Home, personal profile, company registration/profile, employer posting list/create/edit | `AppWorkspace` + `WorkspaceContent` |
| Job browsing/details, applications/applicants, account settings | `AppWorkspace` + `WorkspaceContent` |
| Recommendations, attendance/evidence/history/report, workers, location, evaluations, reputation, payment records, extended profile previews and admin sandbox | `DemoPage` + `WorkspaceContent` |
| Chat | `AppWorkspace` + content-constrained split/list layout and responsive padding |
| Real admin dashboard | `ResponsiveLayout` + content-height `ResponsiveGrid` |
| Real admin directory/permissions/company verification, notifications, policies | `ResponsiveContent` + scrollable lists and responsive padding |
| Startup/auth/invitation failure states | Shared responsive content/auth containers; loading-only spinners need no multi-column layout |

Content padding follows available width: 16 px below 600, 24 px below 1024,
otherwise 32 px. Navigation retains the existing 768 px sidebar/drawer switch;
both the shell and job form now use that single rule. `WorkspaceContent` measures
the content region after the sidebar is removed. `ResponsiveGrid` calculates
column widths and lets each card grow with its content; it reduces columns as
text scaling grows. `ResponsiveFilter` sizes from parent constraints rather than
subtracting guessed padding from the full viewport. Pagination can stack on a
narrow screen. The real Users page scrolls headings, filters, records and paging
together so short screens and keyboards do not squeeze a fixed-height column.

Web routed pages use the shared `appPage` factory's `NoTransitionPage`; native
pages retain `MaterialPage` transitions. No browser history API is replaced.
Workspace pages keep sidebar/drawer exits and hide inferred Web back arrows.
Standalone pages use `ResponsivePageAppBar`: no Web arrow/empty leading gap, a
text return action, and native Back with a safe fallback for direct URLs.
Detail-page return links keep their text without an arrow on Web. App return
actions preserve existing `PopScope`/GoRouter exit checks; newly added form exits
confirm before losing entered data. Existing job dirty-form guards and profile/
company edit locks are retained. This does not add universal protection against
browser refresh/tab closing or extend dirty checking to every system Back path.

`test/responsive_navigation_test.dart` covers portrait/landscape/tablet/desktop,
1.6x text scaling, content-height cards, keyboard insets, direct-route fallback,
discard cancellation and platform page/arrow behavior. The existing Phase 5.2
25-screen fixtures additionally cover 320 px / 1.6x text and 568x320 landscape /
1.3x text. These are local fixtures, not live Supabase acceptance tests. No
dependencies, backend schema, RLS or Supabase Dashboard changes are required.

Validation for this pass: the full suite reports 367 passing tests and the two
previously documented failures (the obsolete registration `CheckboxListTile`
finder and the router-uninitialized counter smoke test). All 21 new responsive/
navigation tests and all 100 expanded Phase 5.2 screen scenarios pass. Analysis
retains the eight existing diagnostics (deprecated radio properties and unused
home/profile declarations), with no new errors. Formatting, whitespace checks
and Web compilation pass. Chrome runtime tests stalled while loading and were
stopped; browser history/direct-URL acceptance and native Android device behavior
remain unverified. No Supabase mutation, migration, commit or push was performed.

## 5. Security and Collaboration

### Job form route and Admin sidebar fixes

`lib/features/jobs/job_form_route.dart` now gives each pushed Create/Edit Job
route its own form `GlobalKey` and registers the corresponding exit guard by
GoRouter page key. Opening Location Picker above a job form and then Create Job
again no longer attaches one key to two mounted forms. Disposing a route removes
only its own guard. The existing discard, busy/AI and save/list-return behavior
is retained. The posting regression suite uses this production route factory.

The real Admin dashboard sidebar now owns a white `Material` surface, with only
the border on its intervening decoration. ListTile ink/background is no longer
covered by an opaque box. The account dropdown also constrains its two labels
to one line. Its test renders the real dashboard shell, pushes Job Moderation,
returns and disposes the shell with no live account or Supabase requests.

Company logo picking now retains the chosen image bytes/type and preserves the
selected supporting PDF. Independent Company logo updates and Job Seeker resume
management are now implemented in Flutter with a pending backend migration
(see the deployment section below). They are not live until that SQL is approved
and successfully executed against the existing project.
`supabase/diagnostics/profile_assets_inspection.sql` is a read-only catalogue
query for the existing columns, functions, triggers, policies and bucket limits.
It reads no user rows and applies no migration. Keep the existing verification
and owner/member checks; the migration is based on the supplied inspection output.

Focused verification: all 40 posting/Admin Material regression tests pass,
including duplicate Create/Edit route instances and preserving the active form's
exit guard. `flutter analyze` retains the same eight pre-existing diagnostics.
No live upload, Supabase permission change or real account sign-out is tested by
these local fixtures.

### Company photos and personal resumes — pending deployment

The user reports applying `20261103000100_profile_assets.sql`. Do not rerun it.
The follow-up `supabase/migrations/20261103000200_company_logo_approval.sql` is
prepared for review and manual execution, **not applied by the agent**. It upgrades
the existing project; all Resume data and stored images are retained. It creates
new objects without silently replacing conflicting tables. If a new object already
exists, stop and inspect rather than deleting it. No environment changes are needed.

Company Owners click their saved photo to submit JPG/PNG/WebP up to 2 MiB for
Admin approval. Uploads retain the immutable
`<owner-id>/profile-<upload-id>/logo.<extension>` namespace in the existing private
`jobmate-company-logos` bucket. `submit_company_logo_change` checks active Employer,
Owner membership, expected current logo, own exact path and stored MIME/size.
Only one request may be pending per Company; the server accepts an identical
request-ID replay idempotently, but the Logo UI does not offer or perform retries.
The displayed/current logo remains unchanged while pending or rejected.
Owners see their latest request status/rejection reason, with a status refresh.
Refresh the Company profile after approval to fetch the newly approved image.

Company Verification has separate Company documents and Logo changes queues.
The existing Company Review permission is required; reviewers cannot approve or
reject a Company they created or belong to. Rejection requires a reason. Approval
atomically updates only the Company's logo, records the review/history and sends
an in-app notification; verification status, ownership and job permissions stay
unchanged. The dashboard application count continues to count document reviews.
The old `update_company_logo` RPC now rejects direct updates, including old clients.
Regular members have read-only photo UI. Initial company registration still
submits its optional logo alongside the supporting PDF through the existing flow.

`company_logo_change_requests` keeps request/review records. `company_logo_history`
records old/new paths, reviewer and request ID for approved changes, and records
other actual path changes (including onboarding) separately. Its baseline for
already-existing logos records observation time, leaving unknown change/reviewer
dates null. This does not label past logos as Admin-approved. History has RLS with
no client grants/policies: inspect it only through the Supabase Dashboard for now.
There is no logo-history browsing UI or new public/history image-read permission.
Restrictive Storage policies prevent client overwrite/deletion of logo objects;
existing private-read rules remain in effect. Failed/unused uploads are retained;
automatic file cleanup is not implemented.

Job Seeker Resume management reuses `/document-submission`; the legacy Employer
personal-document branch remains available. New versions go to an additive
`personal_resumes` table and private `jobmate-resumes` bucket (PDF, 5 MiB), via
`save_personal_resume`. Active Job Seekers can save regardless of legacy personal
verification status. The server serializes saves per user, validates the actual
stored object/path/metadata, and makes an identical upload-ID retry idempotent.
Neither `users.verification_status` nor Company verification changes. Auth email
confirmation is unchanged. `list_personal_resumes` returns the latest ten versions
and the same user's legacy resume files, newest first; the first is current.
Older files/records are retained; no automatic deletion/cleanup is introduced.

Resume RLS and signed-link creation permit the active owner only. No employer
or public resume-read permission is introduced. Legacy files retain their original
private-bucket permissions. A trigger rejects new Job Seeker verification-request
inserts (including old clients) without rewriting old requests or auto-verifying
accounts. Profile/Home/Admin directory omit the seeker's obsolete resume-review
badge. Actual application/resume sharing is still not connected to the demo Apply
flow; uploading a personal resume does not silently send it to an employer.

`CompanyLogoEditor` releases its selection after a failed upload and offers
Choose photo again; selecting the same image is allowed with a fresh immutable
path. It does not automatically re-upload or resubmit, and no Retry same photo
button is shown. A Storage 403 is reported as denied access, not an uncertain
successful request. Before upload, the client rechecks active Employer/Owner
membership for a clearer error; Storage RLS and submission RPC authorization
remain authoritative. A duplicate-path response is no longer ignored.
After a failed submission RPC, a read-only status lookup checks for an existing
Pending request before another selection is allowed. If the lookup fails, Refresh
logo review status is required; if a request is already Pending, choosing another
photo remains disabled. The database's one-Pending-request constraint also guards
against a delayed response racing a new selection. Old/unused uploads are retained.

For a repeated Storage RLS 403, run the read-only
`supabase/diagnostics/company_logo_upload_inspection.sql` in the existing project's
SQL Editor and inspect the deployed INSERT/ALL policies and bucket limits. Compare
`company_profile_logo_insert` against the original migration's Owner/path checks;
do not rerun entire applied migrations, disable RLS, change the bucket to public,
or add broad upload policies. The November 4 diagnostic result confirms that
`company_profile_logo_insert` is absent, the private 2 MiB image bucket is correct,
and the approval RPC exists. The old onboarding policy alone only permits users
without a membership or Owners of rejected Companies; it cannot authorize other
Company Owners' profile uploads. The targeted repair is
`supabase/migrations/20261104000100_restore_company_logo_upload_policy.sql`.
Review it and run once in the existing project: it adds only the missing scoped
INSERT policy and preserves the approval flow. It deliberately fails rather than
replacing a policy if that name already exists. Do not rerun the older full
migrations to repair this one missing object. No remote policies have been changed
by the agent. After this upload-error UI change, all 37 focused profile-assets and
Company-review tests pass, including denied upload, same-image reselection, lost
submission response and unavailable-status recovery. Analysis retains the same
eight pre-existing diagnostics. Live upload after applying the targeted policy
repair still requires manual verification.

`ResumePage` retains its upload ID/path and bytes for an uncertain result instead
of duplicating a version on retry. Signed PDF links expire after 60 seconds; if the browser blocks the first
window, a retry uses the prepared link. Resume explicit/native Back confirms before
discarding selected input, and busy operations retain loading/navigation locking.
Browser refresh/tab close still requires manual caution, as in the existing forms.
File-header/MIME/size checks are not a full PDF parser or malware scan.

After reviewing/approving the **new upgrade** migration, run that complete file
once in the existing project's SQL Editor, then Hot Restart Flutter. No SMTP,
Gemini, role initialization or separate project is required. Manually verify:
Owner submits a logo; current photo remains; duplicate pending submissions are
rejected; permitted Admin previews both images and approves/rejects; own-company
and unpermitted Admin reviews fail; rejection reason and notification appear;
approved logo loads on Company refresh; history retains both paths; legacy direct
RPC cannot change the image; Company verification stays unchanged. Also verify
existing Resume replacement/read restrictions and legacy files still work.
These server/RLS and native-picker checks are not established by fixture tests.

Local validation before the approval upgrade: the full suite reported 387 passes
and two existing failures in the obsolete registration lookup and router-
uninitialized counter smoke test. After the approval upgrade, all 77 affected
Resume/logo/review/dashboard/job regression tests pass, including 320/1440-width
logo previews with 1.6 text scaling. Analysis retains eight existing diagnostics
in registration/Home/password verification, with no new diagnostics. Neither migration has been executed
or authorization-tested in PostgreSQL by the agent. Native file pickers, live
Storage permissions and physical Android behavior require manual verification.

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

### Real in-app notifications (Module 2 Step 25C)

`NotificationsPage` uses the authenticated client through `NotificationsRepository`.
Both Job Seekers and Employers load server-provided content with
`list_my_notifications(p_limit: 50, p_offset: 0)`. Both parameters are mandatory
in Flutter to select the deployed two-argument overload unambiguously.
`mark_notification_read(p_notification_id)` must return a boolean: true and false
both trigger a fresh list read; false also displays an unavailable message.
Read indicators come only from `read_at`, without optimistic updates.

Account changes clear the list, discard stale reads/mutations and reload for the
new session. Initial load, manual refresh, retry, returning through navigation
and app resume refresh the list. Timestamps display in device/browser local time.
The 50-record list is not a complete unread count. Deep links, dashboard counts
and email delivery are intentionally absent pending their backend contracts.
Focused checks: `flutter test test/notifications_repository_test.dart test/notifications_page_test.dart`.

### Real Job Seeker application actions (Module 2 Step 27A)

Application Details uses the authenticated `respond_to_job_application`
RPC with `p_application_id` and `p_action`. Accept/decline are available only
for Offered applications; withdrawal is available for Applied, Shortlisted,
Interview and Offered applications. Every action requires confirmation.
Declined and Withdrawn remain distinct terminal statuses.

Actions are locked while submitting and refreshing. Both successful requests
and failures refresh the owned application and real history without optimistic
status changes; account changes discard stale responses. Returning to My
Applications reloads the list. Tests use local fakes/mock HTTP only and never
change live applications. Live acceptance testing starts by inspecting Interview
withdrawal without pressing it, followed by an employer offer and deliberate
Job Seeker acceptance after verifying Offered status.

### Flutter learning resources

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)
- [Flutter documentation](https://docs.flutter.dev/)

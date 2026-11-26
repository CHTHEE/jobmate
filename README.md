# JobMate

See the [documentation index](docs/README.md) for setup, feature guides,
verification, deployment references, and design history.

Chat's active attachment design is a Supabase-only **basic university demo**:
JPG/JPEG, PNG, PDF, DOCX and XLSX up to 5 MiB, private Storage and trusted Edge
file-type/content validation. It provides **no antivirus protection** and requires
no external scanner or hosting. CH/KZ approved general activation;
`JOBMATE_CHAT_BASIC_ATTACHMENTS` now defaults true. CH reports backend/Edge activation
and Web image-preview, PDF-download and text-message acceptance successful.
The scanner architecture remains a future
enhancement. See [basic attachments and approval steps](docs/chat_basic_attachments.md).

CH reports the corrected basic attachment rollback trial and exact before/after
catalogue comparison complete. [Disabled backend deployment preparation](docs/chat_basic_deployment_preparation.md)
records that evidence and the separate deployment/QA approvals still required.
That preparation record is historical; see the approved activation steps in
[basic attachment activation](docs/chat_basic_activation.md).

Basic attachment CORS supports normal `flutter run -d chrome` with automatically
assigned HTTP localhost/127.0.0.1 ports. `CHAT_BASIC_ALLOWED_ORIGIN` separately
allows one exact production origin; no per-developer port configuration is needed.
The approved local default does not itself change the backend/Edge release gates.

Chat attachment selection includes Android MIME/iOS document-type filters, and
Android release builds have Internet permission. Shared Chat uses platform plugins
and byte-based previews/uploads. Downloads now use one click: Web opens its download
tab during the gesture, then obtains the authorized URL; mobile uses the system
browser/download UI. Android/iOS device acceptance remains pending.

Image attachments display thumbnails with a tap-to-open zoomable preview;
PDF, Word and Excel attachments use file cards and downloads without an embedded
document viewer. Preview openings obtain fresh authorized short-lived URLs.

The final Chat polish adds compact incoming/outgoing bubbles, navigation unread
dots and automatic reads only for incoming content displayed in a visible thread.
Unread dots use existing RPC/Realtime results; cross-tab read-state clearing has
a 30-second repair refresh without publication changes. See
[Chat UI polish and acceptance](docs/chat_ui_polish.md).

Option B defers automatic hourly attachment cleanup for the university demo.
No cleanup Cron job is registered according to CH's checks. pg_net queue access
and unconfirmed safe http 1.6 redirects remain blockers; the existing authorized
Edge cleanup endpoint remains available for manual maintenance. Abandoned uploads
may accumulate until cleanup runs. Existing secrets/extensions remain unchanged.
Resolve this known limitation before production use; see the
[cleanup compatibility review](docs/chat_basic_cleanup_http_review.md).

## 1. Project Overview

JobMate is a Final Year Project (FYP): an AI-assisted recruitment and workforce management platform developed collaboratively with Flutter and Dart for **Web and Android**. Supabase provides authentication, database access, storage and Edge Functions. Gemini integration is intended to run through a Supabase Edge Function, keeping AI credentials off the client.

### Implemented in this checkout

The worker hiring-membership UI and transport are implemented behind the new
compile-time `JOBMATE_HIRING_MEMBERSHIP` flag, which defaults to **false**. Existing
production builds retain their current application source. Enabling the flag
requires an approved, deployed and verified atomic backend transaction plus the
new applicant-scoped membership read RPC; this flag does not establish backend
readiness. The unexecuted [supported SQL candidate](docs/membership_c3/candidate/001_hiring_membership_supported_candidate.sql)
is outside deployment migrations and is not a complete production release: KZ
onboarding/Admin and remaining authorization compatibility are release gates.
The read-only worker panel supports authoritative active/inactive/revoked/missing
state, loading, failure and refresh without reaccepting or reactivating membership.
No database migration, production activation or real PostgreSQL test is implied.

Multi-company compatibility changes for company onboarding/Home and authorized
Admin account details are prepared for KZ review. Profile context prefers the owned
company and otherwise requires a unique legacy Employer affiliation; ordinary
memberships do not select a management context. Admin details retain all
authorized affiliation rows and reject inconsistent account data. The guarded
coordinated candidate additionally uses historical schema source with mandatory
body/security matching; it remains blocked pending evaluation source, complete
database tests and joint release approval.

- Authentication flows for sign-in, registration, email verification and password recovery/change.
- Role-aware dashboards, personal profiles, document submission, company onboarding and company verification submission/history.
- Administrator invitation/access, permissions, user management and company review screens; notifications with read tracking.
- Employer job listing/filtering, creation, preview, draft saving, publication, published-job editing and closing. Closed jobs are not editable.
- AI formatting client integration: invokes `format-job-description`, validates responses, keeps generated sections editable and displays recoverable errors.

These are codebase capabilities, not confirmation that every workflow works against the deployed backend. The formatting Edge Function source is **absent from this checkout**; its deployment and Gemini configuration require team confirmation.

### User Management Phase 2B (prepared, not deployed)

The `/admin-users` directory is available to every active Admin as a limited,
read-only directory. Its safe detail view uses the separately prepared
`20261106000500_admin_read_only_directory_details.sql` projection and omits
email, phone, restriction history and account actions. Admins assigned
`can_manage_user_accounts` receive full account details, restriction history,
and suspension/reactivation actions through the protected Phase 2B RPCs. The
old
`/admin-preview/accounts` URL redirects to this directory. The migration adds
the separately assigned `can_manage_user_accounts` permission and a
server-written audit table; it reuses `users.status`. Until the migration is
reviewed, tested and deployed, manager-only details and actions are
unavailable. The read-only details migration requires the existing JobMate
baseline followed by Phase 2B and Phase 2D; it adds no management authority.
Neither migration has been deployed or database-tested here.
Existing administrator permission controls fall back to their previous RPC.
The Phase 2B test plan and integration dependencies reference
`supabase/diagnostics/phase2b_user_management_test_plan.md`, which is unavailable in this checkout.
Suspension and reactivation both require a reason. A separate prepared Phase
2B.1 migration adds a read-only, caller-scoped assignment summary for suspended
Job Seekers; the suspended account page can display it after that migration is
reviewed with the assignment owner, tested and applied. The suspension enforcement matrix
(`supabase/diagnostics/phase2b1_suspension_enforcement_matrix.md`) and Phase 2B.1 release review
(`supabase/diagnostics/phase2b1_release_review.md`) are unavailable in this checkout.
The release review
records the live Phase 2A fingerprint result, teammate decisions and disposable
database, real-JWT and Storage test setup. None of those database/API tests has
been executed by the coding agent.

The migration does not revoke Supabase Auth sessions or enforce status across
every existing RPC or module. Existing account gates and active-status checks
cover only their respective paths. Suspended users see their reason at the home
account gate. The inspected live posting and application RPCs check current
account status, but existing deep links, already-open sessions, concurrent
mutations and uninspected Edge Functions still require integration review.
Payment, appeal and dispute access for unresolved
obligations is not yet implemented. Do not treat the prepared feature as a
complete platform-wide suspension control.

### Dispute Resolution Phase 2C (prepared, not deployed)

Separate real-data dispute pages use the RPCs in the prepared
`20261105000500_dispute_resolution.sql` and
`20261105000600_dispute_integration.sql` migrations. They show an unavailable
state until the migration is reviewed and applied in an isolated test project.
The existing preview dispute pages remain explicitly labelled demos. The new
module selects authorized applications/assignments, supports private case-scoped
PDF/image evidence and does not change work, application or payment state.
The dispute design and integration dependencies reference
`supabase/diagnostics/phase2c_dispute_design.md`, which is unavailable in this checkout.
Phase 2C.2 end-to-end integration testing is paused while Job Posting/Application,
Recommendation, and Attendance/Work Verification modules are still in development.
The Dispute module is not considered complete or production-ready.

### Company Management Phase 2D (prepared, not deployed)

The Admin Company Management workspace uses the existing Companies and
membership records. Every active Admin receives a limited directory and
company detail view from `20261106000500_admin_read_only_directory_details.sql`;
the view excludes internal restriction reasons and audit history. Restriction
actions and their history still require `can_manage_company_restrictions` and
the protected Phase 2D RPCs. A separate company-keyed operational restriction state is
kept apart from `companies.verification_status`; restriction actions require the
new `can_manage_company_restrictions` permission and a reason, write append-only
history, and notify Company members. Permission grants are restricted to an
active Superadmin and cannot target themselves. Apply
`20261106000100_admin_company_restrictions.sql` only after the Phase 2B Admin
Management migration in an isolated test database. Restriction enforcement in
Job Posting/Application, Recommendations, Attendance/Work Verification,
Company profile/logo, and payment paths remains pending agreement and integration
with those module owners. Existing jobs, applications, assignments, evidence,
and payment history are not changed by this migration or UI.
`supabase/diagnostics/phase2d_company_restriction_test.sql` is unavailable in this checkout.
It is a rollback-only SQL test for a disposable project and expects synthetic users at
`phase2d-manager@example.invalid`, `phase2d-unpermitted@example.invalid`,
`phase2d-superadmin@example.invalid`, and
`phase2d-target-admin@example.invalid`, plus an owner membership in the uniquely
named `PHASE2D SYNTHETIC TEST COMPANY`. Assign the manager permission only in the
isolated fixture setup and run the test as a project database administrator; it
rolls back restriction actions, audit rows, and notifications.

### User Reports Management Phase 2E (prepared, not deployed)

The real User Reports workspace is separate from the fictional Reports Analytics
demo. Job Seekers and Employers can submit categorized reports against a selected
JobMate User or verified Company using name search; email, phone and other private user
fields are not returned. The server validates targets again and stores a foreign
key to `users.user_id` or `companies.company_id`. Admins with the separately
assigned `can_manage_user_reports` permission can investigate, request information,
resolve or dismiss. Admins cannot inspect or act on reports about themselves, a
Company they created, or a Company they belong to. Report targets are not notified
and cannot read the report, which protects the reporter's identity. Admin actions
require reasons, transitions are recorded in append-only history, and generic
notifications go to authorized reviewers or the reporter. Report resolution does
not suspend accounts, restrict Companies, moderate jobs or change payment state.
The `20261106000200_user_reports.sql` migration depends on Phase 2B followed by
Phase 2D; Phase 2C is optional. Its Admin permissions projection preserves
`can_manage_disputes` when that column exists and reports that Dispute permission
as unavailable when it does not. Prepare an isolated baseline with the existing
Phase 2B and Phase 2D migrations, then run the Phase 2E migration; no live project
was changed. Specific Job Posting target links remain pending the Job Posting
module contract, so reports currently identify only a User or Company. UI tests
use a fake gateway and do not verify deployed RPC authorization, notifications or
navigation.

### Job Moderation Phase 2F (prepared, not deployed)

The real Admin Job Moderation workspace uses existing `job_postings` and
`companies` records. `/admin-job-moderation` is separate from the Phase 4 UI
Sandbox demo. Admins with the default-false `can_manage_job_moderation`
permission can flag a posting, start an investigation, record notes, clear or
restrict it, and restore a restriction. Every action requires a reason and is
recorded in append-only history. Conflict checks exclude jobs created by the
Admin and Companies the Admin created or belongs to. Employer notifications are
generic; internal investigation reasons are not disclosed. Existing posting
statuses, Applications, Assignments, Attendance, Payment, and Trust data are
not changed.

Prepare the database in this order: Phase 2B Admin Management, Phase 2D Company
Restrictions, then `20261106000300_admin_job_moderation.sql`. Phase 2C Disputes
and Phase 2E User Reports are optional; the migration uses a JSON projection
for their optional Admin permission columns and does not require either module.
It also installs a restrictive RLS policy for direct authenticated reads of
restricted postings. The existing published-job SECURITY DEFINER RPC and
future Recommendation queries still require Job Posting/Application owner
integration, so platform-wide visibility enforcement is not complete. The
existing raw `job_postings` access also requires review for salary-field
exposure; this migration's Admin detail RPC deliberately omits salary fields
but does not change teammate-owned job queries.

Phase 3C.5 now has a prepared standalone grant patch at
`supabase/patches/hidden_salary_column_privileges.sql`. It removes direct
authenticated SELECT from the three salary columns while preserving direct
SELECT on the other columns; it does not replace application or employer RPCs.
The patch is guarded by the inspected relation/RPC contract and has a limited
matching recovery script. Its preflight and catalog assertions are in
`supabase/diagnostics/hidden_salary_security_preflight.sql` and
`hidden_salary_security_catalog_test.sql`; the real-client test is
`hidden_salary_security_real_client_test.mjs`. These files are prepared only:
no database ACL has been changed and no authenticated-client test has run.

`supabase/diagnostics/phase2f_job_moderation_test.sql` is unavailable in this checkout.
It is a rollback-only test for a disposable database with synthetic Auth users and fixture jobs. The test
has not been executed against Supabase. The real Flutter pages use the
Supabase RPC gateway; widget tests use a fake gateway and verify presentation,
reason entry, and empty/error states only. A User Report target for a specific
Job Posting remains an integration dependency. Its contract document,
`supabase/diagnostics/phase2f_user_reports_job_target_contract.md`, is unavailable in this checkout.

### Admin access consolidation (prepared, not deployed)

The Admin shell builds one consistent sidebar from the signed-in
administrator's own permission profile. Protected module entries are omitted
when their permission is false or unavailable; backend RPC authorization
remains authoritative. The Admin Permissions page uses its existing
Superadmin-only RPC and does not list Superadmin accounts as grant targets.
The prepared `20261106000400_superadmin_effective_permissions.sql` migration
sets the installed non-account-management Admin permissions for accounts
marked with `can_manage_admin_permissions` and adds `list_admin_accounts_v8`,
which filters those accounts before pagination. `can_manage_user_accounts`
remains a separately assigned privilege; Superadmin status alone does not
grant authority to view account details/history or suspend/reactivate users.
Phase 2C Disputes and Phase 2E Reports remain optional; the versioned
projection treats both permissions as optional. Apply this migration only in
an isolated test project after Phase 2B, 2D and 2F; it has not been applied or
database-tested. Removing Superadmin status clears only the automatic module
grants. Module-specific conflict-of-interest checks remain in force.

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

Module 4 deployment status (2026-11-06, confirmed by the project owner): the four
follow-up migrations below are deployed and catalog-verified in the shared
Supabase database, over the existing `20261105000100` base:

- `20261105000300_work_evidence_attempt_reservations.sql`
- `20261106000100_work_assignment_creation_idempotency.sql`
- `20261106000200_employer_attendance_gps.sql`
- `20261106000300_work_evidence_workflow.sql`

Deployment is complete; do not reapply these migrations. Catalog verification
does not establish runtime authorization, Storage access, concurrency or client
release readiness. Remaining security/device QA and coordinated client cutover
are separate release gates. Keep Module 4 writes paused outside separately
approved synthetic-fixture QA until cutover is complete. The alternative
`20261105000200` prototype is excluded and must not be deployed.

Scheduling release note: the undeployed November 10 candidate now uses
application-row NOWAIT locks for direct schedule UPDATEs to avoid waiting back
on application-first cancellation. Contention raises 55P03 and requires rollback
and whole-operation retry; cancellation and authorization remain unchanged.
The owner reports the previous candidate's B1 31/31 rehearsal and fresh A0 31/31;
the revised candidate still needs compilation/concurrency/API verification.
See [the release sequence](docs/module4_release_execution.md). Neither patch is permanently deployed.

Module 4 production worker attendance at `/work-attendance` now supports
confirmed check-in/check-out through the existing attendance RPCs. The worker
confirms fresh GPS coordinates when available, or retries/continues with denied
or unavailable status and null coordinates. Employers can open a read-only GPS
view with Google Maps links through a separately authorized RPC. Migration
`20261106000200_employer_attendance_gps.sql` is deployed and catalog-verified. See
[GPS behavior and deployment review](docs/work_attendance_gps.md).
The server controls timestamps and eligibility, including the check-in window
from 60 minutes before scheduled start through scheduled end. Actions lock
duplicate submissions and reload authoritative assignments without optimistic
timestamps. Failed responses also refresh before retry; a lost response may have
committed. Existing attendance demos remain separate. This describes the client
implementation; live attendance actions and device acceptance require explicit
testing approval.

The owner reports Batch 1 deployed and manually reviewed on both role screens.
Batch 1 attendance lifecycle UI uses the additive, **not deployed by the agent**
`supabase/diagnostics/module4_attendance_lifecycle_read_candidate.sql`. It wraps
the existing authorized assignment-list RPCs without replacing them, adding one
server statement timestamp per snapshot. Shared Flutter classification uses that
timestamp, never the device clock. Missing-contract fallback retains existing
lists/actions and explicitly reports unavailable timing; permission/network/data
errors do not trigger fallback. Snapshot classifications update on Refresh.
The existing `/attendance/history` URL now uses real owned assignments: All
includes past shifts (using the server snapshot), Recorded requires valid effective
attendance (not payment/work approval), and Issues covers unresolved missed,
overdue, incomplete, inconsistent, late-checkout and disputed records. Future
assignments stay in My Work Shifts. Cancelled work is not Recorded or an attendance
issue. Check-out Overdue begins strictly after scheduled end; Incomplete begins
strictly after end+24h. Both are informational: checkout enforcement is unchanged.
There is no automatic absence, penalty, correction or payment decision. Batch 2
resolution writes/cutoff require separate contract review and approval. Review the
read-only `module4_attendance_lifecycle_read_inspection.sql` and existing B1 catalog
checks before any operator-approved installation. No candidate SQL was executed.

Attendance UI uses compact collapsible job/application groups. Actionable worker
checkout and evidence controls remain visible when a group is collapsed. Worker
evidence uses the same server-snapshot attendance lifecycle as the shift summary;
raw workflow statuses are used for evidence eligibility, not attendance labels.
Ineligible worker closure actions open informational requirements. Attendance
History remains read-only, with an origin-aware return from evidence details.
See [final UI polish and validation](docs/module4_final_ui_polish.md).
The November 16 polish adds consistent action-required colors, a scrollable
evidence form with a bottom submit area, single-dialog employer confirmation,
clear attendance-resolution success, conditional empty-record actions and
separate engagement/closure eligibility labels. See the
[consolidated UI report and Git preparation](docs/module4_final_consolidated_ui_report.md)
for validation, remaining manual correction/cutoff QA and the proposed staging scope.
Current owner-supplied QA (17 November): the functional workflow is complete,
including expired recovery, employer correction, preservation of originals/GPS,
PDF evidence, private employer review and verification. The engagement has five
shifts: four verified and one confirmed absent. Successful closure displayed Closed
and disabled Add Shift. This is owner-reported live acceptance of the existing
workflow, not a browser/device review of the latest presentation changes.
The separate authenticated late-checkout RPC rejection probe was **not performed**;
only the worker UI cutoff and deployed server-side cutoff function were inspected.
The earlier [QA record](docs/module4_final_qa_2026-11-16.md) is historical.

The November 17 polish consolidates effective attendance and collapsed original/
audit records, applies semantic status colors, bounds correction/closure dialogs,
and opens private PDFs from one click with blocked-popup retry. Web PDF preview
dialogs dismiss after successful launch; mobile and image previews retain their
existing behavior. Attendance summaries use neutral responsive time columns with
original device records and nested technical details collapsed initially. Sidebar action
indicators use only the active page's loaded authorized snapshot; they are not
global counts and add no queries. New Chrome and physical Android acceptance is
pending. See the [implementation and regression report](docs/module4_ui_polish_2026-11-17.md).

CH reports Batch 2 **deployed to the existing live Supabase database on
14 November 2026**, using
`supabase/migrations/20261114000100_attendance_resolution_candidate.sql`.
Permanent execution returned `Success. No rows returned.` The post-deployment
verification passed **34/34 checks**, with every `passed` and `all_checks_passed`
value true and no SQL errors. Do not rerun this or previous migrations.
The migration uses the owner's live-definition export and aborts on dependency drift. One
immutable assignment-scoped employer resolution records reason, actor, server
time, request ID, original attendance/GPS snapshot and separate corrected times.
Correction is permitted only for ended, open, unverified shifts before any
evidence attempt/submission; after a resolution, changes require a separately
reviewed superseding-audit contract. Confirmed absence requires untouched attendance
and does not change the assignment to completed/verified. Clients cannot directly
read or write the audit table. Existing lifecycle signatures remain; optional
resolution metadata enables the real Review Attendance dialog only when the
backend supplies eligibility. Requests use an explicit preview/confirmation,
optimistic version, application-first locking, one resolution per assignment and
payload-matching idempotency; uncertain results retain the same request for manual
reconciliation/retry. Original timestamps and GPS are never overwritten.
Affected attendance/assignment writes require READ COMMITTED, including trusted
writers, to prevent an old repeatable-read snapshot from bypassing resolution
guards. The existing authenticated API was measured as READ COMMITTED; confirm
any additional trusted writers during controlled integration QA.

The same migration installs the correction path AND ordinary checkout cutoff:
scheduled end+24h inclusive; after it, employer correction is required. Historical
active shifts without an eligible correction path abort deployment.
Manual correction may record a true checkout beyond that ordinary cutoff, up to
the resolution's server time, with an explicit reason/actual-time confirmation.
Corrected check-in still stays inside the original check-in window. Effective
attendance is read through a private view by the fingerprint-guarded existing
evidence/verification functions. The advisory evidence target remains effective
checkout+24h, even when already overdue after a historical correction; it never
blocks submission or approves pay. Check-in and the 15-minute grace rule remain.
Normal closure continues to require at least one verified shift, and accepts
audited absence for remaining shifts while retaining cancellation, reservation,
dispute and existing closure audit checks. Resolution never closes an engagement.

An all-absent engagement remains ineligible for normal successful closure. A
future explicit `unsuccessful_no_work` closure outcome would require a separate
schema/contract review with KZ: all shifts resolved absent or audited cancelled,
no verified work, no unresolved reservations/disputes, explicit employer reason,
and an immutable decision. Evaluation/reputation eligibility currently tied to
closure must be reviewed before introducing that outcome. No such path or KZ
side effect is implemented by this candidate.

The completed deployment sequence used the dependency inspection, read-only
preflight, rollback compilation rehearsal, permanent migration, then
`supabase/diagnostics/module4_attendance_resolution_post_deployment.sql`.
These catalog checks do not establish runtime authorization, concurrency or
end-to-end workflow acceptance. Those remain subject to controlled manual QA
in Chrome with the existing employer and job seeker test accounts. Old B1
fingerprints for intentionally changed functions differ; do not restore old
functions or reapply migrations to make those historical checks pass.

The November 14 Batch 2 pre-deployment validation now pins the six actual Supabase
DDL hooks and existing dependency ACLs. CH reports the read-only preflight passed
at 16:29:47 MYT. CH also reports the strengthened rollback rehearsal passed with
`BATCH2_ALL_CHECKS_PASSED_AND_BASELINE_RESTORED`: PostgreSQL creation, asserted
catalog/cutoff checks and original baseline restoration passed. Real authorization/
concurrency and workflow integration remain unverified. Follow the QA checklist, limitations and
targeted staging list in [Batch 2 deployment handoff](docs/module4_batch2_deployment_handoff.md).
Launch the updated application from the project root with `flutter run -d chrome`;
startup uses the existing bundled `.env`, without additional Dart defines. The
deployed SQL and rollback artifacts are retained as deployment records.

Module 4 cards use server-derived status banners and contextual evidence actions.
The employer Work Verification route presents Work Assignments & Verification
with loaded-record summary counts, local job/worker search, and job, shift and
verification filters. Awaiting-verification counts use `pending_review`; Verified
uses `verified`, independently of assignment/attendance status. Counts describe
the loaded authorized projection, not a guaranteed complete company total.
Worker-name search reuses the existing authorized name lookup and omits unavailable
names. Compact shift cards preserve GPS, evidence, Add shift and closure actions.
Application cards start collapsed, show their summary and Add shift action,
preview the nearest matching upcoming shift when available, and retain their
individual expansion state across refreshes on the same page.
The short Work Verification sidebar label remains; Attendance Review (demo) is
hidden from normal employer navigation but its direct route remains available.
Workers (demo) and Payments (sandbox) are unchanged.
Worker attendance details and authorized employer Work Verification show an
informational On Time/Late check-in label using saved server timestamps: exactly
15 minutes after scheduled start is On Time; later is Late. No check-in means no
label. This presentation rule does not affect status, eligibility, review or pay.
The Add shift/Create Assignment dialog uses one `Shift date (MYT)` and Material
clock pickers with AM/PM display. Both timestamps use the selected Malaysia date
(UTC+08:00), independent of device timezone; overnight shifts require separate
daily assignments. Field errors appear after Review and clear as values become
valid. Review/explicit confirmation and server scheduling checks remain required.
The review stays open and shows Saving assignment while the request is pending.
An uncertain result offers Check current assignment to reconcile the request.
New shifts require a hired application for a Part-Time or Temporary posting.
The Flutter selector filters these types. Apply
`20261120000300_require_shift_eligible_employment_types.sql` after the workplace
coordinates and Temporary posting migrations to enforce the rule on new
assignment inserts. Existing assignments remain visible.
The picker alone caps text scaling at 1.3 to keep its fixed-size Material controls
usable on narrow screens; the surrounding scrollable form retains full scaling.
Worker attendance groups shifts by hired application ID, with the job title,
company name and shift count shown once per group. My Work Shifts starts with
groups collapsed and previews the next upcoming shift. Shifts that need worker
action stay accessible while collapsed. The Show application shifts control
appears below the preview or summary. Employer and worker shift lists show
actionable shifts first, followed by upcoming shifts nearest first and past
shifts newest first.
Collapsed worker groups highlight the next shift’s date, MYT time and saved
workplace. Upcoming shift details lead with the schedule and check-in guidance.
Employer upcoming details also lead with the shift schedule and workplace.
Authorized detail and history views show original attendance, correction reasons,
resolution times, and verification events in readable form. Internal identifiers
and server snapshot diagnostics are omitted from routine views.
Employer verification details, Worker shift details, and expanded Worker shift
cards show effective attendance in responsive time cards. Evidence submissions show the full worker note,
submission metadata, and attachments in separate sections.
The normal Job Seeker menu shows My Work Shifts; attendance demo routes remain
available directly but are hidden from the menu. Shift cards group workplace and
recorded check-in/out times. Saved GPS status is not returned by the worker
shift-list RPC and is labelled as unavailable in this summary; none is inferred.
Checkout has a separate irreversible-shift confirmation before the GPS prompt.
Confirmed attendance uses snackbars; confirmed evidence submissions and reviews
close their dialogs and refresh server state. Unsaved drafts retain exit guards,
and uncertain outcomes stay locked for reconciliation. Evidence groups show the
latest submission first, with earlier rounds and history collapsed. Private file
previews and backend eligibility checks remain authoritative.

Production assignment cards now open read-only evidence metadata at
`/work-attendance/:assignmentId/evidence` for active Job Seekers and
`/work-verification/:assignmentId/evidence` for active Employers. Direct entries
resolve fresh authorized assignment lists; employer company selection comes
from existing company-access checks, never URL parameters. Submitted images can
be previewed and PDFs opened in the browser/PDF app using private, 90-second
signed links after fresh assignment and per-file authorization. No public links
are created. The separate `/attendance/evidence` demo remains unchanged.

Employers can create additional non-overlapping shifts for the same hired
application using Add shift on each expanded employer assignment group. Groups
use application ID, show the hired worker, job title and shift count, and list
shifts chronologically. Add shift resolves that application against fresh
authorized eligibility data; unavailable applications cannot be substituted.
Each assignment represents one shift with a future start, a strictly later end,
and both times on the same Malaysia (UTC+8) calendar date. Multi-day work requires
separate daily assignments; overnight shifts are rejected by Flutter. Matching
server enforcement is proposed in `docs/work_shift_schedule_validation.sql` for
review only and has not been deployed. No worker availability form or per-shift acceptance is added.
Attendance, GPS, evidence and verification remain independent per shift.
Employers can also use the existing Create Assignment selector for a hired
application from Work Verification, with explicit worker/job/company/MYT schedule
and workplace confirmation. A valid workplace from the selected posting
prefills the new shift. The employer can change that text before confirming,
and each shift stores its own reviewed workplace. Creation requires the
server-issued request-ID contract; there is no direct-write fallback. Uncertain
responses block further writes for that application's running session.
Reconciliation uses the request ID only.
Migration `20261106000100_work_assignment_creation_idempotency.sql`
is deployed and catalog-verified. Environments without that contract fail closed. Server
request identity and duplicate protection survive client restart; local unresolved
locks do not. Never refresh/restart to retry an uncertain action.
Reopening a dialog for an unresolved application retains the read-only Check
current assignment action; it reconciles the original request without another
creation attempt. See the [Module 2/4 integration review](docs/module2_module4_integration_review.md)
for regression coverage and remaining backend/device acceptance gates.

Assignment creation saves the reviewed address and optional pin per shift
through the coordinate-aware v2 request contract. If the v2 reservation RPC
is missing, a reviewed text-only shift can be explicitly saved in compatibility
mode. Pending requests and pinned shifts are never downgraded.
Confirming a Geoapify result in the shift picker fills the shift address and
pin together. Confirming a manually moved pin keeps the existing shift address.
Editing a pinned shift address clears the pin from the draft until the employer
explicitly verifies that the previous pin still matches the edited workplace.
Work Verification and My Work Shifts, including history, display the saved shift
address and offer a Google Maps link when that shift has a valid saved pin.
See [Stage 2B.2 deployment and rollback notes](docs/work_assignment_workplace_coordinates_review.md).
No live assignments or evidence/verification records were changed.

Phase 4 future-shift editing/cancellation is audit-only: no verified edit/cancel
RPC exists in the checked-in contracts, so no UI actions were added. The existing
`cancelled` shift status does not establish mutation safety. See the
[backend capability audit and proposed contracts](docs/future_shift_management_audit.md)
for authorization, future/unstarted guards, cross-company overlap, concurrency,
creation-request compatibility and required migration/tests. No SQL was executed
and no migrations, policies or RPCs were changed.

The local evidence workflow now supports checked-out worker PDF/image submission,
authorized private PDF opening, employer verification or requests with a reason,
worker resubmission and shared verification history. It requires the reviewed
server-reservation and workflow/cutover migrations; both are deployed and
catalog-verified in the shared database.
The client fails closed without the new contract. GPS and repeat-shift work remain
unchanged. Existing local-only draft and supervised QA code remain separate;
general workflow controls exclude the protected QA assignment. Legacy QA write
calls are intentionally restricted by the deployed cutover grants. No protected records
were accessed or changed. See [evidence workflow and migration order](docs/work_evidence_workflow.md)
for overlapping drafts, recovery rules and isolated/live QA prerequisites.

Phase 6 adds a suggested initial evidence target of recorded checkout plus 24
hours, displayed per shift in MYT. Due soon means the final four hours; Overdue
is advisory, uses the device clock and never blocks eligible late submissions.
Submitted/Verified and More Evidence Required take precedence; no new resubmission
deadline, automatic failure or extension request is introduced. See
[deadline behavior, source audit and reminder design](docs/evidence_deadlines.md).
Reminders require separately reviewed backend support and are not implemented.

Final Module 2/4 polish checks the worker's owned applications before enabling
Apply, uses direct 24-hour MYT shift-time input, blocks confirmation of known
schedule conflicts, and shows prominent attendance-failure dialogs. See
[root causes, behavior and acceptance limits](docs/module2_module4_ui_polish.md).

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

### Real-data Job Seeker dashboard

The dashboard uses one owned applications snapshot for current status counts,
recent applications, and recommendation exclusion. Recommendations use the
existing deterministic matcher and appear only when the application RPC snapshot
can be verified complete. A partial published catalogue is labeled, and For You
remains available. The dashboard makes no recommendation insight requests.
My Work and My Reputation load independently from their existing authorized
sources. The worker reputation card uses released evaluations and verified
completed shifts. Dashboard demo state remains available to the legacy demo routes.

### Real-data Employer dashboard

The Employer dashboard shows loaded posting counts and up to three published
postings with open deadlines. Posting and work reads load independently after
existing employer and company access checks. Work Management and Worker Overview
reuse the scoped Work Verification assignment snapshot and its server timing.
Review Applicants opens the existing posting selector. Company-wide applicant
totals, recent applicant rankings, and worker ratings are omitted because the
existing reads are scoped to individual postings or applications.

### Employer posting compensation

Create and Edit Job Posting use employment-specific pay units. Full-time and
Contract allow Monthly or Yearly, Part-time and Temporary allow Hourly or Daily,
and Internship uses Monthly. Changing units with salary amounts entered requires
confirmation and clears the amounts for re-entry. Unrelated edits preserve
legacy terms. Legacy drafts need compatible terms before first publication.
Posting eligibility does not establish Payment Handling coverage.

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
- The Job Seeker dashboard keeps search beside notifications in the top bar, a compact profile-completion checklist, demo applied-company cards, and a future-evaluations placeholder. The checklist disappears when name, email, phone and photo are all present; the Employer's completion progress also disappears at 100%. Demo applications remain clearly labeled and separate from real account data; no evaluation score is shown until that feature exists. On Web and Android, the dashboard search button opens a panel near the top center with a light background dim, without changing the URL; Web notifications open a compact panel at the upper right. The Admin dashboard uses the same Web notification panel. Search history is kept only while that panel is open; it starts empty. Android notifications retain the existing focused page. The Jobs action opens the real Browse Jobs catalogue at `/jobs` with the optional keyword in the URL. The old `/search` URL redirects to Browse Jobs, and `/notifications` remains available. Companies calls `search_public_companies` for verified company name, industry and location only, once the new migration is reviewed and applied; People shows no results until public/private profile controls exist. The company function does not expose documents or private logos.
- Do not stretch mobile-style full-width forms across large desktop screens. Size forms and dialogs appropriately for desktop.
- Avoid redundant top-left AppBar back arrows when clear in-app navigation exists. Provide Cancel, Back to Job Postings, breadcrumbs or sidebar navigation as appropriate. Never rely exclusively on browser Back.
- Preserve browser Back, Forward, refresh and direct URL navigation through the existing router. Verify authentication and route-state behavior rather than assuming every flow survives refresh.
- Protect unsaved changes when leaving forms where feasible, including browser navigation where supported.
- Support mouse, keyboard, Tab navigation, visible focus indicators and appropriate hover states. Mobile-only interactions must not be the only way to access a feature.

### Android requirements

- Use touch-friendly layouts, comfortably sized targets and mobile-appropriate dialogs, spacing and navigation.
- Use the shared bottom NavigationBar at root destinations, including wide tablets. Three primary role destinations, a separate Account avatar and More are shown where the account menu is enabled. Account opens profile and settings; More opens the grouped navigation sheet with Sign out at the bottom. The mobile More sheet omits Dashboard and Job Seeker Browse Jobs; the Job Seeker Jobs tab opens `/jobs`, while the dashboard search icon opens the search panel. Web sidebar entries remain available. Screens that intentionally hide the account menu retain only More. Do not render the Web sidebar/drawer as native primary navigation.
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

Create/Edit Job provides a manual workplace map picker using MapLibre GL and
OpenFreeMap's Liberty style. Enter the address, pan the map to position the pin,
and confirm. New on-site and hybrid postings require a confirmed pin before
publication, including publication from the draft list. Incomplete drafts and
unrelated edits to existing published postings without a pin are supported.
Changing a published workplace address requires reconfirmation. Saving a remote
posting clears any stored physical pin. The picker depends on network access and
a WebGL2-capable browser on Web. Android map rendering requires API 24 or later
and a build JDK supporting Java 21. Location selection uses the existing posting
RPC and leaves the address exactly as entered apart from existing trimming.

Explicit workplace place search is prepared locally behind an authenticated
Supabase Edge Function and a private quota migration. Manual pin placement works
while search is unavailable. See [workplace search setup and quota design](docs/workplace_place_search_design.md).

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

Browse Jobs supports keyword, employment type, work arrangement, and city or
state text filtering. Geoapify place search, radius filters, and workplace
distances belong to the real Nearby Jobs experience. Its List and MapLibre views
share one filtered result set behind the existing Job Seeker gate at
`/nearby-jobs`. Results require a complete catalogue. To verify the
production baseline, inspect the `list_published_jobs` response while signed in as an active Job
Seeker and compare its `Content-Range` total and JSON row count with the
database eligibility count from the same period (7 at the Phase 2D audit).

#### Job Seeker place search deployment

The separate endpoint returns up to five validated Malaysian Geoapify results
to active Job Seekers. It shares the Employer endpoint's private quota ledger
and transaction lock. Across both endpoints the limit is 2,000 reservations per
rolling 24 hours and two per rolling second. Each account has a 20-per-rolling-day
limit and a three-second cooldown. Reservations count before provider dispatch,
including failed provider requests. External use of the Geoapify account is
outside this budget.

After approval, deploy through the Dashboard in this order:

1. Confirm the Employer quota RPC uses the shared ledger, lock and quota limits.
   If the Job Seeker migration has already been applied and its permission
   checks passed, skip SQL Editor. For a fresh deployment, run
   `supabase/migrations/20261119000100_job_discovery_place_search_quota.sql`
   once. Verify effective EXECUTE is denied for `anon` and `authenticated` and
   granted to `service_role`. Keep the existing private schema outside the Data
   API exposed schemas.
2. Under Edge Function Secrets, retain the existing server-only
   `GEOAPIFY_API_KEY`. Leave `JOB_DISCOVERY_SEARCH_ALLOWED_ORIGIN` unset for
   Flutter Web on HTTP `localhost` or `127.0.0.1` with dynamic ports, and for
   Flutter Android. Android requests can omit `Origin`. Other browser origins
   are denied unless they exactly match the configured origin. If hosted Web
   is added later, set the optional secret to the exact origin (scheme, host,
   optional port, and no path or trailing slash). The function uses the
   runtime-provided `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
   `SUPABASE_SERVICE_ROLE_KEY`.
3. Under Edge Functions, choose **Deploy a new function**, then **Via Editor**.
   Name it `search-job-discovery-places` and replace `index.ts` with
   `supabase/dashboard/search-job-discovery-places/index.ts`. Deploy only this
   function. Keep gateway **Verify JWT** enabled for the new function and
   test with the Flutter app's real Job Seeker session bearer. The handler also
   validates the bearer with Supabase Auth. If a valid session fails at the
   gateway, check the project's JWT configuration before changing the setting.
4. Verify localhost Web preflight, an Android lookup, signed-out denial, and
   cross-role denial on both endpoints. Test hosted Web only if configured. Confirm
   the Job Seeker can read their own role/status with their session token, and
   check catalogue completeness and radius filtering in Nearby Jobs. Keep
   production smoke tests small and use local mocks or a separately approved
   isolated database for quota boundary and concurrency testing.

To roll back, disable or remove only the new Edge Function, then run
`supabase/rollback/20261119000100_job_discovery_place_search_quota_rollback.sql`.
It drops only the Job Seeker reservation RPC. Keep the shared ledger, Employer
function, and Geoapify secret in place.
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
title, company, date and status, with a work icon, compact summary counts and
a responsive action footer. No logo, resume
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
labeled and Apply is disabled. Hidden or missing salary displays as Salary not disclosed.
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

Focused coverage is in `test/job_marketplace_application_workflow_test.dart`: filtering/sorting, salary
projection, status mapping/invalid transitions, duplicates, expiry, cross-role
state/history, reset, access states, responsive pages/modals, internal-note
visibility and direct-route fallback. Run `flutter test test/job_marketplace_application_workflow_test.dart
test/workspace_test.dart test/job_postings_test.dart`. Platform acceptance and
live Supabase/AI behavior still require separate verification.

### Phase 3 — Modules 3, 4, 5 and 10

This table records the original preview routes and their current entry points.
For You uses the real Phase 1A data flow described below. Demo routes continue
to use fixture records behind their existing account gates.

| Figma screen | Route / entry | Implemented presentation |
| --- | --- | --- |
| JS-05 | `/recommendations` | Real For You with estimated fit, matching skills, supported skill gaps, filters and sorting |
| JS-06 | Apply on a recommendation | Job Details opens the existing responsive Apply form after its application checks |
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
| JS-07 | `/nearby-jobs` | Real Map/List views, Malaysian place selection, 5/10/20 km radius, employment type, workplace markers and published job cards |
| JS-08 | `/nearby-jobs/:jobId` | Legacy redirect to the gated Nearby Jobs root. Current job cards open `/jobs/:jobId`. |
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

#### For You Phase 1A

`/recommendations` uses the existing published-job feed, the signed-in seeker's
profile and caller-scoped application list. It excludes expired and already
applied jobs. A failed read shows a retry state. Save Job uses the same
session-only list as Browse Jobs.

For You uses a two-column recommendation grid when the workspace has room
and a single column on smaller screens. A percentage and progress bar appear
when the match has enough evidence. Matching skills and the rule-based
explanation remain visible when optional AI insights are unavailable.
**Load AI insights** makes one explicit request per page visit.
Supported guidance appears in a separate callout on each job card.

Estimated Match uses 50% skill overlap, 30% headline, bio and work-experience
keyword overlap, 10% selected employment type and 10% selected location.
Available category weights are normalized to 100%. A score requires two
comparable explicit skills, or a comparable posting overview and background
with an independent skill or preference signal. Skills are
compared using normalized whole phrases. Skill gaps use explicitly labeled
skill lists in posting requirements. Profile proficiency is loaded but carries
no weight because postings lack a comparable proficiency scale. The estimate
describes fit. Salary comparison uses the disclosed minimum within the selected
pay period. Preferences and recommendations are computed on demand.

Phase 1A uses Flutter and the existing Supabase read contracts. Phase 1B
verifies runtime behavior in Shared before Gemini explanations are added.

Chat is between fictional role personas, not signed-in accounts. Enter sends and
Shift+Enter inserts a newline; an explicit Send button supports touch. Attachment
drafts and sent files stay in memory. Opening a thread marks sample incoming
messages read; a labeled control advances Sent → Delivered → Read for sample
outgoing messages. Every receipt is visibly simulated; there is no actual online
presence or automated fake reply. Search, unread counts and messages share one
source across both role views. No administrator chat interface is added.

Nearby Jobs computes straight-line distance from an explicitly selected place
to eligible on-site and hybrid workplace pins. Map and List share the same
radius-filtered results. Remote and coordinate-less jobs remain available in
Browse Jobs. The separate employer demo picker uses **DEMO GRID X/Y out of 100**.
Its confirmed address/marker are isolated from `job_postings.location`,
`latitude` and `longitude`; it cannot update a real posting.

Figma inconsistencies resolved: percent-based map coordinates are no longer
mislabeled latitude/longitude; placeholder View Job/Evidence/History actions now
open actual local views; the static RPT-01 uses current session records instead
of unrelated identities/dates; recommendation thresholds use one definition;
fake online/GPS/legal-verification claims and reputation scores are omitted.
Real feature logic takes precedence over prototype simulation. Existing fallback
fonts and teal/slate/white Material styling are reused without dependencies.

#### AI recommendation insights

`JOBMATE_RECOMMENDATION_AI_NOTES` defaults to `true` in Flutter. Run
`flutter run -d chrome` to show **Load AI insights** for eligible results on
For You. Flutter requests insights only when the Job Seeker clicks the button.
To hide the control and disable requests from the app, run
`flutter run -d chrome --dart-define=JOBMATE_RECOMMENDATION_AI_NOTES=false`.
The `recommendation-insights` Gemini provider is disabled by default on the
server and its tests use mocked HTTP.
Run them with
`node --test --test-isolation=none supabase/functions/recommendation-insights/index.test.mjs`.

The adapter sends `{"job_ids":[...],"insights_version":1}` with one to five
job IDs to JobMate's Edge Function. The handler verifies the bearer and
active Job Seeker role, then checks the caller's published feed and application
list. Filtered RPC responses need an exact count so incomplete reads fail
closed. The closing date remains inclusive, using Kuala Lumpur time on the
server. Gemini receives only request-local aliases, allowlisted public employment
types and work arrangements, plus the fixed `insights-v1` instructions,
hypothetical scenarios and template catalog. Every job receives the same
three hypothetical scenarios. Real IDs, scores, skills, profile and preference
evidence, application history, and raw job text stay inside JobMate.

Gemini returns `{"insights":[...]}` with one row per alias. Each row contains
`job_id` and `strong`, `partial`, and `limited` choices with `why`,
`consider`, and `next` template IDs. The ID `"0"` omits a section. Edge maps
aliases back to JobMate job IDs and adds `insights_version: 1`. Flutter checks
the version, plan, and each template's local evidence before rendering. Its
presentation bands are strong at 70% or above, partial for any lower numeric
score including 0%, and limited only for a null score. The scoring formula
and ranking remain unchanged.

The team confirmed the live `recommendation-insights-v1` baseline in Shared on
24 November 2026. The browser received OPTIONS 204 and POST 200 with an upstream
processing time of 2,006 ms. For You showed **AI insights loaded** and personalized
sections, with the estimated match, skill chips and existing job actions still
available.

The team also confirmed Phase 3C wording in Chrome on 24 November 2026. The
`recommendation-insights` function returned OPTIONS 204 and POST 200, with a
2.40-second POST in Chrome. The Software Developer Intern card at BCD123 showed
the 32% estimated match, Git and JavaScript overlap, and the matched Full-time
preference. It displayed all three insight sections, including the local project
tip labelled **JobMate suggestion**. This acceptance covers that Chrome scenario.

Phase 3D uses a mint callout with icons, structured evidence emphasis and a
quieter deterministic explanation when scored AI insights are visible. The
visual checks use mocked data; Android device acceptance is pending.

Phase 3E separates **Your job matches** (including a genuine 0% match) from
**Other opportunities to explore**. Both Browse Jobs and For You use the same
caller-scoped published feed. For You additionally excludes jobs with a past or
missing deadline and jobs in the seeker's loaded application history. Browse Jobs
can show expired listings as unavailable. Publication, company and moderation
visibility depend on the feed RPC. The client follows up when a readable exact
total shows more published rows exist. A missing count, an internal RPC limit,
or limits on the unfiltered application-history read still need Shared evidence
to confirm completeness. The prior six Shared checks covered filtered fixtures.

Employment filters use Full-time, Part-time, Contract, Internship and Temporary.
Salary periods use Hourly, Daily, Monthly and Yearly. Any period includes jobs
with undisclosed pay; a selected period requires disclosed pay in that period.
Location uses the exact published label, so `Selangor` and `Serdang, Selangor`
are separate options. Any match includes unscored jobs; 25%, 50%, 70% and 90%
thresholds require a computed score. Best Match uses score, newest publication
and job ID; Newest and unscored results use publication date and job ID.
The location and employment dropdowns also feed the existing 10-point preference
comparisons. They affect the weighted average alongside comparable skills (50)
and background keywords (30). Only comparable components contribute to the
denominator, and the result rounds to a whole percentage. The observed 9% to
32% change is consistent with background-only scoring corroborated by prose
skills, plus the full 10-point employment match once selected. The exact input
counts for that live fixture were not recorded. Saved preference inputs separate
from visibility filters would require separate approval because the score
behaviour would change.

Phase 3I adds **How is my match calculated?** above the For You filters. The
panel starts collapsed and explains the base weights, normalization over
comparable factors, limited evidence and ways to keep profile details current.
Opening or closing it keeps the selected filters, scores and loaded AI guidance
in place. For manual acceptance, open For You in Chrome and on Android, expand
and collapse the panel, and repeat after setting a salary period and loading
AI insights. Confirm that the minimum pay field and results are preserved and
the toggle sends no new insight request. Check wrapping with larger text on
Android and at narrow Chrome widths.

The For You page explains the optional **Load AI insights** action below the
filters. One successful request per page visit covers up to five visible scored
jobs with supported posting facts. The success notice explains that filters do
not require reloading insights for covered jobs. Cached plans are rendered with
current match evidence, and newly revealed uncovered jobs keep their normal
cards. Temporary failures retain the existing notice and offer manual retry after a 30-second
account cooldown, which also applies when leaving and reopening For You. The
deployed endpoint sends no `Retry-After`, and the Flutter SDK does not expose it.
The client keeps deterministic results visible for unavailable or invalid responses.
The team confirmed the Phase 3E sections, canonical filters, filtered empty
state, reset, 9% to 32% preference change, fallback and retry countdown in
Chrome. A later one-job POST returned 504 after about 5.49 seconds. The manual
retry returned 502 with `provider_unavailable` from `recommendation-insights-v1`
and 3,403 ms upstream service time. That category does not identify which
provider call or validation step failed. An RPC error or invalid exact count
returns 503 unless the handler deadline expires. The client uses an unavailable
state for 503, which also covers disabled or misconfigured service.

The team reported successful live Chrome runs of both AI features and verified
that, for the tested job, Monthly kept the match at 9%, Full-time raised it to
32%, and adding Selangor raised it to 46%. Newest kept 46%, Hourly hid the job,
and Clear filters restored 9%. Covered insights adapted locally without
another request. These observations precede the Phase 3H presentation changes.

Flutter now adds concrete matching skills, shared keywords, selected preference
matches and estimated-match context to supported template choices. A missing or
unsupported next-step template can receive a separately labelled **JobMate
suggestion** when matching skills support one and another AI-selected section
is displayed. If the AI request fails, the existing deterministic card explanation
remains visible. The request and Edge contract are unchanged.

The provider uses the Gemini v1 Interactions endpoint. It sends the configured
model, `store: false`, a JSON string containing the fixed instructions and
allowlisted job facts, and a structured JSON response schema. The legacy path
retains 512 output tokens. V1 uses compact template IDs and a 1,024-token cap
for up to five rows. Phase 3F removes duplicate scenario constraints from the
prompt, retains them in the schema and validator, and explicitly uses minimal
thinking for the documented `gemini-3.5-flash-lite` model. It keeps the current
model selection and one attempt. The local Phase 3F budgets are 12 seconds for
Gemini (including reading its body), 16 seconds for the Edge handler, and 20
seconds for Flutter. The margins leave room for Auth, RPC reads, validation,
and client transport.

The team confirmed the manual Phase 3F deployment in Chrome. The deployed
`recommendation-insights-v1-reliability` returned HTTP 502 with `provider_http`
and upstream 503. Deterministic matches and the cooldown remained usable.

For a future approved update, use `recommendation-insights` in the Supabase
Dashboard editor. Paste only
[`supabase/functions/recommendation-insights/index.ts`](supabase/functions/recommendation-insights/index.ts)
and keep Verify JWT enabled. The existing `explain-job-recommendations` stays
available for older builds. Its four-file bundle under
`tools/recommendations/dashboard-deployment/` belongs to that older slug.
The single `index.ts` above is both the source and the Dashboard package for
`recommendation-insights`. No new secrets are required.

For a failure, inspect the recommendation POST in Chrome DevTools
under **Network → Headers → Response Headers**. The diagnostic build emits
`X-JobMate-Recommendation-Revision: recommendation-insights-v1-reliability`. A missing or
different marker leaves the active deployment or response path unconfirmed.
A 400 `invalid_shortlist` also includes `X-JobMate-Recommendation-Rejection`
with one fixed category: `body_read` (missing, unreadable or over 1 KiB),
`json_parse` (invalid UTF-8 or JSON), `request_fields`, `request_version`,
`shortlist_shape`, `job_uuid`, or `duplicate_jobs`. For 502, the header
distinguishes `provider_http` (with numeric
`X-JobMate-Recommendation-Upstream-Status`), `provider_transport`,
`provider_incomplete`, `provider_response_json`, `provider_response_shape`,
`provider_response_too_large`, `provider_output_json`, `provider_output_shape`,
`provider_alias_invalid`, `provider_template_invalid`, and internal provider
errors. A 504 distinguishes `provider_timeout` from `handler_timeout`. An
upstream 429 retains the outer 429 and includes the upstream status; the
function's own limit has no upstream status. Share only the status, the fixed
`error` field, and these diagnostic response headers.

After deployment approval, enabling the server provider requires all three
server-side settings:

- `JOBMATE_RECOMMENDATION_GEMINI_ENABLED=true`
- `JOBMATE_RECOMMENDATION_GEMINI_MODEL` set to the explicitly approved model ID
- `GEMINI_API_KEY` available as a Supabase Edge Function secret

Set the optional `JOBMATE_RECOMMENDATION_GEMINI_DEMO_USER_ID` to restrict
access to one Supabase Auth user UUID. Other authenticated users receive
forbidden. A malformed or empty value returns unavailable. If the setting is
absent, all eligible active Job Seekers can use the enabled provider. Broader
activation requires team approval and an agreed shared Gemini quota budget.

There is no default model or automatic model fallback. The formatter's model
and free-tier eligibility do not establish recommendation access. Omit the
enable setting or set it to `false` to keep the provider off.

Before deployment, approve the cutoff time zone with the posting owner.
The Shared fixture verification below covers both filtered RPC projections
and exact count headers for the tested requests. Approve the Web origin,
free-tier model, server-side credential reuse and shared quota budget with
the deployment owners. The
local handler limits authorized attempts to one per user per 30 seconds and ten
per minute per instance. A shared quota needs a separately approved deployment
plan. Verify v1 structured output and the exact payload with synthetic data
before enabling the server provider. The existing employer formatter is separate.

#### Isolated Gemini recommendation smoke check

`node tools/recommendations/gemini-smoke.mjs --offline` uses mocked Gemini
responses and in-memory Supabase fixtures. It checks the actual provider
request, completed interaction parsing, alias mapping, approved sentences,
and timeout handling without network access.

Only after separate approval, run the following in a fresh PowerShell window
at the repository root. Use the approved Gemini project key. The live mode
makes one request to Gemini for `gemini-3.5-flash-lite` and does not use
Shared Supabase or an Edge deployment. It prints outcome codes and HTTP
statuses, without the response body or credentials.

```powershell
try {
  $env:JOBMATE_GEMINI_SMOKE_KEY = [System.Net.NetworkCredential]::new(
    '', (Read-Host 'Approved Gemini API key' -AsSecureString)
  ).Password
  node tools/recommendations/gemini-smoke.mjs --run-live
} finally {
  Remove-Item Env:JOBMATE_GEMINI_SMOKE_KEY -ErrorAction SilentlyContinue
}
```

Success means the production parser and validator accepted both notes and
mapped them back to their synthetic fixtures. A live timeout means the
provider call did not finish within four seconds. The deliberately stalled
timeout case is covered offline to keep the live check to one request.
The check does not establish Shared RPC compatibility or free-tier quota.

#### Shared recommendation RPC verification

The team reported that all six authenticated Shared fixture checks passed for
the eligible and previously applied jobs, including the eligible job's empty
application lookup (`*/0`). This verifies the RPC HTTP contract for those
fixtures.

For the reported Browse Jobs 11 versus For You 3 discrepancy, reconcile the
feed and history after separate approval using the same active account and a
fresh load of both pages. Clear both sets of filters before comparing.

1. Inspect the unfiltered `list_published_jobs` response and its response
   `Content-Range`. For a separately approved RPC check, use
   `select=job_id,application_deadline`, `order=job_id.asc` and
   `Prefer: count=exact`. Collect pages with `offset` and `limit` in memory
   until the distinct job count agrees with the total. Compare against the
   Browse count and the published-feed reads made on For You. Both are backed
   by the same RPC; the client fetches further pages only when it gets a readable
   exact total and stops on an empty or overlapping page.
2. Verify the unfiltered `list_my_job_applications` total and pages the same
   way, using `select=application_id,job_id` and `order=application_id.asc`.
   Keep IDs local and use the job IDs as a set. Count all statuses, which
   matches the client exclusion rule. The app currently reads history in one
   call without an exact count. Ask the RPC owners to confirm whether the
   deployed definitions apply internal limits or status filters. Both calls
   are read-only `POST /rest/v1/rpc/<name>` with `{}` and the existing Job Seeker
   session. The count is for the returned RPC relation, which can have its own
   internal cap.
3. Assign each distinct published job to exactly one bucket. For missing jobs,
   use this precedence: missing or invalid deadline, expired deadline, previously
   applied, other verified exclusion, unexplained. Assign visible jobs to scored
   or unscored. Record rule conflicts separately and never count the same ID
   twice. Match the Flutter deadline rule using the device date; compare Kuala
   Lumpur time for deadline-day cases. Verify future-deadline roles against the
   local set of previously applied job IDs before attributing their absence to
   applications.
4. Share only aggregate counts by reason and sanitized response count headers.
   Keep job IDs, application IDs, headers with credentials, and response bodies
   out of screenshots and shared logs. If either exact total or source limit
   is unknown, record the reconciliation as incomplete.

For the existing signed-in localhost Flutter Chrome session, open My
Applications and run
[`verify-shared-rpcs-from-chrome.js`](tools/recommendations/verify-shared-rpcs-from-chrome.js)
once in DevTools Sources → Snippets after approval. Click **Refresh
applications** within 30 seconds. The snippet uses that request's credentials
in memory, restores the original browser fetch, and reports six read-only
results. Check for six `pass: true` entries, including `*/0` for the eligible
job's application lookup. If JavaScript cannot read the count header, inspect
only the **Response Headers** in the Network panel, or use the CLI harness
below. Do not copy request headers or export a HAR.

Run the following only after Shared access is separately approved. Use a fresh
PowerShell window, the approved project's direct HTTPS `*.supabase.co` URL,
its publishable or legacy anon key, and a current access token from an existing
active Job Seeker session. Use an eligible published job with no prior
application and a different job that the same seeker previously applied to.
The applied job may be absent from the current published feed. Use existing
records and open the shell at the repository root.

```powershell
$env:JOBMATE_VERIFY_SUPABASE_URL = Read-Host 'Approved Shared project URL'
$eligibleJob = Read-Host 'Eligible job UUID with zero applications by this seeker'
$appliedJob = Read-Host 'Previously applied job UUID for this seeker'
try {
  $env:JOBMATE_VERIFY_PUBLIC_KEY = [System.Net.NetworkCredential]::new(
    '', (Read-Host 'Publishable or anon key' -AsSecureString)
  ).Password
  $env:JOBMATE_VERIFY_USER_JWT = [System.Net.NetworkCredential]::new(
    '', (Read-Host 'Existing Job Seeker access token' -AsSecureString)
  ).Password
  node tools/recommendations/verify-shared-rpcs.mjs --run-shared $eligibleJob $appliedJob
} finally {
  Remove-Item Env:JOBMATE_VERIFY_SUPABASE_URL, Env:JOBMATE_VERIFY_PUBLIC_KEY, Env:JOBMATE_VERIFY_USER_JWT -ErrorAction SilentlyContinue
}
```

The harness sends the two existing read RPCs with the Edge handler's filtered
projections and exact count preference, for each fixture alone and together.
Output includes HTTP status, the numeric or wildcard `Content-Range` as sent,
and rows labeled `eligible` or `applied` in place of real IDs. Error bodies,
credentials and application details are withheld. A passing empty lookup has
`rowCount: 0`, `contentRange: "*/0"`, and `countMatchesHandler: true`.
Exit code 1 means a request or compatibility check failed. Exit code 2 means
the run flag, fixture IDs, or environment inputs failed validation. Close the
fresh shell after the check and keep the access token out of command history.

The separately approved
[`recommendation_rpc_definitions.sql`](supabase/inspections/recommendation_rpc_definitions.sql)
query reads function definitions from the catalog without invoking the RPCs.
Use it to review internal filters, limits, and called helpers. An exact
PostgREST count cannot reveal rows the function already removed. This harness
also does not verify salary masking because the Edge projection omits salary.

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

Phase 3 tests are in `test/demo_work_chat_location_navigation_test.dart`: deterministic scores, attendance and
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
| 6 / JS-16–21 | `/evaluations`, `/evaluations/:assignmentId/rate`, `/evaluations/:assignmentId` | Legacy local demo; retained for compatibility |
| 6 / EMP-21 | `/employer-evaluations` and corresponding detail/rate routes | Legacy local demo; retained for compatibility |
| Phase 1 bidirectional evaluations | `/soft-skill-evaluations`, `/employer-soft-skill-evaluations` | Supabase RPC-backed eligibility, submission, history, core summaries, controlled additional criteria and blind release after both parties submit; requires the standalone local SQL patch below |
| 7 / JS-25, EMP-22 | `/reputation`, `/employer-reputation` | Illustrative 0–100 score/factor/trend fixtures, visible demo evaluation average and insufficient-data view |
| 8 / ADM-01–04 | Existing Dashboard and `/admin-users` | Real directory; details and suspend/reactivate require the prepared Phase 2B migration and dedicated permission |
| 8 / old account preview | `/admin-preview/accounts` | Redirects to the real user directory |
| 8 / ADM-05–06 | `/admin-preview/jobs` | Fictional job search/filter/detail/removal; no actual publication/moderation |
| 8 / ADM-07–11 | `/admin-preview/disputes`, `/admin-preview/disputes/:disputeId` | Linked demo cases, timeline, information request, resolution/rejection, evidence and internal remarks |
| 8 / ADM-12 | `/admin-preview/reports` | Filtered session analytics and Web printable report; no live analytics/CSV service |
| 8 / additive entry | `/admin-preview` | Demo sandbox overview with explicit links back to real administration |
| 9 / EMP-15–17 | `/employer-payments/record`, `/employer-payments`, `/employer-payments/:paymentId` | External-payment form, local proof, confirmation/success, history and details; all demo |
| 9 / JS-26 | `/payments`, `/payments/:paymentId` | Demo history/pending views, receipt confirmation and payment-issue case linkage |

#### Bidirectional Soft Skill Evaluations — Phase 1 prepared

The new Job Seeker and Employer Evaluations destinations use verified
Work Assignments and server-checked RPCs. Each side submits three fixed Core
Skills and two controlled additional criteria, can mark a criterion Not
Observed, and may add a bounded comment. Evaluations are unique per assignment
and direction; received feedback is returned only after both parties submit.
The Core average excludes Not Observed responses and includes its valid-rating
count. Existing `/evaluations` and `/employer-evaluations` routes remain the
earlier demo workflows.

The actual Job Posting schema has no controlled Job Category field. Phase 1
therefore uses documented generic recommendations and does not mislabel the
free-text `department` as a category. Category-specific mapping requires a
later agreed schema contract. The standalone candidate SQL is
`supabase/patches/soft_skill_evaluations_phase1.sql`; it remains outside the
active migration chain pending migration-history reconciliation and has not
been deployed to Shared Supabase. See
`supabase/diagnostics/soft_skill_evaluation_phase1_smoke_checklist.md` for
Local/isolated validation prerequisites. Evaluation reporting through Dispute
Resolution and reputation-wide summaries remain follow-up work; the current
dispute contract has no evaluation target.

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
admin-view-only local data, not proof of secure storage. The old sample account
actions are superseded by Phase 2B; job Removed remains **sample-only**. Demo mutation confirmations identify
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

The deployed historical Dispute finding RPC can be exercised from the existing
Admin Dispute Details page in local Debug builds with
`--dart-define=ENABLE_HISTORICAL_CLASSIFICATION=true`. The flag defaults off and
cannot enable the workflow in profile/release builds. The Admin must explicitly
select an outcome and provide a reviewed reason; the backend remains authoritative
for report classification, Incident consistency, Appeals and authorization.

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

The account restriction portion below is superseded by the prepared Phase 2B
migration; the deployment and cross-module dependencies described above remain.

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
code is additive under `lib/features/phase4/`; tests are in `test/evaluation_reputation_admin_payment_preview_test.dart`.
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
  `test/workspace_responsive_rendering_test.dart` (four additional tablet scenarios).
- Assets/documentation: `pubspec.yaml`, five `.ttf` files, three OFL license files,
  `assets/fonts/README.md`, and this README. No dependency additions.

## Phase 5.2 — UI consistency and application integration preparation

The improved Phase 5.1 employer dashboard/posting/form design is preserved. The
existing uncommitted working tree was retained. See [the 71-screen audit](docs/archive/phase52_screen_audit.md)
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

`test/workspace_screen_rendering_and_text_scale_test.dart` covers 50 render/interaction scenarios: 25 representative
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

### Job Seeker Profile extension and Flutter UI

The current development handoff reports the additive SQL candidate installed
in Local and its rollback-only regression passed; those database results were
not rerun during the Flutter UI task. The candidate defines overlap-free ISO
weekday availability in `Asia/Kuala_Lumpur`, an application-scoped Employer
read of applicant professional details, and a verified-Company profile read
for active Job Seekers. Certificate documents remain private and are omitted
from read RPC payloads; self-declared and Company-provided certificate metadata
is labelled unverified. The Job Seeker `/profile` screen now uses the additive
Profile contract for About Me, Skills, Certificates, Education, Work Experience,
Languages and Weekly Availability. Existing free-text profile data is not
backfilled, and Company review/logo approval flows are unchanged.

`supabase/patches/profile_job_seeker_certification_delete_local_delta.sql`
is an additional Local-only contract for certificate metadata deletion and an
explicit education `is_current` field; it has not been applied. Until that delta
is reviewed and applied, the extended editor reports unavailable when those
objects are missing. The UI does not assume the extension is present on Shared.
Its transaction-scoped regression is
`supabase/diagnostics/profile_job_seeker_certification_delete_local_delta_test.sql`;
run it only after applying the delta to the named Local database. It checks
owner-only metadata deletion, education date/current-state constraints, and
that deleting metadata leaves the private Storage object record in place.
The ERD and security contract are in
`supabase/diagnostics/profile_schema_extension_review.md`.

The same `/profile` screen also provides Employers with personal Bio, Job Title,
Department and Professional Experience fields from `employer_profiles`. Reads
use the owner's existing RLS-protected row; writes use the active-Employer
`save_my_employer_profile(text,text,text,text)` RPC and do not update legacy
Company fields or `company_memberships`. The Employer view reports the Profile
Extension as unavailable with Retry when its schema is absent; the extension
still requires review and deployment before those fields are available in
Shared.

The existing Employer `/company` workflow now includes Company-scoped
Specialties and Certifications, while preserving Company Description, Industry,
verification submission and approved-logo flows. Specialty writes use the
Profile Extension table's current-membership RLS; Certification metadata uses
`save_company_certification`, and private documents use the existing
`jobmate-profile-certificates` bucket with short-lived signed reads. Company
profiles in Job Details use `get_public_company_profile_v1`; the UI displays
only its public projection and never renders certification document paths.
The Employer applicant list now opens a read-only professional profile through
`get_applicant_profile_for_company(p_application_id)`. The Application ID is
the only lookup key; applicant and Company identity remain server-derived.
The current RPC Education projection does not include `is_current`, so the
Employer view does not infer or display a current-study state. Certificate
document paths are not returned or shown.
Because the installed Profile SQL has no Company certification delete RPC,
`supabase/patches/profile_company_certification_delete_local_delta.sql` and its
rollback-only test are prepared but not applied. This Flutter change does not
modify or deploy Profile SQL.

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

Browse Jobs uses compact, description-free listing cards with session-only
bookmark controls, semantic employment badges and existing salary disclosure.
Employment type, arrangement and location filters expand through **Filters**;
active filters remain visible when collapsed. Result counts and the existing
Newest / Title / Deadline sorting remain available below search. Browse and
production Job Details now use centered content up to 880 logical pixels. Cards
combine secondary metadata and View Details on desktop and wrap at narrow widths
without fixed heights. Job salaries display Malaysian Ringgit (RM), thousands
separators, and stored pay periods. Equal endpoints display as a single amount.
Readable dates retain the existing parsing semantics.
Job Details has one hero, a responsive two-column information grid, independent
application-status and deadline messages, populated content sections and the
existing public Company profile action. Application eligibility, session saves,
demo recommendations and Location presentation remain unchanged.
Focused validation includes `test/browse_job_card_test.dart` and
`test/job_marketplace_refinement_test.dart`, together with existing published-jobs
and application-status tests; browser and Android device acceptance are separate.

Employer My Job Postings uses the same 880-pixel content limit, with one company
identity, four company-scoped summary counts, search before All / Published /
Draft / Closed filters, compact metadata and a separate action footer. Fresh
visits default to All; explicit status URLs and form-return statuses retain their
selection. Counts cover the loaded company catalogue, independent of search.
An expired deadline remains a warning on a Published posting and does not close it.
Existing authorization, Publish validation, Close confirmation, Preview and
View Applicants routes are unchanged; View Applicants remains available for all
three persisted statuses. No currency or applicant totals are inferred.
Focused checks: `test/employer_job_postings_refinement_test.dart` and
`test/job_postings_test.dart`. Create/Edit and Preview presentation are outside
this Phase 2A refinement.

Phase 2B refines the shared Create/Edit form with the same 880-pixel content
limit, tinted section headers, external required-field labels and employment
type chips (including Internship). Compensation contains salary range/period,
Vacancies, disclosure and a live display preview. Company identity stays locked
to the existing membership; the verified badge requires the actual verified
company state. Published edits use Save Changes instructions; drafts retain
Save Draft and Publish Job. Existing validation, AI replacement/review and route
exit guards are unchanged. The read-only Preview shows current unsaved values,
compact metadata, a visible scrollbar, Close/Back controls and the separate
Employer Original description; it has no Apply action. Posting footers use a
soft-teal Applicants action, icon secondary actions and desktop-right Close Job.
Focused coverage adds `test/employer_job_form_refinement_test.dart`. Browser and
physical Android acceptance, including keyboard and route history, remain manual.

Phase 3A refines the Employer View Applicants overview at the same 880-pixel
content width. A single posting remains mandatory; the authorized source does
not provide all-job aggregation. Compact All / Active / Completed cards also
serve as filters; their counts and the status-selector counts use the complete
loaded list for the selected job, independent of search. Active and Completed
retain `MyApplicationStatus.completed` semantics. Applicant cards show existing
identity, local applied time, resume availability and cover note,
with the existing Profile, Resume, Message and permitted recruitment actions in
a tinted footer. Internal application IDs and generic lifecycle explanations are
omitted from overview cards; existing lifecycle restrictions and explanations in
other views remain unchanged. Hired does not imply completed shifts or a supported
termination action. Matching-result text uses singular for one application. No overview
skills, ratings or reputation source is introduced. Profile and recruitment
dialog internals, repositories and backend contracts remain unchanged.
Focused coverage adds `test/employer_applicant_overview_refinement_test.dart`.

Job Seeker application details pair the application summary and actions with a
connected status timeline at wide widths and stack them on smaller screens.

Phase 3B presents Applicant Profile in a responsive 640-pixel modal with a stable
header/footer, visible scrollbar, application identity/status and local applied
time from the authorized overview row. The existing application-scoped profile
RPC remains unchanged. About, Skills (including proficiency), Education, Work
experience, Languages, Weekly availability and Certifications use compact
sections; empty data is distinguished from failed or unavailable reads. The real
cover note appears separately as Application note. No IDs, reputation scores,
ratings or review counts are displayed. The modal binds to the overview account,
company and job context and discards stale profile results after context changes.
Its Resume action reuses `EmployerResumeButton` and the existing browser-tab
signing flow. Message Applicant reuses the existing lazy chat handler with an
optional navigation callback that dismisses the modal before opening the same
conversation route; ordinary overview/worker chat buttons keep their navigation.
Recruitment dialogs retain Shortlist, Move to Interview, Make Offer and Reject,
with the original confirmations, optional 2,000-character note, dirty-note guard,
session checks and authoritative refresh. Make Offer still requires worker
acceptance before Hired; no employer Hire action is added. The Phase 3A overview
remains free of IDs and generic lifecycle paragraphs. Focused coverage adds
`test/employer_profile_recruitment_dialog_test.dart`. Browser/new-tab and physical
Android acceptance remain separate manual checks; no backend changes are needed.

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

### Cross-party Reputation MVP (prepared SQL; Flutter verified)

The existing Applicant Profile dialog now shows an application-authorized
applicant Reputation summary. The existing verified Company Profile dialog,
reachable from Job Details, shows Company Reputation for active Job Seekers when
that Company has a Job visible through the existing published-job directory.
Both reuse the self-facing aggregate UI; unavailable/undeployed RPCs show an
error with Retry rather than fabricated ratings. The additive candidate creates
two scoped public read RPCs and one private release helper, preserving existing
Phase A/B/C definitions, RLS and legacy Shift Evaluations. The user reports a
successful SQL postflight and basic Flutter manual checks; isolated authorization
regression remains unexecuted by the coding agent. The cross-party implementation
and manual SQL sequence (`docs/reputation/cross_party_reputation.md`) are unavailable
in this checkout.
No internal Trust Score or Payment/Attendance scoring is implemented by this
change. Earlier demo descriptions elsewhere document historical UI stages.

### Internal Job Seeker Trust engine (prepared; not deployed)

`supabase/patches/job_seeker_trust_score_candidate.sql` adds four owner-only
private functions for on-demand evidence calculation and bounded formula
arithmetic. Work evidence separates future/ongoing/ended, verification, Disputes
and cancellation audits; original-attendance observations never imply confirmed
absence or an approved grace period. Released Evaluation averages have equal weight per Application and
normalize to 0-100. A numerical C/A kernel implements a versioned candidate
policy over trusted canonical obligations, with original-record candidates wired
through the work evidence helper. The supplied installed Attendance Resolution
catalog now supports exact corrected/confirmed-absence mapping; the proposed
15-minute grace and C/A scoring rules are adopted as provisional FYP v1
decisions; C/A factor scores are available from complete authoritative evidence.
D and the composite remain NULL in the existing v1 calculator. Separate
incident/finding/appeal and mediation SQL candidates now prepare an explicit
Admin decision path and an internal v2 score, but remain undeployed and require
isolated authorization tests, historical coverage review and correction-policy
review. The incident candidate now guards legacy terminal actions, provides an
explicit historical-case classifier and binds coverage attestations to an
effective-evidence fingerprint. Existing Flutter terminal actions require a
structured-outcome integration before backend deployment. A dependent,
unexecuted finalized-incident correction candidate now
prepares independent Admin approval and append-only audit. The earlier
Assignment-keyed D candidate is superseded. The dependent candidate changes
only the prepared internal incident D evidence and mediation relink guard needed
for an approved correction. It adds no public score RPC, Flutter UI or mutable
score table. Read-only preflight/postflight and
an isolated-only rollback regression are prepared; no SQL execution is implied.
The internal Trust engine contract and missing policies are documented in
`docs/reputation/job_seeker_trust_score.md`. The Dashboard-only isolated
Trust/Dispute procedure in `docs/reputation/trust_dispute_isolated_runtime_verification.md`
records the exact candidate order, required baseline and unexecuted test gates.
Both documents are unavailable in this checkout.

### Phase A/B/C authenticated Local integration (prepared only)

`test/reputation_phase_abc_local_integration_test.dart` exercises the existing
Engagement Closure, reciprocal application Evaluation and Reputation RPCs
through real Local Auth sessions. Run it only with
`supabase/diagnostics/run_reputation_phase_abc_local_integration.ps1` against a
separately named disposable Local Supabase project whose reviewed Phase A/B/C
schema is already installed. The runner checks function fingerprints/security,
RLS, constraints, skills and trigger contracts; it does not install SQL. It
creates synthetic Auth/business fixtures and destroys the dedicated project
data volumes afterwards because closure and evaluation audit records are
immutable. The isolation requirements, cleanup limitations and exact PowerShell
command are documented in `supabase/diagnostics/reputation_phase_abc_local_integration.md`,
which is unavailable in this checkout. The test and runner paths above are also
unavailable locally. This integration has not been executed; an empty Supabase install or
the existing shared development database is not an acceptable target.

### Details requiring team confirmation

Confirm the deployed `format-job-description` implementation, Gemini configuration, server-side secret names and deployment ownership. Confirm the existing Supabase schema/RPC/storage/policy baseline and authentication settings before attempting a fresh environment; checked-in migrations are partial. Web hosting and its URL behavior require deployment-specific verification. This documentation does not imply live-backend or platform acceptance testing.

### Applicant unseen counts

Migration `20261120000200_new_applicant_notification_foundation.sql` installs
the applicant count and acknowledgment RPCs with the feature disabled. Keep
`applicant_notifications_private` outside the API's exposed schemas.

The shared Flutter unseen-count controller refreshes on entry to My Job
Postings or View Applicants after company access is resolved, on app resume,
and after a successful acknowledgment. It clears its cached state when the
account or company changes. Positive counts show a dot on the employer's
View Applicants menu item and a per-job badge beside View Applicants on
My Job Postings. View Applicants acknowledges only IDs from successfully
rendered, filtered results for the selected job. It sends up to 100 IDs per
request and refreshes authoritative counts after successful receipts. Receipt
failures leave the applicant list usable and can be retried on a later load.

In the SQL Editor, check migration-history availability before querying it:

```sql
SELECT pg_catalog.to_regclass('supabase_migrations.schema_migrations')
  AS migration_history_relation;
```

Query the history table only if the result identifies a relation and your role
has read access. If it returns NULL, compare deployed objects and definitions
with the expected migrations and review deployment records. SQL Editor changes
can exist without a CLI migration-history entry.

After deployment and separate activation approval, the migration owner or an
authorized database administrator can run this one-time statement and commit
immediately. One returned row means the cutoff was set. Zero rows means the
cutoff was already set and should be left in place.

```sql
UPDATE applicant_notifications_private.activation
SET activated_at = pg_catalog.clock_timestamp()
WHERE singleton AND activated_at IS NULL
RETURNING activated_at;
```

The activation trigger assigns the database timestamp on a NULL-to-non-NULL
request. It rejects NULL-to-NULL updates, all updates after activation, and
deletion or truncation of the activation record. Apply migrations
through version tracking. A manual rerun fails on existing object names and
does not replace the cutoff. Use a trusted migration owner and verify effective
permissions for any custom API roles before release.

Only applications whose stored `applied_at` is later than the cutoff count.
`list_unseen_applicant_counts()` groups positive counts across the caller's
managed companies. `acknowledge_applicants_seen(uuid, uuid[])` accepts one job
and up to 100 IDs from the displayed list. It returns the number of newly
inserted receipts. Counts and acknowledgments do not alter application status.
Deploying the Flutter badge and acknowledgment flow is a separate step.

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

Phase 5 scheduling notifications are audit-only. No verified atomic shift emitter
or notification-to-assignment target is present in the checked-in contracts.
The current Flutter boolean mark-read RPC also differs from the older checked-in
SQL function. See the [notification audit and proposed atomic event design](docs/shift_scheduling_notifications_audit.md)
for recipient identity, per-assignment uniqueness, MYT content, existing route
integration and required backend/notification-owner review. No notification UI,
RPC, trigger, RLS or migration was changed; no SQL was executed.

### Real Job Seeker application actions (Module 2 Step 27A)

Phase 3 clarifies the existing application/offer lifecycle for both roles, with
job/company-specific confirmation and an explicit post-hire boundary. Hired is a
recruitment outcome, not completed work. Post-hire arrangement cancellation is
not implemented: its required backend contract and the missing Module 2 SQL
sources are documented in [the lifecycle audit and review design](docs/application_arrangement_lifecycle.md).
No new status, RPC, policy, migration or notification behavior is introduced.

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

### Chat backend and Flutter data layer

Chat backend is permanently deployed, with CH-confirmed prospective catalogue
integrity verification. The typed five-RPC Chat source/repository and persistent
send retry storage are available in `lib/features/chat/`; authenticated runtime
acceptance passed the core controlled messaging fixture checks. Messages now uses
the real repository for both participants, with application entry buttons,
responsive list/thread navigation, persisted-send recovery, pagination and
authenticated Realtime reconciliation. Read marking is explicit on displayed
messages. Ordinary unsent drafts are memory-only; navigation prompts protect
them, but browser refresh/tab closure does not. No fake presence/receipts or
attachments are included. Final UI/device/security acceptance remains pending.
See [Phase 5 evidence and Phase 6 review](docs/chat_phase5_runtime_review_and_phase6_ui.md).
See [Chat Phase 3 acceptance and UI integration](docs/chat_phase3_runtime_acceptance.md).

For temporary authenticated runtime acceptance, a debug-only tester is available
at `/#/debug/chat-acceptance` after normal sign-in. Run
`flutter run -d chrome --web-hostname=localhost --web-port=7357 --no-pub`, then open
`http://localhost:7357/#/debug/chat-acceptance`. It uses the actual typed repository,
supports explicit reads/pagination and Realtime observation, and copies evidence
without message text or credentials. CH/KZ approved the fixed QA application and
two participant messages; only those active identities can enable scoped writes
after **Check account**. Request IDs/text are fixed, preventing extra logical
messages on retries/restarts. Backend denial/read-only stops the trial. See the
linked acceptance procedure for exact buttons and scope. No production navigation/demo change; release/profile
builds omit the tester route. Live acceptance remains pending CH's results.

### Flutter learning resources

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)
- [Flutter documentation](https://docs.flutter.dev/)

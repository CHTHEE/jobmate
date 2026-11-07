# Module 2 and Module 4 integration review: Phase 7

## Assessment and scope

The inspected Flutter workflows use consistent production application statuses
and preserve per-assignment identity through grouping, attendance, evidence and
advisory deadlines. A connected local-fake journey now exercises the boundary
between hiring and Module 4. One reproduced Flutter recovery defect was fixed.
This is not a production-readiness or deployed backend security certification.

Review covered the production application/offer repositories and pages; scheduling
discovery/dialog/request ledger; worker/employer grouping; attendance/GPS;
evidence reservation/upload/review; deadline calculation/refresh; route entry and
safe exits; README and the Phase 3–6 audit documents. Legacy demo lifecycle code
was distinguished from production. No shared navigation, KZ-owned module, SQL,
RLS, trigger, migration, live record or remote infrastructure was modified.

## Scenario coverage and evidence

Paths below are local automated test evidence. Fakes validate client contracts
and behavior; they do not establish PostgreSQL/RLS/Storage correctness.

| Scenario | Evidence |
| --- | --- |
| Applied -> Shortlisted -> Interview -> Offered -> Hired | New `module2_module4_integration_test.dart` connects employer and worker repositories, refreshes both projections and verifies no scheduling candidate before Hired |
| Offer decline versus withdrawal | New connected tests end in distinct Declined/Withdrawn projections for both roles, with no eligible scheduling candidate, reservation or shift; existing `application_response_test.dart` covers withdrawal from all supported pre-hire states |
| Invalid transitions and conflicting actions | `employer_status_update_test.dart`, `application_response_test.dart`, `application_lifecycle_test.dart`; new journey rejects employer direct hire, worker premature acceptance and post-hire withdrawal/decline |
| First and additional Hired shifts | New journey uses freshly discovered candidates and the existing request-based creation repository; `work_assignment_creation_repository_test.dart` and dialog tests cover incomplete reads, access changes, duplicate requests and uncertainty |
| Flexible/overnight scheduling | New journey checks MYT 22:30 -> next-day 02:15 maps to correct UTC values and creates a second earlier shift under the same application; existing dialog tests cover editable fields, validation and date/time pickers |
| Application grouping, identical names and chronological order | New six widget cases exercise both real grouped pages at 320/840/1440 with 1.6 text scaling, identical job/worker identities across distinct application IDs and an overnight shift ordered after an earlier shift; existing worker/employer grouping tests cover independent actions/routes |
| Overlap rejection and adjacent intervals | New connected journey rejects an overlapping third shift before dispatch; `work_assignment_creation_repository_test.dart` covers cross-application overlap and adjacent intervals. Cross-company database coverage is source review only, not an executed database test |
| Independent check-in/out and GPS | New journey changes only the selected shift, uses denied/granted location inputs and authoritative refresh, and preserves its sibling; `work_attendance_actions_test.dart`, `work_attendance_gps_test.dart` verify exact adapters, coordinate validation, confirmation/cancellation, duplicate locking, stale sessions and GPS fallback |
| Submission, more evidence, resubmission, verification | New journey drives existing upload/submission and employer review controllers against per-request fakes, preserves both files/rounds and checks all four history actions; `work_evidence_workflow_test.dart` covers uncertainty, replay, roles, private PDF opening and round guards |
| Late evidence and independent deadlines | New journey advances the advisory clock beyond checkout+24h and still submits/resubmits while leaving the sibling unstarted; `work_evidence_deadline_test.dart` covers exact 20/24h boundaries, UTC/MYT rollover, missing attendance, clock reversal/resume and fresh workflow status overriding stale header data |
| Loading/error/retry/account changes | Application details/list and employer tests, creation repository/dialog tests, attendance pages/repository tests and evidence pages/workflow tests exercise these independently; no fixture fallback is used by production pages |
| Direct URLs, ownership and exits | `work_attendance_routes_test.dart`, `work_verification_routes_test.dart`, `work_evidence_routes_test.dart` verify role/company gates, fresh owned-list resolution, denied/foreign routes, stale-account invalidation and safe exits in a test GoRouter |
| Mobile/tablet/desktop and unsaved drafts | New grouping cases plus existing 320/840/1440 page/deadline checks; creation tests include 360px at 2.0 text scaling. Dialog/draft tests retain discard guards and busy locks. These are widget layouts, not physical platform acceptance |

The connected fake journey shares application status and created assignment
records between existing test sources, then connects the existing attendance and
evidence controllers. It asserts the second shift's complete fixture remains
unchanged while the first is checked out, submitted, supplemented and verified;
the parent application remains Hired. It does not simulate a second company's
hidden assignments or claim a real HTTP/database end-to-end test.

## Reproduced defect and fix

**Uncertain shift creation lost its read-only recovery action after dialog reopen.**
`WorkAssignmentCreationDialog` showed Check current assignment only when both
`_confirm` and the persistent creation lock were true. Reopening resets `_confirm`
but preserves the lock. Selecting that application (or opening its Add shift
dialog) consequently hid both new creation and the only request lookup action.

Two regression cases first failed with zero Check current assignment widgets:
generic Create Assignment selection and application-scoped Add shift. The fix
shows the existing read-only reconciliation action whenever the selected
application is locked, and explains the unresolved request. It does not enable
creation, remove the lock, invent dates, or replay a write. Both regressions now
verify an absent lookup keeps the operation uncertain, a later positive lookup
returns the original assignment, and reservation/create counts remain exactly one.

No other verified in-scope production defect was established by this review.
Unverified backend assumptions below were not converted into client workarounds.

## Backend/security assumptions still requiring verification

1. **Missing Module 2 SQL.** Application table/status constraints and definitions
   for submit/list/history, employer status updates and worker offer responses
   are absent from the checkout. Client state guards, ownership reads and fakes
   cannot prove server actor authorization, row locking, atomic transitions,
   history or notification side effects. Obtain actual definitions for offline
   review with the backend owner. Do not infer new status support.
2. **Company authorization helper missing.** Module 4 uses
   `can_manage_company_jobs`, whose body is not checked in. The request-based
   follow-up checks `IS NOT TRUE`, while several base functions use `IF NOT`
   (including legacy creation and company assignment listing). If the helper can
   return NULL, those latter guards cannot be assumed to deny access. This is a
   conditional source-level concern, not a demonstrated bypass. Verify active
   employer, company verification/membership and deny-on-null behavior offline;
   this phase does not change SQL or shared account checks.
3. **Cross-company overlap.** The base migration's
   `work_assignments_no_worker_overlap` GiST exclusion uses worker ID and `[start,end)`
   for all companies, excluding cancelled assignments. The Flutter precheck sees
   only the selected company's complete list. Preserve the global constraint;
   only an approved isolated database/multi-session test can prove race outcomes.
4. **Creation identity and recovery.** Server request IDs/duplicate shift claims
   are distinct from the process-local UI ledger. The new fix restores lookup
   while that ledger is retained; it does not make unresolved locks survive app
   restart. Never refresh/restart to retry an uncertain write. Historical shift
   claims remain reserved and committed creation lookup returns original identity.
5. **Evidence/Storage cutover.** Checked-in SQL locks assignments and rounds,
   validates attendance/private objects, records history and restricts legacy
   write grants. Owner-reported deployment/catalog checks do not establish real
   JWT authorization, Storage permissions, concurrent behavior or physical client
   release readiness. Preserve append-only files and protected QA exclusions.
6. **Advisory timing.** Due time uses authoritative checkout+24h, never scheduled
   end. No server-now field exists; relative timing uses the device clock and can
   be wrong under clock skew. Submission/review eligibility remains server-based.
   More Evidence Required has no invented new deadline or mandatory extension.
7. **Large/read-capped candidate discovery.** The existing creation repository
   requires complete count-verified company/job/applicant/assignment reads and
   fails closed on truncation. These are not an atomic database snapshot; server
   preconditions still govern writes. Large-company scalability requires a
   reviewed backend read contract, not ignoring completeness errors.

## Deferred features and notification compatibility

No deferred feature was implemented:

- [Future-shift editing/cancellation](future_shift_management_audit.md): missing
  verified guarded mutation, revision/concurrency and audit contracts. Existing
  `cancelled` shift status alone is insufficient. Durable creation claims/request
  payloads need compatibility review before any schedule edits.
- [Durable scheduling notifications](shift_scheduling_notifications_audit.md):
  missing verified atomic emitter, per-assignment event uniqueness and target
  projection. No client-only emit or simulated successful delivery was added.
- [Post-hire arrangement termination](application_arrangement_lifecycle.md):
  requires explicit lifecycle/authorization/record-retention decisions and guarded
  backend operations; pre-hire withdrawal is not a substitute.

The notification compatibility concern remains: Flutter consumes
`mark_notification_read(uuid)` returning boolean, whereas the older checked-in
migration defines `mark_my_notification_read(uuid)` returning void. The currently
consumed definition is missing. List calls supply both p_limit=50 and p_offset=0
to disambiguate overloads. Coordinate with the notification owner; do not rename,
fallback, or modify KZ/shared UI without reviewing the actual contract. Notification
tests are part of the full suite, not proof of the deployed function.

[Deadline reminders and extension policy](evidence_deadlines.md) remain design
work only. No penalties, payment/trust effects, acceptance per shift or automated
work-failure handling were introduced.

## Validation results

- Changed Dart files formatted; focused reproduction passed after the fix.
- Final analysis: four pre-existing informational lints, no errors/warnings or
  new issues (two admin company-management brace lints; two sign-up Radio API
  deprecation lints). Those files remain untouched.
- Final focused Module 2/4 suite: **699 passed**, no failures.
- Full Flutter suite: **1,266 passed, five known admin failures**, no new failures.
  The failures are the admin-sidebar ink test in
  `admin_dashboard_material_test.dart` and four `company_review_page_test.dart`
  cases: large-text logo preview at 320/1440, 21-row lookahead pagination, and
  retryable Storage permission errors. KZ's code/tests were not changed.
- Added **11 passing cases**: the connected hired-work journey, decline and
  withdrawal journeys, six overnight/grouping/layout cases, and two reopened
  uncertain-creation recovery cases. The latter two were reproduced failing
  before the focused fix and now pass without duplicate writes.
- Documentation references, new-file whitespace and `git diff --check`: passed.
  Git reports LF-to-CRLF notices for the edited Dart files.

## Acceptance limits and next steps, in priority order

1. Supply missing Module 2/helper/notification definitions for coordinated offline
   review. Confirm the actual authorization and transition contract before
   claiming security or deployed end-to-end readiness.
2. In a separately approved isolated Supabase project, test real JWT/role/company
   boundaries, count completeness, global overlap and multi-session races,
   request replay/uncertainty, Storage/legacy grants and evidence/history retention.
   Do not use the shared live database or protected QA records for this review.
3. Perform manual Chrome desktop/narrow-browser acceptance for direct URLs,
   Back/Forward/refresh, focus/keyboard and private-file opening. Test Android
   GPS granted/denied/unavailable, check-in window/checkout confirmation, system
   Back, native picker/PDF launcher, insets and app background/resume on a device.
   Widget tests do not establish these behaviors or browser hosting fallback.
4. Check device timezone/clock differences and stale multi-session evidence
   review. Explain advisory overdue labels and test late submissions against the
   approved backend; no automatic failure or extension gate.
5. Review the three deferred designs with their owners before any separate
   migration/deployment phase. Do not silently bundle them into this regression
   fix or change another module's obligations.

No database, deployment, staging, commit or push was performed in Phase 7.

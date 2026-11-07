# Future-shift editing and cancellation: Phase 4 audit

## Decision and scope

**Do not implement editing/cancellation UI against the current contracts.** No
authenticated employer edit/reschedule or shift-cancellation RPC was found in the
checked-in Module 4 SQL or Flutter adapters. A `cancelled` shift status and an
overlap constraint already exist, but neither authorizes a client mutation nor
implements the necessary lifecycle guards.

This audit inspected local source only. It did not query the shared database,
execute SQL, change migrations/RLS/RPCs, or verify deployed runtime behavior.
The README records owner-confirmed Module 4 deployment/catalog checks; those are
not verification of a new edit/cancel contract. Any additional backend functions
outside this checkout remain unverified and must be supplied for offline review.

Post-hire arrangement cancellation remains separate and outside this phase; see
[the Phase 3 lifecycle audit](application_arrangement_lifecycle.md).

## Existing lifecycle and capabilities

| Assignment state / verification | Existing operation | Checked-in enforcement |
| --- | --- | --- |
| New scheduled / not_submitted | Employer creates a shift for a Hired application | Creation RPCs validate application/company; server-issued requests and duplicate claims protect creation identity |
| Scheduled / not_submitted | Assigned worker checks in | Active Job Seeker identity, assignment row lock, scheduled status and server-time window |
| Active / not_submitted | Assigned worker checks out | Assignment/attendance locks, assigned active worker, prior check-in and no duplicate checkout |
| Awaiting verification / not_submitted or more_evidence_required | Worker submits evidence | Assignment ownership/eligibility, recorded attendance, round/reservation validation and private append-only files |
| Awaiting verification / pending_review | Employer requests more evidence | Company authorization, assignment/round locks and review request identity; history preserved |
| Awaiting verification / pending_review | Employer verifies | Authorized review; becomes completed / verified with verification timestamp and history |
| Cancelled or disputed | Recognized by schema/models/presentation | No shift edit/cancel transition RPC found; recognized values alone do not establish write permission |

Relevant inspected sources:

- `lib/features/work_attendance/work_verification_pages.dart`: grouped employer
  shifts, Add shift, GPS and evidence navigation; no edit/cancel handler.
- `work_assignment_creation_dialog.dart`: independent MYT start/end dates and
  24-hour times, overnight schedules, workplace validation, confirmation and
  unsaved-input guards. Its Edit button edits the **unsubmitted creation form**,
  not an existing shift.
- `work_assignment_creation_repository.dart`: complete company-scoped reads,
  Hired eligibility, duplicate/overlap preflight, server reservation/create and
  request-only reconciliation. No update/delete adapter or edit/cancel API.
- `work_attendance_models.dart` and `work_attendance_repository.dart`: assignment
  identity, schedule, status and attendance projections; list/check-in/check-out
  APIs. The list models have no concurrency revision token or cancellation audit
  fields. Missing check-in timestamps do not prove all dependent records absent.
- `supabase/migrations/20261105000100_work_attendance_verification.sql`: assignment
  status checks, FKs, RLS, revoked direct table grants, overlap exclusion,
  creation/attendance/evidence/verification and list functions.
- `20261105000300_work_evidence_attempt_reservations.sql`: submission attempts and
  assignment locks; prepared/uncertain attempts must also be considered.
- `20261106000100_work_assignment_creation_idempotency.sql`: immutable creation
  request payloads and durable shift claims; trigger covers schedule updates too.
- `20261106000200_employer_attendance_gps.sql` and
  `20261106000300_work_evidence_workflow.sql`: private read/round review contracts,
  actor authorization, review locks and legacy-write cutover.
- Existing creation repository/dialog, attendance action, evidence workflow and
  employer grouping tests; `supabase/tests/work_assignment_creation_idempotency.sql`.
  The SQL test explicitly calls for separate multi-session race testing. None of
  these tests verifies a future edit/cancel operation.

## Required safety checks versus available support

| Requirement | What is established by local source | Missing for edit/cancel |
| --- | --- | --- |
| Authenticated authorized employer | Creation/list/GPS/review functions check company management; direct assignment/attendance/evidence/history grants are revoked and RLS enabled | A dedicated mutation with target-derived company authorization; the actual `can_manage_company_jobs` helper definition is absent |
| Future, unstarted shift | Check-in checks server time from 60 minutes before start through end | Edit/cancel must lock and recheck original start in the future, scheduled state, no attendance row and no dependent work records |
| No evidence/verification history | Existing evidence functions enforce their own lifecycle | No edit/cancel function checks absence of evidence, submissions, attempts, review reservations and verification history |
| Atomic overlap, including other employers | GiST exclusion uses worker ID and `[start,end)` for **all companies**, excluding only cancelled assignments | New edit RPC must retain/enforce it; the company-scoped client precheck cannot see another employer's shifts |
| Concurrent check-in/schedule changes | Check-in and evidence/review operations take assignment locks; creation locks application/job and duplicate claims | No edit/cancel lock protocol, optimistic revision or idempotent request contract |
| Other shifts and application preserved | Records reference individual assignment IDs; grouping does not merge them | No reviewed mutation restricted to exactly one assignment with audit and retention assertions |
| Both lists refresh | Existing lists read server assignments, including cancelled statuses | No edit/cancel response, revision projection or invalidation hook; no cross-session automatic refresh guarantee |

The exclusion constraint allows adjacent intervals, rejects overlap on inserts
and updates, and is not company-scoped. Do not replace it with a client or
company-only query. A conflict must not reveal another employer's identity or
schedule. `end > start` is already constrained; new endpoints must also reject
null/nonfinite timestamps and require the proposed start to remain in the future.

Two additional compatibility issues require explicit review:

1. The duplicate-shift trigger claims `(application_id, start, end)` durably and
   rejects another assignment with the identical interval, even if it is
   cancelled. It claims a new interval on schedule update but does not release
   the old claim. Cancellation changes status only and does not release claims.
   Therefore freeing worker overlap is **not** permission to reuse an identical
   historical application slot. Preserve this behavior unless separately reviewed.
2. Creation requests retain their original immutable schedule and link to an
   assignment ID. Replaying a completed creation request returns that same ID;
   after a later edit/cancellation it must never restore the original schedule or
   create a replacement. Read reconciliation must distinguish original request
   payload from the assignment's current revision/status.

## Proposed RPC contracts — design only, names not implemented

Proposed signatures for review (not existing callable APIs):

- `edit_future_work_shift(p_assignment_id uuid, p_expected_revision bigint,
  p_request_id uuid, p_scheduled_start timestamptz, p_scheduled_end timestamptz)`.
  Change only this shift's start/end. Workplace and all identity fields remain
  unchanged; workplace editing is not needed for the requested scope.
- `cancel_future_work_shift(p_assignment_id uuid, p_expected_revision bigint,
  p_request_id uuid, p_reason text)`. Require a nonblank reason with a proposed
  1,000-character limit, subject to product review. Preserve schedule and identity.
- `get_work_shift_change_request(p_request_id uuid)` for authorized read-only
  reconciliation after a lost response. An absent result does not prove failure.

The proposed revision, request ledger, cancellation metadata and audit data do
not exist as these contracts today. A future reviewed migration must supply them.
Return the committed request result plus an authorized assignment projection,
revision and server time; include no foreign-company shift details. An old request
replay returns its recorded outcome; the client reloads current state and must not
project an older result over newer changes. Define a versioned read projection or
management-context read supplying revision and eligibility, without breaking
existing list RPC consumers.

Common transactional requirements:

1. Require `auth.uid()` and active Employer status, resolve the target's company,
   application, job and worker from stored relationships, and require existing
   company-management/verification/membership semantics with an explicit true
   result. Never trust a caller's company/worker/application selection. Verify the
   actual helper definition first. Require the linked application still be Hired;
   neither operation changes its lifecycle.
2. Use SECURITY DEFINER with a fixed safe search path, qualified objects and
   minimal execute grants consistent with existing Module 4. Keep direct table
   writes revoked; no broad UPDATE policy or public helper access.
3. Adopt and test a compatible parent application/job -> assignment -> management
   request/audit lock order, accounting for the duplicate-claim trigger and all
   existing paths. Resolve identity, acquire locks, then revalidate relationships,
   authorization and expected revision. Every relevant assignment mutation must
   advance revision atomically, including attendance changes; reject stale tokens.
4. For a **new** operation, under the assignment lock require: `status=scheduled`,
   `verification_status=not_submitted`, null `verified_at`, original scheduled
   start strictly after a fresh server-clock check, and no `work_attendance` row
   (even one with null timestamps). Reject any `work_evidence`,
   `work_evidence_submissions`, `work_evidence_submission_attempts`,
   `work_evidence_review_requests` or `work_verification_history` rows. Validate
   any additional dependencies found in the reviewed backend; uncertainty fails
   closed. Prior management audit events alone need not block another valid edit.
5. All dependent writers must serialize on the same assignment lock before
   writing, so absence checks cannot race an insert. Recheck fresh server time
   immediately before mutation, not just transaction-start time or device time.
   Reject a new edit whose proposed start is not future or whose end is not later.
6. Edit only the target row and let the existing cross-company GiST exclusion and
   duplicate-claim trigger arbitrate competing updates/inserts atomically. Roll
   back the entire mutation/request/audit on conflict. Preserve historical claims
   and creation payloads; do not disable triggers to make edits succeed.
7. Cancellation sets the target's existing status to `cancelled` and leaves its
   not_submitted verification state and all other shifts unchanged. Persist actor,
   reason, server timestamp, old/new values and revision in protected audit data.
   Do not delete rows/files, reassign ownership, end the hired application, or
   write to dispute/payment/trust/penalty systems.
8. Bind idempotency to actor, assignment, operation and the exact immutable payload
   (including expected revision). Serialize duplicate request IDs; a replay of an
   already committed request returns that result after fresh access checks rather
   than applying the change again. A different operation/payload for the same ID
   is rejected. Distinct requests from stale forms cannot overwrite each other.

Check-in may occur **before** the scheduled start under the current 60-minute
window. Future alone is therefore insufficient. If check-in wins the row lock,
edit/cancel must fail. If cancellation wins, subsequent check-in fails on status.
If editing wins, a later check-in must revalidate the new schedule. Whether to
freeze all edits during the pre-check-in window is a product decision; the minimum
proposal permits a future, unstarted shift while enforcing the lock/record guards.
No per-shift worker acceptance is proposed.

Return stable, reviewed domain errors for access denied, stale revision, shift
started/no longer future, dependent work records, invalid schedule, overlap and
historical duplicate slot. Map them to refresh/correct/reconfirm actions. Timeout,
serialization/deadlock or lost response must not trigger a blind mutation retry;
reconcile by request ID and reload state before another confirmed attempt.

## Cancellation representation and record preservation

No additional cancellation **status** is needed: the existing `cancelled` value
already renders in both lists and blocks normal attendance actions. Use it as
the single lifecycle source of truth; do not add a competing boolean. Protected
cancellation metadata/audit is still needed; current assignment fields do not
record a cancellation reason/actor/time. Exact schema requires later review.

Keep the assignment as a soft-cancelled record with its original identity and
schedule. Keep group membership/counting based on the actual returned shifts;
show the cancelled shift rather than silently removing it. Existing attendance,
evidence and verification records are never erased to make an operation eligible:
their presence rejects the operation. Completed, active, awaiting-verification
and disputed shifts remain immutable through these proposed endpoints. Historical
private reads and assignment foreign keys remain intact. No completed shift is
converted to cancelled, and no implicit arrangement cancellation is introduced.

## Required later migration, client and test work

No migration is created or applied in Phase 4. A separately approved implementation
would need migration work for revision tracking/projection, guarded RPCs,
request identity/reconciliation, protected audit/cancellation metadata and grants.
Review interactions with existing creation claims/requests and every assignment
writer; preserve existing constraints, RLS, Storage restrictions and data. Obtain
missing helper/baseline definitions and test on an approved isolated database
before any separate deployment review.

Backend tests must cover anonymous/worker/foreign-company/inactive/unverified or
unpermitted employers; every status; null or nonfinite dates; past/equal/boundary
times; overnight shifts; anomalous attendance rows; every evidence/history/attempt
dependency; and immutable job/worker/company/application identity. Multi-session
tests must race edit/edit, edit/cancel, cancellation/check-in, edit/check-in,
creation/edit across companies, evidence preparation and membership changes.
Assert exactly one permitted outcome, no partial updates, no information leakage,
and unchanged sibling shifts/application/history/files. Test adjacent/overlapping
intervals, permanent historical claims, request replay after subsequent changes,
response loss and rollback/deadlock recovery. Existing Flutter fake tests cannot
establish any of those database race/authorization guarantees.

Only after the backend is verified should Flutter reuse MYT validation/dirty
guards, add per-shift actions and explicit old/new schedule or cancellation
confirmation, lock duplicates, map errors and reload authoritative lists.
The employer's current route can reload immediately after confirmation; an
already-open worker session needs a documented refresh-on-entry/resume/manual
invalidation policy and separate testing. There is no current push-update
guarantee; notifications are outside this phase.

## Phase 4 verification

Documentation only changed. No Dart code, tests, SQL or runtime behavior changed;
Flutter format/analyze/test runs were not repeated for this audit. The supplied
baseline remains 1,235 passing tests, five known admin failures and four existing
informational lints; these are not presented as newly executed results. Local
documentation links and `git diff --check` were checked. Live backend, browser,
Android and proposed concurrency behavior were not tested.

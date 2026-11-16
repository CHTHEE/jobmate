# Module 4 Batch 2 deployment handoff — 14 November 2026

Historical deployment record. Current owner-supplied manual/database QA and the
17 November live-test limitations are in [final QA](module4_final_qa_2026-11-16.md).
Use the [final pre-commit scope](module4_precommit_review_2026-11-16.md) instead of
the older staging suggestions below. Do not rerun deployed migration scripts.

**Live database deployment complete, owner-reported on 14 November 2026 (MYT).**
CH executed the permanent Batch 2 migration in the existing JobMate Supabase
project and reported `Success. No rows returned.` Post-deployment verification
passed **34/34 checks**: every `passed` and `all_checks_passed` value was true,
with no SQL errors. Do not rerun the migration or earlier deployment scripts.

Controlled manual Chrome UI and functional QA is the next stage. Actual caller
authorization, concurrency and end-to-end workflow behavior remain unverified;
catalog success does not establish those results. The agent did not deploy SQL,
modify live attendance, stage, commit or push. The approved Flutter UI is unchanged.

## Launch for controlled Chrome QA

From `C:\Users\theec\Desktop\jobmate`, run:

```powershell
flutter run -d chrome
```

This uses the existing `lib/main.dart` startup and bundled `.env` configuration.
No new Dart defines or configuration files are required. If an older Flutter run
is still active, quit it with `q` in its terminal and launch again. Do not use the
separate Payments preview entry point for Module 4 QA.

## Validation evidence

The owner reran the read-only dependency export at **16:21:03 MYT
(08:21:03 UTC)** on PostgreSQL **17.11**, database `postgres`, role `postgres`.
Compared with the earlier 14:35:58 MYT export:

- All 21 required signatures are present. Both corrected integer overloads are
  present; the earlier missing markers came from incorrect diagnostic signatures.
- All 13 full-definition fingerprints pinned by the candidate match. Their
  owners, `search_path`, security modes and reported execution ACLs match.
- The supplied relation layouts, RLS/ACLs, constraints, indexes and 16 ordinary
  trigger definitions show no relevant change from the previous supplied export.
  This is comparison of the supplied snapshots, not a fresh agent connection.
- Section 08 newly exposes six enabled Supabase event triggers. The original
  candidate incorrectly rejected every hook except `pgrst_ddl_watch`. This was a
  candidate guard defect, not evidence that Supabase recently changed hooks.
- The corrected guard pins all six names, event kinds, tags, owners, handler
  definitions and security settings. The four extension-tagged hooks cannot
  match this migration, which performs no extension operation. Both PostgREST
  watchers only issue transactional NOTIFY. Unknown/drifted hooks stop before DDL.
- Existing function ACLs are now explicitly asserted before replacement. The
  historical-active-shift preflight now also rejects anomalous `verified_at`
  values that would make correction ineligible.

Local preparation consistency check passed:

```powershell
node tools/module4/prepare_batch2_validation.mjs --check
```

The owner executed the generated read-only preflight in the existing project and
reported `BATCH2_PREDEPLOYMENT_PASS` at **16:29:47 MYT (08:29:47 UTC)**. Thus the
13 fingerprint/ACL and six hook assertions, targeted schema/security/trigger
checks and active-shift recovery guard actually ran successfully on PostgreSQL
17.11. This pass does not execute new RPCs.

The owner then ran the whole initial rollback rehearsal and reported
`BATCH2_BASELINE_RESTORED_AFTER_ROLLBACK`: PostgreSQL accepted creation of the
candidate and the baseline restoration assertions passed. Intermediate catalog
booleans were not returned by the SQL Editor. The rehearsal was strengthened to
RAISE on any false/null catalog check. The owner then reran it and reported
**`BATCH2_ALL_CHECKS_PASSED_AND_BASELINE_RESTORED`**, with no errors. PostgreSQL 17
creation, all asserted catalog/cutoff checks and original baseline restoration
have therefore passed through the owner's existing-project SQL Editor runs.
The tested candidate SHA-256 is
`1d9486a4dbc5f6352cdfbfc1e4bc55b20d0d44d97140c4fef451b25916832edf`
(UTF-8, LF). The migration has not changed since that successful rehearsal.

This verifies that preflight/rehearsal are derived from the current candidate;
it is **not PostgreSQL compilation**. The installed PostgreSQL 18.6 binaries
cannot initialize a disposable cluster: their installation lacks
`share/postgres.bki`. No server was started. No further local environment setup
is proposed, as requested by the owner.

Earlier Flutter evidence remains: 365 focused tests, 43 final affected checks,
focused analysis and the final web release build passed. They were not rerun
here because this step changes preparation SQL/documentation only.

**Unverified:** actual database caller authorization/RLS, foreign-company rejection, stale versions,
idempotent replay, lock contention, sibling/original preservation, corrected
evidence/verification and closure integration. Static review and client fakes do
not establish those runtime results. The owner accepts controlled manual QA
after separately approved deployment; there is no isolated test environment.

## Completed pre-deployment procedure (historical; do not rerun)

Run whole files, as `postgres`, in the existing verified project. Pause concurrent
administrator DDL. Do not execute selected fragments or bypass assertions.

1. `supabase/diagnostics/module4_attendance_resolution_pre_deployment.sql`
   is **read-only**: no write RPC or row locks. It checks function fingerprints/
   ACLs, six DDL hooks, protected table layouts/security, assignment triggers and
   whether every existing active shift retains a correction path.
   Pass: `BATCH2_PREDEPLOYMENT_PASS`. Any SQL error is failure; stop and review.
2. `supabase/diagnostics/module4_attendance_resolution_rollback_compilation.sql`
   is **rollback-controlled DDL, not read-only**. Pause attendance, scheduling,
   evidence and closure activity briefly. It takes table locks (2-second lock
   timeout), installs the exact candidate inside one transaction, checks its
   catalog/ACLs and pure cutoff predicate, then ROLLBACKs. No existing business
   data or attendance/resolution/evidence/verification/closure write RPC is used.
   The header contains the normalized candidate SHA-256. Regenerate if it changes.
   Pass requires no SQL errors and the final result
   `BATCH2_ALL_CHECKS_PASSED_AND_BASELINE_RESTORED`. Every catalog boolean is now
   asserted, so an interface showing only the final result is sufficient if the
   complete run had no errors. Never ignore an earlier error even if a client
   continues executing subsequent statements. Capture other result sets if shown.
   The second transaction asserts the original 13 definitions/ACLs and absence
   of candidate objects after rollback. Creation validates syntax; many embedded
   PL/pgSQL queries are planned only when first executed.

On any error, stop. If the SQL Editor stopped before the final rollback, execute
`ROLLBACK;` in the **same session**, or disconnect it to release the transaction.
Do not assume a separate SQL Editor session can roll back the first session.
No permanent migration is authorized by a successful rehearsal.

PostgreSQL references: [transactional NOTIFY](https://www.postgresql.org/docs/17/sql-notify.html),
[event-trigger behavior](https://www.postgresql.org/docs/17/event-trigger-definition.html),
and [deferred PL/pgSQL planning](https://www.postgresql.org/docs/17/plpgsql-implementation.html).

## Completed permanent installation and verification (deployment record)

The owner has completed the following procedure successfully. The instructions
are retained for traceability, not as a request to run the migration again.

After reviewing preflight/rehearsal results and accepting the policy limitations
below, pause affected application activity and administrator DDL. Re-run preflight
if anything changed, then execute this one complete file:

`supabase/migrations/20261114000100_attendance_resolution_candidate.sql`

This **permanent migration** commits the new audit table/private view, guards,
read/write RPCs and integrated evidence/closure/checkout changes as one transaction.
It creates no accounts, fixture records, evidence objects or automatic resolutions.
It explicitly uses READ COMMITTED. Expected result: successful completion through
COMMIT, without any assertion/permission/timeout error. The SQL Editor may report
success with no rows. A lock timeout is a safe failure, not a reason to weaken it.
Do not reapply Batch 1, security, scheduling or earlier migrations.

Immediately run
`supabase/diagnostics/module4_attendance_resolution_post_deployment.sql`:

- Read-only transaction, invoking only the fingerprint-guarded pure cutoff helper.
- Expect 34 rows; all returned `passed` and `all_checks_passed` values must be true.
- Exact predicate boundaries: one microsecond before end+24h = allowed; equal =
  allowed; one microsecond after = rejected. This tests the predicate, not a
  real checkout transaction at a controlled server clock.
- Inspect emitted full definitions/ACLs against the candidate. Fragment checks
  alone are not exhaustive exact-code or runtime proof.
- Confirm RLS, private helper/view grants, authenticated-only new RPC grants,
  expected new triggers and preserved check-in/raw listing definitions.

Coordinate the prepared Flutter build after successful catalog verification.
Old B1 fingerprints for intentionally modified functions will differ. Do not
restore old functions or disable a guard to make the old catalog check pass.
If post-checks fail after COMMIT, pause the rollout and investigate; do not blindly
rerun this non-idempotent candidate or drop audits to reverse it.

## Resolution limitations and smallest follow-up

There is one immutable final resolution per shift, not an editable override:

- Identical request/actor/version/payload replay returns the saved audit.
  A new request or different payload cannot revise it.
- A wrong absence remains absence; no later worker check-in, employer correction
  or cancellation can repair it through the current contract.
- A wrong correction remains the effective attendance used by evidence checks.
  Originals/GPS remain available as the audit trail, but cannot repair the
  effective values through the UI. Verification/payment are not automatic.
- There is no implemented administrator exception. Do not delete/update audit
  rows, overwrite original attendance or disable immutable guards as a repair.

The existing preview/confirmation reduces mistakes but does not solve recovery.
If operationally reversible decisions are required before rollout, that is a
policy release blocker. The smallest proposed follow-up is an append-only
superseding correction referencing the previous resolution and current version,
restricted to the same authorized company, an open unverified engagement and no
evidence attempt/submission; retain every original decision and reason. This is a
proposal only, not added without approval. Post-evidence or post-closure repair
requires a separately reviewed dispute/remediation contract.

Correction eligibility is deliberately conservative:

- Shift must have ended, have a valid hired application/worker/job/company
  relationship, and be scheduled/active/awaiting verification with `not_submitted`
  and no verification timestamp.
- Any evidence file, submission or preparation attempt blocks correction, even a
  blocked attempt. This prevents changing the attendance basis of an immutable
  evidence request. No reset/expiry workaround was introduced.
- Cancelled, completed/verified, disputed or closed records are ineligible. An
  unresolved related application/shift dispute also blocks resolution.
- Absence requires no recorded attendance, GPS status or coordinates. Correction
  requires a complete chronological pair, allowed-window check-in and no future
  times. Manual checkout can exceed the ordinary cutoff with actual-time confirmation.

Historical cutoff protection: preflight aborts the **whole installation** if an
active shift has evidence/preparation, a closed engagement, a dispute, inconsistent
associations/verification or no active authorized representative in a verified
company. Eligible historical active shifts retain manual correction after cutoff.
Later account/company restrictions or newly opened disputes can temporarily make
that path unavailable; there is no automatic bypass. Trusted writers must use
READ COMMITTED; non-API writers have not been runtime verified.

The absence guard freezes assignment/verification status. Therefore an external
workflow that tries to change an absent shift to `disputed` would be rejected.
The supplied export does not establish every KZ dispute writer's behavior.
Before claiming full dispute interoperability, check that workflow with KZ; no
KZ code was changed and no new dispute workflow is proposed here.

Normal closure keeps its minimum verified work requirement. Verified work plus
legitimate audited absences/cancellations can close when reservations/disputes
are clear. All-absent/no-verified engagements remain blocked. No automatic
closure, reputation, evaluation or payment outcome is introduced.

## Controlled manual QA after deployment

Use existing employer/job-seeker test accounts and explicitly designated existing
shifts. Do not experiment on unrelated real attendance. A final resolution cannot
be undone; confirm the intended actual attendance/absence before saving.

1. Refresh both roles: correct scope, lifecycle, status colors, compact groups,
   issues shortcut, History All/Recorded/Issues, and AM/PM Review Shift confirmation.
2. Employer: eligible absence/correction offers only allowed decisions; reason,
   actual-time confirmation and preview required. Success refreshes only that shift.
3. Worker: own reason/date/corrected times visible; other workers/companies cannot
   access the audit. If no foreign-company test actor exists, mark that test unrun.
4. Compare original raw timestamps/GPS and sibling shifts before/after a designated
   resolution. Absence must not invent attendance or mark work verified.
5. Correction: actual effective times support normal evidence prepare/submit/review;
   work becomes verified only after explicit employer evidence verification.
6. Exercise stale review and competing tabs only on a designated shift: one audit,
   no overwrite; lost responses reconcile the same request, not a replacement.
   Multi-session database contention remains unverified until actually exercised.
7. Ordinary checkout after cutoff rejects; historical correction remains reachable.
   Late checkout retains the actual server timestamp and no payable-hours approval.
8. Closure: verified + absent can be eligible; all absent remains ineligible;
   unresolved reservations/disputes still block. Close only if explicitly intended.

## Targeted staging preparation — commands NOT executed

`git check-ignore -v` confirmed these patterns:

- `.gitignore:59 supabase/migrations/`: the new permanent candidate.
- `.gitignore:63 supabase/diagnostics/*`: all five Batch 2 diagnostic SQL files
  listed in the force-add block below.
- `.gitignore:72 *test*`: the four new lifecycle/resolution tests below.
  Existing tracked tests remain tracked despite that pattern.

Review each diff before staging. No wildcard, `git add .`, `.gitignore` edits or
unrelated phase/workspace/admin/reputation tests are needed. These commands
prepare a combined pending Module 4 Batch 1/2 commit: the route/navigation files
already carry its uncommitted History integration. If committing Batch 2 separately,
split those reviewed hunks first rather than staging unrelated changes.

```powershell
git add -- README.md docs/module4_batch2_deployment_handoff.md tools/module4/prepare_batch2_validation.mjs
git add -- lib/features/work_attendance/work_attendance_lifecycle.dart lib/features/work_attendance/work_attendance_resolution.dart lib/features/work_attendance/work_attendance_resolution_dialog.dart
git add -- lib/features/work_attendance/work_attendance_models.dart lib/features/work_attendance/work_attendance_pages.dart lib/features/work_attendance/work_attendance_repository.dart lib/features/work_attendance/work_verification_pages.dart lib/features/work_attendance/work_assignment_creation_dialog.dart
git add -- lib/features/work_attendance/work_evidence_pages.dart lib/features/work_attendance/work_evidence_deadline.dart lib/features/work_attendance/work_evidence_submission_repository.dart lib/features/work_attendance/work_status_presentation.dart
git add -- lib/features/work_attendance/work_attendance_routes.dart lib/features/work_attendance/work_evidence_draft_page.dart lib/features/work_attendance/company_workers_page.dart lib/main.dart lib/shared/navigation/workspace_destinations.dart
git add -- test/work_assignment_creation_dialog_test.dart test/work_verification_pages_test.dart test/work_verification_grouping_test.dart test/work_attendance_pages_test.dart test/work_attendance_repository_test.dart test/work_evidence_deadline_test.dart
git add -f -- supabase/migrations/20261114000100_attendance_resolution_candidate.sql
git add -f -- supabase/diagnostics/module4_attendance_resolution_dependency_inspection.sql supabase/diagnostics/module4_attendance_resolution_schema_guard.sql supabase/diagnostics/module4_attendance_resolution_pre_deployment.sql supabase/diagnostics/module4_attendance_resolution_rollback_compilation.sql supabase/diagnostics/module4_attendance_resolution_post_deployment.sql
git add -f -- test/work_attendance_lifecycle_test.dart test/work_attendance_lifecycle_pages_test.dart test/work_attendance_resolution_test.dart test/work_attendance_resolution_dialog_test.dart
git diff --cached --name-only
git diff --cached --check
```

Keep `.vscode/launch.json`, `test/phase3_test.dart`, `test/phase4_test.dart`,
`test/phase52_visual_test.dart`, `test/workspace_test.dart`, KZ's files, unrelated
diagnostics/plans, `jobmate_module4_inspection.txt` and `remaining_failures.txt`
out of this staging list. Older deployed Batch 1 diagnostic SQL is not force-added
by these commands and must never be executed again as an installation step.

# PDF evidence and work verification — local implementation

Workers with completed server attendance can select 1–5 validated PDF/image files
(10 MiB each), enter a description, explicitly confirm private upload/submission,
and submit for employer review. Existing byte/header, duplicate-file, MIME and
size validation is reused. Upload uses append-only private Storage, UUID paths,
`upsert: false` and no transport retries. There is no automatic cleanup/deletion.

Employer **View PDF → Open PDF** opens the actual private file in the browser or
PDF app after fresh assignment and per-file authorization. Existing private
90-second signed access is reused; URLs are not displayed as permanent links.
Both old and resubmitted files remain accessible to authorized viewers. A PDF
viewer/tab that has already received a file cannot be recalled on sign-out.

Employers confirm Verify work or Request more evidence with a 1–1,000 character
reason. Each decision is bound to a specific submitted round. Workers see the
reason and can submit new files for the next round. Both roles see authorized
submission/request/resubmission/verification history. New events carry the actual
server round; historical events keep a null round and are labelled accordingly.
There is no guessed backfill or rewrite of existing audit data.

## Completed deployment and migration order

The project owner confirms that the four follow-up migrations (steps 2–5 below)
are deployed and catalog-verified in the shared Supabase database as of
2026-11-06. Step 1 is the existing base prerequisite. Do not reapply deployed
migrations. This cleanup performs no deployment or remote verification.
Catalog checks do not establish runtime authorization, Storage behavior,
concurrency safety or client release readiness. Keep writes paused outside
separately approved synthetic-fixture QA until coordinated cutover is complete.

The relevant Module 4 order is:

1. `20261105000100_work_attendance_verification.sql`: existing base prerequisite,
   not a standalone backend bootstrap; do not reapply an already deployed file.
2. `20261105000300_work_evidence_attempt_reservations.sql`: required worker
   reservation contract; deployed and catalog-verified.
3. `20261106000100_work_assignment_creation_idempotency.sql`: repeat-shift
   creation; deployed and catalog-verified.
4. `20261106000200_employer_attendance_gps.sql`: employer GPS viewing;
   deployed and catalog-verified.
5. `20261106000300_work_evidence_workflow.sql`: new workflow context/history,
   round-bound review reservations, active-account/private-file checks and
   legacy-write cutover; deployed and catalog-verified. Requires steps 1–2;
   steps 3–4 are independent features.

Do not blindly push every migration in the directory. The excluded
`20261105000200_work_evidence_submission_idempotency.sql` is an alternative
caller-key prototype, **not required**. It adds a four-argument overload and
submission columns, whereas draft 0003 uses a server-issued reservation and a
two-argument overload. They are technically distinct overloads but competing
write paths. Do not deploy 0002. The approved deployment checks reject its known
alternative footprint; any installation requires separate compatibility review.

Draft 0003 alone leaves legacy writes executable and is insufficient for safe
production cutover. The new migration revokes authenticated/PUBLIC/anon EXECUTE
on legacy submit, request-more and verify calls. Trusted definer owners must
retain permission for nested calls. This intentionally prevents old clients,
including old supervised QA controls, from writing after cutover. Coordinate
client release and test the exact grants/owners in isolation first. General
workflow controls exclude the protected QA assignment; no cafe/QA record was
used or changed. Never use those records for rollout tests.

The new migration requires an already-private `work-evidence` bucket and fails
otherwise; it does not make a bucket public or change existing objects. It adds
restrictive scoped read/insert/delete policies while retaining the existing
update denial. Inspect all actual bucket grants/policies and the deployed
`can_manage_company_jobs` helper, whose definition is absent from this checkout.
No new credentials, environment variables, dependencies or Dashboard secrets.

## Retry, concurrency and recovery rules

- Worker preparation reserves exactly one immutable attempt per assignment/target
  round. Current ownership/active role, checked-out attendance, expected previous
  round, description, 1–5 paths, Storage owner/MIME/size and path reuse remain
  server validated. No arbitrary total-round cap is added.
- Submission commits that server request only. Replaying the same ID returns
  its original result; old requests cannot become later resubmissions. Blocked
  attempts remain terminal; no reset/rekey API is introduced.
- Reviews similarly reserve one immutable actor/decision/reason per round.
  Commit and audit linkage are atomic. A competing employer cannot replace a
  reserved decision. An abandoned prepared review must be completed by its
  original authorized employer; ownership loss needs separately audited support.
- Read workflow status on reopening. After a prepared reservation is recovered,
  **Complete reserved action** explicitly commits the same request. No upload,
  preparation, submit or review write is automatically retried.
- Missing responses and empty reads do not prove failure. Running-app locks span
  dialogs/controllers and block replacement batches/decisions after uncertainty.
  Account changes permanently invalidate the old controller and clear draft
  bytes/history/links. Server reservations survive restart; local upload-only
  locks do not. Do not restart to bypass an uncertain action.
- An uncertain upload before preparation can leave orphaned private objects.
  Reopening must reconcile; do not overwrite/delete/reupload to “fix” it. Server
  round uniqueness still prevents duplicate formal submissions across devices.
  Orphan cleanup and terminal blocked-attempt recovery require separate review.

## Remaining runtime/security QA and release gates

Flutter tests use fake state machines and loopback HTTP only; they do not prove
PostgreSQL behavior, RLS or actual Storage/PDF rendering. The isolated SQL script
`supabase/tests/work_evidence_workflow.sql` was authored but not executed: no
isolated database/fixture environment or `psql` was available.

Before client release, test runtime behavior on a disposable isolated database
with synthetic checked-out workers and authorized employers.
Use real PDFs uploaded through private Storage, not fabricated Storage rows.
Run the SQL script plus multi-session races, lost responses, stale-round replay,
account/membership revocation, immutable history/request linkage, file limits,
private signing expiry and Storage read/write/update/delete authorization.
Verify original record counts/content remain unchanged. Do not rerun migrations
or make schema/ACL changes as part of these tests. All `supabase/tests` scripts
are isolated-database-only; they are not the shared deployment's catalog checks.
For the evidence script, supply the required non-empty `protected_assignment_ids`
JSON array from a private, reviewed protection manifest. Include all protected
real/QA assignments, never dummy IDs; do not commit the populated manifest.
Missing, empty, null or invalid protection inputs must stop the test before RPCs.
The script does not prove the list is complete or that the connection is isolated.

Then, only with explicit live QA approval, verify Web/Android checkout → PDF
submission → private PDF opening → request reason → updated PDF → final verify
and history, including browser refresh, direct routes, large text, PDF-app/new-tab
handling and account switching. Neither SQL nor live browser/Supabase behavior
has been verified by this local implementation.

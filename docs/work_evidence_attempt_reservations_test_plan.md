# Evidence attempt reservations — DRAFT, NOT EXECUTED

Migration: `supabase/migrations/20261105000300_work_evidence_attempt_reservations.sql`.
No SQL, fixtures, uploads or deployment were executed to prepare this document.
Neither migration draft is deployment authorization. Submit Evidence stays disabled.

## Dependencies and caller inventory

Requires the deployed original `20261105000100`, its exact schema/RPC, trusted
function ownership and JWT-backed `auth.uid()`. It does not require or apply the
undeployed `20261105000200` prototype. Do not blindly push all pending migrations.
If the prototype is present, its four-argument overload is a separate bypass.
This draft adds a two-argument overload and does not change the prototype.

Local inventory: the sole Flutter transport string calling `submit_work_evidence`
is `SupabaseWorkEvidenceSubmissionSource.submit()` in
`lib/features/work_attendance/work_evidence_submission_repository.dart`.
It passes `p_assignment_id`, `p_description`, `p_storage_paths` and expects an
integer. No production page constructs that submission source or repository;
the draft form's Submit Evidence button is disabled. The targeted submission
test uses fakes and a loopback HTTP server. There is no Flutter caller of either
idempotent overload. This inventory cannot establish external clients, previous
deployed builds, Edge Functions outside this checkout or teammate scripts.

The legacy SECURITY DEFINER function obtains the actor through `auth.uid()`, not
`current_user`. A wrapper changes execution privileges, not the request JWT. It
locks the same assignment, checks worker/active role, writes one submission round,
evidence/history/status and returns that round. It has no independent commit or
exception handler. Its writes roll back with any wrapper failure. These are
source-review conclusions, requiring runtime verification against deployed code.

## Wire contract and transaction boundaries

- Prepare: `(p_assignment_id uuid, p_expected_previous_round integer,
  p_description text, p_storage_paths text[]) -> jsonb`.
- Recover: `(p_assignment_id uuid) -> jsonb`.
- Submit: `submit_work_evidence_idempotent(p_assignment_id uuid,
  p_request_id uuid) -> jsonb`. Unlike the earlier proposed four-argument API,
  this consumes only the immutable server payload; callers cannot replace it.
  Flutter must show the recovered canonical description/files for confirmation.

Attempt JSON has exactly the new table's columns: request_id, assignment_id,
worker_id, target_round, description, storage_paths, state, submission_id,
error_code, created_at, updated_at. `target_round` is a committed round ONLY when
state is `committed`; a prepared target is not evidence history or success.
Recovery JSON adds assignment_id, latest_submission_round, assignment_status,
verification_status and an attempts array ordered by descending target_round.
Recovery includes all own recorded attempts, including blocked/older rounds.

Prepare and submit are separate RPC transactions. After explicit user intent,
uploads must already be confirmed; preparation reserves the payload and commits
before submission dispatch. Recover before any new attempt after restart.
No automatic retry, regenerated key or replacement payload after uncertainty.
An empty recovery result cannot establish failure or unlock a replacement.
Repeating preparation is safe ONLY for the same explicit intent, baseline and
payload; it is not permission for the client to automatically submit afterward.

All writers lock assignment first, attempt second. Baseline is a stale-intent
precondition; actual round allocation is server-owned. Existing original-baseline
reservations are checked before current new-round eligibility. A delayed round-1
request remains tied to round 1 after an employer requests round 2.
At READ COMMITTED, a caller waiting for another assignment writer must see its
commit in subsequent statements. At stronger isolation, serialization failure
is acceptable: recover first; never interpret failure as permission to rekey.

## Definite failures and blocked recovery policy

Only explicit server-observed business conditions record `blocked`: baseline or
assignment eligibility changed, incomplete attendance, invalid reserved payload,
missing/invalid owned Storage metadata, or a previously registered path.
Internal helper SQLSTATEs JM001/JM002/JM003 identify these deliberate validations.
Authentication failures do not disclose or mutate attempts. Changed preparation
payload raises conflict without blocking or changing the original reservation.

No catch-all converts a timeout, network/database outage, deadlock, serialization
failure, arbitrary P0001, trigger/constraint error or failed association into a
terminal business rejection. A submission transaction that raises rolls back;
its separately committed reservation stays prepared. A lost response can mean
prepared, blocked or committed; only authorized recovery establishes which.

Blocked is terminal: no expiry, delete, payload edit, reset or replacement at
the same round. Even restoration of a missing file does not unlock it. This
conservative policy prevents delayed old requests from reviving. A safe user or
administrator correction workflow remains UNRESOLVED and is a production UX
blocker. Do not disable the trigger or manually edit attempts to bypass it.
Any later recovery design requires separate authorization, stale-request analysis
and audit history; no reset mechanism is invented here.

## Test environment and fixtures

There is no established isolated PostgreSQL/Supabase harness in this checkout.
The following matrix is for a separately approved disposable environment with
the prerequisite auth/application/Storage schemas, roles and extensions. Do not
execute fixtures against the shared development project as a substitute.

Use only synthetic active workers A/B, an inactive worker, an employer/manager,
companies, jobs, hired applications, checked-out assignments and owned private
Storage objects. Include legacy submissions with no attempt rows. Simulate real
authenticated role/JWT claims in separate sessions; do not test only as owner.
Verify `auth.uid()` is the synthetic worker inside both nested functions.
Record per-assignment evidence, submission and history counts/status before and
after. Never use the real cafe assignment or the live QA assignment as fixtures.

## Minimum PostgreSQL test matrix — NOT RUN

| Case | Expected result |
| --- | --- |
| Empty additive installation over legacy rows | Only new table/functions/trigger/ACLs added; all existing data, original grants, Storage policies and employer history unchanged |
| Prepare round 1 | Server UUID, target 1, prepared row; no submission/evidence/history/status writes |
| Prepare invalid inputs | Reject NULL/blank/>2000 description; NULL/empty/>5/duplicate/NULL-element/multidimensional/non-1-based arrays; malformed paths; no reservation or partial writes |
| Private object validation | Reject wrong folder/owner/bucket, missing/NULL/unsupported MIME, malformed/zero/>10 MiB size, reused paths; never upload, overwrite or delete objects |
| Same payload prepare replay | Outer ASCII spaces normalize with PostgreSQL btrim; exact ordered paths return original UUID; timestamps/counts unchanged |
| Changed payload | Description change, reorder/add/remove/replace paths conflicts; original reservation remains intact |
| Lost prepare response / restart | Recovery by assignment returns UUID and canonical payload; same-baseline prepare cannot create a second reservation |
| Authorized submission | One actual round, expected worker/assignment/description/file count, evidence and history; attempt becomes committed with exact submission_id |
| Lost submit response | Recovery returns committed; repeated same request returns same row; no new round/history/status timestamp changes |
| Replay after request-more/verification | Current active worker may recover original committed attempt without rechecking NEW-submission eligibility; no review decision is reversed |
| New round 2 | Only after authorized employer request-more; baseline 1 -> target 2 with NEW unused paths; old baseline/request remains bound to round 1 |
| Delayed old preparation | Identical baseline-0 request returns original round-1 reservation, including terminal state; changed payload conflicts, never allocates round 2 |
| Delayed blocked request | Returns blocked, even if attendance/Storage/eligibility later restored; no reset or submission |
| Authentication and scope | Anonymous, employer, inactive/wrong worker, foreign assignment or request denied before payload disclosure; account reactivation never changes reserved identity |
| Ownership changes | New assignment owner cannot recover previous worker's payload or reuse its reserved round; fail closed |
| Guard/constraints | Trusted test role attempts UPDATE of payload/request/baseline/created_at, DELETE, terminal-state reversal, invalid state/submission/error combinations: reject |
| Direct access and ACLs | authenticated/anon/PUBLIC cannot read/write attempts or invoke helpers; only authenticated EXECUTE on three RPCs; verify effective inherited/default ACLs too |
| Definite business rejection | Structured blocked result persists, no evidence/history/submission writes; no RAISE after marker update |
| Transient DB failure | Inject serialization/deadlock/statement cancellation; request transaction rolls back, prior reservation stays prepared, never blocked |
| Unknown legacy P0001 | Inject a test trigger raising arbitrary P0001; entire call rolls back, reservation stays prepared; do not misclassify as business rejection |
| Post-legacy failure | Test trigger rejects attempt commitment or wrong returned round/association; no new evidence/submission/history/status survives |
| Recovery during in-flight request | May observe older prepared snapshot; never claim failure or permit replacement; subsequent recovery observes committed result |
| Legacy bypass | Until cutover, a legacy caller can consume a reserved target; new submit records round_changed instead of claiming the legacy round |
| Prototype coexistence | If older four-argument prototype installed, verify no overload collision and explicitly demonstrate it remains a bypass pending cutover |

Use two independent sessions for concurrency, including delayed commits:

1. Identical preparation: second waits, then same UUID; first rollback allows only
   one eventual reservation. Conflicting preparation: second conflicts, no mutation.
2. Identical submission: second waits, then same committed submission; only one
   submission/history action. First rollback leaves prepared for recovery.
3. Race submission with request-more/verification: shared assignment lock and
   existing eligibility rules serialize valid decisions. No cross-round replay.
4. Race legacy and reserved submission: safe association failure/blocked result,
   never adoption of a legacy round; demonstrate why cutover is mandatory.
5. Repeat under READ COMMITTED, REPEATABLE READ and SERIALIZABLE. Examine outcomes
   rather than requiring all stronger-isolation calls to succeed.

Fault-injection triggers/explicit transaction rollbacks belong ONLY in the
disposable environment. Remove those fixtures afterward, never real records.

## Deployment blockers, coordinated cutover and recovery

No verified full backup or runtime tests exist. Do not deploy this draft yet.
Establish a permission-complete, encrypted logical backup and a tested restore
procedure; Storage bytes require separate backup. Capture deployed definitions,
ownership, effective ACLs and baseline counts. Coordinate a quiet window with the
teammate. Function owners need protected-table and Storage metadata access and
legacy EXECUTE; auth.uid() must use unchanged request JWT claims.

The new table avoids ALTER/index creation on the populated submissions table,
but foreign keys and DDL can still acquire locks. Use an independently reviewed
bounded lock-wait/deployment procedure. This BEGIN/COMMIT draft is apply-once,
not rerunnable: name collisions or failures abort it. Lost COMMIT responses need
catalog inspection before rerunning, not a blind migration retry.

Before enabling UI: inventory external callers and older app builds; adapt and
mock-test Flutter to the new JSON/two-argument contract; preserve explicit
confirmation and startup recovery. In a SEPARATE approved cutover, remove direct
authenticated EXECUTE on legacy submit_work_evidence(uuid,text,text[]) and any
installed four-argument prototype; verify PUBLIC/anon/inherited role paths cannot
bypass this and the trusted wrapper owner retains legacy EXECUTE. Reject old
clients safely; attendance/read/review RPC grants remain unchanged. Until then,
reservation enforcement is NOT universal. No such revocation is in this draft.

If a defect is found after deployment, first keep UI disabled and separately
authorize containment of new RPC entry points. Prefer additive forward fixes;
preserve reservations, committed associations and evidence. Do not drop the
table/functions or erase keys after use. Full restore can lose teammate work
since the backup; it requires a separate incident decision and restore plan.

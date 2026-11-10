# Module 4: exact manual release sequence — NOT EXECUTED

## Current sprint status — November 10, 2026

This section supersedes historical setup/backup/fixture instructions below.
Owner-verified today: security rollback compilation passed; updated NOWAIT
scheduling B1 passed 31/31; independent fresh A0 passed 31/31 at
2026-11-10 08:25:05 UTC (16:25:05 MYT). Original objects were restored.
Neither candidate is permanently deployed. Do not repeat compilation rehearsal
unless SQL changes; the Flutter contention edits do not change any SQL.

Flutter now treats 55P03 as a rejected, retryable contention outcome: clear the
failed creation attempt, reload server candidates/assignments, refresh closure
status and return to review before explicit reconfirmation. Failed refresh keeps
submission unavailable. No automatic retry; uncertain/lost responses retain their
existing reconciliation lock. No CH Flutter reschedule/cancel RPC call was found.
Formatting and scoped whitespace checks passed; no tests/analyzer were rerun.

Remaining operator actions: (1) authorize a temporary authenticated, read-only,
caller-gated measurement RPC returning only transaction_isolation, invoke it via
actual PostgREST and review the scheduling RPC/role/hook settings for equivalence,
then remove it; no existing inspected RPC exposes that value. This is separate
reviewed DDL, not authorized or executed here. (2) Provide an explicitly approved
synthetic fixture graph in the existing project for two-session NOWAIT versus
cancellation verification and security manager/foreign/revoked authorization/audit
checks. No fixture currently available is authorized, and no real user/production
record mutation or fixture provisioning is inferred. A lock-only demonstration
is not actual guard/cancellation runtime evidence. Keep release blocked until
these results exist. No Docker, second database or local backups are required.

Deployment order, CONDITIONAL and not yet cleared:

1. `supabase/diagnostics/closure_decline_authorization_patch_candidate.sql` — only
   after its runtime authorization/release prerequisites are satisfied; then
   require A1 31/31 from `work_shift_release_catalog_checks.sql`.
2. `supabase/migrations/20261110000100_work_shift_schedule_enforcement_candidate.sql`
   — only after security A1, scheduling rehearsal, actual authenticated API
   isolation evidence and locking prerequisites pass; then require B1 31/31.

Implemented lock-conflict fix: the CH scheduling UPDATE guard now acquires both
old/new application rows in UUID order with FOR UPDATE NOWAIT. If cancellation
holds either application while waiting for the assignment tuple, the rescheduler
fails immediately with SQLSTATE 55P03 instead of waiting back on cancellation.
The failed transaction must roll back; retry the whole operation after contention
ends, rechecking eligibility. No SKIP LOCKED, exception swallowing, automatic
retry, cancellation-body change or authorization change is introduced. INSERT
keeps its existing blocking application lock. Application-first prelocking is
still preferred for trusted writers; arbitrary multi-row/external transaction
lock graphs are not claimed deadlock-free. Verify this specific race using two
sessions before scheduling release. Updated guard LF body MD5:
`f31c8ce2ade136ac0d0ab016dd450b46`. Existing security and baseline hashes remain.

Official PostgREST transaction documentation confirms READ COMMITTED is the
default with impersonated-role/function overrides:
https://docs.postgrest.org/en/stable/references/transactions.html#isolation-level
This supports the expected default, not a measurement of this project's API.
SQL Editor settings and catalog absence of overrides do not establish actual
request isolation or hooks/pool freshness. Keep the candidate's isolation guard.
No checked-in PostgREST server configuration or exported RPC that returns actual
transaction isolation was found. All 63 exported function definitions were
searched; none exposes transaction_isolation/default_transaction_isolation.
An ordinary successful read RPC does not measure isolation. The project operator
must supply effective PostgREST configuration/role/function/hook evidence or a
separately reviewed, authenticated read-only measurement path; do not infer it
from the SQL Editor, expose pg_catalog or invent an existing RPC.
No connected Supabase SQL tool or authenticated database session is available
in this agent session; no live SQL/API execution is claimed.

Flutter inbox implementation now locks responses during confirmation/submission,
ignores replaced-gateway completions and refreshes after success or uncertain
failure. Closure RPC transport retries are disabled. No new tests or analyzer
runs were requested or executed for these edits; earlier results do not validate
the new changes. Web/Android and real private Storage acceptance remain pending.

**Security: NO-GO. Scheduling: NO-GO. Operations: NO-GO.** These are deployment
verdicts, not a rejection of the approved security implementation.

KZ/closure-owner approval is user-confirmed, including the concurrent membership
revocation limitation. The fresh check rejects membership removal/demotion committed
before authorization under READ COMMITTED; it does not serialize a later revocation
with commit. No membership helper changes are proposed.

Available tooling: postgres/psql 18.6 at `C:\Program Files\PostgreSQL\18\bin`;
not on PATH. `postgres --version` and `psql --version` ran. `share/postgres.bki`
is missing and no PostgreSQL service was found. No usable isolated database was
established or connected to. No Docker/Supabase CLI was found on PATH. No setup,
SQL compilation, database tests or live connections occurred.

## Execute in this order only after each preceding gate passes

1. Human verifies the Supabase project/environment and confirms a usable backup/
   PITR restore point, restore-capable operator/access and maintenance window.
   Neither backup availability nor restore access is established by local files.
2. **Read only:** `supabase/diagnostics/work_shift_rpc_isolation_inspection.sql`.
   Save the export. Existing user-reported results show READ COMMITTED/default and
   no catalog isolation overrides. Actual authenticated PostgREST isolation and
   hook/pool behavior still need verification; SQL Editor values are insufficient.
3. **Read only:** `supabase/diagnostics/work_shift_release_catalog_checks.sql`.
   Every `A0_BEFORE_SECURITY` row must pass. Other stage failures are expected at
   this point. This is target/code/security evidence, not runtime approval.
4. Gate: obtain PostgreSQL execution evidence for the four security cases below
   using a verified test target/fixtures; review recovery and drain existing closure
   responses. **Only after separate human release authorization:** execute the
   entire `supabase/diagnostics/closure_decline_authorization_patch_candidate.sql`.
   Its existing pre/post assertions preserve the approved one-block change and
   exported grants/owner/locks/audit statements; this file was not modified today.
5. **Read only:** rerun `work_shift_release_catalog_checks.sql`; every
   `A1_AFTER_SECURITY` row must pass. Perform approved synthetic security smoke
   checks through actual user API sessions. Stop on any mismatch; save evidence.
6. Gate: confirm actual API READ COMMITTED, recovery access, and that all service
   reschedulers prelock applications in UUID order before UPDATE (or keep them
   paused). Obtain the six focused scheduling checks below. No requirement to run
   the full 31-scenario catalogue. Then, with separate human release authorization,
   execute the entire
   `supabase/migrations/20261110000100_work_shift_schedule_enforcement_candidate.sql`.
7. **Read only:** rerun `work_shift_release_catalog_checks.sql`; every
   `B1_AFTER_SCHEDULING` row must pass. Repeat approved synthetic smoke checks,
   confirm no unauthorized writes/audit changes, then owners authorize resuming work.

Never execute all files as an unattended batch. An error means stop, preserve the
result and investigate; do not skip assertions or restore historical grants.

## Small critical verification set — prepared, NOT run

Security (real authorized/unauthorized API identities, distinct pending requests):

- Authorized representative: `close` returns closure time, accepted state and
  original closure/audit event; separate valid `decline` returns null and records
  declined/actor/time/reason plus one declined event. Recorder eligibility still applies.
- Worker/foreign-company caller: decline denied with 42501, no state/event change.
- Remove/demote the manager's membership using the approved fixture process;
  a subsequent decline must be denied, even if their UI was opened before removal.
- Repeat a completed response or use invalid reason/decision: preserve original
  rejection/state semantics and no duplicate event. Check original owner/ACL/settings.

Scheduling (only designated synthetic fixtures; no arbitrary live mutations):

- Future same-day MYT shift succeeds once; separate days use separate assignments.
- Past/equal start and overnight/MYT-midnight crossing reject without residual shift/link.
- Completed request replay after start returns the original ID; lookup remains historical.
- Legitimate historical status-only lifecycle UPDATE bypasses new schedule validation.
- Two sessions: lock-wait creation versus closure; no new shift after closure and
  no closure while an unfinished shift/unresolved reservation exists.
- Two sessions: approved direct rescheduling versus cancellation using the prelock
  protocol. If any approved writer cannot follow it, scheduling stays NO-GO.

## Recovery and remaining gates

Scheduling code rollback:
`supabase/diagnostics/work_shift_schedule_enforcement_rollback_candidate.sql`.
It now EXPECTS and PRESERVES the approved security fix. It only removes scheduling
guards/restores the original four scheduling bodies; no data rollback is claimed.
Closure security rollback:
`supabase/diagnostics/closure_decline_authorization_rollback_candidate.sql`.
It is deliberately disabled because it reopens the known authorization defect;
forward repair/approved containment is preferred. It must NOT be used after
scheduling installation without reviewing pinned dependency drift.

Read-only-resolvable gates: verified target, code/ACL freshness, catalog settings,
operator backup/PITR/restore-access evidence and approved-writer inventory.
Execution-required gates: compilation, actual authenticated RPC isolation/behavior,
authorization/audit assertions, critical races and a verified recovery method.
Backups and runtime outcomes cannot be inferred from the new catalog check script.

Scheduling's rebased security dependency is an **expected approved-artifact body**
(`8558e154e5eae1e8ea7b09c3fed41103`, LF MD5), not a newly verified live definition.
All other baseline definitions remain from the 3,392-row November 10 export.
Actual stage-A1 checks must match before B can proceed. No claim of production
readiness is made until outstanding evidence is supplied and validated.

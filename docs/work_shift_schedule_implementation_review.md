# Module 4 scheduling enforcement candidate review

**NOT DEPLOYED. No database connection, SQL execution or database tests performed.**
Prepared 2026-11-10 for offline review and isolated testing, not live deployment.
This supersedes the missing-body blocker in the Phase 1 readiness document for
the objects present in this export; it does not certify current-live equivalence.

## Evidence and reproducibility

Authoritative supplied baseline:
`supabase/diagnostics/work_shift_schedule_catalog_export_20261110.csv`.
Capture: 2026-11-10 02:43:03.451069 UTC, PostgreSQL 17.11, execution/session role
postgres. Parsed 3,392 CSV records and 3,392 JSON detail objects. Every record's
total count and every section count match. All 11 required function markers and
8 table markers report found; each required function has one overload. The
export contains 63 function definitions, 12 relations and 24 selected roles out
of 31 installed roles. All 63 supplied definition MD5s match the decoded UTF-8
source bytes, including original CRLF body content.

`work_shift_schedule_baseline_manifest.json` records the CSV SHA-256, capture
metadata and exact definitions, signatures, settings, owners, grants and MD5s for
the pinned scheduling/lifecycle functions. Do not silently normalize line endings
inside baseline bodies: that changes raw baseline fingerprints. Candidate and
restored-body checks normalize CRLF/CR to LF so SQL Editor newline conversion
cannot cause a false rollback/apply failure; all other source text remains checked.
The raw pre-deployment definition hashes remain strict. The offline builder
`build_work_shift_schedule_candidates.ps1` verifies counts/hashes and uses
single-match edit anchors; it never connects to PostgreSQL or executes SQL.

Artifacts:

- `supabase/migrations/20261110000100_work_shift_schedule_enforcement_candidate.sql`:
  complete transactional forward candidate. Do not include it in an automatic
  migration push. Its presence under migrations is not deployment authorization.
- `supabase/diagnostics/work_shift_schedule_enforcement_rollback_candidate.sql`:
  complete conditional restoration proposal, separate approval required.
- `work_shift_schedule_isolated_test_scenarios.md`: required real-database cases.

## Baseline and meaningful differences from old migrations

| Function | Exported definition MD5 |
| --- | --- |
| `public.reserve_work_assignment_request(uuid,timestamptz,timestamptz,text)` | `7a5fd48bd7bcd9779f4c9d39f6fd67a2` |
| `public.create_work_assignment_request(uuid,uuid,timestamptz,timestamptz,text)` | `12255c24979f6e24e79e83b0ecd252af` |
| `public.create_work_assignment(uuid,timestamptz,timestamptz,text)` | `bb8d8bda205e02207b57541a185ca950` |
| `public.guard_work_assignment_duplicate_shift()` | `3de11b7ad06274924f25c49651767259` |
| `public.lookup_work_assignment_request(uuid)` (unchanged) | `d25d36d41b920c39381d4cb1799a5ef4` |
| `private.record_job_engagement_closure(uuid,uuid,text)` (unchanged) | `eecdf7e6d167363639b505a7dbc8a6a0` |
| `public.can_manage_company_jobs(uuid)` (unchanged) | `7c41597c243580062e49efd25af2f9f0` |

The three creation RPC bodies and lookup retain the old local design; the deployed
duplicate guard has materially newer logic: locks old/new application IDs in UUID
order on relink, rejects closed engagements, rechecks Hired under lock, rejects
cancelled request tuples, then maintains historical exact-shift and durable-claim
checks. The old migration omits those protections. The candidate patches the
**complete exported body**, retaining every branch rather than replaying migration
DDL. Its existing `work_assignment_duplicate_shift_guard` trigger is not recreated.

The export also contains closure, audited assignment cancellation, reservation
cancellation and terminal-state protection absent from the original Module 4
migrations. Closure refuses unresolved uncancelled reservations and unfinished
shifts; it permits only verified completion or audited cancellation and checks
related disputes. These functions/triggers remain unchanged and fingerprinted.

Contrary to earlier release notes suggesting legacy EXECUTE was revoked, this
capture grants the legacy creation RPC and all three request RPCs execution to
postgres, authenticated and service_role. The duplicate guard is executable by
postgres/service_role, not authenticated/PUBLIC. All are postgres-owned DEFINER,
empty search_path; creation/request/guard functions are VOLATILE. Existing ACLs
are preserved exactly; there are no GRANT/REVOKE statements targeting them.
Only the two NEW private helpers receive REVOKEs, leaving owner-only execution.
Unexpected additional default grants abort the candidate instead of being ignored.

## Validation and lifecycle scope

New private `validate_work_shift_schedule(timestamptz,timestamptz)` rejects NULL,
infinite, past/equal-current starts, non-increasing ends, and unequal Malaysia
calendar dates using explicit `Asia/Kuala_Lumpur` conversion and
`pg_catalog.clock_timestamp()`. Errors use SQLSTATE 22023. It is VOLATILE,
INVOKER, empty search_path and called from trusted postgres-owned functions.

Reservation: matching request lookup/payload checks return BEFORE new validation.
Only a new reservation is checked before and after its INSERT. Request creation:
authorized completed-request replay returns BEFORE validation; an unfulfilled
request is checked before legacy creation and after assignment linking. Legacy
creation checks both before and after INSERT. The existing BEFORE duplicate guard
checks effective new/relinked/rescheduled shifts after its application/claim waits.

New private DEFINER trigger function provides AFTER-row checks on assignment
INSERT or UPDATE OF application_id/scheduled_start/scheduled_end and reservation
INSERT. The final AFTER check covers immediate GiST, unique and FK waits occurring
after a BEFORE trigger. A validation failure rolls back the whole statement,
including assignment/request links and claims; it is not caught and suppressed.
The RPC's final check also covers later link UPDATE/trigger waits.

Status-only attendance, verification and audited cancellation UPDATEs do not fire
the new assignment trigger. Effective no-op schedules skip the new checks; the
pre-existing duplicate/closure trigger's original behavior still applies if its
columns are targeted. No existing rows, old claims, request IDs or cancellation
records are rewritten; old overnight/historical shifts remain readable and their
ordinary lifecycle updates continue through the existing paths.

The validation point is the final relevant database check, not client receipt or
an arbitrarily delayed COMMIT. In an explicit transaction, callers can wait after
successful validation; this candidate does not claim commit-time enforcement.

## Locking and closure

The deployed closure recorder locks the application row first, re-reads eligibility,
then writes closure/request/event state. Closure response locks application before
closure-request row; assignment/request cancellations also lock application first.
The deployed duplicate/request-insert guards use that same application lock.

The candidate explicitly locks application before the existing joined
application/job lock in both request writers. Legacy creation locks application
before its original non-locking joined job read, without adding a job-row lock.
Request creation
then locks the creation request; the duplicate guard reuses the already-held
application lock, takes a claim/unique wait, then assignment INSERT takes immediate
constraints. The old legacy eligibility read now happens after serialization.
Closure winning the application lock makes subsequent new scheduling fail in the
unchanged closure guard. Creation/reservation winning makes closure observe an
unfinished shift/unresolved reservation and refuse closure. Cancelled reservations
remain terminal; completed replay does not run the new guard or create anything.

**New scheduling requires READ COMMITTED.** This is intentional fail-closed behavior:
the exported closure protocol only locks the application, without updating its row
version. A REPEATABLE READ transaction with an old snapshot might miss a separately
inserted closure even after obtaining that lock. Rather than modifying KZ/closure
functions or claiming the lock refreshes such a snapshot, the new helper rejects
new reservations, assignments and effective schedule changes at other isolation
levels. Replay, lookup and lifecycle-only operations do not call it. Integration
owners must approve this restriction and verify actual PostgREST/session settings.

Separate baseline authorization finding: the exported
`respond_job_engagement_closure_request(uuid,text,text)` checks authentication but
its `decline` branch has no explicit current-company-management check; only its
`close` branch delegates to the authorized private closure recorder. The closure
request table has no exported noninternal guard compensating for that omission.
This is a source-level concern, not an executed exploit test. It is not changed
by this scheduling candidate. The closure owner must review/fix it separately;
pinning an existing body is not a claim that all baseline authorization is sound.

Existing reschedule UPDATEs can lock the assignment row before entering the
application-locking BEFORE guard, while cancellation locks application first.
That pre-existing inversion is not removed by this scheduling patch. Any trusted
alternate writer must prelock affected application IDs (UUID order) before touching
assignment rows. Multi-session tests must check supported RPCs and approved service
writers; no claim of universal deadlock freedom is made. Cross-application,
multi-row transactions and unrelated job/membership writers also need coordination.

## Other writers, RLS and privilege preservation

Exported assignment/request/claim tables have RLS enabled, not forced, with no
policies. anon/authenticated have no effective direct assignment writes. postgres
and service_role have direct INSERT/UPDATE privileges. Consequently RPC-only
validation would leave trusted alternate writes uncovered; the new AFTER guard
and patched existing BEFORE guard cover normal table INSERT/reschedule statements
without changing any existing table ACL/RLS policy.

The discovered assignment INSERT is legacy creation. Discovered assignment UPDATE
writers are check-in, check-out, evidence submission/request-more, verification and
audited cancellation; none reschedules in its exported body. No reschedule RPC is
invented. Source discovery and pg_depend cannot prove absence of dynamic/external
writers. The guards cover their ordinary writes when triggers are enabled; owners,
superusers, replication modes, disabled triggers and schema changes are outside
this guarantee. Neither the candidate nor the rollback changes replication mode.

Baseline pre/post assertions pin relevant function source/security/ACLs, table
owners/ACLs/RLS, deployed lifecycle triggers, owned constraints and indexes,
including immediate worker overlap and request uniqueness. Checks fail on drift;
they never restore grants. New helper/trigger body/config checks also protect the
rollback. This is not a substitute for a fresh catalog export or review of new
writers/triggers before deployment.

## Lost reservation response: authorized recovery policy

If reservation commits but its response/request ID is lost, the Flutter in-memory
ledger cannot perform request-ID lookup. No automatic retry, tuple mutation,
row deletion, timestamp change or blind refresh/restart is authorized as recovery.
An empty lookup/list is not proof of rollback.

Use an authorized, audited support process to identify the existing reservation
by original actor/application/company/start/end and verify immutable location.
Protect that metadata from unauthorized users. With the original request ID, the
original actor may use existing authorized lookup; if it links an assignment,
return that existing outcome, never create another. Current authorized company
management may use the existing cancellation RPC if abandoning an unfulfilled
reservation: it locks application then request, rejects an already-created result,
records cancellation and prevents subsequent creation from that tuple. Never
reactivate/delete cancelled requests; a different legitimate future schedule is
a new assignment with a separate explicit employer decision.

There is no new support RPC or client auto-unlock in this candidate. A production
support runbook and client handling of confirmed terminal cancellation remain
necessary before claiming self-service recovery. No arbitrary claimant may read
another actor's lookup result; current lookup actor/company checks stay intact.

## Rollback, integration and readiness

Rollback requires candidate function/helper fingerprints and unchanged exported
security/lifecycle metadata, then drops only the two new triggers, restores the
four exact exported bodies, and drops only the two new helpers (without CASCADE).
No data is deleted or repaired. It intentionally restores the old permissive
scheduling behavior; freeze scheduling and obtain separate approval before use.
It aborts on later function/helper/trigger/security drift. Outstanding reservations
and completed links remain valid identities. Do not replay rollback after unrelated
schema changes; prepare a fresh reviewed recovery patch instead.

`can_manage_company_jobs`, membership, acceptance, KZ UI/company selection and
closure/cancellation functions are untouched. KZ C3 lifecycle changes alter the
authorization helper baseline; fingerprint failure requires joint review/rebase,
not overwriting the newer helper or weakening checks. Ordinary worker membership
must never grant scheduling management authority.

No SQL syntax compilation, runtime, permission or multi-session test has run.
The catalog is a dated snapshot, not a fresh live check. Do not execute either
candidate or run a migration push as part of this review. The 31-scenario document
remains a regression catalogue; this focused review does not require running all
31 or setting up Docker/WSL/a new database. The specific evidence gates below
remain unmet regardless of whether the full catalogue is run.

## Focused pre-deployment review: verdict BLOCKED

### Corrections made to executable candidates

- **BLOCKER, corrected statically:** the table assertion block declared a composite
  PL/pgSQL variable `t` and also used SQL alias `t` for `pg_trigger`; references
  such as `t.tgrelid` could resolve to either. Renamed the variable `v_trigger`
  in forward/rollback generation. No global variable-conflict setting is changed.
- **IMPORTANT, corrected:** removed the newly added legacy job-row lock. Legacy
  creation still serializes on application before eligibility/closure checking;
  its job read retains baseline behavior. Request RPCs retain their existing
  joined job locks, preceded by explicit application locking. This avoids adding
  an unnecessary lock edge to direct legacy creation.
- **IMPORTANT, corrected:** new/restored body hashes normalize line endings, while
  raw exported pre-apply hashes remain strict. Added argument names/defaults,
  return type, set-returning flag and routine kind to pre/post/rollback assertions;
  matching a body alone must not accept a changed calling contract.

The builder, both SQL candidates and baseline manifest have been regenerated.
Static regeneration/hash checks are not PostgreSQL compilation or execution.

### Every created/replaced function and trigger

| Object | Static result / remaining runtime condition |
| --- | --- |
| `validate_work_shift_schedule` | Explicit finite/order/MYT/future checks, volatile clock, no auth bypass or writes. READ COMMITTED gate fails closed; actual API compatibility remains unverified. |
| `enforce_work_shift_schedule_after_write` | INSERT branch avoids reading OLD; effective UPDATE compares application/start/end; trusted DEFINER can call private owner-only validator. AFTER failure rolls back statement. |
| Reservation RPC | Existing matching request returns before new validation. Existing authentication/Hired/company/payload checks remain; new INSERT is checked before and after waits. |
| Request creation RPC | Current authorization/ownership/payload checks precede completed replay; replay returns before new checks even for past/overnight schedules. Final check follows link UPDATE. |
| Legacy creation RPC | Holds application lock before original eligibility read; existing trusted identity derivation/auth/location checks retained. New validation before/after INSERT. No new job lock. |
| Duplicate guard | All exported closure/cancellation/exact-shift/claim branches retained. Checks occur after its blocking application/claim work; effective reschedule UPDATE retains existing row/app inversion risk. |
| Assignment AFTER trigger | INSERT and listed schedule/application UPDATE events are valid trigger forms; immediate constraints/normal FK AFTER processing can wait before final validation. Existing FK triggers precede the new trigger by name in the exported baseline. Status-only UPDATE does not fire it. |
| Reservation AFTER trigger | INSERT only; existing BEFORE guard holds application lock. Replay and cancellation UPDATEs do not fire it. |

Ordinary direct INSERT and schedule UPDATE use these enabled triggers; no table
privileges or RLS policies are loosened. Historical lookup is unchanged. Existing
Hired/current-company checks can still deny historical replay where they did
before; replay preservation does not mean unconditional access. A historical
no-op UPDATE still encounters the original BEFORE guard if its columns are named.

### Unresolved findings

**BLOCKER — actual RPC isolation/configuration and runtime evidence.** Flutter uses
Supabase `.rpc()` for reserve/create and the exported RPCs are VOLATILE with only
empty search_path settings. PostgREST documents POST/VOLATILE as READ WRITE and
READ COMMITTED by default, but allows per-role/function isolation overrides:
https://docs.postgrest.org/en/stable/references/transactions.html.
The completed isolation inspection is user-reported to show READ COMMITTED for
SQL Editor/current default, no catalog role/database isolation overrides and no
scheduling-function isolation overrides. No isolation-results CSV was supplied
for independent parsing in this task. This removes the reported catalog-override
concern; authenticator runtime configuration, pre-request behavior and actual
API transaction isolation are still not directly verified. SQL Editor defaults
do not prove the authenticated API path. The
restriction is reasonable for the documented default, **not verified acceptable
for this project yet**. Do not remove it or force a weaker isolation level inside
an already-started transaction to bypass a failure. Compilation and the actual
RPC/trigger behavior cannot be marked passed without database execution.

**BLOCKER — closure decline authorization.** An authenticated user who knows a
pending request ID can reach the exported decline UPDATE/event INSERT without a
company-management check. The postgres DEFINER/owner bypasses non-forced RLS;
withholding direct table privileges does not protect this RPC. It does not close
an engagement or bypass the new scheduling guard, but can alter another party's
closure workflow. It predates the scheduling patch, which does not fix it. A
separate one-function security candidate is now prepared (details below), but has
not been deployed or runtime-verified. For a shared Module 4 release, require the closure owner/KZ to approve a fix
or explicit effective containment before deployment review. UUID secrecy or hiding
the button is not containment. A fix should authorize BOTH decisions using the
current company helper under the existing lock protocol, not edit membership
logic. A separate fix changes the pinned fingerprint: obtain its authoritative
definition and rebase, rather than disabling the migration's drift assertion.

**IMPORTANT — lock-order limits.** Supported one-request creation/closure paths
serialize on application. Direct reschedule UPDATE locks the assignment tuple
before the BEFORE guard seeks application, while cancellation seeks application
then assignment: that is a real possible cycle. Multi-row/cross-application service
transactions can introduce further cycles. Require service writers to prelock
application IDs in UUID order before UPDATE, or pause those writers. Migration
table locks also require a maintenance window with in-flight work drained; the
5-second lock timeout aborts rather than making deployment wait indefinitely.
The patch does not claim deadlock freedom without a two-session check.

**IMPORTANT — recovery is not verified.** Rollback drops the new triggers before
their function dependencies, restores original bodies, then drops helpers using
RESTRICT. Body/config/ACL drift stops rollback. Dynamic PL/pgSQL callers may not
be recorded dependencies, so review any writers added after installation. Rollback
does not reverse real assignments, reservations, cancellations, immutable closures,
claims, notifications, external actions or elapsed time; it restores weaker
scheduling validation. Already-issued IDs must remain valid. Do not delete rows
or reopen terminal requests to imitate a rewind. A schema-only rollback file is
not a verified backup/data recovery method. Rehearsal or another independently
verified recovery method and an authorized support operator remain required.

**LOW — baseline/export scope.** The 3,392-row export and 63 raw source hashes match;
27 relevant routines are pinned, including unmodified authorization/lookup/
closure functions. Raw ACLs are preserved; REVOKEs target only the two new private
helpers. Catalog/text discovery cannot prove absence of external/dynamic writers
or trigger-disabled administration. Refresh evidence if deployments changed since
capture. Do not restore old grants to make a fingerprint check pass.

### Short controlled deployment checklist (future manual approval only)

1. KZ and Module 4/closure owners approve exact forward/rollback hashes, unchanged
   membership authorization, READ COMMITTED compatibility and closure-decline
   remediation/containment. Rebase any changed exported baseline first.
2. Verify the real authenticated RPC execution settings, including role/database
   defaults and hooks, and obtain PostgreSQL execution evidence for the critical
   paths. No SQL Editor-only assumption or static syntax claim substitutes for it.
3. Confirm a verified recovery method, named operator and paused scheduling/
   rescheduling/closure window. Drain in-flight work. Review rollback dependencies
   and preserve all existing IDs/audit records. Do not bypass failed baseline checks.
4. After separately authorized application, keep general scheduling paused while
   running these six small smoke groups using designated synthetic fixtures:
   (a) future daily creation plus repeat reservation/completed replay;
   (b) past/equal/reversed/MYT-midnight rejection with no residual shift/link;
   (c) past historical lookup and a legitimate lifecycle-only update;
   (d) anonymous/foreign-company denial and private-helper inaccessibility;
   (e) normal trusted direct insert/reschedule coverage, plus delayed application
   lock and closure-vs-create in two sessions; (f) cancelled request and lost-response
   support recovery without automatic retry. Check preserved owners/ACLs/triggers.
   Synthetic changes need the usual explicit testing authorization; none ran here.
5. Stop on 22023 isolation failures, deadlocks, unexpected permission behavior,
   duplicate IDs or drift. Preserve evidence; the authorized operator chooses
   guarded rollback/forward repair. Resume writes only after owner sign-off.

**Final focused verdict: BLOCKED.** A smaller test set is acceptable; zero execution
evidence, unverified actual API isolation, an unexecuted closure authorization fix
and an unverified recovery method cannot be replaced by this static review.

## Separate closure-decline authorization security candidate

Files (NOT DEPLOYED; no SQL executed):

- `supabase/diagnostics/closure_decline_authorization_patch_candidate.sql`
- `supabase/diagnostics/closure_decline_authorization_rollback_candidate.sql`

The patch replaces ONLY `public.respond_job_engagement_closure_request(uuid,text,text)`
from the November 10 export, raw definition MD5
`f02b6fef2e4ae491a9ce7e6e046eea6a`. After the existing application lock, request lock
and pending-state check, a single added `IF NOT EXISTS` query derives company from
the stored application/job and requires `can_manage_company_jobs(company_id) IS TRUE`.
Otherwise it raises 42501 before either close/decline branch can write. No
client-supplied company or remembered UI permission is accepted.

All original statements remain in the same order. Valid `close` still calls the
unchanged private recorder with its existing closure eligibility checks and audit
events. Valid `decline` still records declined/processed_by/processed_at/reason and
one declined event in the same transaction. Invalid decision/reason, missing or
non-pending request, return values and application-before-request lock order are
unchanged. No membership/user/company row locks or eligibility rules are invented.

The exported postgres owner, DEFINER mode, empty search_path, VOLATILE/UNSAFE flags,
signature/defaults/result and ACL `{postgres=X/postgres,authenticated=X/postgres}`
are preserved and asserted before/after replacement. The unchanged helper and
private recorder are pinned too. No GRANT/REVOKE, table/RLS/trigger change or helper
replacement occurs. The patched response body MD5 after LF normalization is
`8558e154e5eae1e8ea7b09c3fed41103`.

Static authorization cases (NOT runtime test results):

| Caller/current state at authorization query | Result implied by the exported helper |
| --- | --- |
| No authenticated actor | Existing 28000 check, before request processing. |
| Manager of B, request belongs to A | 42501; authority over B is not authority over stored A. |
| Worker who submitted the request, ordinary member or wrong account role | 42501; helper requires active Employer plus owner/employer membership. |
| Former A manager whose membership was removed, moved to B or demoted before the fresh check | 42501; no cached membership decision. |
| Inactive Employer or unverified Company | 42501 according to current helper predicates. |
| Current authorized A representative, pending request and valid reason | Existing decline behavior; close retains recorder checks. |

Under READ COMMITTED the new authorization statement gets a fresh snapshot after
application/request lock waits, so membership changes committed before this check
are observed. This does NOT serialize arbitrary concurrent membership revocation
with the final write/commit; changes after the check or stale higher-isolation
snapshots are not claimed protected. Stronger revocation serialization requires
KZ's agreed lock/lifecycle protocol, not ad hoc extra row locks here. The exported
helper does not inspect future C3 inactive/revoked membership columns; future
lifecycle semantics must come from KZ's approved helper, never a guessed predicate.

Rollback restores the exact exported vulnerable definition, so it is deliberately
disabled by a local false acknowledgement variable. Restoring it would reopen the
known authorization flaw; prefer forward repair. Any intentional baseline restore
requires separately approved effective endpoint containment, drained in-flight
calls and an explicit reviewed acknowledgement edit. It preserves all audit/data
rows and cannot undo past unauthorized declines. It first verifies the patched
body/security contracts and does not overwrite drift or restore historical grants.

Closure owner/KZ approval is now user-confirmed, explicitly including the
concurrent membership-revocation limitation described above. The approved patch
was left byte-for-byte unchanged (SHA-256
`1B4A49728412F09EA96649D42EFDCFBA12BB21C03867593E495D887355518A6F`).
Remaining deployment dependencies: actual authenticated API denial
for foreign/former members and valid close/decline/audit evidence, confirmation of
the READ COMMITTED execution path, and approved recovery/containment. Replacing
the function does not stop old invocations already executing its body: drain them.
The scheduling candidate, rollback and builder are now rebased to EXPECT the
approved security response body (LF MD5 `8558e154e5eae1e8ea7b09c3fed41103`).
They do not replace that function; scheduling rollback also preserves the fix.
The manifest keeps the original export and labels the expected approved-artifact
dependency separately. This is not a new live capture: verify the actual deployed
match before proceeding. Other source/security metadata must still match the
November 10 export. Do not waive drift checks.

Exact pre/post catalog checks and the short human SQL Editor order are now in
`supabase/diagnostics/work_shift_release_catalog_checks.sql` and
`docs/module4_release_execution.md`. The query evaluates before-security,
after-security and after-scheduling expected states without invoking RPCs. Neither
successful catalog checks nor owner approval prove runtime tests or recovery.
Local PostgreSQL/psql 18.6 binaries were found, but postgres.bki is missing and no
service/test database was found; only version commands ran. No isolated setup or
SQL execution occurred. Backup/restore availability and actual PostgREST isolation
remain unverified. Security, scheduling and operations deployment verdicts remain
NO-GO until those gates and the focused execution evidence are satisfied.

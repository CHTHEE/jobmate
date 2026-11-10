# Isolated tests, release sequence and recovery

**DRAFT / NOT APPROVED FOR DEPLOYMENT. Specifications, not executed DB tests.**

Current actual attempt: see ISOLATED_TEST_RESULTS.md. Side-effect table evidence
is integrated; local PostgreSQL 18.6 lacks share/postgres.bki, so no server/test SQL
ran. Prepared cases in local_tests/ remain UNRUN. Review-file guards remain intact.

Use a disposable isolated database with the reviewed actual baseline and synthetic
Auth identities. Do not point fixtures, test environment variables or client
configuration at the shared project. Never copy production application data.
Test JWT role/auth.uid behavior, direct API access and SQL constraints separately;
SQL Editor administrator success cannot prove client authorization.

## Required fixtures

Two verified companies A/B, one unverified company, Owner OA of A, Owner OB of B,
ordinary worker W, ordinary member M, legacy Employer manager E, revoked/inactive
members, suspended accounts and unpermitted/permitted platform Admins. Model OA's
ordinary affiliation with B while preserving Employer account role. Offers and
assignments must satisfy original role/eligibility rules; do not modify roles to
make Owner acceptance work if the deployed RPC forbids it.

## Security/behavior matrix

| ID | Exercise | Required assertion |
| --- | --- | --- |
| S01 | W accepts one Offered application in A, one in B | Two active member pairs; account role unchanged; no management grants |
| S02 | W/member calls posting/applicant/scheduling/GPS/evidence review/evaluation APIs and direct tables | Denied, including guessed IDs and explicit foreign company contexts |
| S03 | Existing Owner or Employer pair reused | No role/status/created_at downgrade or added capability |
| S04 | OA ordinary member of B | Owner A intact; no B management; Owner A onboarding still resolves A |
| S05 | Attempt second Owner of A or second owned company for OA | Database uniqueness failure, including concurrent attempts |
| S06 | Delete/transfer/demote/deactivate Owner or change required account role | Denied; creator audit unchanged |
| S07 | Inactive/revoked pair accepts new offer | Transaction fails; still Offered; no new history/notification/provenance/reactivation |
| S08 | Inject membership/provenance/history/notification failure | Full rollback, no partial hire/member event |
| S09 | Repeat completed acceptance after lost response or later revocation | No duplicate writes; revoked status remains revoked |
| S10 | Decline/withdraw, foreign actor, suspended actor, stale offer | Original behavior/guards; no membership side effects |
| S11 | Direct member self-enrollment/elevation/status edits | Denied by effective ACL/RLS and protected RPCs |
| S12 | Legacy Hired without new provenance | Explicit reconciliation path; no silent activation or new notification |
| S13 | Logos/verification documents/private requests | Ordinary and revoked members cannot upload/review/read private metadata outside approved projection; unrelated buckets unchanged |
| S14 | Admin directories/details/conflicts | One account with multiple memberships; permissions/privacy preserved; creator/historical conflicts tested |
| S15 | Dispute parties vs company members | Historical party access preserved; ordinary membership grants no case access |
| S16 | Notification audiences | Exactly original authorized recipients; no ordinary worker included as manager; direct participant messages retained |
| S17 | Module 2/4 regression | Posting drafts/publish/close, offer lifecycle, shift overlaps/replay, attendance, private evidence/reserved requests and uncertain locks preserved |
| S18 | Evaluation/payment regression | Directions/self-rating/uniqueness and current payment amounts/eligibility/history unchanged |
| S19 | Historical reconciliation twice | Second pass inert; inactive/revoked/ambiguous cases reported, no fabricated timestamps or duplicate hiring events |

## Concurrency schedules (two real independent sessions)

Use barriers after lock acquisition and a bounded lock_timeout in the isolated
harness. Record outcomes, final identities and deadlock/serialization behavior.

1. Same application: session A accepts and pauses before commit; B accepts.
   Commit A; B reconciles with one enrollment, Hired history event and each
   original notification recipient/event, no second insert.
2. Same worker/company, different Offered applications: both attempt pair creation.
   One pair, two distinct authorized application enrollments, no lost provenance.
3. Same worker, different companies: both commit without user-only uniqueness;
   unrelated company data never leaks through reads or notification recipients.
4. Lifecycle revocation versus acceptance: force each lock ordering. Revocation
   first blocks activation; acceptance first may commit, then revocation removes
   operational authority without rewriting application/work history.
5. Concurrent Owner creation across companies for same user and within one
   company for two users: exactly one succeeds for each protected invariant.
6. Acceptance versus employer status update, company/account restriction and
   scheduling: compare to original contract; no transition bypass, stale authority
   write or new deadlock cycle. Retry whole transaction only on reviewed errors.
7. Lost COMMIT response: reread/replay same application; prove no second event.
   A socket error is not evidence of rollback. Check external emitters separately.

## Local validation versus DB proof

Local Flutter mock tests may establish company-context isolation and unchanged
client contracts, never SQL constraints, ACLs, RLS or atomicity. C3 SQL drafts now
contain executable-format review changes with deliberate execution-stop guards;
they have not been syntax/runtime tested against PostgreSQL.
Do not describe static checks as isolated database testing.

## Proposed release order

1. Attach actual C2 exports and resolve every source/body/ACL gap. Fingerprint
   exact originals and candidate artifacts; source-trace nested/dynamic helpers.
2. Approve lifecycle initialization, ordinary data visibility, notification and
   historical dispute/conflict/backfill rules; no implicit reactivation.
3. Build isolated executable patches from originals; preserve identities/settings/
   ACLs. Install compatibility reads and KZ client changes before multiple rows.
4. Add lifecycle/history structures with approved original-state mapping; protect
   new fields from existing table/column grants before clients can write them.
5. Coordinate authorization/policies, both Owner indexes, key/role changes and
   atomic hiring into one reviewed cutover with no unsafe intermediate window.
   Prevent new hires through old code during cutover using an approved release
   procedure; no unreviewed live pause/trigger is supplied here.
6. Run security/concurrency matrix and client regressions in isolation. Rehearse
   recovery and old-client behavior. No production test permission is implied.
7. Obtain explicit CH/KZ approval for exact artifacts, operator, window and
   recovery plan. Backend owner deploys only after separate approval.
8. Approved post-deploy catalog checks first; synthetic JWT/write QA only with
   separate scope approval. Backfill is a separate reviewed dry-run/release.

## Non-destructive recovery

Before multi-company writes, restore only reviewed original definitions/ACLs if
data and dependencies still satisfy them. Once multiple memberships exist, do
not restore user-only PK by deleting rows or transferring ownership. Retain the
expanded schema and history; prefer approved roll-forward correction. Never
restore hiring without enrollment while allowing new acceptance. Operational
pause, backup/PITR and recovery require an approved incident plan; PITR has
project-wide effects and is not a routine membership rollback. Preserve private
Storage objects, audits, assignments and financial history. No down migration is
included because lossless reversal is not generally available.

## Deployment approval checklist

- [ ] Full reviewed C2 definitions/ACLs are attached and matched to live baseline.
- [ ] CH and KZ approve exact SQL artifact hashes and every resulting privilege.
- [ ] Both approve lifecycle mapping, inactive/revoked conflicts, backfill scope,
  reactivation authority, historical disputes/conflicts and notification audiences.
- [ ] KZ approves onboarding/Home/Admin/company/dispute compatibility changes.
- [ ] Module owners approve Module 2/4, evaluation, Storage and payment regressions.
- [ ] Isolated real-JWT security and multi-session concurrency results attached.
- [ ] No broadened EXECUTE, no restored legacy bypass, no ordinary privilege grant.
- [ ] Backup/recovery rehearsal, old-client cutoff and non-destructive incident
  plan approved; operator/window and post-deploy verification explicitly named.
- [ ] Explicit CH AND KZ production approval recorded for these exact artifacts.
- [ ] Backfill and production synthetic-write QA separately approved if requested.

Unresolved source gaps mean these boxes cannot currently be signed off.
Current evidence/validation status: see EVIDENCE_INTEGRATION.md. SQL drafts are now
executable-format but have intentional execution-stop guards and remain unexecuted.
# Exact coordinated candidate release blockers

**DRAFT / NOT APPROVED FOR DEPLOYMENT. No SQL executed.**

## Latest implementation (supersedes missing-source/client statements below)

Recovered 22 complete definitions from the local
jobmate-before-module4-20261106.dump using schema-only pg_restore, without a
database connection or application-row export. historical_function_evidence.json
keeps the exact bodies, historical owner/signatures and ACL statements; the
original 110-object evidence is unchanged. These are historical, NOT proof of
current deployment. 002 now requires exact body/owner/SECURITY DEFINER/search_path
matches, preserving actual server ACLs, and aborts on drift.

- submit_company_for_review now resolves owned membership only. v2 delegates to
  it; its exact original body is asserted unchanged, including retry behavior.
- get_user_account_details, update_job_application_status, get_managed_company
  and list_managed_companies are asserted unchanged against recovered bodies.
  The historical employer status writer explicitly excludes hired, so needs no
  enrollment patch if that exact version is deployed. The Admin RPC keeps its
  authorized repeated-row contract; no breaking SQL return-type change is needed.
- Dispute read/create and dispute/moderation/restriction notification membership
  audiences have active Owner/Employer predicates. Historical Admin conflict
  exclusions are unchanged; original direct recipients are preserved. Approve
  revoked-company-party access semantics before execution.
- Dispute eligible-record listing and moderation visibility now filter active
  management memberships; company-logo submission retains active Owner-only
  mutation. Review-conflict functions/queues remain historical and are exact-body
  assertions, not active-only rewrites. These checks cover every membership-reading
  function found in this historical schema except source already covered by 001.
- KZ-owned create_company_page.dart/home_page.dart now select an owned company
  before a unique legacy Employer affiliation, ignoring ordinary affiliations.
  Home posting counts use that explicit context and existing authorization.
  Admin gateway validates account consistency/scope and groups all returned
  memberships; details dialog displays them. Changes are isolated in these files
  plus pure helpers/tests for KZ review; shared navigation is unchanged.

Remaining: evaluation functions are absent from recovered backup; full deployed
Module 4 body matches and remaining inline dispute helpers still need coverage;
real database tests and lifecycle/retention approvals remain open. Do not present
002 as final or executable for production. Existing release stops are intact.

Manual execution order once ALL gates are resolved: isolated baseline first,
exact completed 002 in one transaction second, release_acceptance_tests.sql and
multi-session/real-JWT tests third; obtain CH/KZ approval of that artifact hash
and results. For production, compare approved metadata before execution, deploy
only the completed coordinated artifact (never run 001 and 002 sequentially),
then verify_release_metadata.sql and approved synthetic smoke checks. Keep the
Flutter flag off until separate activation approval. Present 002 MUST NOT run.

Latest local validation: 58 focused Flutter tests passed (including nine new
compatibility tests); full suite 1,342 passed and five Admin/company-review tests
failed. Flutter analysis has only the four existing infos in untouched files.
Dart formatting, original evidence/draft assertions, coordinated deterministic
assembly/security assertions and git diff --check passed. No PostgreSQL SQL
parsing/runtime/concurrency/JWT/Storage test ran: postgres.bki is still missing.

Explicit managed-company selection remains necessary for unscoped management
callers with multiple management affiliations. JobPostingsRepository.loadAccess
continues to fail closed on ambiguous memberships; only Home's counts now receive
the selected explicit context. Do not claim general management company switching
or delegated capability support is implemented by these profile changes.

002 is a separate, deliberately blocked coordinated candidate, not a final release.
It includes 001 unchanged plus two lifecycle patches conditional on exact local
Module 4 function-body/security matches. Original 001 and three review guards are
untouched. The extra unconditional stop must remain until the omissions below
are resolved through reviewed code; setting 001's acknowledgement is insufficient.

## Source audit and concrete omissions

The 110-object snapshot contains 14 complete functions, including acceptance and
can_manage_company_jobs; it does NOT contain the functions listed below. Catalog
discovery is not proof of absence of dynamic SQL or PL/pgSQL dependencies.

| Path | Exact local source / evidence | Release requirement |
| --- | --- | --- |
| Evidence/GPS | 20261106000300_work_evidence_workflow.sql: can_review_work_evidence_company; 20261106000200_employer_attendance_gps.sql: read_employer_work_attendance_gps | 002 adds active lifecycle to existing inline predicates only on exact body/security match; original OID/ACL/owner/settings checked unchanged. Missing deployed bodies/ACLs prevent certifying baseline equivalence. |
| Assignment creation/verification | 20261105000100_work_attendance_verification.sql: create_work_assignment, verify_work_assignment; 20261106000100_work_assignment_creation_idempotency.sql: reserve/create/lookup_work_assignment_request | Local definitions already call can_manage_company_jobs, so patched helper propagates lifecycle denial. Confirm deployed bodies and helper calls, preserve revoked legacy EXECUTE and durable request recovery. Do not redeploy old migration grants. |
| Evaluations | lib/features/evaluations/soft_skill_evaluation_gateway.dart: list_evaluation_candidates, list_my_soft_skill_evaluations, submit_soft_skill_evaluation | No full SQL in snapshot/migrations; reuse existing C2 exports including identities, owners/settings/ACLs before edits. Ordinary affiliation must not grant evaluator authority; participant history and management require separate rules. |
| Alternate hiring | lib/features/applications/employer_applicants_repository.dart: update_job_application_status | Deployed body absent; determine whether it can write hired, prevent bypass or route through approved enrollment semantics without granting applicant impersonation. Other writers cannot be ruled out from catalog alone. |
| Onboarding/managed selection | submit_company_for_review, submit_company_for_review_v2, get_managed_company, list_managed_companies | Missing deployed bodies/ACLs. Known any-membership onboarding rejection must become owned-company check. KZ create_company_page.dart and home_page.dart user-only lookups must be fixed separately before release. |
| Admin | get_user_account_details; checked-in 20261105000300_admin_user_management.sql joins memberships at user level; 20261106000500_admin_read_only_directory_details.sql projects affiliation/counts | Checked-in source is not deployed provenance. KZ must approve versioned one-account/memberships response and update user_management_gateway/dialog together. Do not arbitrarily choose one row. |
| Dispute/conflict/recipients | No full deployed dispute/evaluation or recipient helper definitions supplied | Exact identities must come from existing C2 exports/source calls. Keep historical affiliation conflict exclusions; operational recipient/manager authority active-only. Original acceptance recipient remains job.created_by. No invented blanket lifecycle rewrite. |

Paths in the table are under supabase/migrations unless specified. No KZ files
were changed. Existing logo/document policy fixes in 001 remain source-derived.

## Decisions that require CH/KZ, not inference

- Existing acceptance requires active Job Seeker. An Employer/company owner
  cannot accept through it. Preserving that authorization conflicts with a test
  expecting an owner to accept another company's offer: approve a separate
  eligibility change or keep that case denied. 002 does not weaken authorization.
- Approve mapping existing memberships to active, historical Hired backfill
  without receipts, conflict handling and audited lifecycle/re-enrollment process.
- Inactive/revoked pair blocks a fresh acceptance; receipt-backed replay returns
  hired without reactivation. Approve user-facing resolution and retained work,
  evidence, payment and dispute access after revocation.
- Owner immutability plus cascade user/company deletion and receipt NO ACTION
  dependencies can block deletion. Approve retention/anonymization compatibility.
- Delegated capabilities are not implemented by legacy employer role or ordinary
  member. Approve the future explicit capability contract independently.

## Exact candidate test/deployment gate

1. Supply the existing exact exports above; integrate compatible replacements,
   captured ACL/security assertions and fingerprint drift checks. No broad query
   round is needed. Resolve KZ client compatibility before creating member rows.
2. Fix disposable harness startup cleanup/bounded waits. Its existing baseline is
   synthetic Auth/types, omits full Storage and does not apply all 002 policies.
   It is insufficient certification of the full release.
3. Approve a complete isolated baseline. Run the exact completed artifact in a
   disposable local Supabase/PostgreSQL environment, retaining original guards.
   Run release_acceptance_tests.sql via psql -X with ON_ERROR_STOP, only loopback
   and database prefix jobmate_c3_disposable. It never applies migrations itself.
   Tests are executable but UNRUN, not a real-JWT/Storage test suite.
4. Run independent-session acceptance vs acceptance, same worker/different offers,
   enrollment vs revocation, Owner creation vs account-role change, and opposing
   account/membership locks. Record timeouts/deadlocks/serialization failures;
   RPC exceptions require authoritative refresh, never blind retries. Existing
   same-offer concurrency harness alone does not cover these races.
5. Verify original function OIDs/owners/proacl/proconfig and all companion policy
   composition, real JWT cross-company ordinary-member denial, historical access,
   onboarding/Admin and current Module 2/4/payment flows on the isolated baseline.
6. CH AND KZ approve exact completed artifact SHA256, lifecycle/backfill rules,
   test results, operator/window, backup and forward-recovery procedure. Set lock
   and statement timeouts for deployment; drain hiring/onboarding/lifecycle writes
   to avoid application→job→membership vs other-writer lock-order deadlocks.
7. Authorized operator alone deploys one coordinated transaction after fresh
   metadata comparison. No execution is authorized by this document. Old clients
   immediately use replaced acceptance even with Flutter flag false.
8. On failure before commit, transaction rollback preserves baseline. After
   commit/new rows, do not restore user-only PK, delete affiliations/receipts or
   roll back only acceptance. Pause affected writes and use reviewed forward repair;
   restore only through separately approved full recovery retaining history.
9. Keep Flutter flag OFF until deployed catalog and synthetic smoke tests pass,
   then obtain separate activation approval.

Execution is currently prevented by the unconditional stop, incomplete compatible
definitions/KZ client work, undecided policies and absent real database test proof.
Agreement in principle does not clear those gates.

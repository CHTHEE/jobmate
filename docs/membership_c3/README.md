# Phase C3 implementation review package

**DRAFT / NOT APPROVED FOR DEPLOYMENT. Partial actual-evidence integration.**

Latest: combined_evidence_snapshot.json preserves all 110 objects (original 91
unchanged plus 19 final history/notification objects). ISOLATED_TEST_RESULTS.md
records successful metadata validation and the actual local PostgreSQL bootstrap
failure. No database acceptance tests have run; do not infer a pass from the
presence of the disposable test harness.

This package does not authorize SQL execution, backfill, deployment or production
testing. SQL files now contain executable-format unexecuted drafts outside
migrations, with an unconditional draft exception before modifications. 03 remains
partial. See EVIDENCE_INTEGRATION.md for current coverage and release blockers.

## Reconciliation and evidence gap

**Current update:** evidence_snapshot.json preserves the actual 91-object bundle
and original-file hash from jobmate_c2_evidence.txt.txt. EVIDENCE_INVENTORY.md lists
every object. EVIDENCE_INTEGRATION.md supersedes the older absence statements below.

CH reports all C2 inspections and follow-ups are complete and reviewed. The two
referenced files in this checkout do not contain their actual results:

- `docs/multi_company_membership_c2_proposal.md` contains owner-reported summaries
  and still says ACL/helper outputs are pending.
- `docs/multi_company_membership_c2_followup_inspection.md` contains collection
  queries and explicitly says results are not embedded.

Do not interpret those older statements as contradicting CH's completed review.
The distinction is that the source results are unavailable to this package's
author. No result exports were found among docs/supabase filenames inspected.
Acceptance/management/Owner source and selected policies are now integrated from
actual evidence. Missing history/notification/helper/KZ definitions remain blocked
as itemized in EVIDENCE_INTEGRATION.md. No missing deployed body is invented.

Confirmed by prior owner report: user_id membership PK; company_id UUID;
member_role TEXT restricted to owner/employer; created_at timestamptz; one Owner
per company partial index; no inbound membership FKs found; Owner immutability
and Employer account safeguard; acceptance writes Hired/history/notification
atomically but no membership; verified-company Employer authorization; Admin
details produce one row per membership. Follow-up reports Storage/logo policy
dependencies, without supplying exact expression text here.

Repository comparison:

| Evidence | Current repository | C3 consequence |
| --- | --- | --- |
| Ownership | `20261030000100_restore_employer_registration.sql`: jobmate_one_owner_per_company_idx, protect_jobmate_company_owner, require_jobmate_owner_employer_role, protect_jobmate_company_creator | Preserve functions/trigger bindings; extend Owner protection to lifecycle; explicitly replace user ownership uniqueness |
| Acceptance | `applications/my_applications_repository.dart`: SupabaseMyApplicationsSource.respond expects text | Keep signature/response and existing authorizations; server-only atomic enrollment |
| Management | `jobs/job_postings_repository.dart`: immutable companyContext, Employer/role/verification checks; no lifecycle | Default multi-row lookup still fails closed; lifecycle/client selection rollout needed |
| Module 4 | `20261106000300_work_evidence_workflow.sql`: can_review_work_evidence_company requires active Employer, owner/employer and verification | Ordinary role remains denied; add lifecycle to all operational paths |
| Admin | `20261105000300_admin_user_management.sql`: get_user_account_details; `admin/user_management_gateway.dart`: details rejects multiple rows | KZ versioned account-plus-memberships contract prerequisite |
| Company read | `20261031000100_admin_dashboard_and_review.sql`: companies_select_internal uses any membership | Retained revoked rows must cease authorizing operational reads |
| Storage/logo | `20261103000100_profile_assets.sql`, `20261103000200_company_logo_approval.sql`, `20261104000100_restore_company_logo_upload_policy.sql` | Exact deployed policy set required; permissive/restrictive composition and private content need review |

Paths above under Flutter are relative to `lib/features/`; SQL paths are under
`supabase/migrations/`. Checked-in sources are partial and not proof of live ACLs.

## Artifacts

1. `01_schema.sql`: proposed schema transitions and lifecycle invariants.
2. `02_acceptance.sql`: proposed integration points and concurrency/replay rules.
3. `03_authorization.sql`: per-path authorization/RLS patch requirements.
4. `KZ_REVIEW.md`: coordination checklist; no KZ implementation.
5. `TESTS_AND_RELEASE.md`: isolated tests, deployment gates and recovery.

The existing `member_role='employer'` authority is legacy compatibility, not a
new ordinary-member capability. Independent capability grants and Job Seeker
management access are deferred; adding membership must not enable delegation.
An Owner of A can be an ordinary member of B without losing ownership of A.

## Unresolved decisions/blockers

- Attach complete inspected definitions/ACLs and stable artifact fingerprints;
  include helpers called by PL/pgSQL/dynamic SQL and view-mediated references.
- Confirm all status/role constraint names, defaults/nullability, FKs/delete
  actions, extra triggers and external consumers before key replacement.
- Approve initial lifecycle mapping for existing memberships, historical Hired
  eligibility, reactivation authority and capability revocation semantics.
- Identify actual notification emitter and recipient rule. Exactly-once means
  database event rows, not guaranteed external message delivery.
- Confirm all alternate Hired writers (RPCs, direct access, triggers/admin tools).
- Decide case-participant historical dispute access versus current management,
  and historical conflict-of-interest duration. Do not disable conflict checks.
- Deployed employment constraint reportedly excludes temporary; Flutter choices
  and payment handling include it. Separate issue, no change in this package.

No migration can be approved while these source/decision gates remain unresolved.

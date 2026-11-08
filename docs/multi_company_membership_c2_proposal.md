# Hired to multi-company membership: C2 proposal

Status: review draft, not executable migration SQL. No deployment authorization.

## Evidence boundary

The project owner supplied the following deployed findings in chat: membership
columns are user_id UUID primary key, company_id UUID, member_role TEXT,
created_at timestamptz; roles allow owner/employer; a partial unique index
enforces one owner per company; no inbound membership foreign keys were found.
The owner trigger prevents deletion/transfer and requires an Employer account.
respond_to_job_application(uuid,text) is SECURITY DEFINER, atomically records
accept_offer -> hired, history and employer notification, but no membership.
can_manage_company_jobs requires active Employer, owner/employer membership and
verified company. get_user_account_details returns one row per membership.
Companies SELECT RLS accepts any membership. These are owner-reported findings,
not a new database inspection or a verbatim schema export.

Query 4b/4c ACL/schema-role outputs and helper/dependency inspection are pending.
Exact constraint names, nullability/defaults, FK actions, complete policies,
routine bodies, overloads/settings/owners and notification dependencies must be
supplied before executable SQL can be written. Do not reconstruct an existing
SECURITY DEFINER function from a behavior summary.

## Repository comparison

- supabase/migrations/20261030000100_restore_employer_registration.sql documents
  the user_id PK and defines jobmate_one_owner_per_company_idx,
  private.protect_jobmate_company_owner, private.require_jobmate_owner_employer_role
  and private.protect_jobmate_company_creator. Reported findings agree with this
  partial baseline; the original membership DDL is absent.
- respond_to_job_application, update_job_application_status,
  can_manage_company_jobs, save_employer_job_posting and
  submit_company_for_review_v2 bodies remain absent from checked-in sources.
- 20261105000300_admin_user_management.sql: get_user_account_details joins all
  memberships. lib/features/admin/user_management_gateway.dart details rejects
  more than one row. Confirmed deployment behavior matches this incompatibility.
- 20261031000100_admin_dashboard_and_review.sql: companies_select_internal uses
  membership existence without lifecycle checks, consistent with the summary.
- lib/features/jobs/job_postings_repository.dart loadAccess supports immutable
  companyContext but still requires Employer and owner/employer. Default callers
  fail closed on multiple rows. No lifecycle filtering exists yet.

## Proposed schema contract (all new names are provisional)

Use a composite primary key (company_id,user_id). This also enforces the required
pair uniqueness without a redundant unique index. No inbound membership FKs were
reported, making this simpler than introducing an unnecessary surrogate key;
recheck full dependencies, views and external consumers before key replacement.
Both key fields must be non-null, with existing FKs/actions reviewed and retained.

Preserve the existing partial unique owner-company index. Add a separate partial
unique owner-user index on user_id for owner rows. Both apply to all owner rows,
not just active rows. Owners must remain active and cannot change identity/role,
be deleted or lose their required account role. Ordinary membership elsewhere
does not count toward ownership uniqueness. Existing owner creation remains an
onboarding-only operation; enrollment never creates ownership.

Extend roles with an ordinary `member` label. Preserve existing `owner` and
`employer` rows. Introduce a separate lifecycle with proposed states active,
inactive and revoked, plus server-written transition metadata and append-only
membership history. Do not physically delete memberships to remove access.
Preserve created_at and all existing application/work/payment history. One pair
row persists across separately approved reactivation episodes.

Existing rows need an explicit migration mapping: do not assume all historical
rows were active until owners approve baseline semantics. If existing semantics
are confirmed as active, preserve that behavior and audit the initial mapping.
Hired application is recruitment history, not proof of ongoing employment.
Job title/employment type remain separate; do not recategorize any jobs.

Keep company membership separate from capability grants. New ordinary members
receive no grants. Existing owner/employer rights must not silently disappear;
first preserve them in compatibility helpers while reviewing their exact scope.
Future capabilities for jobs, shifts, evidence and evaluations are independently
authorized per active membership. Do not grant platform Admin status or change
users.role. Job Seeker delegation is a later coordinated release, not enabled by
adding the member role. Reactivation must not restore old capabilities implicitly.

## Proposed atomic acceptance flow (pseudocode, not a replacement RPC)

1. Preserve deployed signature, text acknowledgement, security settings, actor
   checks, account-status checks and existing legal transition guards.
2. Lock/validate the application; derive applicant and company from the posting.
   Determine a consistent lock order with existing application, onboarding,
   scheduling and membership lifecycle operations from actual helper bodies.
3. For a fresh Offered acceptance, create the active ordinary pair if absent.
   Conflict handling may insert nothing, then lock/re-read the existing pair;
   it must never overwrite role, lifecycle, created_at or capabilities.
4. Reuse an active existing pair, including owner/employer, without downgrade.
   Reject inactive/revoked pairs and roll back the entire acceptance. A separate
   authorized reactivation decision is required before a new acceptance can run.
5. Record a unique application enrollment association/event. Atomically perform
   the existing Hired transition, history and employer notification exactly once.
   Do not add a second client membership write or duplicate notification emitter.
6. Preserve decline/withdraw behavior. No enrollment for other transitions.
7. Return only after all transactional writes succeed. Any enrollment error must
   leave the application Offered and preserve its previous history/notifications.

On replay, authorize the same worker and reconcile a previously committed
acceptance without new enrollment/history/notification writes. A subsequently
revoked pair stays revoked. Use the unique application enrollment association to
distinguish replay from historical Hired records; application ID alone is not
proof that new enrollment already occurred. Preserve current acknowledgement
format; changing response shape requires a versioned contract/client release.

Per-application locks serialize same-offer acceptance. Pair uniqueness serializes
different offers for one company; different companies can create different pairs.
Membership lifecycle mutations must take compatible row locks. Review actor and
company status/verification races, deadlocks and transaction failure handling in
isolation. A generic upsert that resets lifecycle is prohibited.

PostgreSQL transactional rollback covers database history/notifications only.
Verify no external emitter creates nontransactional side effects before commit.
Do not assume a durable outbox exists; inspect notification helpers first.

## Historical reconciliation

Prepare an authorized, resumable dry-run report before backfill. Derive pairs
from Hired applications, create only eligible missing ordinary pairs and unique
enrollment associations, and retain existing elevated roles. Skip/report inactive
or revoked memberships, ambiguous employment history and invalid references.
Do not change account roles, fabricate join dates, rerun hiring transitions,
resend offer notifications or change assignments/payments. Reruns must be inert.

## Affected authorization and compatibility inventory

This is the complete identified repository inventory, not a claim that pending
live helper/dependency inspection is complete.

| Area | Files/definitions requiring review | Required treatment |
| --- | --- | --- |
| Membership | Original DDL/RLS/ACLs absent | Composite key, role/lifecycle, explicit active access; no client self-enrollment/elevation |
| Owner/account | 20261030000100_restore_employer_registration.sql: protect_jobmate_company_owner, require_jobmate_owner_employer_role, protect_jobmate_company_creator | Retain invariants and prevent Owner lifecycle deactivation |
| Company reads | 20261031000100_admin_dashboard_and_review.sql: companies_select_internal | Active ordinary members may receive approved company metadata, never management rights; inactive rows must not authorize access |
| Logo/storage | 20261103000100_profile_assets.sql: company_profile_logo_insert; 20261104000100_restore_company_logo_upload_policy.sql: employer upload gate | Owner and active lifecycle checks remain; no ordinary upload rights |
| Logo review | 20261103000200_company_logo_approval.sql: company_logo_requests_read, submit_company_logo_change, list_company_logo_review_requests, review_company_logo_change | Explicit lifecycle for operational access; separately decide historical conflict-of-interest scope |
| Admin | 20261105000300_admin_user_management.sql: get_user_account_details; 20261106000500_admin_read_only_directory_details.sql: directory/count/detail RPCs | Version account details to one account plus memberships array; preserve privacy/permission checks; label historical counts appropriately |
| Onboarding | lib/features/company/create_company_page.dart _loadCompany; deployed submit_company_for_review_v2 | Select owned company, not any membership; an ordinary member may still create their one owned company |
| Home/logo | lib/features/home/home_page.dart _loadAccountRole; company_logo_editor.dart _checkOwnerAccess | Replace user-only lookup in Home; logo user+company lookup remains cardinality-safe but needs lifecycle awareness |
| Module 2 access | lib/features/jobs/job_postings_repository.dart loadAccess/list/save/close; job_form_page.dart; job_postings_page.dart; applications/employer_applicants_repository.dart | Explicit authorized company context; revalidate lifecycle; ordinary role denied |
| Hiring client | applications/my_applications_repository.dart respond; my_application_details_page.dart respond | Preserve RPC contract and authoritative refresh; explain enrollment only after guaranteed backend rollout |
| Module 2 backend | Missing respond/update/save/list/close/applicant/resume functions | Audit all Hired writers and access paths; no bypass around atomic enrollment |
| Module 4 base | 20261105000100_work_attendance_verification.sql: create_work_assignment, list_company_work_assignments, can_view_work_evidence, can_read_work_evidence_file, legacy verification functions | Active company authorization; preserve worker access, eligibility and existing revoked legacy grants |
| Module 4 requests | 20261106000100_work_assignment_creation_idempotency.sql: reserve/create/lookup_work_assignment_request | Lifecycle and authorization on new writes and reconciliation; preserve existing committed identity |
| GPS | 20261106000200_employer_attendance_gps.sql: read_employer_work_attendance_gps | Explicit active membership and existing Employer/role checks |
| Evidence | 20261106000300_work_evidence_workflow.sql: can_review_work_evidence_company, can_view_work_evidence, can_read_work_evidence_file, workflow_context, prepare/commit review; Storage read policy | No member verification rights; retain private signing, history and uncertainty protections |
| Module 4 client | work_assignment_creation_repository.dart; work_assignment_people.dart; work_verification_routes.dart; work_verification_pages.dart; work_evidence_repository.dart | Use same selected authorized company; deny mismatch/revocation, no arbitrary fallback |
| Evaluations | evaluations/soft_skill_evaluation_gateway.dart and missing candidate/history/submit RPC bodies | Membership alone never grants company evaluation rights; preserve worker direction and self-evaluation restrictions |
| Navigation | main.dart; module2_widgets.dart; shared navigation | Account-role gates block delegated Job Seekers today; no changes until separately approved |
| Payments | payments/payment_models.dart; supabase/functions/_shared/payments/domain.ts and missing assignment/store adapters | Preserve eligibility/amounts/history; review membership authorization dependencies without changing payment policy |

## Separate employment-type discrepancy

The owner reports deployed posting constraints exclude temporary. Flutter
jobs/job_form_page.dart and applications/browse_jobs_page.dart include temporary;
payment eligibility includes part_time/temporary. Record the exact deployed check
definition and agree a separate correction. Do not alter constraints, choices,
existing jobs or payment handling in this proposal.

## Validation and ownership

CH-safe work now: mock-HTTP client regression tests showing an Owner in company A
cannot use ordinary membership in B for save/close, and duplicate scoped rows
fail closed. These tests prove current client behavior only, not SQL security.
No executable migration or replacement production RPC is safe from the summary.

KZ coordination: onboarding/Home/company/profile and platform Admin projections,
owner/account protections, company review/privacy and any shared navigation.
Joint backend ownership: all schema/RLS/ACL/RPC/trigger changes and backfill.
Ownership of remaining helper/evaluation/payment code must be confirmed; a path
in this inventory is not permission to edit it.

Isolated database acceptance tests required: multi-company hires, two concurrent
accepts, same-company different applications, lost response/replay, existing
owner/member, pair insertion failure and full rollback, inactive/revoked conflict,
concurrent revocation/acceptance, historical backfill rerun, foreign actor/company,
direct-table attacks and capability self-elevation. Regression-test onboarding,
Owner uniqueness, Admin one-account projection, scheduling overlaps/replay,
evidence/Storage/GPS, evaluations and payments with real authenticated roles.

## Deployment order and rollback

1. Collect complete deployed source/ACL/dependency exports and compare offline;
   approve lifecycle initialization, historical access and capability semantics.
2. Prepare additive versioned reads/history/lifecycle in an isolated environment;
   keep existing user-only key until compatible clients/Admin/onboarding are ready.
3. Update and verify every operational authorization path for lifecycle, with
   ordinary role denied; coordinate old-client support and release gates.
4. Rehearse one coordinated key/role/owner-index/atomic-acceptance change so new
   hires cannot occur between removal of user uniqueness and enrollment security.
5. Review CH/KZ sign-off, backups, tested recovery, QA evidence and deployment
   artifact fingerprints; only then request explicit production approval.
6. Authorized backend owner deploys in an agreed window; verify catalogs first,
   then separately approved synthetic real-JWT tests. Backfill needs separate
   approval and dry-run review. Delegated capabilities remain disabled until a
   subsequent authorization release.

Rollback before new multi-company data exists may restore reviewed prior
definitions. After multiple pairs exist, restoring user_id uniqueness cannot be
lossless. Do not delete memberships/history to force rollback. Prefer retaining
the expanded schema and rolling forward with a reviewed fix; pausing new hiring
requires an approved incident plan. Never roll back only the acceptance RPC to
one that hires without enrollment. Record all definition/ACL versions and avoid
unreviewed dependency cascades or changes to previously deployed migrations.

## Exact approval gates

- CH and KZ approve full deployed definitions/ACLs and resolved dependencies.
- Both approve composite key, both Owner indexes, lifecycle initialization,
  inactive/revoked conflict semantics, and legacy Hired reconciliation policy.
- KZ approves onboarding/Home/Admin and privacy/conflict compatibility changes.
- Module owners approve every authorization change, including old-client behavior.
- Both approve isolated security/concurrency results and backup/recovery rehearsal.
- Both explicitly approve the exact production migration artifacts, deployment
  order/window/operator and post-deployment tests. Read-only inspection approval
  does not authorize deployment, backfill or synthetic production writes.

No production action is authorized by this document.

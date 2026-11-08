# C3: exact evidence required to complete the drafts

**DRAFT / NOT APPROVED FOR DEPLOYMENT. Evidence integration only.**

**Latest:** history/notification evidence is supplied and validated. No repeat
export is needed. ISOLATED_TEST_RESULTS.md records the current local PostgreSQL
bootstrap blocker and the remaining production approval gates.

**Final priority:** see `FINAL_EVIDENCE_GAPS.md`. Only the two side-effect table
definitions block faithful acceptance runtime testing on a matching isolated
baseline; known onboarding/Admin/Module 4 behavior is not being rediscovered.
Other exact-source gaps gate broader patch/release approval, not static parsing.

CH reports the live inspections are complete. This is a request for the existing
reviewed exports, not another investigation or permission to run SQL. Local C2
files contain summaries/queries, not result rows or complete deployed bodies.
**Coverage update:** evidence_snapshot.json now preserves the actual 91-object
bundle. EVIDENCE_INTEGRATION.md records exact coverage, source discrepancies and
remaining gaps. Original request tables below are historical; do not request
already-supplied objects again. SQL drafts are partially integrated but unexecuted.

## Export keys and minimum contents

- **C2 Q1/Q2a/Q2b/Q3a/Q3b**: relations/RLS flags; columns/defaults/types;
  enums/domains; named constraints/FKs; indexes/predicates/validity.
- **C2 Q4a/Q4b/Q4c**: policies; raw table/column ACLs; schema usage/role metadata.
- **C2 Q5/Q6/Q7/Q8**: trigger definitions/functions; named RPC definitions and
  security metadata; helper inventory; recorded dependencies.
- **F1**: `C2_followup_01_functions.csv`.
- **F2**: `C2_followup_02_policies.csv`.
- **F3**: `C2_followup_03_schema_access.csv`.
- **F4a/F4b**: `C2_followup_04a_execute.csv` and
  `C2_followup_04b_membership_access.csv`.
- **F5**: `C2_followup_05_membership_functions.csv`.

The C2 Q numbering refers to the original C1 inspection queries, not a new set.
F1–F5 are the five sections of the existing follow-up guide (F4 has two results).

For every function supplied, retain schema, all collected identity signatures,
argument defaults/result, complete body, owner, SECURITY DEFINER flag, settings
(especially search_path), and exact ACL/grant options. Effective EXECUTE alone
cannot reconstruct the original ACL. Use Q6/F1 for those fields where covered;
F5 supplies source/owner/settings but NOT ACLs. Supply the matching already-
collected ACL result where available, otherwise explicitly mark that gap.
Do not guess overloads or assign schema `public` to an unknown helper.

## Priority 1: unblock 01_schema.sql

| Required exact object/result | Existing query coverage | Why necessary |
| --- | --- | --- |
| `public.company_memberships`: all four existing columns, defaults/nullability, relation owner/RLS flags | Q1, Q2a | Preserve baseline; safely add lifecycle and composite key |
| Named membership PK, member_role check, outbound FKs and all unique/check constraints | Q3a; Q2b if a domain applies | Exact constraint replacement and retained FK actions; names absent from summaries |
| `jobmate_one_owner_per_company_idx` and every other membership index | Q3b | Preserve Owner-company rule; avoid conflicting or redundant key/index changes |
| Inbound membership FKs and recorded dependencies, including views/policies | Q3a, Q8 | Confirm reported absence and avoid dropping dependencies |
| `public.job_applications` primary key/status definition; referenced `public.users`/`public.companies` keys | Q2a/Q2b/Q3a | Enrollment provenance and audit FKs need real target keys/types |
| Trigger `jobmate_protect_company_owner` -> `private.protect_jobmate_company_owner()` | Q5; F5 source where returned | Extend lifecycle protection without weakening actual Owner safeguards |
| Trigger `jobmate_owner_must_remain_employer` -> `private.require_jobmate_owner_employer_role()` | Q5; F5 source where returned | Preserve account-role protection |
| `private.protect_jobmate_company_creator()` and its actual trigger binding | Q5 | Preserve company creator audit protection; binding name must come from export |
| All other triggers on membership/users/companies/applications returned by Q5 | Q5, then only referenced helper bodies | Detect interacting writers/constraints; do not invent extra trigger names |
| Membership policies and raw table/column ACLs; application write policies/ACL coverage | Q4a/Q4b, F4b | Existing grants must not permit self-enrollment or lifecycle/elevation writes; F4b does not cover application ACLs |
| Schema owner/USAGE and relevant routine execution ACLs | Q4c/Q6, F3/F4a | Preserve invocation boundaries; assess new private helper access |

**Decision gate, not missing metadata:** approve initial active-state mapping,
retained membership history, lifecycle authority and no silent reactivation.
No user rows are requested to resolve the definition gaps. Any later data-quality
preflight/backfill report requires its own approved scope.

## Priority 2: unblock 02_acceptance.sql

| Required exact object/result | Existing query coverage | Why necessary |
| --- | --- | --- |
| `public.respond_to_job_application(uuid,text)` complete deployed definition/ACL/settings | Q6; F4a effective privilege only | Insert enrollment into actual transition, preserve text contract/history/notifications |
| `public.update_job_application_status`: all exported signatures | Q6, F5 if direct reader/writer | Ensure alternate Hired transitions cannot bypass enrollment |
| `public.can_manage_company_jobs(uuid)` and actual referenced account/company guards | Q6, F5, then Q7/Q8 helper results | Preserve actor/verification/restriction semantics and lock interactions |
| Application/posting/history/notification triggers actually called by acceptance | Q5 covers application/posting triggers; Q7/Q8 and source tracing for nested side effects | Preserve exactly-once database writes and transaction boundaries |
| Actual history relation columns/constraints and notification relation/emitter signature used in the body | Body identifies exact names; original Q2/Q3 do NOT cover arbitrary history/notification tables | Match inserted fields, uniqueness and recipient identity; supply existing reviewed export if collected, otherwise mark genuinely missing |
| Acceptance's directly/nested-called notification/history helpers, including dynamic SQL/view paths | Q7/Q8; F5 only if membership is referenced | No helper names are established locally; take exact names from the supplied acceptance body, not a guessed notification function |
| `public.create_work_assignment`, `public.reserve_work_assignment_request`, `public.create_work_assignment_request`, `public.lookup_work_assignment_request`: exported signatures/bodies | F1 explicitly includes create_work_assignment_request; F5 covers membership references; other bodies may be in referenced helper exports | Check actual application/job/membership lock graph; checked-in definitions alone do not certify deployed lock order |

Do not request the whole notification/dispute database. First supply acceptance
and its exported direct dependencies; request only a source-referenced missing
definition if required. Catalog dependency output does not establish PL/pgSQL or
dynamic SQL closure. Direct writes in the RPC need no invented emitter helper.

**Decision gate:** distinguish fresh acceptance, C3 replay and legacy Hired;
approve unique enrollment provenance, inactive/revoked conflict response and
replay acknowledgement. Preserve original actor-role eligibility.

## Priority 3: unblock 03_authorization.sql and KZ compatibility

### Exact policies

| Object/policy | Existing coverage | Required result |
| --- | --- | --- |
| `public.companies` / `companies_select_internal` | Q4a | Complete USING/CHECK, roles, command, permissive flag and relation RLS flags |
| `public.company_memberships` / all actual policy names | Q4a | Actual policy names are not in local evidence; supply exact exported rows, do not name them from convention |
| `public.company_logo_change_requests` / `company_logo_requests_read` and all companion policies | F2 | Avoid ordinary/private-request access expansion; preserve policy composition |
| `storage.objects` / `company_profile_logo_insert` and any actual companion Employer gate | F2 | The named policy exists in checked-in sources; any companion name and live expressions must come from F2 |
| `storage.objects` / `company_logo_no_client_overwrite`, `company_logo_no_client_delete` | F2 | Preserve restrictive immutability gates |
| `storage.objects` / `jobmate_company_document_uploads_require_employer` and actual companion document policies | F2 | Owner/document access and bucket/path checks; companion names must come from export |
| `storage.objects` / `work_evidence_scoped_private_reads`, `work_evidence_scoped_private_inserts`, `work_evidence_no_authenticated_deletes`, `work_evidence_no_authenticated_updates` | F2 | Preserve evidence lifecycle/private-read/immutability gates and effective combination |

Supply **all F2 rows**, not only the named subset: other permissive policies can
broaden access even if the named policy is correct. Follow only policy helpers
whose bodies/ACLs are missing from the supplied results. Live name differences or
absent named rows must be recorded explicitly, not silently replaced.

### Exact function groups

| Function names (all collected signatures; public unless export says otherwise) | Existing coverage | Blocked compatibility |
| --- | --- | --- |
| `can_manage_company_jobs`, `save_employer_job_posting`, `update_job_application_status` | Q6, F5; F4a effective access | Lifecycle-aware management and no ordinary authority |
| `get_managed_company`, `list_managed_companies`, `submit_company_for_review`, `submit_company_for_review_v2` | F1 | Owned-company selection and user-only upsert assumptions; KZ change prerequisite |
| `get_user_account_details` | Q6, F5 | One account vs multiple membership rows; versioned KZ contract |
| `list_admin_company_directory`, `get_admin_company_directory_details`, `get_admin_user_directory_details` | F5 only where membership referenced; Q7/helper exports otherwise | Directory counts/projection compatibility; do not require unrelated Admin APIs |
| `submit_company_logo_change`, `list_company_logo_review_requests`, `review_company_logo_change` | Q7/F5, source-referenced helper exports | Owner-only actions and active vs historical conflict semantics |
| `can_review_work_evidence_company`, `create_work_assignment_request`, `verify_work_assignment` | F1 | Inline Employer/role checks and preserved legacy revoked execution |
| `read_employer_work_attendance_gps`, `create_work_assignment`, `reserve_work_assignment_request`, `lookup_work_assignment_request`, `list_company_work_assignments`, `can_view_work_evidence`, `can_read_work_evidence_file`, `work_evidence_workflow_context`, `prepare_work_evidence_review`, `commit_work_evidence_review`, `request_more_work_evidence` | F5 when membership is direct; F1 when exact names added; Q7/Q8 existing helper exports | Selected-company/lifecycle checks, evidence access and reconciliation; only missing actual bodies are requested |
| `list_evaluation_candidates`, `list_my_soft_skill_evaluations`, `submit_soft_skill_evaluation` and exact authorization helpers they call | F1 includes entry points and evaluation-named helpers | No employer evaluation authority through ordinary membership |

For functions retrieved only by F5, their raw EXECUTE ACL is not in that result.
Use already-collected matching Q6/F1 metadata if available. If not, flag an exact
signature-specific ACL gap; do not infer preserved grants from effective access.
F3/F4a establish effective schema/EXECUTE privileges for listed roles, not every
definer owner's inherited rights. Inspect the collected owner/role metadata only
where that execution path needs it.

### Conditional blockers: disputes, notification recipients and other direct readers

Use existing F5 and Q8 outputs first. These are blockers **only for returned or
source-traced membership/authority-dependent paths**, not a request to export every
dispute/payment/notification routine.

- Dispute gateway entry names: `list_disputes_page`, `list_dispute_eligible_records`,
  `get_dispute`, `get_dispute_history`, `list_dispute_evidence`,
  `list_dispute_evidence_history`, `submit_dispute`, `act_on_dispute`,
  `prepare_dispute_evidence`, `finalize_dispute_evidence`.
  These names come from `lib/features/disputes/dispute_gateway.dart`, not proof of
  live definitions. F5 finds only direct membership references; Q8/source tracing
  may identify indirect helpers. Do not label the whole group already covered.
- Notification recipients: supply the exact membership-dependent emitter/helper
  returned by F5 or called from acceptance/onboarding/dispute bodies. No deployed
  emitter name is established in this checkout. Read/mark notification RPCs are
  not blockers unless those bodies identify them as dependencies.
- Other F5 rows: include only user-only selection/upsert, Owner protection,
  authorization, recipient fan-out or conflict-of-interest paths affected by
  pair cardinality/lifecycle. Record the actual exported signatures.
- Payment/worker-owned paths need additional definitions only if supplied source
  shows a membership dependency affected by the change. Employment-type changes,
  broad payment redesign and independent capability delegation are out of scope.

## What CH should supply now (shortest path)

1. Attach the existing Q1–Q6/Q8 results and F1–F5 exports, retaining original
   query/file identifiers. No new broad discovery is requested. Q7 inventory can
   accompany exact helper definitions already collected. Mark unavailable pieces.
2. In each export retain full cells, empty/missing markers, inspection timestamp,
   project alias and role. Redact secret/private literals visibly; no credentials
   or application rows. Keep sensitive originals inside the authorized team.
3. Integrate schema/Owner evidence into 01, then acceptance/side-effect evidence
   into 02, then policy/authorization evidence into 03. Resolve only named
   source-referenced gaps; record original ACL/body fingerprints before patching.
4. CH/KZ resolve the decision gates above and historical dispute/conflict/recipient
   scope. Produce reviewable SQL from actual originals, still marked DRAFT / NOT
   APPROVED FOR DEPLOYMENT. Do not run it against the shared database.
5. Use TESTS_AND_RELEASE.md for isolated validation and subsequent approval gates.
   A complete implementation draft is not production authorization.

Actual acceptance/management/Owner source and six policy patches are now integrated
from evidence. SQL remains unexecuted, draft-guarded and blocked on full release
compatibility. No missing deployed body has been invented.

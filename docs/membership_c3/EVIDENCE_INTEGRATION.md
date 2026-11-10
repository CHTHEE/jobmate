# Actual evidence integration

**DRAFT / NOT APPROVED FOR DEPLOYMENT. No SQL executed.**

**Final side-effect evidence update:** 19 history/notification objects have been
added without overwriting the original snapshot; combined_evidence_snapshot.json
contains 110 objects. Item 1 below is resolved. See ISOLATED_TEST_RESULTS.md for
actual validation and failed local PostgreSQL startup (no test SQL executed).

## Validation and provenance

Actual source is `C:\Users\theec\Desktop\jobmate_c2_evidence.txt.txt`, 49,055 bytes.
It is one CSV row whose evidence cell is JSON. The original file was not renamed
or modified. `evidence_snapshot.json` preserves the parsed original bundle and
source SHA-256; `EVIDENCE_INVENTORY.md` lists every exact identity.

Both found flags are true. There are 91 unique objects: 32 constraints, 14
functions, 3 indexes, 25 policies, 5 relations and 12 noninternal triggers.
Multiline bodies, function endings, constraints, policy expressions and ACLs parse
intact. There is no independent source row-count/timestamp, so parsing alone
cannot certify SQL Editor export completeness or absence of a result cap.

The bundle partly covers Q1/Q2a/Q3a/Q3b/Q4a/Q4b/Q5/Q6 and F2/F5. It does not contain
Q2b type internals, Q4c/F3 schema-role privileges, Q8 dependency graph or all F1/F4
functions/effective privileges. Do not mark entire query groups complete.

## Confirmed findings and discrepancies

- Membership columns are NOT NULL; created_at defaults to now(). Exact PK/check:
  company_memberships_pkey(user_id), company_memberships_member_role_check.
- company_memberships_company_id_fkey and company_memberships_user_id_fkey both
  use ON DELETE CASCADE. Draft 01 retains them; new receipt references do not
  cascade. No inbound membership FK is present in the returned constraints.
- Indexes: company_memberships_pkey, company_memberships_company_id_idx,
  jobmate_one_owner_per_company_idx (unique company_id for owner rows).
- Membership ACL gives authenticated SELECT only, postgres/service_role full table
  privileges. No column ACLs. RLS enabled, not forced. company_memberships_select
  allows own historical affiliations and existing Admin reads, not management.
- Acceptance and management functions are postgres-owned SECURITY DEFINER with
  empty search_path and EXECUTE for postgres/authenticated/service_role only.
- Acceptance verifies an active Job Seeker applicant, locks the application, and
  directly inserts history and a notification to job_postings.created_by. There
  is no membership-wide emitter call to guess or replace.
- Actual side-effect tables: public.application_status_history and
  public.notifications. Their definitions/triggers/ACLs are absent from this
  bundle. The original INSERT text is preserved, not reconstructed.
- Exported Owner trigger compares TG_OP with lowercase delete/update. PostgreSQL
  supplies uppercase TG_OP values: its intended deletion/transfer guard branches
  do not run. Draft 01 corrects those comparisons. This is a source-level defect,
  not a demonstrated live exploit; KZ must review the safeguard correction.
- Exported user triggers are ensure_role_profile, set_signup_role and updated_at.
  There is NO jobmate_owner_must_remain_employer trigger in this result. Its
  function is also absent. Draft 01 proposes a separately named new guard rather
  than claiming the checked-in safeguard is deployed.
- job_applications has broad anon/authenticated table ACLs and enabled RLS, but
  no policies are returned. This does not prove direct writes are possible:
  no-policy RLS normally denies them. Alternate privileged Hired writers remain
  an exact dependency review item.
- Posting employment check excludes temporary. No employment/payment change made.

## What the drafts now implement for review

01: original constraint names, pair PK, ordinary member, lifecycle, both Owner
uniqueness rules, amended original Owner trigger, proposed missing account-role
guard and server-only acceptance provenance. Active initialization, prohibition
of physical membership deletion/reactivation and new receipt identity are explicit
proposals requiring CH/KZ approval. created_at and original outbound FKs retained.

02: four anchored changes to the full exported acceptance definition. Original
applicant check, action branches, application update, history and notification
blocks retained. Fresh acceptance locks application then job, insert-or-reuses a
pair without updating it, locks/validates active state, writes a receipt and then
executes original side effects. Errors roll back the whole transaction. Same-offer
replay requires receipt ownership and performs no new writes/reactivation. Legacy
Hired without receipt is blocked pending separate reconciliation.

Pair conflict insertion waits under READ COMMITTED; a separate SELECT observes
the committed pair. Inactive/revoked pairs cause failure. Stronger isolation may
raise serialization conflicts; no automatic client retry is introduced. Existing
membership role and users.role stay unchanged. Active Job Seeker eligibility is
retained, so an Employer Owner cannot newly accept via this RPC without separate
approval. Owner A can still hold an ordinary affiliation with B.

03: partial source-derived management-helper change and six ALTER POLICY patches.
Original commands/roles/permissiveness remain. Affiliation access gains active
lifecycle; initial company upload checks use no OWNED company, rather than no
membership, and require Employer. Ordinary seekers gain no onboarding uploads or
management authority. Historical conflict exclusion, restrictive immutable gates
and unrelated policies are retained. Missing Module 4/KZ/evaluation/dispute paths
mean this is not a complete deployable authorization release.

All three files have an unconditional draft exception BEFORE modifications.
It is an intentional accidental-execution stop. No SQL has been executed or
database syntax/runtime tested. Existing EXECUTE grants are not changed by
CREATE OR REPLACE; new private objects explicitly have no client execution/write
grants. Intended isolated operator/new-object owner is postgres, matching evidence.

## Genuine remaining evidence gaps (only missing existing exports)

1. **public.application_status_history and public.notifications**: full columns,
   defaults, constraints, triggers and called trigger functions. Do not request an
   imagined emitter: the original acceptance performs direct INSERTs.
2. **Onboarding**: submit_company_for_review and submit_company_for_review_v2,
   get_managed_company/list_managed_companies: complete signatures/bodies/ACLs.
3. **Admin**: get_user_account_details and relevant company directory/conflict
   bodies/ACLs. Runtime source absent; repository joins are not live evidence.
4. **Other Hired writers**: update_job_application_status and actual privileged
   writers identified in existing C2 exports; no broad new discovery requested.
5. **Module 4**: can_review_work_evidence_company,
   read_employer_work_attendance_gps, reserve/create/lookup_work_assignment_request,
   list_company_work_assignments, evidence context/read/prepare/commit and guards.
   Inline checks may bypass lifecycle in can_manage_company_jobs.
6. **Exact policy helpers referenced in supplied expressions**:
   can_view_published_job_logo, can_upload_dispute_evidence,
   can_read_dispute_evidence, can_view_work_evidence, can_read_work_evidence_file,
   can_upload_work_evidence. Supply missing bodies/ACLs and only their affected
   source-traced dependencies, not the whole dispute system.
7. **Evaluations**: list_evaluation_candidates, list_my_soft_skill_evaluations,
   submit_soft_skill_evaluation and affected authorization helpers only.
8. **Existing Q2b/Q4c/Q8/F1/F3/F4 outputs** where relevant to the above, definer
   owner execution and new-object default privileges. No repeat export of the
   91 already-supplied definitions is needed.

The supplied creator/profile/timestamp/restriction trigger bodies are covered.
private.enforce_company_restriction_on_job_write references company_restrictions;
preserve that contract where onboarding/posting patches eventually need it.

## Decisions and shortest approval route

CH/KZ approve active initialization, Owner bug/account-role corrections,
membership retention/reactivation rules and historical Hired policy. KZ completes
onboarding/Home/Admin cardinality compatibility before enrollment creates multiple
rows. Preserve historical disputes/conflicts and exact notification recipients.
Supply the exact missing existing exports above; complete 03 and KZ drafts from
originals. Run real-JWT authorization and independent-session concurrency tests
in isolation, including rollback, acceptance/revocation and Owner-role races.
Then approve exact artifacts/ACLs, coordinated release window, old-client support
and non-destructive recovery. Never delete memberships to restore user-only PK or
restore old hiring-without-enrollment alone. No live action or Flutter activation
is authorized by this integration pass.

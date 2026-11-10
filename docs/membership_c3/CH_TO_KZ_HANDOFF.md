# CH to KZ: hiring to company membership handoff

**DRAFT / NOT APPROVED FOR DEPLOYMENT. CH local code is ready for KZ review;
the full feature is not live or deployment-ready.**

Latest implementation update: worker membership UI, new candidate read RPC and
compile-time source composition are now connected behind
JOBMATE_HIRING_MEMBERSHIP=false. Production selection is no longer absent code;
it is present but OFF by default. The new supported candidate is under candidate/,
with a fail-closed review acknowledgement guard; original C3 guards remain intact.
Remaining KZ and isolated database release gates below still apply. No backend
deployment or Flutter activation has occurred.

## What CH has implemented locally

- `lib/features/jobs/job_postings_repository.dart`: optional immutable
  companyContext, explicit pair lookup, scoped-list mismatch rejection and fresh
  access checks for save/close. Existing Employer/Owner-or-Employer/verified-company
  guards retained. Ordinary role never grants management. Multiple unscoped rows
  still fail closed; this does not yet implement future company-selection UI.
- `lib/features/applications/hiring_membership_source.dart`:
  AtomicHiringMembershipGateway, unavailable-by-default source decorator and
  SupabaseAtomicHiringMembershipGateway.forApprovedBackend. The source's matching
  forApprovedBackend factory composes both paths with one client. Transport uses the
  actual existing respond_to_job_application(application UUID, accept_offer)
  contract, expects text, disables SDK transport retries, checks session and makes
  no second membership write. Production composition selects it only when the
  explicit compile-time flag is enabled; the flag defaults to false.
- The decorator routes only acceptance through the atomic gateway, preserves
  legacy list/history/decline/withdraw contracts, blocks duplicate in-flight
  actions and invalidates stale account responses. No legacy acceptance fallback.
- Existing MyApplicationDetailsRepository establishes owned/current application,
  confirms legal status/session, locks through mutation AND authoritative refresh,
  refreshes on success/failure, and never infers Hired/membership from an ack.
  Failed refresh removes the application snapshot, preventing blind UI retry.
- `test/hiring_membership_source_test.dart`: 13 source/repository integration
  tests. `test/hiring_membership_transport_test.dart`: 10 transport/composition tests.
  `test/hiring_membership_ui_test.dart`: 8 projection/widget tests, including
  mocked acceptance, authoritative refresh, revocation and sign-out.
  Existing application/company-context/Module 4 regressions remain covered.
- The separate Module 4 uncertain-upload fix retains shared uncertainty gates
  across controller reopening. Process-restart recovery is not claimed.
- 110 metadata objects preserved: original 91-object evidence_snapshot.json is
  intact; final and combined snapshots retain actual history/notification schema.
- Three guarded SQL review drafts outside migrations: schema/Owner/lifecycle,
  original acceptance with atomic membership/receipt, partial authorization and
  six source-derived policy patches. Exact original inserts/ACL boundaries retained.

## Disabled production state and activation boundary

Module2Repository.myApplications uses createMyApplicationsSource. With
JOBMATE_HIRING_MEMBERSHIP omitted or false, it selects the unchanged legacy
SupabaseMyApplicationsSource. Only an explicitly enabled build selects the atomic
adapter and membership panel, using the SAME authenticated client. The wrapper's
default gateway remains UnavailableHiringMembershipGateway. Do not enable the
flag until joint backend approval and deployment; navigation is unchanged.

The named constructor is an explicit integration boundary, not a runtime backend
readiness check. The old RPC has the same signature; a successful response cannot
prove enrollment is deployed. No speculative readiness endpoint/flag is added.
Importantly, replacing that RPC affects EXISTING clients immediately even if the
new Flutter source stays disabled. Backend deployment must therefore wait for all
compatibility work; adapter activation is not a server-side rollout switch.

## KZ's exact compatibility tasks (not implemented by CH)

| Area | Exact files/functions | Required result |
| --- | --- | --- |
| Onboarding backend | submit_company_for_review, submit_company_for_review_v2 and called helpers | Replace any-membership rejection/user-only conflict assumptions with owned-company checks; ordinary B affiliation must not block owning A; preserve one owned company, Employer eligibility and verification |
| Onboarding UI | lib/features/company/create_company_page.dart, _loadCompany/_eligible | Resolve owned/onboarding company explicitly; no arbitrary first membership; retain rejected-owner resubmission and unsaved-input guards |
| Home | lib/features/home/home_page.dart, _loadAccountRole | Replace user-only membership maybeSingle; summary uses explicit authorized company/owned company according to approved product rule |
| Management selection | get_managed_company/list_managed_companies; job_postings_repository access consumers | Return only authorized active company contexts; do not make every ordinary affiliation manageable; preserve deny-on-ambiguity for old callers |
| Admin backend | get_user_account_details | Version one-account response with memberships array, rather than one row per membership; retain account-management permission/privacy rules |
| Admin UI | lib/features/admin/user_management_gateway.dart details; user_account_details_dialog.dart | Adopt versioned response together; do not simply discard extra rows or relax >1-row error |
| Company directories | list_admin_company_directory/get_admin_company_directory_details; company_management_gateway.dart/company_management_page.dart | Label active vs historical memberships/counts, avoid user duplication/pagination changes and preserve platform Admin permissions |
| Company/logo | company_logo_editor.dart _checkOwnerAccess; submit_company_logo_change and review helpers; Storage policies | Pair lookup stays cardinality-safe; retain active Owner-only mutations and exact bucket/path protections; approve draft 03 initial-upload changes |
| Conflicts/disputes | Actual membership-based Admin/company review and dispute participant helpers | Operational authority uses active lifecycle; historical affiliation conflicts and existing case-party access need separate rules. Ordinary membership gives no case access |
| Notifications | Existing emitters and recipient helpers affected by membership | Preserve original acceptance notification to job_postings.created_by. Do not fan private management messages out to all ordinary members; preserve historical/direct participants |

Paths in the Admin directory row are under lib/features/admin. Shared navigation,
main.dart and KZ application files were not edited. Confirm ownership for any
additional evaluation/dispute/payment helper before modifying it.

## SQL review: consistency and exact remaining blockers

- 01 pair PK matches 02 ON CONFLICT and receipt FK. Both Owner uniqueness rules
  apply to all Owner rows. Existing created_at and FK definitions are retained.
- 02 adds membership/provenance before the original application/history/notification
  writes in the same transaction. Receipt-backed replay avoids duplicate writes;
  inactive/revoked pairs fail, and account role never changes. Legacy Hired without
  receipt is explicitly blocked for separate reconciliation, not silently repaired.
- 03 uses active lifecycle on supported operational paths; ordinary members remain
  outside management helper predicates. ALTER POLICY preserves original policy
  command/roles/permissiveness and companion restrictive gates.
- ALL THREE contain execution-stop guards; NONE was executed. 03 is PARTIAL,
  with missing inline Module 4/evaluation/dispute authorization compatibility.
  Separate file commits are not an approved safe live deployment sequence.
- Owner TG_OP uppercase correction and newly proposed missing account-role guard
  need KZ review and concurrent Owner/account-change tests. Original history and
  notification tables are now covered; do not request them again.
- Remaining exact-source inputs for edits: onboarding/Admin originals and ACLs;
  update_job_application_status/alternate Hired writers; lifecycle-dependent
  Module 4/evaluation and actual referenced policy/dispute helpers. Reuse existing
  C2 exports, not broad rediscovery. Resolve schema/default-grant/dependency gaps
  only where the proposed changes rely on them.
- Deployed employment constraint excludes temporary while UI/payment contracts
  mention it. Separate unresolved issue; no employment/payment changes included.

## Required CH/KZ decisions

1. Approve initializing legacy memberships as active; retention/no physical delete;
   inactive/revoked conflict handling; explicit future reactivation/audit authority.
2. Approve historical Hired backfill eligibility and receipt/replay behavior. No
   backfill, fabricated join dates or replayed offer notifications are included.
3. Confirm ordinary membership gives zero hiring/scheduling/verification/evaluation
   management rights. Independent employee capabilities and grant/revoke UI are
   deferred, not implemented by changing account role or employment type.
4. Preserve Owner of A with ordinary membership B. Current active Job Seeker-only
   acceptance rule remains: hiring an Employer Owner is a separate eligibility
   decision, not an exception to introduce silently.
5. Approve historical conflicts/dispute access separately from active operational
   recipients, Owner safeguard fixes, old-client support and non-destructive recovery.

## Testing and release order

1. KZ reviews this handoff, completes compatibility drafts from exact existing
   sources, and CH/KZ resolve lifecycle/permission decisions. Keep all guards.
2. Use a disposable isolated PostgreSQL environment for actual SQL syntax/runtime,
   real-role authorization and multi-session acceptance/revocation/Owner races;
   preserve review guards, test generated copies only. This remains UNRUN.
3. Run joint Web/Android/direct-URL/client regressions and review exact ACL/policy
   diffs. No ordinary-management grants or restored legacy evidence bypasses.
4. CH AND KZ explicitly approve exact artifact hashes, lifecycle/backfill policy,
   test evidence, coordinated cutover/window/operator and non-destructive recovery.
5. Authorized backend owner deploys the coordinated backend/compatibility release
   after approval. No isolated old hiring RPC rollback and no deleting membership
   rows to force the old user-only PK. Verify approved catalog and synthetic QA.
6. Only after backend is approved, deployed and verified: separately approve enabling
   the Flutter compile-time flag. The existing RPC replacement already affects old
   clients; do not rely on this final step to prevent premature enrollment.

## Actual local validation / untested scope

Final handoff run: focused Flutter tests cover source/transport, acceptance pages,
lifecycle, company contexts/applicants and Module 4 creation/routes/evidence.
Formatting, Flutter analysis and static draft-preservation checks are run locally;
current results: **233 focused tests passed**, including 31 source/transport/UI
tests. Dart formatting and git diff --check passed. Flutter analysis reported the
same four informational diagnostics in untouched Admin/signup files, with none in
the CH integration code. Static evidence/draft-preservation assertions passed.
Full Flutter suite: **1,333 passed, 5 failed**. The failures were reproduced by
running the untouched admin_dashboard_material_test.dart and
company_review_page_test.dart alone: sidebar Users tile, two private-image error
expectations, Check for updates control and private-PDF error expectation.
These KZ UI/test discrepancies were not edited in this task.

PostgreSQL tests are UNRUN: the existing local distribution lacks postgres.bki;
no further installation or investigation was attempted for this handoff. Test
harness also needs startup-timeout cleanup and bounded client waits before use.
No Supabase JWT/RLS/Storage, SQL transaction/concurrency or deployed-device
acceptance is established by Flutter fakes or local HTTP. Nothing is deployed.

Future CH release work is intentionally not performed ahead of KZ/backend approval:
enable the approved source flag, adopt the approved lifecycle-aware company
access/selection contract for job/applicant/Module 4 consumers, and run coordinated
device acceptance. The present code must not query undeployed lifecycle columns
or guess a new managed-company RPC response to simulate that cutover.

**Ready for KZ code/design review: YES. Ready for production deployment: NO.**

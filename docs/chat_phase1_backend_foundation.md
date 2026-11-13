# Chat & Communication: Phase 1 inspection and foundation design

## Phase 2 addendum — supplied live verification, 12 November 2026

The user's Phase 2 request supplies authoritative results from manual inspection
of the existing Supabase project. The original Phase 1 text below is retained as
a historical audit; its missing-schema blockers and proposed contracts are
superseded where stated here and in
[the Phase 2 implementation document](chat_phase2_backend_implementation.md).
The agent did not independently execute any live inspection or SQL.

Confirmed: no live chat tables; the eight application statuses below; current
one-row-per-user company_memberships with owner/employer role and no status
column; active Employer/current membership/verified company checks in the existing
can_manage_company_jobs(uuid) helper; application transition FOR UPDATE locks;
company restriction records and locks; an empty existing supabase_realtime
publication with insert/update/delete/truncate enabled. The helper does not check
company_restrictions and is reused without replacement. Membership proposals in
membership_c3 remain unapproved and are not dependencies.

Both notification list overloads and both read functions exist live. Flutter's
explicit p_limit/p_offset and boolean mark_notification_read call remain valid;
the earlier apparent mark-read discrepancy is resolved without code changes.
User-confirmed Option B permits hired application communication even during
company/job restriction and after engagement closure. Rejected, declined and
withdrawn are read-only; a missing company restriction row blocks new writes,
including hired. Account, role, current membership and company verification
requirements are not bypassed.

The new guarded Phase 2 candidate proposes a 4000-character limit, scoped
(conversation,sender,request UUID) idempotency, per-user sequence cursors and atomic
generic notifications. It supersedes the older 2000-character/global-request
design suggestions below. Flutter integration is now Phase 3, not Phase 2.
Phase 2A KZ confirmation resolves retention compatibility with current supported
suspension/reactivation, company restriction and application status/engagement
closure workflows. Hard deletion is outside current application scope; NO ACTION
history references remain approved and may prevent future privileged hard deletion.
No Employer removal workflow or membership lifecycle dependency is introduced.
Read states are personal UI state, distinct from immutable message evidence;
their existing FK retention is unchanged pending any separately reviewed policy.

Phase 2A removes the global membership lock, uses locked notification-recipient
snapshots, adds an authorized existing-thread read-only fast path, narrows mark-read
to participant/own-cursor locking and makes read-state access RPC-only.
Phase 2B CH supplied the completed Section 6 results: supported deployed
update_job_moderation locks its existing job FOR UPDATE before state UPDATE or
initial INSERT; moderation state has RLS, postgres-only explicit ACL, no policies
and no non-internal triggers. Membership ACLs, enabled owner protection and
user-first onboarding were also confirmed. The agent did not run this query.

Phase 2B removes the remaining global moderation lock and reuses the existing
relevant job SHARE NOWAIT lock. Both global locks are now absent. Final creation/
send eligibility is rechecked in a separate post-lock query; fresh writes require
READ COMMITTED to prevent a stale repeatable moderation snapshot. Supported
moderation uses the verified parent-job protocol; privileged/dynamic/external
writers outside it are not certified. Section 6 remains baseline/drift discovery,
not an outstanding request for CH to repeat the inspection. Final CH/KZ review
of that supported boundary and an explicitly approved validation approach,
including still-unperformed PostgreSQL/runtime security tests, remain
release gates. No approved PostgreSQL test environment currently exists. The
candidate intentionally raises before DDL and is not approved for deployment.

Final hardening adds immediate FOUND checks after each required authorization/
relationship row lock, including write-side company/restriction locks; final
authorization and identity-drift checks remain. READ COMMITTED is now enforced
once by lock_participant for creation, sends, identical replay and mark-read.
Read-only retrieval/list/history remain unchanged. Submitted and shortlisted
messaging by either authorized party remain allowed; Chat never changes an
application status or implies shortlisting/hiring.

Separate guarded rollback-DDL validation, read-only post-rollback verification
and DDL event-trigger inspection candidates are prepared under supabase/diagnostics
and documented in the implementation guide. They were not executed. The rollback
body is an exact checked copy of the final migration after its deployment guard
and before COMMIT; original deployment and separate validation guards remain.
CH subsequently supplied PostgreSQL 17.11 origin-mode inspection and reviewed all
six event handlers. Validation now pins their full set/metadata/normalized grant
sets/definition MD5s rather than rejecting every enabled hook. Both guards remain
unconditional and unchanged. A 90s transaction timeout and explicit pre-rollback
success marker supplement existing limits/NOTICE; missing marker means unconfirmed.
The single-query/single-JSON baseline now covers internal FK triggers, complete
publication column/filter metadata, event-handler bodies/ACL provenance and all
previous fingerprint categories; Section 5 shares the exact query. MAINTAIN
privileges are included in the PostgreSQL 17 table assertions. Final execution
approval, residual extension/external-side-effect risk, baseline/rollback confirmation and
runtime security/concurrency/Realtime validation remain outstanding.

## Original Phase 1 audit (historical)

Status: 12 November 2026. Offline checkout audit only. No SQL executed, backend
deployed, synthetic records created, or Flutter integration changed. Phase 2
has not started. The backend design below is proposed, not an existing API.

## Findings and reusable infrastructure

| Exact path | Finding |
| --- | --- |
| `lib/features/chat/chat_page.dart` | Entire chat uses `Phase3Store`, not Supabase. Reusable responsive list/thread, search, job context, empty state, composer and safe list exit. Demo labels are accurate. |
| `lib/features/demo_work/phase3_store.dart` | `DemoConversation` has display strings, local ID, messages, role-keyed unread/drafts. No application FK or authenticated sender ID. `DemoMessage` uses role strings, client time and simulated receipts. In-memory lifetime only; unsuitable as persistence/security model. |
| `lib/features/demo_work/local_attachment.dart` | Local demo files only; no real upload contract. Preserve demo; attachments deferred. |
| `lib/main.dart` | Role-gated `/messages`, `/messages/:conversationId`, `/employer-messages`, `/employer-messages/:conversationId` render the same `ChatPage`. |
| `lib/shared/navigation/app_routes.dart` | Existing Messages route constants. |
| `lib/shared/navigation/workspace_destinations.dart` | Both workspace entries explicitly say Messages (demo). |
| `lib/features/applications/module2_widgets.dart` | `Module2Gate` is a UI account/role gate, not conversation authorization. |
| `test/phase3_test.dart` | Existing chat tests exercise local drafts/send/unread/simulated receipts and responsive demo UI. They do not establish database security, delivery or durable history. |
| `lib/features/notifications/notifications_repository.dart` | Real authenticated list/read adapter; account-generation protection is reusable. Calls `list_my_notifications(p_limit: 50, p_offset: 0)` and boolean `mark_notification_read(p_notification_id)`. |
| `lib/features/notifications/notifications_page.dart` | Real inbox, refresh/resume and unread state; no chat subscription or verified immediate delivery. |
| `test/notifications_repository_test.dart`, `test/notifications_page_test.dart` | Local notification contract/UI regression tests. |
| `supabase/migrations/20261031000100_admin_dashboard_and_review.sql` | Defines notifications, RLS, revoked client table access, active-account/recipient-scoped definer list/read routines. Its `mark_my_notification_read(uuid)` returns void and differs from the consumed deployed-contract name. |
| `supabase/migrations/20261105000100_work_attendance_verification.sql` | References application `application_id`, `applicant_id`, `job_id`, `status`; assignment creation derives company through job and calls `can_manage_company_jobs`. Multiple assignments belong to an application. |
| `docs/application_arrangement_lifecycle.md` | Prior audit records missing authoritative Module 2 DDL/RPC/transition/notification sources. |
| `docs/shift_scheduling_notifications_audit.md` | Existing notification mismatch and owner-coordination constraints. |
| `docs/membership_c3/01_schema.sql`, `docs/membership_c3/candidate/001_hiring_membership_supported_candidate.sql` | Guarded, explicitly undeployed membership proposals. Not a live schema baseline. The candidate replacement helper must not be adopted as current authority. |

No conversation/message table, chat RPC, chat RLS policy, chat Storage bucket or
Realtime publication configuration was found in checked-in migrations. This does
**not** prove those objects are absent live. No existing live chat policy can be
declared secure or insecure without its definition. No private messages were read.

## Actual lifecycle and employer access evidence

`lib/features/applications/my_applications_repository.dart` defines wire statuses
`submitted` (Applied), `shortlisted`, `interview`, `offered`, `hired`, `rejected`,
`declined`, `withdrawn`. There is no `reviewing` or application `completed` status.
Its completed grouping includes Hired and terminal recruitment outcomes, not work
completion. Shift completion must not disable application chat.

`lib/features/applications/employer_applicants_repository.dart` reuses
`lib/features/jobs/job_postings_repository.dart`: active Employer, selected company
membership with role owner/employer, verified company, authorized jobs then
`list_job_applicants`. Status changes call `update_job_application_status`.
The legacy membership lookup fails on ambiguous multiple memberships; it does not
prove active/revoked membership enforcement. Server-side management is referenced
through `can_manage_company_jobs(company_id)` by Module 4, but its authoritative
deployed body and recruitment-specific equivalence are unverified. Do not grant
chat access from membership existence, original poster identity or Flutter gates.

## Minimal proposed foundation (pending schema review)

Reuse compatible live chat objects if found. Otherwise introduce only the necessary
application conversation, immutable text message, and per-user read-state objects.
All names/fields below describe a design; no new callable API is established.

- Conversation: immutable application FK with a database UNIQUE constraint;
  server-created ID/time. Initiate only on explicit authorized messaging action.
  Atomic insert-on-conflict/retrieve returns the same row under concurrent starts.
  No company/worker/shift uniqueness or new hiring restriction. No cascade deletion
  of history from recruitment/work updates; inspect upstream deletion first.
- Resolve applicant, job and company from stored relationships, validate identity
  consistency and `auth.uid()`, and recheck current account/recruitment authority
  on list/history/create/send/read-state calls. Worker access is application-owned;
  employer access uses the exact reviewed current recruitment permission predicate.
  No administrator bypass or dispute access. Revocation must end future access.
- Allow first initiation and fresh sends for submitted, shortlisted, interview,
  offered and hired. Rejected/withdrawn retain authorized history but cannot send
  or create a new thread. Propose the same restriction for declined, subject to
  CH/KZ confirmation. Unknown statuses fail closed. Hired stays writable after
  completed shifts. Historical read access still requires current actor authority.
- Messages: authenticated actual sender user ID, server timestamp, immutable body,
  conversation ID, durable client request UUID. Validate trimmed nonempty text and
  a reviewed length limit (propose 2,000 characters matching current composer).
  Do not accept sender/company/worker/status/timestamp as trusted client fields.
  Do not implement UPDATE/DELETE or attachments.
- Durable UNIQUE(sender user ID, request UUID): same request and identical canonical
  conversation/body returns the original message; different payload is rejected.
  Authenticate and authorize every replay; a now-terminal application may return
  its already-committed identical message but cannot create a new one. Lost response
  retries retain the same UUID across reconnect/restart. A success response means
  persisted, never recipient-delivered or read.
- Allocate a monotonically increasing per-conversation sequence while holding its
  lock. Read cursor keyed by (conversation, authenticated user), bounded to a real
  observed message sequence, updated monotonically. Count incoming messages beyond
  that cursor, excluding own sends. Never share employer read state by role/company.
  Serialize sends with application terminal transitions and permission revocation
  using a reviewed common lock order; current helper checks alone cannot prove this.
- Paginate history by stable sequence and list by stable last activity/ID. Return
  company/applicant name, job title, last preview/time, unread count and authoritative
  can-send state without exposing resumes or unrelated application data.
- Prefer RPC-only writes with explicit revocation of PUBLIC/anon/authenticated
  table mutation grants, RLS defense, fixed safe search_path, fully qualified
  objects, trusted function ownership and explicit authenticated EXECUTE grants.
  Audit views, other definer routines and inherited grants for bypasses.
- For Realtime, use narrowly granted SELECT with RLS that repeats current actor
  authorization; list/history RPCs remain authoritative. Use publication INSERTs
  only as needed, never broad public payload broadcasts. If SELECT would expose
  unnecessary fields, use an authorized minimal invalidation event and RPC refresh.
  Test already-open subscriptions after revocation; do not assume channel join
  authorization alone revokes access. Reconcile missed events on reconnect/resume.
- Persist recipient-scoped in-app notifications atomically with each new message;
  reuse notifications only after owner review of current schema/emitters. Deduplicate
  by (message, recipient), resolve authorized employer recipients server-side,
  exclude sender, avoid private body previews in generic inbox rows that could
  outlive membership. Replays/read-cursor updates emit nothing. Define retention
  and membership-change visibility with KZ. No email/background push.

## Blockers and migration decision

No migration candidate is created: the requested stop-on-ambiguous-authorization
rule applies. An additive candidate depending on guessed application constraints
or a proposed membership helper would be unsafe. This is a blocked foundation
design, not a deployment-ready backend. Obtain the following before writing SQL:

1. Current application/job/user/membership DDL, keys, statuses, RLS, grants, views,
   recruitment read/update/create routines and all helper dependencies; especially
   `can_manage_company_jobs` and current active/revoked membership semantics.
2. Existing live chat objects, if any, including grants/policies/functions/triggers.
3. Actual notification list/read overloads, triggers, emitters and recipient rules.
4. Realtime publication and subscription authorization configuration.
5. CH/KZ decisions: declined behavior, historical access on company/account
   restriction, newly authorized employer history/unread baseline, length limit,
   and notification recipient/retention behavior after revocation.

Do not apply the membership proposal, replace notification RPCs or change Module 2
to resolve these gaps as part of this phase.

## Exact manual read-only verification

CH/KZ can run `supabase/diagnostics/chat_phase1_catalog_inspection.sql` manually in
the existing project's SQL Editor. It contains only SELECTs and catalogue definition
readers, never application mutation RPC calls. It inventories all public relations
and routines deliberately so unexpectedly named legacy chat objects are not missed.
Keep exports private: routine definitions may contain private implementation detail.
It retrieves no business rows, message bodies, storage objects or credentials.

Review every result set: relation inventory/RLS/ACL/owners, columns/defaults,
constraints/indexes/enums, all permissive/restrictive policies and table/column
grants, routine overloads/owners/ACL/search_path/bodies, trigger bodies, publications
and member tables, and bucket limits. SQL Editor visibility is required; missing
rows under a restricted role do not prove absence. Follow helper dependencies into
other schemas if any public function references them. Inspect any discovered
views and their owner/security options before declaring a direct-access audit done.
Do not export JWTs, service-role keys or real conversation data.

After offline reconciliation, prepare one additive migration that fails on unknown
conflicting objects, plus focused isolated authorization/concurrency SQL tests.
Review it jointly before any separately authorized deployment. Then manually verify
schema/grants/publication and use authorized isolated users for runtime RLS,
Realtime and retry checks. No production fixtures or remote changes are requested now.

## Validation and next phase

Only this document and the catalogue inspection SQL were added. README and all
pre-existing dirty files remain untouched. There is no new runtime contract to
unit-test. Executed `flutter analyze`: exit 1, five informational diagnostics in
unchanged files (two braces in company_management_page.dart, two deprecated radio
properties in sign_up_page.dart, one async BuildContext in
engagement_closure_controls.dart); no errors or warnings reported.
Executed `flutter test test/phase3_test.dart test/notifications_repository_test.dart
test/notifications_page_test.dart --reporter compact`: 65 passed, two failed.
Failures are employer Phase 3 destination reachability at 320 and 1440 widths,
with `Bad state: No element` from scrollWorkspaceMenuTo in
`test/support/workspace_navigation_test_helper.dart:41`. These tests and their
helper were not changed. Chat demo/notification checks passed within this run;
they cannot validate proposed SQL or live security. The catalogue SQL has not
been compiled or executed against PostgreSQL. No browser/device acceptance ran.

Required later database cases: concurrent initiation; foreign worker/company/Admin;
inactive/revoked and ordinary membership; terminal transitions racing sends;
matching/mismatched retry UUIDs including lost responses; notification rollback;
two employer readers with independent cursors; cursor/send race; missed events;
existing subscription after revocation; direct table/view/RPC bypass attempts;
offline recipient return; multiple applications and multiple shifts preserving
separate application conversations and all existing records. No PostgreSQL tests
have run in this phase.

Phase 2 begins only after foundation review: add typed real repository/models,
session-scoped request persistence/reconciliation, authorized application entry
actions and the reusable responsive list/thread with real pagination, errors,
retry, read cursors and subscriptions. Preserve workspace/browser/Android exits
and drafts, remove simulated receipts only from the real interface, and leave
attachments deferred. No Figma file was supplied or accessed in this audit.

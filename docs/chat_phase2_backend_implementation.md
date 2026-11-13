# Chat — final backend hardening and validation preparation

Latest status (13 November 2026): **backend permanently deployed; prospective
catalogue integrity passed; authenticated runtime acceptance pending.** CH supplied
the permanent marker `CHAT_PERMANENT_DDL_CATALOG_ASSERTIONS_PASSED_COMMIT_PENDING`,
PID 2812168/read committed, followed by an independent activity inspection with
no rows for that PID. Fresh Section 0 was `post_deployment_or_partial`, all 12
checks PASS. Artifact SHA-256:
`F8C7F05FB086BB53E82B9E6BB406975DAE7B9E96DF10BFE857B957138CC5AA63`.
Fingerprint source/compared/duplicates: **5769/5757/0**; all 13 category counts
and hashes matched the pre-deployment digest. Global SHA-256:
`c08532d80fd3e19fc228329f1400d6319564bd62f0eaada0a624abdc1fdf7451`.
All four absence checks FAIL as expected with Chat present. Exactly six expected
enabled parent FK triggers have correct DELETE/UPDATE NO ACTION definitions;
exactly two Realtime memberships have expected columns and null row filters.
These are CH-supplied live results, not agent-executed database tests.

The earlier complete rollback fingerprint comparison remains **unconfirmed**;
the prospective comparison does not prove it retroactively. Runtime messaging,
cross-account authorization, concurrency and Realtime delivery remain untested.
Both guarded repository SQL candidates are retained unchanged. The visible demo
is unchanged; the new typed data layer awaits runtime acceptance and UI wiring.
See [Phase 3 acceptance and integration](chat_phase3_runtime_acceptance.md).

Latest Phase 5/6 status: CH's two messaging exports confirm the same QA
conversation, two-way typed messaging, idempotent replay, actual Realtime events
and own cursor updates. Remaining partial checks are explicitly UNVERIFIED in
[the evidence review and real UI notes](chat_phase5_runtime_review_and_phase6_ui.md).
No blocking issue was found; the authorized real Messages UI, application entry
points and repository reconciliation are implemented without backend changes.
Older “demo unchanged / pending integration” statements below are historical.
No additional live test writes, accounts or fixtures were created by the agent.

Current approval update: CH/KZ explicitly authorized the debug-only trial for
application `fb352472-8a41-45cf-a9a6-5e70e25e66e8` and the two recorded actors, with
one fixed agreed message each. The tester now enforces that scope at controller
and RPC boundaries, verifies the application's returned conversation and fresh
capabilities, pins deterministic request IDs across clients/restarts, and stops
on access/read-only rejection. Exact history/read-cursor/Realtime/notification
evidence buttons are documented in Phase 3. No live write was executed by the
agent; no backend SQL, business rules, dependencies or production demo changed.
Earlier locked/pending-approval status below is retained as history.

Paired evidence update, 13 November 2026: employer JSON confirms active employer
`50c0d35f-c1cd-4fa1-b864-6f6e1e833fd0`, a successful typed empty Chat list and
locked writes. CH confirmed the exact QA application UUID/hired state through
the existing Employer Applications screen, supporting ABC management context and
its existing verified-company access gate. Company restriction row/state is not
in the available exports; full send eligibility remains subject to the deployed
RPC. Both participant IDs are now bound in the proposed narrow approval. No
approval has been supplied, no code unlocked and no live writes executed.

Latest CH runtime evidence, locally inspected 13 November 2026: seeker JSON
confirms active `job_seeker`, a typed empty conversation page (limit 1, no cursor),
and four existing application IDs including `fb352472-8a41-45cf-a9a6-5e70e25e66e8`.
These limited read-only checks passed through the actual Dart runtime. CH reports
the selected ABC Company QA application is hired; the export records IDs only.
Full Chat eligibility and the corresponding employer UUID/management context are
not yet verified. Nonempty parsing/history/pagination, messaging and Realtime
remain unconfirmed. Phase 3 records the exact remaining reads and a proposed
narrow CH/KZ approval; all tester writes remain locked. No agent live calls.

Current acceptance preparation: a temporary debug-only authenticated Flutter
tester now reuses the completed data layer, supports real typed reads/pagination,
optional Realtime event observation and credential-free evidence copying. CH
reports both accounts can log in and share an existing application. No agent live
requests were made; acceptance awaits CH's tester results. Create/send/retry/read
marking remain disabled behind fixed approval guards in the tester. SQL and the
normal demo/navigation remain unchanged; see Phase 3 for the short launch steps.

13 November 2026 read-only runtime acceptance attempt: **BLOCKED** before any
live request. No authenticated participant runtime/credentials were supplied;
connected-session discovery found none, and available tools cannot access CH's
signed-in browser. Real response parsing, retrieval, pagination, account isolation
and error checks remain unverified. The Phase 3 document records each blocked
check and the existing-account/runtime prerequisites. No business writes or
database/code changes were performed. Messaging acceptance is not yet cleared;
unencrypted pending storage, device restart, cross-tab acceptance and Realtime
observation remain outstanding, as does the historical full rollback comparison.

The remainder records historical preparation and its then-current restrictions;
earlier “not deployed” statements below are historical, superseded by this status.

12 November 2026. Prepared for CH/KZ review, **not deployable yet**. The agent has
executed no SQL, PostgreSQL tests, deployment or production mutation. CH manually
ran the read-only Section 6 inspection and supplied its results for Phase 2B.
Flutter integration is Phase 3; the existing demo is unchanged.
This is a focused revision of the existing candidate. All five public RPC
signatures, table columns and history-preserving foreign keys remain unchanged.

## Deliverables and evidence

- `supabase/migrations/20261112000100_chat_backend_foundation_candidate.sql`
- `supabase/diagnostics/chat_phase2_catalog_verification.sql`
- `supabase/diagnostics/chat_phase2_static_check.ps1`
- `supabase/diagnostics/chat_phase2_rollback_validation_candidate.sql` (guarded, unexecuted)
- `supabase/diagnostics/chat_phase2_post_rollback_verification.sql` (read-only, unexecuted)
- `supabase/diagnostics/chat_phase2_ddl_safety_inspection.sql` (read-only, unexecuted)
- This document, including the deployment checklist and security test plan.
- Phase 1 audit addendum in `docs/chat_phase1_backend_foundation.md`.

The user's Phase 2 request supplies authoritative manual live-catalog results:
application/job/user/company identities and enums; one current membership per
user with owner/employer role and **no membership_status column**; the exact
semantics of `can_manage_company_jobs(uuid)`; application-transition row locks;
company restriction locks; both notification list overloads and both mark-read
functions; and an existing empty `supabase_realtime` publication. These are
user-verified results, not live inspections independently executed by the agent.

Repository reconciliation:

- `lib/features/applications/{my_applications_repository,employer_applicants_repository}.dart`
  consume the supplied eight statuses and recruitment contracts.
- `lib/features/jobs/job_postings_repository.dart` gates Employer UI through
  active role, owner/employer membership and verified company. Database authority
  remains the existing helper, not that UI gate.
- `lib/features/notifications/notifications_repository.dart` explicitly sends
  `p_limit: 50, p_offset: 0` to the two-argument list overload, and sends
  `p_notification_id` to boolean `mark_notification_read`. No adapter change needed.
  `mark_my_notification_read(uuid)` returning void also exists live; the old
  checked-in migration is partial evidence, not a reason to rename either RPC.
- `supabase/migrations/20261030000100_restore_employer_registration.sql` has an
  owner-protection membership DELETE/UPDATE trigger and owner-role protection.
  It does not establish complete staff-removal/deletion workflows.
- `docs/membership_c3/candidate/002_coordinated_release_candidate.sql` embeds
  historical moderation source: Admin/account permissions, job FOR UPDATE, then
  moderation-state FOR UPDATE or INSERT; status values unflagged, flagged,
  under_review, cleared, restricted. The complete historical body is not asserted
  identical to deployed SQL; CH's Phase 2B results now confirm its relevant
  job-first FOR UPDATE protocol before state UPDATE/initial INSERT. Chat depends
  only on job_id and restricted status, not an absent state-row lock.
- Current account-status SQL (`20261105000300_admin_user_management.sql`) locks
  users in ID order. Historical company restriction SQL locks actor, company,
  restriction. Phase 2B establishes the supported moderation writer boundary
  below; it does not certify arbitrary privileged/dynamic mutation paths.
- KZ's authoritative Phase 2A confirmation resolves **current supported lifecycle
  compatibility**: set_user_account_status supports suspend/reactivate; deactivated
  remains displayable/filterable, not a new Admin action. Company restrict/restore
  preserves company/members. Applications change status or, after hiring, use
  engagement closure. There are no exposed permanent account/company/application
  deletion workflows. Account Settings disables deletion. Authenticated membership
  access is read-only; no deployed Employer removal UI/RPC was found. Owner deletion
  is protected by the existing trigger. None of this proves that privileged manual
  deletion/cascades or a future privacy workflow is safe.
- Employer signup calls Supabase Auth signUp in `lib/features/auth/sign_up_page.dart`;
  role triggers are in `20261030000100_restore_employer_registration.sql`.
  Company onboarding calls `submit_company_for_review_v2` from
  `lib/features/company/create_company_page.dart`. Historical
  `docs/membership_c3/historical_function_evidence.json` contains an older
  submit_company_for_review owner-membership INSERT; the coordinated candidate
  embeds historical v2 onboarding as well. These establish discovery leads, not
  deployed staff reassignment/removal protocols. The owner-protection trigger
  covers INSERT/UPDATE/DELETE; the owner-role trigger rejects changing an owner's
  Employer role. No current reassignment workflow was established. The unexecuted
  worker-membership lifecycle proposal is not a dependency.

New authoritative Phase 2B evidence (user-supplied CH live inspection):

- Deployed `update_job_moderation(uuid,text,text)` is SECURITY DEFINER with empty
  search_path and supports flag/start_review/note/clear/restrict/restore. It locks
  the existing job FOR UPDATE, checks conflicts, then locks/updates the moderation
  state or INSERTs its initial row. Both mutation paths hold the parent job lock.
- Moderation state has RLS, postgres-only explicit table ACL, no policies and no
  non-internal moderation-table triggers in the returned catalogue results.
- Membership has RLS, postgres/service_role full ACLs and authenticated SELECT
  only. The enabled owner-protection trigger covers INSERT/DELETE/UPDATE and
  prevents owner removal or owner role/company/user reassignment. Current owner
  onboarding locks its relevant user before creating company/membership.
- Existing `can_manage_company_jobs` is unchanged. No conflicting supported
  moderation writer was identified in the supplied results or repository review.
  Source discovery is not proof that external/dynamic privileged SQL cannot exist.

No collisions with the proposed chat tables/RPCs were found in repository code;
the supplied live inventory reports no chat tables. Candidate CREATE statements
reject conflicting tables and schema; preflight rejects any public RPC-name
collision, including alternative overloads. Nothing is silently replaced.

## Release guard and clarified retention compatibility

An unconditional exception immediately after BEGIN stops execution **before any
DDL**. There is no session setting or bypass flag. The remainder is concrete
review SQL, not an approved release. Do not run `supabase db push` over the
migrations directory. The guard must remain until CH/KZ approve a revised,
tested release artifact; removing it alone does not resolve the blockers.

KZ confirmed retaining ON DELETE NO ACTION for application,
conversation, sender-user and read-user/message foreign keys. This preserves
history and prevents silent cascading erasure. It can also prevent hard-deleting
an application, message sender, read-state user, or an upstream cascading
job/company/Auth user. Current suspension/reactivation, restriction/restore,
application status/withdrawal and engagement closure workflows preserve references
and are compatible. An unknown current hard-delete UI is **not a remaining blocker**.
Permanent deletion is outside current application scope; future privacy/deletion
work requires explicit Chat and dispute-evidence retention review. Privileged
Dashboard/service-role maintenance is not a normal application deletion workflow.

Messages and their application/sender references are evidence. Read cursors are
personal UI state, not evidence that someone read a message; they could have a
different future retention policy. Their NO ACTION FKs are unchanged in this
revision so no cleanup/deletion lifecycle is silently introduced. No nullable
sender IDs, anonymization tables or cascading deletion were added. The unchanged
guard's original deletion-review wording is historical: current lifecycle
compatibility and supported moderation-writer evidence are now clarified. Final
candidate approval and an approved validation/release approach remain outstanding.

## Tables and order

All three tables have RLS, postgres ownership (preflight requires current_user
postgres) and no ordinary write grants. Only conversations/messages have
authenticated SELECT under current-participant policies. Read-state access is
RPC-only, with no direct SELECT grant or policy. RLS is intentionally not forced: trusted postgres-owned
definer routines must read the underlying relationships without recursive RLS.

| Table | Columns/invariants |
| --- | --- |
| `public.chat_conversations` | conversation_id UUID PK/server default; application_id UUID unique/non-null FK; created_at server timestamp; last_sequence bigint >= 0, initially 0; nullable last_message_at consistent with whether messages exist |
| `public.chat_messages` | message_id UUID PK/server default; conversation_id FK; sender_id users FK; body text; client_request_id UUID; sequence bigint > 0; sent_at server timestamp; unique(conversation_id,sequence); unique(conversation_id,sender_id,client_request_id) |
| `public.chat_read_states` | PK(conversation_id,user_id); last_read_sequence bigint > 0; updated_at server timestamp; composite FK(conversation_id,last_read_sequence) to a real message |

No employer ID is fixed at initiation. Worker/job/company are always derived
through the application and job. No shifts or engagement closure records are
written or consulted: a hired application's chat continues after closure and
across additional shifts, including when the posting is closed.

Application uniqueness handles concurrent initiation. Each send increments the
conversation sequence under its lock, so timestamps are never the read cursor or
pagination identity. Last activity time is clamped to the preceding activity time
if the server clock moves backward. The activity index plus PK/unique indexes
cover application lookup, stable list order, history/unread scans and replay.
No message editing/deletion, attachments, presence or receipts are implemented.

## Authorization and Option B

Every retrieval/RLS helper requires an active current caller: owning Job Seeker
or Employer passing the unmodified `can_manage_company_jobs` for the derived
company. Administrator has no ordinary access, regardless of Admin permission.
Current membership is checked afresh; a missing/changed Employer membership denies
access. This is defensive authorization, not a newly introduced removal workflow.
No invented active/revoked flag or dependency on membership_c3 exists.

| Current application / restrictions | Existing history | First creation / new send |
| --- | --- | --- |
| submitted, shortlisted, interview, offered; normal | Authorized participants | Allowed |
| hired; normal | Authorized participants | Allowed |
| rejected, declined, withdrawn | Authorized participants | Denied |
| pre-hire; company or job restricted | Authorized participants | Denied |
| hired; company or job restricted | Authorized participants | Allowed, also after engagement closure |
| missing/invalid company restriction record, including hired | Authorized participants | Denied with explicit reason |
| company unverified | Owning active worker retains history; employer fails existing helper | Denied for either side |
| inactive/wrong-role caller, foreign worker/company, removed employer member, Admin | Denied | Denied |

Company verification is not bypassed by the hired exception. Blocking worker
creation/sends while company verification is absent is the conservative application
of that requirement; an active owning worker can still read existing history.
Company/job administrative restriction differs from company verification.
Unknown application statuses also fail closed for writes. No new status is added.
Missing moderation row is treated as no recorded job restriction, matching the
existing EXISTS-style recruitment rule; the gap is protected during mutations.

Read-only reason codes: `company_restriction_missing`,
`company_restriction_invalid`, `company_unverified`, `application_terminal`,
`application_status_unknown`, `recruitment_restricted`, in that precedence order.
Unauthorized callers get the same `Chat unavailable`/42501 outcome for guessed
or nonexistent IDs. The filtered conversation list returns no unauthorized rows.
Retrieving an existing conversation is permitted in read-only states; no row is
created in them. Mark-read remains allowed when history is readable.

## Exact RPC contract

These five public functions are SECURITY DEFINER, fixed empty search_path, fully
qualified, and executable by authenticated only (plus their trusted owner).
All input identities are application/conversation/request/cursor selectors,
never trusted sender, company, worker, status or timestamp assertions.

| Signature and parameter names | Return / behavior |
| --- | --- |
| `get_or_create_chat_conversation(p_application_id uuid)` | UUID. Lazily creates only when eligible, or returns the authorized existing conversation even if read-only. |
| `list_my_chat_conversations(p_limit integer DEFAULT 50, p_before_activity_at timestamptz DEFAULT NULL, p_before_conversation_id uuid DEFAULT NULL, p_conversation_id uuid DEFAULT NULL)` | Table described below; limit 1–100. Cursor time and ID must both be null or both present. Optional conversation filter supports direct-route capability lookup without scanning every page. |
| `list_chat_messages(p_conversation_id uuid, p_limit integer DEFAULT 50, p_before_sequence bigint DEFAULT NULL)` | Table(message_id uuid, conversation_id uuid, sender_id uuid, sender_name text, body text, sent_at timestamptz, sequence bigint). Latest first, exclusive earlier sequence cursor; limit 1–100. |
| `send_chat_message(p_conversation_id uuid, p_client_request_id uuid, p_body text)` | One table row: message_id uuid, conversation_id uuid, sender_id uuid, body text, sent_at timestamptz, sequence bigint. Server identity/order/time; identical retry returns the committed row. |
| `mark_chat_conversation_read(p_conversation_id uuid, p_message_id uuid)` | bigint resulting monotonic cursor. ID must identify an existing message in that conversation. |

Conversation list columns: conversation_id uuid, application_id uuid, job_id uuid,
job_title text, company_name text, worker_name text, application_status text,
created_at timestamptz, activity_at timestamptz, last_message_preview text (160
characters), last_message_at timestamptz (nullable), last_sequence bigint,
unread_count bigint, can_send boolean, read_only_reason text (nullable).
Sort activity_at descending then conversation UUID descending; cursor is exclusive.
Activity changes can move a thread ahead of a page: refresh page one and deduplicate
IDs. Do not treat a mutable activity list as a repeatable historical snapshot.

History sender_name is the current user's stored display name, not a historical
snapshot. Stable sender_id preserves the actual sender. No email/phone/resume,
other members' read states or private Admin fields are returned. Authenticated
direct SELECT also exposes a participant's message request UUID and server metadata;
request UUIDs are not credentials and cannot authorize a send for another sender.

Text: validate 1–4000 PostgreSQL characters/code points, not UTF-16 units or
grapheme clusters. Reject null, empty and Unicode-White_Space-only bodies
(explicit whitespace code points). Preserve body bytes/spacing and valid Unicode;
do not normalize, trim or truncate. Empty/oversized/request mismatch = 22023.
Read-only create/send = 55000. Access denied = 42501. Lock contention = 55P03;
relationship drift = 40001. Any locked operation (create/send/replay/mark-read)
at isolation other than READ COMMITTED rejects with 25001. Unexpected integrity/notification errors propagate
and roll back the whole transaction.

## Idempotency, notifications and cursors

Scope is (conversation,sender,client request UUID), so the same UUID in another
conversation represents a separate send. The exact same body returns its original
row; changed content rejects. The sequence and notification inserts occur only on
the first insert. No separate dedup ledger is necessary while messages are immutable
and undeletable by clients. If a message committed but eligibility later ended,
the identical replay succeeds **only if current history authorization remains**;
it reconciles a past write without sending again. Suspension, membership loss or
other loss of read authorization prevents replay disclosure. Missing restriction
records likewise prevent fresh writes, but do not conceal an authorized old result.

Message plus activity metadata plus notification rows commit atomically. Failure
of notification insertion rolls everything back. Employer sends notify only the
active Job Seeker applicant, if still in that role. Worker sends notify every
eligible Employer owner/employer member of the verified derived company selected
by the locked recipient snapshot described below.
No coworker notifications for employer-originated messages. Sender excluded;
one membership per user plus recipient-user SELECT gives at most one row each.
Zero eligible recipients is permitted: durable history remains for later access.
New staff receive no retroactive inbox notifications. Newly authorized staff see
all historical incoming messages as unread until marking their own cursor.

Existing `notifications` receives only user_id, `chat_message`, `New message`,
generic body and server time. Worker body: `You have a new message about your job
application.` Employer body: `You have a new message from a job applicant.`
No new inbox columns, emitters on existing objects or RPC changes. Generic inbox
rows may remain after membership removal; they contain no private conversation ID
or body. Inbox read state and chat cursors are separate; no deep links in Phase 2.

No read-state row means cursor 0. Unread counts exclude the current user's own
sends. Marking a real message advances to GREATEST(old,selected sequence), thereby
marking messages up to that point; stale/out-of-order marks cannot move it back.
The server proves membership of a real cursor message, not that a human read it.
No shared employer/company read flag or read-receipt promise exists.

## Concurrency and security boundaries — Phase 2B

Phase 2A already removed the global membership lock and narrowed retrieval/read
locking, but fresh pre-hire create/send still used global moderation SHARE NOWAIT.
Phase 2B removes that final global lock. **Neither global table lock remains.**
The existing relevant job SHARE NOWAIT lock is reused, rather than adding another
job lock or changing teammate writers. Standard automatic relation locks acquired
by SQL still exist; no explicit global write-blocking LOCK command is introduced.

`lock_participant(uuid)` first requires READ COMMITTED and checks authorization, then locks only caller user
FOR SHARE; for an Employer, the caller's matching membership and company FOR SHARE;
then the derived job and application FOR SHARE. All explicit locks use NOWAIT.
Fresh authorization and relationship comparison follows, so a concurrent role,
status, membership/company/job relationship or verification change either wins
before the lock and is rechecked, waits until this transaction ends, or produces
a retryable conflict. It locks no other members, recipients, restriction rows,
moderation state or conversation activity. The application/job SHARE locks protect
derived identity and conflict with their updates while coexisting with send/read.
Every required acquisition immediately checks FOUND: missing actor, Employer
membership or Employer company raises 42501; missing job/application raises
40001. A later authorization query cannot rescue a missing lock by seeing a newly
inserted membership. The final current-authorization and original relationship
identity-drift checks remain. This is defensive invariant hardening, not evidence
of a demonstrated exploit in the previous candidate. First-create application
lock upgrades and fresh-write company locks likewise check FOUND (40001); a
missing restriction row fails immediately with 55000/company_restriction_missing.
An invalid existing restriction row remains write-ineligible through the unchanged
final capability check. No message, status change or notification is committed
on any of those failures.

`get_or_create_chat_conversation` first uses a single authorized SELECT at its
statement snapshot. An existing thread returns immediately, including read-only
states, with no explicit mutation locks. This uses the same MVCC read boundary as
history/RLS reads: revocation committed before the statement is enforced; an
already authorized response cannot be recalled by a later revocation. Only an
absent thread invokes fresh-creation locks, upgrades its application lock to
NO KEY UPDATE NOWAIT, rechecks existence/eligibility and creates once. The unique
application key remains the database invariant; concurrent upgrades may both
fail and retry, rather than wait in a lock-upgrade cycle.

Send obtains participant locks, then conversation NO KEY UPDATE NOWAIT. An
authorized matching replay returns before fresh-write/recipient locks. A new
send locks company and existing restriction row FOR SHARE, retains application
SHARE and the existing job SHARE protection. It re-evaluates Option B eligibility
**after** those locks in a separate SQL statement. The private write helper only
acquires participant/job locks itself for first creation; send already holds them
from its authorization/replay stage and does not acquire them twice. Account/member
SHARE locks conflict with non-key updates/deletes, unlike KEY SHARE. Existing
application transitions' FOR UPDATE and company restriction/verification updates
therefore cannot silently pass an in-flight send's authorization point.

Notification recipient selection is one statement snapshot **after** sending
eligibility is locked. Worker sends select eligible account/member joins ordered
by user UUID, `FOR SHARE OF recipient, cm NOWAIT`. Employer sends select the
eligible applicant account FOR SHARE NOWAIT. Row locking uses PostgreSQL's
READ COMMITTED recheck rules for rows changed since snapshot; a conflicting
in-flight writer causes 55P03 and rollback. The selected IDs are saved in a local
UUID array. Notification insertion consumes **only that array**, never a fresh
membership scan. Selected accounts/memberships remain locked through commit.
New additions or newly eligible accounts not visible to that candidate snapshot
can be omitted, with no retroactive notification requirement. Ineligible accounts
are not locked, and zero recipients is valid. A retry of a committed message does
not take a new snapshot or duplicate notifications. Concurrent suspension/removal
after a recipient lock is ordered after this transaction, not silently ignored.

`mark_chat_conversation_read` takes only participant locks, validates the real
conversation/message pair, and upserts its own cursor with GREATEST. It does not
lock conversation activity or request fresh-send/moderation/restriction eligibility.
Same-user cursor upserts serialize automatically; different staff cursors remain
independent. Send uses conversation NO KEY UPDATE, so FK KEY SHARE checks on a
new read-state row can coexist with its metadata update. Application SHARE locks
for send and mark-read also coexist. No cursor move backward or future cursor is
possible. Explicit conflict remains retryable; implicit upsert/FK checks may wait.

Supported moderation boundary: the verified `update_job_moderation` RPC holds
its job FOR UPDATE before UPDATE or initial INSERT, with no returned ordinary
direct-write grants/policies or non-internal state-table triggers. Chat's job
FOR SHARE conflicts with that lock. If moderation is in progress, Chat fails
NOWAIT with 55P03 and retries as a whole operation. If Chat acquired its lock
first, moderation waits until Chat commits/rolls back. Because the existing job
is the coordination point, an absent moderation-state row does not create a gap.
There is no supported DELETE/upsert path established by these results; any future
such writer must lock the same job first and be reviewed before concurrent use.

Moderation of Job A no longer imposes a moderation-table lock on Chat for Job B.
Unrelated jobs can still legitimately share company, account or recipient records;
this is not a claim that every cross-job conflict is eliminated. Hired writes
also acquire the existing job lock: active moderation may yield a transient
retry, but a committed restricted status does not remove their Option B eligibility.

Privileged Dashboard/service-role/external/dynamic writers outside this supported
RPC boundary are not certified by the catalogue search. They must obey the same
parent-job protocol or be excluded from concurrent operation; adding a supported
writer that bypasses it invalidates the safety argument and blocks release.
No teammate-owned writer/trigger is modified to enforce this protocol. Section 6
is retained as baseline/drift discovery, not an outstanding request to repeat
CH's completed inspection or a proof of exhaustive writer coverage.

Lock order was compared with supplied application FOR UPDATE contracts, checked-in
set_user_account_status's ordered actor/target locks, supplied company/restriction
locks, newly verified job-moderation locks, user-first onboarding membership inserts and
owner/role protection triggers. Chat's NOWAIT acquisitions abort on differing
orders rather than wait for known conflicts. Recipient locks happen after sender,
job/application/conversation locks; ordered recipients reduce contention but do
not establish a universal cross-module lock order. FK checks, installed triggers,
implicit upsert waits and uninspected remote paths remain runtime risks. No existing
writer, trigger, table permission or membership workflow is changed.

See [PostgreSQL's lock compatibility documentation](https://www.postgresql.org/docs/current/explicit-locking.html).
No full system-wide deadlock or high-throughput guarantee is claimed. Retain UUIDs
and back off/retry whole transactions on 55P03/40001; never retry a partial send.

All locked operations **require READ COMMITTED**, enforced once in the shared
`lock_participant` helper using transaction_isolation: first conversation creation,
fresh sending, identical replay and mark-read. The write helper no longer repeats
that check; send already called participant locking, and creation calls it within
the private write helper. Read-only existing-conversation fast path and ordinary
list/history stay unchanged and do not acquire this guard. Preliminary application_access reads are not
the final eligibility decision. The VOLATILE PL/pgSQL caller runs its final
application_access SELECT as a separate query after the job/company/restriction
locks. Its STABLE access function uses that new calling-query snapshot, so it
observes moderation committed before lock acquisition; no supported moderator
can change the same job's state until the held SHARE lock is released. At
REPEATABLE READ, a parent lock that does not update the parent cannot refresh an
older moderation snapshot. Locked operations are therefore rejected (25001),
not assumed safe because a serialization error might occur. Identical authorized
replay still reconciles a committed message after loss of fresh-send eligibility,
but now shares the same isolation requirement as mark-read and fresh writes. Correct the transaction
isolation before retrying 25001; do not blindly retry it in the same transaction.
See [transaction isolation](https://www.postgresql.org/docs/current/transaction-iso.html)
and [function snapshot rules](https://www.postgresql.org/docs/current/xfunc-volatility.html).
Do not catch and ignore permission, integrity or notification failures. Direct privileged SQL,
TRUNCATE, disabled triggers, table-owner and service-role administration remain
trusted maintenance concerns, not permissions granted to Flutter.

Only the boolean `jobmate_chat_private.can_read_conversation(uuid)` is granted
to authenticated for RLS. The access/participant-lock/write-lock/body helpers are not callable by clients.
The private schema has no default PUBLIC usage; no dynamic SQL, unrestricted
views or ordinary write policies exist. Every new routine has explicit revocation
of PUBLIC/anon/authenticated/service_role defaults before the intended grants.
No pre-existing table/routine/policy grant is altered. Audit effective inherited
privileges and deployment default grants, not only ACL text.

## Realtime and Phase 3 strategy

The candidate adds only `chat_conversations` and `chat_messages` to the existing
publication. Settings, other tables, notifications and private read-state feeds
are unchanged. Message use is INSERT-only; conversation INSERT and activity UPDATE
support the list. No DELETE event or replica-identity-full requirement is introduced.

Direct SELECT is limited to those two tables. Read states have neither direct
SELECT nor a SELECT policy and are not published; authorized list/mark RPCs cover
their UI use. `client_request_id` is not needed in the history RPC or participant
UI, but full message-table SELECT is deliberately retained: column-level grants
and deployed Realtime payload/authorization behavior have not been validated here.
It is a scoped non-secret idempotency selector, not an access credential; sender
identity still comes from auth.uid(). This is an explicit compatibility tradeoff,
not a claim that column grants cannot work or have been tested. Future payload
minimization must verify both RPC/direct SELECT and actual Postgres Changes behavior.

Future Flutter: subscribe to authorized conversation INSERT/UPDATE for list
invalidation and message INSERTs for the open thread; filters reduce traffic but
are not authorization. Re-read list/history through RPCs, deduplicate message IDs
and order by sequence; fetch older pages with exclusive sequence cursor. After
reconnect/resume, reconcile persistent history and unread counts before claiming
the thread is current. No guaranteed delivery/read receipt from a Realtime event.
After marking read, refresh local list. Another device's cursor changes are not
published; refresh on resume, navigation and periodic foreground reconciliation.

Account changes must unsubscribe and clear messages/cursors/drafts/request state
for the old actor. Recheck capabilities on resume, send, selection and periodic
foreground refresh; on denial, clear inaccessible state and leave the thread.
No membership lifecycle feature or removal broadcast is introduced. Previously
downloaded content cannot be recalled; client clearing is a privacy measure, not
server authorization. Test already-open subscriptions with revoked memberships
and accounts, including queued events and JWT refresh.

Supabase documents subscriber-by-subscriber authorization of Postgres Changes;
private history must still be recovered through authorized database reads.
DELETE handling has distinct limitations and is outside this append-only design.
See [official Postgres Changes documentation](https://supabase.com/docs/guides/realtime/postgres-changes).
No live Realtime isolation result is claimed.

## Catalogue verification revisions

Section 0 has 12 compact check rows: exact tables/columns/types/nullability, RLS
and owners, required PK/unique/FK definitions and NO ACTION rules, indexes, exact
RPC/helper signatures, security/return base types, effective table/column/function
and schema privileges, exact two SELECT policies, targeted-lock source shape, and publication settings/member
tables. Before any installation, new-object checks report PASS_EXPECTED_ABSENT
and phase pre_deployment, **not a post-deployment security pass**. Publication
settings are checked even then. Any partial installation switches to post/partial
requirements and reports FAIL for missing/wrong objects. Detailed defaults,
function arguments/results/bodies and catalogue definitions remain available for
manual review; a summary PASS cannot prove their runtime semantics.

Existing-object fingerprints now include formatted type modifiers, column ACLs,
identity/generated attributes and collation, separate column-grant output, and
trigger enabled state. Compare before/after exports; without a baseline, unchanged
objects cannot be proved. Section 6 is the already-completed targeted live query:
it returns membership/moderation references (including INSERT, UPDATE, DELETE,
MERGE/upsert), relevant account/onboarding/application functions, attached triggers,
direct-writer ACLs and policies, and bounded forward/reverse catalogue routine
dependencies. Manually follow helper/dynamic/external calls. These are discovery
leads, not proof of exhaustive writer coverage. CH supplied the relevant verified
parent-job protocol separately; future baseline exports can check for drift.

## Manual deployment and verification checklist — not authorization to deploy

1. Keep the guard in place. KZ clarified retention and CH completed Section 6's
   inspection. Review this Phase 2B candidate against that supported writer
   boundary, READ COMMITTED requirement and complete lock sequence. No additional
   live query is required just to resolve the old moderation-evidence blocker.
   Future permanent deletion or a new privileged writer is separately reviewed.
2. Export the read-only Phase 2 diagnostic results **before** any later deployment.
   Save baseline fingerprints for non-chat routines, ACLs, policies, constraints
   and triggers, plus publication configuration. Check current default privileges
   and any other exposed schemas. Catalogue output is not runtime security proof.
3. There is currently **no separately approved PostgreSQL test environment**.
   The practical work available now is offline syntax/type/privilege review,
   structural checks and existing local Flutter regressions, plus CH's manual
   read-only catalogue query. These do not compile the candidate. Do not install
   a database, create fixtures or propose running DDL in a transaction on production.
   CH/KZ must explicitly approve a validation approach before removing the guard.
   If approved existing non-production capacity and identities later become
   available, use them for compilation and the runtime plan below. Until then,
   compilation, concurrency, cross-account isolation and Realtime revocation
   cannot be established under current constraints; keep these release gates open.
4. Only after tests and explicit CH/KZ release approval, agree the final version
   and dependency baseline. Review a final diff; do not apply unrelated pending
   migrations or rerun previous migrations. Migration execution is a later manual
   CH action, outside this request.
5. Export diagnostics again. Require all expected chat columns/constraints/indexes,
   exactly two SELECT policies, postgres owners, empty search_path on definers,
   authenticated-only intended execution, no ordinary writes/anon reads, RPC-only
   read state and publication additions limited to the two tables. Compare all
   pre-existing fingerprints; investigate any difference. Results cannot prove
   unchanged objects without the before export.
6. Test real-JWT RPC/direct SELECT/write denial and two-device Realtime isolation
   only in the approved environment. No production fixtures. Keep Flutter demo
   until backend review is accepted; Phase 3 then integrates the five contracts,
   persistent request UUIDs, correct Unicode limit, safe errors and existing
   navigation/draft guards. Do not enable attachments or background push.

## Focused runtime security plan (not executed)

Use existing authorized isolated identities only, never production fixture creation.
Assert persistent rows and notification counts as well as RPC results:

| Cases | Expected result |
| --- | --- |
| Worker after submission; owner and employer staff initiate | One application conversation; same UUID on repeated/concurrent attempts after retry; no hiring prerequisite |
| Same company, different applications; multiple shifts | Separate application threads; all shifts of one application retain one thread |
| Foreign worker/company, Admin, wrong role, guessed/missing UUID | No row/content or send/create; uniform denial; optional list filter returns empty |
| Staff removal, company move, role change, suspension/deactivation, company unverification | Fresh reads/sends/replays denied where required; owning active worker may read retained history after company unverification |
| rejected, declined, withdrawn | Existing history/retrieve/read cursor work; no first conversation or fresh send |
| Company/job restricted before hiring | Existing read-only, no first creation/send; no restrictive job-visibility helper grants private chat access |
| Hired during either/both restrictions, closed posting, engagement closure | First creation/send/history work; missing restriction or unverified company still blocks writes |
| Missing/invalid restriction record, unknown application status | Explicit fail-closed write reason; authorized history remains |
| Null/empty/ASCII whitespace/NBSP/Unicode whitespace/4001 code points | Rejected, no message/sequence increment/inbox row; 4000 valid Unicode/emoji and surrounding whitespace preserved exactly |
| Sender/time spoof attempts, direct INSERT/UPDATE/DELETE/TRUNCATE | No accepted spoof fields; ordinary writes denied; server IDs/time used |
| Same request, same/different body; lost response; terminal-before-replay | One original message/inbox row per recipient on matching authorized replay; different body rejects; eligibility loss never creates a fresh message |
| Worker/employer sends with multiple staff; inactive staff; no eligible recipients | Generic inbox only to intended opposite side, no coworkers/unrelated/Admin/sender; one each, or zero eligible; no private body/ID leaked |
| Forced notification insertion failure | Entire message/activity/notification transaction rolls back; retry can then create once |
| Concurrent duplicate/distinct sends and initiation | 55P03 safe retry or committed result; unique message keys/sequences and one conversation; no duplicate notifications |
| Send races rejection/withdrawal/company restriction/moderation insertion | Authorized outcome ordered by locks, or rollback/retry; no ineligible fresh send |
| Send races account/member update/addition; privileged removal as defensive scenario | Sender protected by targeted locks; recipient candidate snapshot fixed and locked; additions after snapshot omitted without retroactive notifications; no removal UI/RPC introduced |
| Read same/older/foreign/future cursor, two sessions in reverse delivery order | Real conversation message only; cursor never decreases; own sends excluded from unread |
| Two employer members; newly added member | Independent cursor/unread; historical incoming messages initially unread for new member; no retroactive notifications |
| Unauthorized Realtime; remove member/suspend during open subscription | No new unauthorized message content; evaluate queued events/token refresh separately; client clears old state on denied capability |
| Reconnect/offline recipient; conversation activity changes during pagination | RPC recovers durable messages/counts, orders by sequence, deduplicates list IDs; no fictional online/read receipts |
| Table/column ACLs, helper calls, policy interactions | No hidden inherited writes, no PUBLIC/anon execution, no internal helper exposure, no direct read-state SELECT; authorized unread/mark RPCs still work |
| Retention and current lifecycle | KZ confirms status/restriction/closure compatibility; NO ACTION references retained. Future hard deletion needs a separate privacy/evidence review, not a new Chat deletion workflow |
| Same-job moderation while fresh pre-hire create/send is attempted, both operation orders | Job SHARE conflicts with verified writer's FOR UPDATE: 55P03/whole-call retry or moderation waits; final eligibility sees authoritative committed status |
| First moderation-state INSERT when no row existed, both operation orders | Parent job locks coordinate even without a state row; no missing-row race or fresh ineligible message |
| Job A moderation versus Job B Chat, including separate companies | No global moderation/membership lock; Job A lock alone does not block Job B. Record any legitimate shared-company/account contention separately |
| Hired create/send during and after moderation, closed posting and engagement closure | Same-job transient contention may retry; a committed restriction retains hired Option B eligibility and atomic notifications |
| READ COMMITTED versus an older REPEATABLE READ/SERIALIZABLE snapshot | Creation/send/replay/mark-read share the same isolation guard; other isolation levels reject with 25001 before locked mutations; read-only fast path/list/history remain unchanged |
| Retried lock contention with the same request UUID | Failed call leaves no message/activity/inbox changes; after retry only one committed message and intended notification per recipient |
| Retrieval/replay/mark-read during unrelated onboarding/moderation operations | No global membership/moderation lock; authorization and own-cursor semantics remain unchanged |
| Mark-read versus send and other staff mark-read | No shared conversation activity UPDATE lock; compatible SHARE/NO KEY UPDATE/FK locks; own cursor only, monotonic even with reversed request arrival |

## Local validation record

Historical checks executed during Phase 2 (before the Phase 2A revision):

- `& .\supabase\diagnostics\chat_phase2_static_check.ps1`: passed 80 offline structural
  and scope checks. Checks cover the release stop,
  permitted DDL/DML targets, no existing-object replacements/destructive commands,
  RLS/policy scope, safe routine headers, explicit intended publication additions,
  paired dollar quotes, and metadata-only SELECT/CTE diagnostics. This is a lexical
  structural checker, **not** a PostgreSQL SQL/PLpgSQL compiler or security proof.
- Trailing-whitespace inspection passed for all five Chat deliverables.
- `flutter test test/notifications_repository_test.dart test/notifications_page_test.dart
  --reporter expanded`: all 18 passed.
- `flutter test test/phase3_test.dart --name 'Chat drafts|Messages at|Conversation at|Employer Conversation at'
  --reporter expanded`: all 10 existing chat-demo checks passed (320/768/1440 widths).
  The unrelated known employer-destination cases were not selected or modified.
- `flutter analyze`: exit 1, five informational diagnostics, no errors/warnings.
  Two missing-braces infos in `company_management_page.dart`, two radio deprecations
  in `sign_up_page.dart`, and async BuildContext in `engagement_closure_controls.dart`.
  All are unchanged from the Phase 1 run.
- SHA-256 comparison of 357 pre-existing files in lib/test/docs/supabase plus root
  README/AGENTS confirmed only the intended Phase 1 Chat document changed.
  Supabase temporary files were excluded from inspection and never edited.

No PostgreSQL executable/test environment was available on PATH. No SQL compilation,
runtime database/security tests, Realtime delivery/isolation tests, Android device
or browser acceptance tests ran. No database/dependency environment was installed.
No Git operation was used in Phase 2. No README, Flutter, existing migration,
pre-existing test, IDE, log or unrelated diagnostic file was modified.

### Phase 2A validation (historical)

- Updated `chat_phase2_static_check.ps1`: **107 structural/scope checks passed**,
  including the exact original unconditional guard, five unchanged public RPC
  names, two direct-read policies, RPC-only read states, targeted participant
  locks, fixed recipient-array insertion, no global membership lock and moderation
  locking limited to pre-hire writes. SQL string/parenthesis checks also passed.
  These are lexical checks, not SQL/PLpgSQL compilation or authorization tests.
- Reran the same focused notification command above: **18 passed**.
- Reran the same selected chat-demo command above: **10 passed**.
- Reran `flutter analyze`: exit 1, the same **five informational diagnostics**,
  no errors/warnings. Unrelated files were not changed to address them.
- SHA-256 baseline comparison of **363 pre-existing files** confirmed changes
  only to the five requested Chat files; no new source files or trailing whitespace.
  The release guard block itself is unchanged. Supabase temporary files were
  excluded from inspection and never edited. No Git operation was used.

Manual review covered RPC input/output types, safe definer search_path/ownership,
helper execution revocations, RLS's definer dependency, authorization snapshots,
row-lock compatibility, idempotent-return placement and atomic notification writes.
No psql/postgres/pg_config executable was available on PATH, and no approved test
database currently exists. No environment/package/account/fixture was installed
or created. Neither the candidate nor the catalogue summary/writer query was
executed against PostgreSQL. Compilation, runtime security, concurrent account/
membership/restriction changes and Realtime revocation remain unverified.

### Phase 2B validation (historical)

- Updated offline checker: **121 structural/scope checks passed**. It checks no
  explicit global LOCK commands, reused job SHARE NOWAIT protection, final
  creation/send eligibility statements after locking, READ COMMITTED enforcement,
  preserved application SHARE protection/hired exception, exact unchanged five
  public RPC parameter/type/default contracts, and the intact original guard.
  The statement scanner now masks SQL string contents before splitting statements
  so a metadata regex containing a semicolon is not mistaken for executable SQL.
- Reran `flutter test test/notifications_repository_test.dart
  test/notifications_page_test.dart --reporter expanded`: **18 passed**.
- Reran `flutter test test/phase3_test.dart --name
  'Chat drafts|Messages at|Conversation at|Employer Conversation at'
  --reporter expanded`: **10 passed**.
- Reran `flutter analyze`: exit 1, the same **five informational diagnostics** in
  unchanged company_management_page.dart, sign_up_page.dart and
  engagement_closure_controls.dart; no errors/warnings.
- SHA-256 comparison of **363 pre-existing files**: only the five authorized Chat
  files changed. No new source files or trailing whitespace; no unrelated tests,
  Flutter code, README, prior migrations, logs or teammate-owned objects changed.

These are local structural/regression results, not PostgreSQL compilation or
concurrency/RLS/Realtime runtime acceptance. CH's manual read-only inspection is
user-supplied evidence; the agent executed no SQL. No approved PostgreSQL test
environment or psql/postgres/pg_config on PATH was available; none was installed.
The documented same-job/absent-row/cross-job/Option B/status/suspension/restriction/
retry cases remain unexecuted. CH/KZ should review the final lock order, supported
writer and READ COMMITTED boundaries and explicitly agree a permitted validation
approach. Compilation, cross-account isolation, concurrent transitions, notification
rollback and open-subscription revocation remain release gates. No new live query
is requested just to repeat the completed writer inspection. The unconditional
guard remains unchanged; no deployment or Flutter integration proceeds.

## Final validation candidates — prepared only, no execution approval

CH accepts the existing business rules: either authorized party can initiate/send
immediately after Submitted, including Shortlisted; no application means no chat.
Chat does not shortlist, accept, hire or otherwise mutate application status.
Option B, terminal history-only access, 4000-character Unicode messages,
idempotency, independent cursors, generic atomic notifications and retention are
unchanged. No employer-first restriction, rate limit, attachment or new feature
is introduced. Both global locks stay eliminated and five public signatures stay
unchanged. The new work hardens required-lock/isolation invariants and prepares
validation only.

### Exact derivation and approval guards

`chat_phase2_rollback_validation_candidate.sql` is a separate, unexecuted candidate.
The original migration's exact unconditional deployment guard is unchanged.
The validation has its **own unconditional exception before DDL**; neither guard
is removed or bypassed in these deliverables. CH/KZ must approve the intended
execution target/session, DDL safety evidence and reviewed validation artifact
in a separate decision before any future execution. Do not run the guarded file
expecting it to validate the database: as delivered, it deliberately aborts.

Its marked EXACT MIGRATION BODY is copied from the final migration starting at
`DO $chat_preflight$` and ending immediately before the final `COMMIT;`. No DDL,
function body, ownership, RLS, grants or publication statement is edited in that
copy. The validation-only differences are outside it:

1. Replace the migration's BEGIN/deployment-guard wrapper with BEGIN ISOLATION
   LEVEL READ COMMITTED, validation approval guard and safety preflight.
2. SET LOCAL lock_timeout=1s, statement_timeout=15s,
   idle_in_transaction_session_timeout=60s, PostgreSQL 17 transaction_timeout=90s
   and check_function_bodies=on.
3. Reject existing Chat relations/index/schema/public RPC names before DDL.
   Compare the entire six-trigger baseline reviewed by CH below. Missing, added,
   disabled, retagged or changed handlers/ACLs/configuration abort before DDL.
   Do not disable or alter hooks to make the validation pass. The separate
   unconditional approval exception remains unchanged; reviewing hooks does not
   authorize execution or remove that guard.
4. Append a catalogue-only DO assertion wrapping the exact Section 0 summary CTE.
   Every check must report PASS in the transient installation or it raises. This
   includes tables/types/keys/RLS/indexes/routine settings and effective table,
   column, function and schema privileges. It invokes no Chat/business RPC.
5. Emit a NOTICE and explicit SELECT success marker only after all catalogue
   assertions pass, then end in ROLLBACK, never COMMIT. No accounts, fixtures, business-row inserts,
   real state changes or business mutation RPC calls are performed by the wrapper.
   Stored function definitions contain their normal write code but are not called.

The offline checker compares the migration body and assertion summary with these
marked copies, normalizing CRLF/LF and surrounding whitespace only. It also checks
that post-rollback fingerprints exactly match Section 5 of the catalogue script.
Do not hand-edit copied sections independently. After a migration or catalogue
change, regenerate the relevant marked block verbatim and rerun the checker.

### DDL safety, timeouts and SQL Editor handling

CH has now manually run `chat_phase2_ddl_safety_inspection.sql` and reviewed all
six handlers for Chat's complete planned DDL scope. The agent has executed no SQL.
Verified target: current_user/database postgres, PostgreSQL 17.11, origin mode,
six total/six enabled triggers; installed extensions btree_gist 1.7,
pg_stat_statements 1.11, pgcrypto 1.3, plpgsql 1.0, supabase_vault 0.3.1,
uuid-ossp 1.1. This supersedes the earlier blanket hook rejection. The inspection
file remains read-only and useful for drift review; it does not need repeating
merely to establish the already-supplied evidence.

| Trigger | Event / exact tags | Handler in extensions / definition MD5 |
| --- | --- | --- |
| issue_graphql_placeholder | sql_drop / DROP EXTENSION | set_graphql_placeholder() / 8da9dff6b2ae47498209d341acaeb60b |
| issue_pg_cron_access | ddl_command_end / CREATE EXTENSION | grant_pg_cron_access() / 53a44336da0ac1dd62d89dbd988e6d1d |
| issue_pg_graphql_access | ddl_command_end / CREATE EXTENSION | grant_pg_graphql_access() / 4e6d7efe4aed1b3b92063b648aa7a0cf |
| issue_pg_net_access | ddl_command_end / CREATE EXTENSION | grant_pg_net_access() / 1d06ef4fb47bb0ab6e6f8818a62013bb |
| pgrst_ddl_watch | ddl_command_end / NULL (unrestricted) | pgrst_ddl_watch() / afaad7193dcf8f81e728d2bedb85e43e |
| pgrst_drop_watch | sql_drop / NULL (unrestricted) | pgrst_drop_watch() / 4357772baf5cfcd5c6d7049585b3a537 |

All six are enabled O, trigger/handler owner supabase_admin, plpgsql,
SECURITY INVOKER and exactly empty search_path. The pre-DDL safety block compares
all names (including disabled/unexpected entries), events, enabled states/tags,
owners, schema-qualified zero-argument identities, language, security/configuration,
event_trigger return shape and complete definition MD5s. ACLs are normalized by
(grantee,privilege) with bool_or(grant-option), ordered using C collation, against
the supplied PUBLIC/postgres/supabase_admin/dashboard_user grant sets. ACL array
order and duplicate grant provenance do not affect that effective grant-set
comparison. Grantors were not supplied and are not invented as pin requirements;
the before/after export retains grantor provenance to detect later changes.

The first four hooks apply only to extension commands absent from this candidate.
The reviewed PostgREST hooks use transactional schema-reload NOTIFY; pending
notifications are discarded on rollback. There is no explicit object DROP, and
transaction rollback is not an explicit DROP command. CH found no external HTTP
or JobMate business mutation in those reviewed handlers. This is a bounded review
of those exact bodies/commands, not absence of all extension/native/external
effects. It does not authorize arbitrary future DDL. See
[PostgreSQL NOTIFY transaction rules](https://www.postgresql.org/docs/17/sql-notify.html).

ROLLBACK-only is **not risk-free**. FK creation can lock referenced application/
user tables, privilege/publication DDL can conflict with other operations, and
locks remain until transaction end. The short lock/statement limits can abort a
busy or slow validation; do not increase them automatically. statement_timeout
limits each server statement, not the entire script's wall-clock time. The idle
timeout limits a session left idle in a transaction, not an actively running hook.
transaction_timeout=90s bounds total transaction duration across individually
short statements, longer than both 15s statement and 60s idle limits so neither
is suppressed. A transaction timeout terminates the backend; it is not a normal
statement cancellation. This deliberately conservative trial may fail on a slow
project. Do not raise limits automatically. See
[PostgreSQL 17 timeout behavior](https://www.postgresql.org/docs/17/runtime-config-client.html).
Hold no additional interactive statements open inside the validation transaction.

DDL event handlers can inspect or react to CREATE/ALTER/GRANT/REVOKE before
commit. Ordinary transactional writes roll back, but external HTTP/network calls,
logs, asynchronous work or nontransactional effects might not. No transaction
guard proves those safe. The pinned six-hook comparison is still a point-in-time result:
coordinate a quiet schema-maintenance window so another administrator does not
install/enable hooks or alter referenced definitions between review and execution.
See [PostgreSQL event-trigger behavior](https://www.postgresql.org/docs/current/event-trigger-definition.html).

If later approved, run the **complete reviewed artifact in one SQL Editor request
and one backend transaction**; never select only DDL or assertions, and never
replace ROLLBACK with COMMIT. Confirm the SQL Editor/session/pooling behavior
before approval; do not assume separate editor requests share the same backend.
Any guard/assertion/timeout/DDL error aborts the transaction. Do not catch errors
and continue, retry selected lines, rerun the deployment migration, or clean up
objects with DROP. If the same backend remains available, issue ROLLBACK there.
If disconnected/cancelled or its state is uncertain, use the platform's session
tools with CH/KZ to establish whether that backend closed or still has an open
transaction/locks. A fresh-session verification cannot release a different
backend's locks, and absence in another session does not prove the original
transaction ended (uncommitted objects are invisible). Do not retry until settled.
Idle timeout is a fallback, not confirmation. Then run the post-rollback checks.

Successful DDL plus catalogue assertions establish only that this PostgreSQL
environment accepts those definitions and metadata at that time. With function
body checks enabled, CREATE FUNCTION still does not execute every PL/pgSQL path
or plan every embedded query. It cannot prove runtime return mappings, auth/RLS
isolation, concurrent transitions, failure rollback, notification delivery or
Realtime authorization. Neither a validation NOTICE nor a later absence PASS
proves that all paths ran. After assertions pass, the explicit SELECT returns
`CHAT_DDL_CATALOG_ASSERTIONS_PASSED_ROLLBACK_PENDING`, backend PID and isolation.
This is the last SELECT before the final ROLLBACK, in addition to the NOTICE.
Save it with the full results/errors and independent transaction-end evidence.
SQL Editor may not retain every result/NOTICE; if this marker is unavailable or
execution is interrupted, classify the trial **UNCONFIRMED**, even if absence
checks later PASS. A marker alone also does not confirm the following rollback.

### Baseline and post-rollback verification

`chat_phase2_post_rollback_verification.sql` now has **one read-only query and one
JSON result row**, replacing fourteen separate result sets. Columns are
record_count and baseline (an array sorted by category/object_identity). Each
entry has category, stable schema-qualified object_identity (or a structured
composite key), and fingerprint_or_value. A single JSON row avoids the SQL Editor
last-SELECT issue and multi-row grid limits. Export the complete value, not a
visually truncated cell; verify its array length equals record_count. No timestamp
or backend PID is included in the comparison data. Context records capture
role/database/version/search_path/replication mode to ensure comparable inspection.

All prior coverage remains: routine definitions/owners/ACLs; relations/RLS/owners;
policies; constraints; **internal and non-internal triggers**; columns including
type modifiers/collations/defaults/ACLs; column grant records; indexes/views;
default privileges; publications and event hooks. Internal RI triggers on existing
users/job_applications are included, so a residual added trigger is an added key.
Publications include owner, all publish flags and pubviaroot; table membership
includes attnames/rowfilter. Event hooks export full identity/owner/language/
security/configuration/normalized ACLs with grantors, definition MD5 and full body.
JSONB serialization and sorted ACL grant tuples avoid concatenation ambiguity
and ACL array ordering. The exact query is shared with main catalogue Section 5
and checked for equality offline. Main Section 0/validation assertions also now
check PostgreSQL 17 MAINTAIN privileges for anon/authenticated/service_role;
column privileges correctly keep their separate supported privilege list.

Manual workflow (subject to separate validation-execution approval):

1. Run the single consolidated read-only script before validation in the intended
   project as postgres; export its **complete baseline JSON** privately.
2. Require all four category=absence entries to PASS and record_count to match
   array length. Any existing Chat object is a stop condition. Check keys are unique.
3. Execute only a separately approved complete rollback-validation artifact, in
   one batch/session. Retain the success marker and full execution outcome.
4. Confirm the original transaction ended; if interrupted or marker missing,
   mark UNCONFIRMED and resolve backend/lock state before any retry.
5. Run the identical consolidated verification in a fresh session with the same
   role/search_path; export the complete post-rollback JSON.
6. Compare by (category,object_identity) over the **union of both key sets**:
   report before-only=missing, after-only=added, shared-key/different-value=changed.
   An inner join or comparing only matching keys is insufficient. Equal record
   counts alone are also insufficient. Require four absence PASS values and no
   missing/added/changed existing-object or context records.

The script emits comparison data, not an automatic claim that it matches a saved
external baseline. KZ's legitimate concurrent administration can cause a mismatch;
investigate rather than automatically attribute it to Chat, accept it or repair it.
Coordinate a quiet schema-maintenance window. No backups/database baseline tables
are created. Matching metadata does not prove absence of external effects or
runtime security, and absence alone never proves that DDL validation actually ran.

### Minimal runtime plan using existing accounts/relationships (separate approval)

No runtime action below is approved or executed now. Do not manufacture states,
remove members, suspend users, alter restrictions or create accounts/fixtures.
Use only existing accounts and real authorized relationships selected privately
by CH/KZ. Never use service-role/SQL Editor identity as proof of client isolation.

| Class | Practical checks / limits |
| --- | --- |
| A — read-only now | Review actual DDL/writer/privilege/hook metadata, baseline and later rollback absence. Offline structural and existing Flutter regressions remain possible. There is currently no committed Chat backend to validate via user RPCs. |
| A — read-only after separately approved backend availability | With existing signed-in worker, authorized company employer and unrelated account, list/history/capability reads must show owned/authorized threads and reject foreign UUIDs. Inspect naturally existing Submitted, Shortlisted, Hired and terminal cases; no state transitions to create a scenario. |
| B — requires committed Chat records and separate approval | After a separately approved deployment, consenting worker/employer can explicitly create/retrieve a real application's conversation and exchange a clearly agreed real message. Existing Submitted and Shortlisted cases must work without changing recruitment status. Both parties must retrieve one thread; wrong actors must fail. Retry the identical request UUID/body and verify one message/one intended generic inbox row per eligible recipient; changed body must fail. No insertion is part of this rollback candidate. |
| B — existing eligible relationships only | Use a naturally Hired/restricted relationship for Option B, if one exists; use an existing terminal thread for read-only behavior. Observe two existing authorized employer members' independent cursors/unread counts; mark only messages actually displayed. Check worker/employer generic inbox text, privacy and Realtime delivery between consenting existing sessions. These operations persist messages, notifications/read state and require approval. Skip unavailable cases rather than create fixtures or change real states. |
| C — cannot establish under current constraints | Forced notification failure/rollback, deterministic lost-response/concurrent duplicate races, account suspension/member-removal/moderation races and open-subscription revocation require controlled state/fault changes or a later approved environment. Existing RPC source supports atomicity reasoning, not runtime fault proof. Natural legitimate revocation could be observed only with separate approval; do not provoke it for testing. Rollback-DDL tables disappear and cannot validate committed Realtime delivery. |

CH/KZ must record skipped cases and residual risk explicitly. Rollback-DDL
acceptance is a prerequisite review aid, not full security acceptance or permission
to deploy/replace the Flutter demo. No approval guard is removed by this work.

### Final hardening offline validation record (previous revision)

- Updated checker: **160 structural/scope checks passed**, including eight
  required-lock FOUND checks, one shared isolation guard, all five unchanged
  public parameter/type/default contracts, both approval guards, exact copied
  migration/summary/fingerprint bodies, transaction-local limits, no COMMIT in
  validation and read-only post-rollback/hook inspection statements.
- Notification regressions: **18 passed**. Selected existing chat-demo checks:
  **10 passed** (the same focused commands recorded above).
- `flutter analyze`: exit 1, the same **five informational diagnostics** in
  unchanged files; no errors/warnings.
- SHA-256 comparison of **363 baseline files** confirmed exactly five allowed
  Chat edits and three allowed SQL additions; no unrelated source changes or
  trailing whitespace were found. Neither SQL
  candidate nor either read-only verification/inspection file was executed.
  No PostgreSQL compilation, PL/pgSQL path execution, runtime authorization,
  concurrency, notification-failure injection or Realtime acceptance is claimed.

### Final validation safety revision — local results and review scope

- **167 offline structural/scope checks passed**. Exact migration-body equality,
  exact shared summary equality (including MAINTAIN), and exact consolidated
  baseline-query equality passed. Both original approval-guard texts remain
  unchanged. Pins cover six named hooks/fingerprints and every supplied metadata
  field; complete-set/full-join checks reject missing and unexpected hooks.
- Before/after SQL-source scope comparison covered **366 pre-existing files**:
  exactly seven authorized Chat diagnostic/check/document files changed; the
  standalone migration and every unrelated baseline file are unchanged. No new
  files or trailing whitespace were found.
- `flutter analyze` rerun: exit 1, **10 informational entries**: the same five
  diagnostic locations in unchanged files, each printed twice; no errors/warnings.
  Flutter tests were not rerun for this
  validation-only revision; prior 18 notification/10 demo passes remain historical.
- PostgreSQL 17 static review checked catalogue column names, pg_proc result-type
  expectations, activity-index deparse matching, policy-expression normalization,
  effective privilege functions and separate valid column/table privilege lists.
  No concrete blocking SQL issue requiring a standalone migration change was
  established. This is not a PostgreSQL parse/compile or runtime claim; the new
  hook comparison and consolidated query have not been run against PostgreSQL.

CH should review the revised rollback candidate (pinned hooks, limits, marker,
exact DDL body), single-query post-rollback export, shared catalogue assertions,
static checker and this workflow before separately approving execution. The
updated read-only DDL inspection can display the same normalized metadata if
future drift needs investigation; the supplied six-handler review is already
accepted evidence, not a request to repeat it. The unchanged deployment migration
stays blocked. No live SQL, deployment, new account/fixture, environment install,
business mutation, event-trigger change, Flutter edit, Git commit/push or unrelated
file change occurred. Remaining gates include execution approval, SQL Editor
single-session behavior/marker retention, original transaction completion, DDL
lock/extension-side-effect risk and all still-unperformed runtime security tests.

### Read-only baseline ACL correction

CH reported PostgreSQL 17.11 error 22023, `ACL arrays must be one-dimensional`,
when executing the consolidated baseline. No baseline was captured; neither the
rollback validation nor deployment migration was executed. Source inspection
confirms the likely empty-array path: NULL column attacl was represented by
`'{}'::aclitem[]` and sent unconditionally to aclexplode. This correction has not
been reproduced or retested against PostgreSQL by the agent.

Both exact shared queries now guard the function argument itself:

```sql
FROM raw_acls r
CROSS JOIN LATERAL pg_catalog.aclexplode(
  CASE WHEN pg_catalog.cardinality(r.acl) > 0
    THEN r.acl ELSE NULL::aclitem[] END
) a
```

Nonempty arrays retain all grantor/grantee/privilege/grant-option entries.
NULL/empty inputs expand to no entries; downstream COALESCE(value,'[]'::jsonb)
still represents missing normalized ACLs. Routine/relation NULL ACLs continue
to use their proper acldefault values. No privileges or fingerprint categories
are changed, and a WHERE-only cardinality filter is not used.

The two other Chat aclexplode calls, in rollback hook pinning and read-only DDL
inspection, used COALESCE(proacl,acldefault(...)). That handles NULL, but not an
explicit empty proacl. Both now apply the same cardinality CASE to the resolved
ACL. The reviewed six nonempty live ACLs normalize unchanged; an empty hook ACL
now produces no entries and fails the pinned comparison normally, rather than
raising an array-shape error before comparison. No hook baseline/guard is changed.

Updated offline checker: **175 structural/scope checks passed**, including four
argument-local ACL guards, exact shared baseline/summary/migration-body equality
and both unchanged unconditional guards. No SQL or Flutter checks were executed
for this targeted correction; the checker is not PostgreSQL/runtime validation.
CH should rerun only `chat_phase2_post_rollback_verification.sql` to capture the
previously missing complete read-only baseline. Rollback validation/deployment
remain separately guarded and unapproved by this correction.

### Correction of two pinned hook ACL expectations

CH's separately approved rollback-only attempt stopped before Chat DDL with a
six-hook baseline mismatch for issue_pg_graphql_access and issue_pg_net_access.
The subsequent read-only cleanup inspection returned no rows (user-reported
evidence; no SQL was executed by the agent). CH reinspected the live handlers:
their definitions/hashes and all other reviewed metadata match. The two expected
ACL arrays were incorrectly recorded, rather than privileges needing modification.

Correct C-collation grant sets (each tuple is grantee, privilege, grant-option):

```json
{
  "issue_pg_graphql_access": [["PUBLIC", "EXECUTE", false], ["postgres", "EXECUTE", true], ["supabase_admin", "EXECUTE", false]],
  "issue_pg_net_access": [["PUBLIC", "EXECUTE", false], ["dashboard_user", "EXECUTE", false], ["supabase_admin", "EXECUTE", true]]
}
```

Only these two expected JSON literals are corrected in the repository validation
candidate. The exact six-trigger comparison, fingerprints, ownership/security/
configuration expectations, collision checks, timeouts, assertions, final ROLLBACK
and original approval guard remain unchanged. Static checks now pin these two
arrays explicitly. No actual ACL, trigger, migration DDL or business rule changes.
CH/KZ's prior trial approval permits regeneration of the separate Desktop copy;
that copy again differs only by removal of its validation approval block. This
does not remove the repository approval guard or authorize agent SQL execution.

Next action remains CH manually retrying the complete corrected rollback-only
copy after preserving the complete baseline and coordinating no concurrent schema/
RPC/permission/hook changes with KZ. Retain the marker and confirm transaction end,
then compare the read-only post-rollback output. The earlier baseline mismatch
was not a successful DDL trial; compilation/runtime security remain unverified.

Correction verification: **177 offline structural checks passed**, including
exact migration DDL, shared summary and shared baseline equality. Reversing only
the two expected ACL literal changes reproduces the previous candidate's exact
SHA-256, proving all other candidate bytes are unchanged. The regenerated
`C:\Users\theec\Desktop\chat_phase2_rollback_validation_APPROVED.sql` differs from
the corrected candidate only by removal of the separate validation approval block.
Its SHA-256 is
`3D257F93D3EA19DEDCFF168D12120AE5FB77315D111C04EAA1C74A67FBD84339`.
Final ROLLBACK, all limits, environment/hook checks, catalogue assertions and marker
remain; no executable COMMIT, business RPC call or test-data insertion occurs
outside stored definitions. Both repository guards and the standalone migration
are unchanged. The regenerated copy was not executed.

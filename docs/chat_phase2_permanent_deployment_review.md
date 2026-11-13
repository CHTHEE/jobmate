# Chat backend — permanent deployment review, not execution approval

## Release outcome — 13 November 2026

**Permanent deployment and prospective catalogue integrity are complete**, on
CH's supplied evidence. Artifact SHA-256:
`F8C7F05FB086BB53E82B9E6BB406975DAE7B9E96DF10BFE857B957138CC5AA63`;
marker `CHAT_PERMANENT_DDL_CATALOG_ASSERTIONS_PASSED_COMMIT_PENDING`;
PID 2812168, read committed; subsequent independent activity inspection: no rows.
Fresh Section 0: `post_deployment_or_partial`, 12/12 PASS. Digest: 5769 source,
5757 compared, zero duplicate keys, all 13 category counts/hashes match pre;
global SHA-256 `c08532d80fd3e19fc228329f1400d6319564bd62f0eaada0a624abdc1fdf7451`.
The four absence FAIL results mean the expected Chat objects exist. Six enabled
parent FK triggers match DELETE/UPDATE NO ACTION; both Realtime memberships match
the expected columns with null filters.

The earlier complete rollback fingerprint comparison is still unconfirmed.
Authenticated runtime messaging, isolation, concurrency and Realtime delivery
are pending. No database work was performed by the agent. Guarded repository SQL
remains unchanged. [Phase 3](chat_phase3_runtime_acceptance.md) adds the typed
Flutter data layer and acceptance procedure; visible Messages remains the demo.

Latest Phase 5/6 update supersedes that earlier demo status: CH's complete
messaging exports passed the core same-conversation, typed send/history, replay,
Realtime-delivery and own-cursor checks. Partial pagination/read/notification and
security/reconnect checks remain UNVERIFIED. The authorized production Chat UI is
implemented; see [the full evidence and release limits](chat_phase5_runtime_review_and_phase6_ui.md).
No migration, guard, schema or additional live write was executed by the agent.

Current scoped-trial approval: CH/KZ approved only the recorded QA application,
two actor UUIDs and one exact message per participant. Debug tooling now enforces
that scope, fixed idempotency identities, fresh capability checks and a stop on
denial/read-only. Production/backend code and both SQL guards are unchanged.
Agent executed no live requests/writes. Runtime acceptance still awaits CH's
button-driven evidence; see the latest Phase 3 procedure. Older approval-pending
statements below describe the earlier state.

Paired read-only evidence update: employer
`50c0d35f-c1cd-4fa1-b864-6f6e1e833fd0` is active and its typed Chat list is empty.
Both exports preserve disabled writes. CH's exact hired application confirmation
in Employer Applications supports the management/verified-company context; actual
company restriction state is unverified. Phase 3 contains the fully identified
conditional CH/KZ approval statement. Trial remains unapproved/hard-locked; no
agent live requests or business writes occurred.

Read-only runtime progress, 13 November 2026: CH's complete seeker evidence was
locally parsed. Active seeker identity, typed empty Chat list and four application
IDs passed. Selected QA application `fb352472-8a41-45cf-a9a6-5e70e25e66e8` is present;
its hired/ABC Company context is CH-reported, not part of the exported ID list.
Employer context and full Chat send eligibility remain unconfirmed. The Phase 3
document records narrow proposed approval for one conversation/two messages;
approval has not been supplied and all writes stay locked. Other runtime gates
and the historical rollback comparison remain outstanding. No agent live calls.

Latest acceptance tooling: a temporary debug-only Flutter tester is prepared for
CH to run the actual repository using the existing signed-in session. Normal
production navigation/demo and deployed SQL are unchanged. All business-write
controls remain hard-locked; real typed/runtime and Realtime delivery results
await CH evidence. The earlier blocked attempt below is retained as history.

Read-only acceptance attempt, 13 November 2026: **BLOCKED at runtime access**.
No authenticated participant contexts were supplied or accessible through the
available tools; session discovery returned no connected sessions. Zero live RPC
calls were made. Deployment evidence above is unchanged; it does not establish
runtime response compatibility, pagination or isolation. See the Phase 3 blocked
check table and prerequisites. Separate messaging approval has not been given by
this read-only instruction, and messaging readiness remains unconfirmed.
Unencrypted pending storage, device restart/cross-tab acceptance, Realtime and
the earlier complete rollback fingerprint comparison remain outstanding.

The following is the historical pre-deployment review, retained for provenance;
its pending-deployment language is superseded by the release outcome above.

12 November 2026. Review preparation only. Neither repository guard is removed,
no unguarded permanent execution copy is prepared, and no SQL is run by the agent.
Flutter remains the existing demo. No new feature or business rule is introduced.

## Evidence and readiness

CH reports that the corrected rollback-only validation passed its DDL/catalogue
assertions and returned CHAT_DDL_CATALOG_ASSERTIONS_PASSED_ROLLBACK_PENDING,
PID 2808501 and read committed. A subsequent pg_stat_activity inspection returned
no rows for that backend, and four post-rollback absence checks passed. Both
exports reported 5761 records. These are CH-supplied live results, not independent
agent database tests. The successful marker and backend closure support a
completed rolled-back definition/catalogue trial, not persistent deployment or
runtime messaging/RLS/concurrency/Realtime acceptance.

**The complete pre/post fingerprint comparison remains unconfirmed.** Equal
counts cannot establish that the 5761 keyed values match. CH chose not to provide
local export files, and none are requested. The prospective digest below does
not retroactively prove the old comparison. Record this limitation in the CH/KZ
release decision; do not relabel it as a completed integrity check.

The local migration DDL body is identical to the corrected guarded rollback
candidate and the approved artifact CH reports executing. Comparison uses the
body from DO $chat_preflight$ to before the standalone COMMIT and the marked
EXACT MIGRATION BODY in both rollback artifacts, with line endings normalized.
The complete standalone migration remains byte-for-byte unchanged:

- Migration SHA-256: `8704715E62DE895324A651C41BFD55CC2A756D2C739FDED85B624FB4AB5FA0E7`.
- Guarded rollback candidate: `84DDF9AB9F30B2FC1930C3F68CFE7371B730C0AE1ADFECEBA859D070368EC099`.
- Approved rollback artifact: `3D257F93D3EA19DEDCFF168D12120AE5FB77315D111C04EAA1C74A67FBD84339`.

Readiness: **ready for a separate permanent-deployment review/decision**, subject
to the fresh checks, integrity limitation and runtime gates below. This document
does not approve, authorize or execute that decision.

## Safety preflight to retain in any later approved permanent artifact

The standalone file has the unconditional release guard, postgres owner check,
namespace/RPC collision checks and helper/publication preflight. It is deliberately
not executable as delivered. It does **not** itself contain the rollback wrapper's
six-hook/environment pinning or timeouts. Therefore removing only its guard and
running it directly would discard reviewed controls and is not the proposed route.

The corrected rollback wrapper pins the complete six-trigger set, PostgreSQL
17.11/database postgres/current_user postgres/origin, names/events/enabled states/
tags, owner/security/configuration/identities, definition hashes and normalized
ACL sets. The two corrected GraphQL/net expectations must remain. No missing,
extra, retagged or changed hook is silently accepted; no hook is disabled/altered.
Previously reviewed PostgREST handlers issue transactional schema-reload NOTIFY.
For a permanent COMMIT, those notifications can now be delivered, unlike the
rollback trial. That expected platform effect is not a JobMate inbox notification.
Other extension/external effects are not comprehensively proved absent.

Retain READ COMMITTED, lock_timeout 1s, statement_timeout 15s,
idle_in_transaction_session_timeout 60s, transaction_timeout 90s and
check_function_bodies on, collision checks, exact validated DDL and catalogue
assertions (including MAINTAIN). The total timeout can terminate a session. Do
not silently increase limits, refresh hook pins, weaken grants or apply unrelated
pending migrations to make a deployment pass.

## Prospective compact catalogue comparison

New read-only candidate:
`supabase/diagnostics/chat_phase2_deployment_fingerprint_digest.sql`.
It has not been executed/compiled against PostgreSQL by the agent. It copies the
exact baseline-record CTE from the existing consolidated verification and emits
one small result: format version, source/compared counts, duplicate count,
global SHA-256, category counts/digests, four absence values and planned additions.
No extension installation, database function or baseline table is created.

SHA-256 is computed over ordered canonical JSON records using PostgreSQL 17's
built-in binary hash function. Some underlying record fingerprints remain MD5
for continuity with the existing baseline; the wrapper does not turn that into
an adversarial tamper-proof audit. It detects ordinary catalogue drift within the
existing fingerprint coverage, not application-row changes or every possible
database setting/extension/role-membership change. Use identical diagnostic
source, role, search_path and environment on both sides; keep the small results
and diagnostic source hash in the shared release record, not necessarily Desktop
files. See [PostgreSQL binary hashing](https://www.postgresql.org/docs/17/functions-binarystring.html).

Permanent Chat installation necessarily adds metadata on existing objects:

- Six parent RI triggers: two on job_applications for the conversation/application
  FK, and four on users for message-sender and read-state-user FKs.
- Two supabase_realtime membership records for public.chat_conversations and
  public.chat_messages. Existing publication owner/settings must stay unchanged.

The digest identifies only those additions using actual internal FK relationships,
exact child/parent columns and NO ACTION rules, and exact publication/table keys.
It excludes those exact keyed rows from the unchanged-catalogue digest **and
reports every excluded row and its details separately for review**. It does not
exclude all internal triggers or all publication changes. The four absence
entries are reported separately because they must change on successful install.
The existing baseline CTE already omits new Chat-owned objects; their definitions
are verified by the main Chat catalogue assertions instead.

Before deployment: four absence PASS, zero planned additions and duplicate count
zero. After deployment: expect four absence FAIL (objects now exist), exactly six
reported parent FK triggers and two reported publication members, zero duplicates,
and matching compared counts/global/category digests. Review the six RI trigger
definitions (two per FK), enabled state and relationship, plus publication column
lists and null row filters. Different counts or unexplained deltas are a stop
condition, not a reason to broaden exclusions. Main catalogue post-install checks
must also all PASS; digest equality alone is not a Chat security/configuration test.

If a digest/category/count differs, use the existing full baseline query and
compare the union of category/object_identity keys to find missing/added/changed
records. Investigate concurrent legitimate KZ administration as well as deployment
effects; do not automatically blame Chat or repair objects. Collect a fresh
pre-deployment comparison now for this future deployment, not an invented digest
for a past snapshot. The earlier 5761-value comparison remains unconfirmed.

## Proposed manual permanent procedure — only after separate CH/KZ approval

1. CH/KZ explicitly approve permanent deployment, target/window/operator, the
   unchanged migration hash, accepted earlier-comparison limitation, safety
   wrapper and prospective comparison method. Rollback-trial approval is not
   permanent approval. Until then, no permanent execution copy is prepared.
2. Coordinate no concurrent schema/RPC/permission/role/membership/hook changes.
   Fresh read-only checks: main catalogue Section 0 must show pre-deployment
   absence (publication settings PASS); four consolidated absence checks PASS;
   inspect current hook/environment output against the exact corrected wrapper;
   preserve fresh digest/full baseline as agreed. Existing objects, drift,
   unexplained privileges or an unconfirmed SQL Editor transaction model stop
   preparation/execution. The fresh digest candidate itself needs CH/KZ review
   before manual use; it is not claimed tested by the past DDL trial.
3. Only after that approval, prepare and review a separately named permanent
   artifact. Preserve repository guards. Planned derivation: use the validated
   READ COMMITTED/timeout/hook/collision wrapper, exact standalone DDL body and
   exact shared catalogue assertions. Change transaction completion to an
   explicit COMMIT, with an unmistakable deployment-specific COMMIT_PENDING
   marker/backend PID after successful assertions. No such artifact or marker
   is implemented by this task. The future copy's exact wrapper changes/hash
   require review before use; do not edit the rollback-approved Desktop script
   in place, or run the standalone guard-free without its safety wrapper.
4. Verify the future artifact contains one BEGIN, no early COMMIT, no business
   RPC/data/fixture execution, all safety checks and the exact validated DDL;
   final explicit COMMIT only after assertions. Use one fresh SQL Editor query
   as postgres in the intended project, complete batch/one backend transaction,
   never selected fragments. Do not run db push/reset/repair or any other pending
   migration. Record the reviewed applied version/hash with CH/KZ.
5. Capture full execution outcome and COMMIT completion. A pre-COMMIT success
   marker alone does not prove persistence. In a fresh backend session, main
   catalogue checks must report post-deployment mode with every check PASS.
   Fresh-session existence proves visibility, unlike an uncommitted same-session
   view. If SQL Editor cannot preserve boundaries/results or original session
   state is unclear, stop and resolve that limitation before executing/retrying.
6. Run the exact fresh pre-deployment digest again under the same inspection
   context. Compare counts/global/category hashes and manually review only the
   planned six RI/two publication additions. Require all main catalogue checks
   PASS and no unexplained existing-object changes. Do not require rollback's
   absence PASS after permanent deployment; those four presence-derived FAIL
   values are expected then.
7. Keep the Flutter demo unchanged until backend/security acceptance. Perform
   only separately approved minimal runtime actions below with existing actors.
   Record all passing/skipped cases and remaining limitations before Flutter
   integration or representing the backend as runtime-complete.

Failure handling: before COMMIT, an assertion/DDL/timeout error aborts the
transaction; if the original backend remains available and open/aborted, issue
ROLLBACK there. A different pooled connection cannot release its locks. After
disconnect/timeout or unknown COMMIT outcome, do not blindly rerun the additive
script. Resolve the original backend/transaction state and inspect committed
objects in a fresh session. A committed deployment cannot be undone by issuing
ROLLBACK afterward. Unexpected partial/conflicting objects require CH/KZ review,
not DROP, CREATE OR REPLACE, broad grants, guard bypass or automatic repairs.
Do not change existing rows/statuses to troubleshoot. Retain the baseline and
execution evidence; investigate any unexpected changes before feature rollout.

## Minimal live runtime acceptance — separate action approval required

Use existing consenting active Job Seeker and authorized Employer accounts and
real application relationships only. Direct RPC/Realtime checks must run with
each real authenticated user's client context, never service-role/SQL Editor
postgres as a substitute for RLS. No credentials/tokens in reports. No new
accounts, synthetic fixtures or manufactured lifecycle/restriction changes.

| Check | Scope and expected result |
| --- | --- |
| Initial authorized reads | Empty/owned/authorized list and unavailable foreign UUIDs; no Admin bypass. Check first without writes. |
| Submitted/Shortlisted relationship, if naturally available | Either party can explicitly start the same application thread and send an agreed real message. No application status change or implied shortlist/acceptance. Different applications remain separate. |
| Persistence/idempotency | Recipient/history reload shows the committed message. Same sender/request UUID/body returns it once; changed body rejects; one generic notification per eligible opposite-side recipient. No fake transport fault is required for the deterministic retry check. |
| Read state | On consenting existing employer staff accounts, each has an independent cursor; mark only displayed real messages; stale marks cannot reduce a cursor; own sends excluded from unread. |
| Natural terminal/Hired restricted cases | Existing terminal history only; no creation/new send. A naturally Hired/restricted application retains Option B creation/send/history, including closed postings/completed engagement. Skip unavailable states instead of changing real statuses/restrictions. |
| Realtime/reconnect | With consenting existing sessions, observe committed messages/list activity, then reconnect and reload persistent history. Unauthorized client must receive neither history nor new contents. |
| Restrictions and remaining gaps | Suspended/deactivated/removed-member denial can be observed only for naturally existing authorized scenarios or legitimate changes separately approved by owners. Do not provoke revocation for a test. No deterministic account/membership/moderation race, forced notification rollback, lost-response fault or open-subscription revocation is claimed tested under current constraints. |

Messages, cursor changes and generic notifications from approved runtime checks
are durable real records. They are not part of metadata deployment or this task.
SQL-source atomicity reasoning and the DDL trial do not replace runtime failure/
cross-account/concurrency/Realtime tests. A backend schema may be deployed while
the Flutter integration stays disabled/demo and these acceptance gates remain.

## Next Flutter sequence — plan only

1. Typed models/source/repository for existing RPCs, strict response parsing and
   per-account state reset; no Phase3Store substitution for real private messages.
2. Lists/direct-route capabilities using list_my_chat_conversations; explicit
   application worker/employer Message actions use get_or_create_chat_conversation
   lazily. Submitted and Shortlisted are eligible; no employer-first rule or
   fixed original-poster participant, no thread per shift.
3. list_chat_messages pagination by sequence; shared responsive list/thread UI
   with company/worker/job context, loading/empty/denied/error/read-only reasons.
4. send_chat_message with durable UUID/body retention through ambiguous failures,
   bounded whole-RPC retries for lock/serialization errors and identical-result
   reconciliation. Handle 4000 Unicode code points, no optimistic persisted/read
   claim, no duplicate notifications from client-side logic.
5. mark_chat_conversation_read with actual displayed message ID, refresh list
   counts; independent staff cursors. Keep chat and inbox read state separate.
6. Authorized conversation/message subscriptions, deduplication by message ID,
   sequence ordering, reconnect/resume RPC recovery and capability refresh. On
   account/access change unsubscribe and clear inaccessible state; previously
   downloaded content cannot be recalled by the server.
7. Preserve existing GoRouter roots/direct URLs/browser Back/Forward and Android
   contextual Back, practical exits and unsent drafts. Replace demo labels/receipt
   simulation only in the later real interface. No attachments, rate limits,
   typing/online indicators, edit/delete, push or dispute-access expansion.

Existing notification repository remains unchanged: explicit p_limit/p_offset
list overload and boolean mark_notification_read(p_notification_id). Generic chat
notifications have no deep-link fields; do not invent targets from their text.
Keep Gemini server-side and all existing Module 2/4/KZ checks intact.

## Local preparation checks

**187 offline structural/scope checks passed.** Exact standalone/rollback DDL,
shared summary/baseline equality, corrected six-hook expectations and unchanged
repository guards passed. The approved rollback Desktop artifact's marked DDL
also matches the standalone body. The new digest's shared CTE matches the exact
existing baseline definitions; read-only single-statement shape, deterministic
hashing, exact-identity planned-delta handling and duplicate/count outputs passed
structural checks. These are not PostgreSQL compilation or runtime tests.

Digest source SHA-256:
`F8B5DE94BF085946056A573525C898BEF0E656DBA7BC4E79752334E9B1A0777B`.
An initial SHA-256 comparison of 366 pre-existing files confirmed only two
authorized edits (implementation notes and checker) plus this guide and the new
digest candidate. No migration, guard, previous SQL diagnostic or rollback
artifact was changed; no trailing whitespace/new unrelated file was found.
Flutter checks were not rerun because no Flutter code or workflow changed.

New digest SQL is read-only source prepared for review, not a live digest or
proof of earlier exports. No permanent execution file, database connection, migration application,
account/fixture, environment installation, backup, Flutter implementation or Git
operation is part of this preparation.

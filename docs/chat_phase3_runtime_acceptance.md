# Chat Phase 3: data layer and authenticated acceptance

13 November 2026. Backend deployment and prospective catalogue integrity are
complete on [CH's evidence](chat_phase2_backend_implementation.md). Authenticated
runtime acceptance is **pending**. No live requests were made by the agent.
Existing demo screens/routes are untouched. No new dependencies or configuration.

Offline verification: `flutter test test/chat_repository_test.dart
test/chat_source_test.dart --reporter expanded` passed all **17 tests** using
fakes and loopback HTTP only. `flutter analyze` reported five existing info-level
findings in company management, sign-up and engagement closure; no findings in
the new Chat source/tests. No errors or warnings were reported. No full unrelated
suite, live runtime, Web/Android UI or native storage acceptance was executed.

## Data contracts and use

### Latest: Phase 5 review and Phase 6 real UI

The supplied seeker/employer messaging exports were inspected completely. The
same conversation, both typed sends/history, identical-request replay, actual
Realtime events and own cursor updates passed the observed fixture checks.
Older-page traversal, cursor non-regression, complete notification dedup and
reconnect/isolation remain partially unverified. No blocking issue was found.
The authorized production UI integration now replaces Messages (demo); earlier
demo/locked/pre-integration statements below describe history.
See [the full PASS/UNVERIFIED matrix and current UI procedure](chat_phase5_runtime_review_and_phase6_ui.md).
No additional live writes were executed by the agent or authorized by that review.

### Approved scoped messaging trial — 13 November 2026

CH and KZ explicitly approved enabling only the existing QA application's debug
trial. This supersedes the earlier locked/pending-approval descriptions below;
those remain historical. **Approval is not evidence of successful messaging.**

| Scope | Fixed value |
| --- | --- |
| Application | `fb352472-8a41-45cf-a9a6-5e70e25e66e8` |
| Seeker | `fb66cc74-1a4f-44e0-ae4f-6831c7a39b8f` |
| Employer | `50c0d35f-c1cd-4fa1-b864-6f6e1e833fd0` |
| Seeker's sole agreed message | `Hi, this is a JobMate Chat QA test.` |
| Employer's sole agreed message | `Hello, employer reply received. Chat QA test.` |

`debug/chat_runtime_scope.dart` enforces the allowlist at the RPC boundary as well
as the controller/buttons. An approved actor must first pass **Check account**
with the matching active role. Creation only passes the approved application ID.
The returned conversation is read back through the real repository and must
belong to that application with backend `can_send=true`. Other application
selections, conversations, actors, roles, text and request IDs cannot write.
Fresh scoped capability checks precede every send/replay/read-cursor update;
backend authorization/eligibility checks remain unchanged and authoritative.
`42501`/`55000` or a read-only capability stops further trial writes in that
tester instance, with no unlock button. Do not restart to bypass a rejection;
export the evidence and stop. Missing restriction rows are not repaired.

Each actor has one deterministic UUIDv5 request identity, based on this approved
trial/application/actor. It is fixed across repeated Send/Retry, tabs, devices,
reconstruction and cleared local storage. Exact approved text is immutable.
Together with the deployed per-conversation/sender/request uniqueness this limits
the tester to one logical message per participant, at most two total. The
existing pending store still saves/read-verifies the UUID/body before dispatch;
conflicting old pending records fail closed. Do not change the namespace/date to
start another trial. Retry receipts record IDs/sequences and whether they match
a previous observed receipt; a first/recovered response is not called a verified
replay. No optimistic persistence, automatic send or automatic read marking.

Launch (stop the older Flutter run first):

```powershell
flutter run -d chrome --web-hostname=localhost --web-port=7357 --no-pub
```

1. Sign in normally. Open `http://localhost:7357/#/debug/chat-acceptance` in two
   separate Chrome profiles, one per approved account.
2. In both: **Check account → Snapshot my notifications (read-only) → Create /
   reuse approved conversation**. No application-picker step is needed. Both
   should bind to the same conversation; stop on an error/read-only result.
3. In both: **Observe Realtime**; wait for `subscribed` before the sends. This
   status alone is not delivery proof.
4. Seeker: **Send agreed message**. Employer: **Load history**, verify the message
   and its event in evidence, then **Send agreed message** for the single reply.
5. Seeker: **Load history**; both profiles retrieve the same two message IDs and
   agreed text (unless pre-existing messages are present). A valid send receipt
   confirms persistence; reconcile event IDs with typed history after reconnect.
6. Each profile: **Retry same UUID/body**. Compare returned ID/sequence with its
   first send; no extra history row/sequence. Repeated Send is also the same
   logical request. No changed-body rejection probe is enabled by this approval.
7. Page size 1: **Load history → Older messages → Older messages** until empty,
   and **Check empty boundary (before 1)**. Click **Mark my read cursor** on a
   retrieved message, then reload conversation counts; mark an older retrieved
   message to observe non-regression where possible. These update only the
   authenticated participant's cursor in the approved conversation.
8. Snapshot each notification inbox after deliveries and after replays. Evidence
   records existing notification IDs/types/times/read flags, not title/body.
   Quiet-window comparisons can support one new generic notification per eligible
   recipient and no extra on replay. This is the existing first-50 projection,
   with no per-message link; concurrent traffic, more than 50 relevant rows or
   unobserved eligible employer recipients remain UNCONFIRMED. No notification
   creation/marking behavior is changed; notifications are server-generated.
9. **Copy evidence JSON** from both profiles before logout; save separate local
   files (for example `seeker_messaging.json` and `employer_messaging.json` under
   `tmp/chat_readonly_acceptance/`) and provide their paths for review.

The tester can observe real authenticated Realtime events but does not simulate
them or declare delivery/reconnect acceptance passed. Reopen/rebind, resubscribe
and refetch history to check reconnect recovery; stale account/selection events
are discarded. One conversation cannot prove ordering across several
conversations or tied activity timestamps. General-purpose cross-tab/device
pending coordination remains untested even though this trial's fixed keys cap
its logical sends across clients.

Implementation tests/build verification are local only. No agent live calls,
writes, schema/dependency/SQL-guard changes or production UI integration occurred.
Messaging, notification dedup, isolation, Realtime/reconnect, concurrency, native
restart/cross-tab behavior, unencrypted pending storage and the earlier full
rollback fingerprint comparison remain pending actual evidence.

Scoped implementation verification: **33 focused tests passed** (existing data
layer plus expanded controller/source-boundary/widget checks), including blocked
foreign scopes/text/UUIDs, wrong roles/statuses, stale account transitions,
fixed request identity after reconstruction with empty storage, conflicting saved
records, read-only stop, own-cursor scoping and credential-free clipboard export.
`flutter analyze` reports only the five existing unrelated info-level findings.
`flutter build web --release --no-pub` passed, including the Wasm dry run; its
JavaScript excludes the tester route/title, approved application UUID and both
agreed message strings. Protected-file hashes match for the demo, route constants,
sidebar, notifications, environment/dependencies and both guarded SQL candidates.
Live Chrome/messaging/Realtime acceptance has not been executed by the agent.

### Paired participant evidence and readiness — 13 November 2026

Both original evidence files were inspected locally, without modification or live
requests. `employer.json` parses completely with two records and consistent actor
IDs; SHA-256 `05E9B2465DAB1CED9AC8E37DC7BE1A447E6CDD579BBF1B0BC61D24E15C87144E`.
The seeker file retains SHA-256
`3E983B056B892921DF7B16C9F94007CEFE07879311C85D93FC225E6274ACA95F`.

| Observed check | Result |
| --- | --- |
| Employer identity | PASS: `50c0d35f-c1cd-4fa1-b864-6f6e1e833fd0`, active `employer` |
| Employer authenticated Chat list / empty handling | PASS: limit 1, null filter and cursor pair, zero rows, no next cursor |
| Seeker identity and empty list | PASS as recorded below: `fb66cc74-1a4f-44e0-ae4f-6831c7a39b8f`, active `job_seeker` |
| Both tester write locks | Confirmed `writes_enabled=false`; source approval constant remains false |
| Exact shared application / employer management context | CH-confirmed existing Employer Applications screen displays Alex Thee, QA TEST – Event Setup Assistant, ABC Company, hired, and exact ID `fb352472-8a41-45cf-a9a6-5e70e25e66e8` |

The UI confirmation is supporting live read-only evidence from CH, not data in
the two JSON files. Its existing source loads job-management access before jobs
and applicants. That path checks active employer, owner/employer membership and
`verification_status=verified`, then invokes the protected listing RPCs. This
supports the corresponding ABC employer authorization and company verification
at observation time; the agent has not independently fetched those current rows.

The selected `hired` status is a supported Chat status. Hired Option B does not
lose rights merely because recruitment is restricted, the posting is closed or
hired work is complete. A present company restriction row with state `active` or
`restricted` is still required. **Its actual value/existence is not in available
evidence.** Empty Chat lists cannot establish that prerequisite. No proven
eligibility failure has been observed, but full can-send eligibility is not yet
confirmed. The deployed creation/send RPCs enforce authorization and eligibility
and reject unavailable/read-only states with `42501`/`55000` before inserting.

No additional Console workflow is required. The next gate is explicit CH/KZ
approval of the narrow trial below, acknowledging the unresolved restriction
check. After approval, prepare a tester allowlist for the exact application and
both actor UUIDs, limit it to one logical message per participant, and allow only
the returned scoped conversation. CH executes all writes manually. The first
approved creation attempt supplies the authoritative current backend decision;
if denied/read-only, stop, preserve evidence and do not change restrictions,
verification, membership, statuses or guards to pass. No speculative repair or
new fixtures are authorized.

Nonempty models/history, pagination, actual idempotency/read cursors/notifications,
Realtime delivery, foreign/admin isolation and concurrency remain unverified.
Unencrypted pending storage, device restart/cross-tab acceptance and the earlier
full rollback fingerprint comparison remain outstanding. Approval is not granted
by this evidence review; all write controls remain hard-locked.

### Observed seeker results — 13 November 2026

Inspected complete JSON evidence at `tmp/chat_readonly_acceptance/seeker.json`.
SHA-256: `3E983B056B892921DF7B16C9F94007CEFE07879311C85D93FC225E6274ACA95F`.
The file parses completely with three records, consistent actor IDs,
`debug_only=true` and `writes_enabled=false`. These are CH-executed authenticated
Dart-runtime observations, locally inspected by the agent; no agent live calls.

| Check | Result | Evidence |
| --- | --- | --- |
| Seeker identity | PASS | Actor `fb66cc74-1a4f-44e0-ae4f-6831c7a39b8f`, role `job_seeker`, status `active` |
| Authenticated conversation-list call / empty-page handling | PASS | Limit 1, null filter and both null cursors, zero rows, `has_next=false` |
| Existing application retrieval | PASS | Four typed applications; target application ID is present |
| Nonempty Chat model parsing/history/cursors | BLOCKED | No accessible conversation returned; empty-list success does not exercise row parsing |
| Employer identity, company-management context and Chat list | Updated above | Employer JSON now confirms identity/list; exact management relationship is CH-confirmed through existing UI |
| Foreign/admin denial, Realtime delivery and messaging | UNCONFIRMED | No corresponding runtime evidence |

Selected application: `fb352472-8a41-45cf-a9a6-5e70e25e66e8`.
CH reports title “QA TEST – Event Setup Assistant”, ABC Company and `hired` status
(all four listed applications are reported hired). The evidence export contains
application IDs only, so title/company/status are user-supplied observations,
not independently established by that file.

**Eligibility is provisional, not a confirmed can-send result.** Deployed SQL
supports hired Chat. It still requires an active participant, the correct
application relationship, a verified company and a present valid
`company_restrictions` row. Hired Option B avoids the pre-hire restriction rule;
closed postings/completed hired engagements alone do not disable Chat. The
employer must satisfy `can_manage_company_jobs` for this application's company;
login or ordinary company membership alone is insufficient. No read-only Chat
application-capability RPC exists before conversation creation; do not probe
`get_or_create_chat_conversation` without write approval.

Before creating anything, CH can finish these read-only steps:

1. Employer tester: **Check account**, **Load conversations**, **Copy evidence
   JSON** to `tmp/chat_readonly_acceptance/employer.json`. This identifies the
   actual employer UUID/role/status and its current Chat-list result.
2. In the employer's existing My Job Postings/Applications pages, view ABC Company's
   QA job and its existing hired seeker application. Confirm the matching
   relationship, not just the job title; supply job/company IDs if available in
   existing records. Do not invoke status actions or open a write form. Existing
   job-management access/company verification screens provide read-only context;
   missing/multiple-company/denied context stays unresolved, not bypassed.
3. Optionally recheck the seeker empty list with page size 10 or 50. An existing
   admin can test list denial; an existing known foreign conversation can support
   denial probes. If none exists, defer those checks. No invented IDs/records.
   Copy evidence before logout; check that switching accounts clears tester state.

The tester already prepares create/send, exact saved UUID/body retry, history,
own read marking and filtered Realtime observation. All controls and method-level
write guards remain locked (`_separateWriteApproval=false`). No code enabling
writes is prepared/applied in this evidence-review step. After explicit approval,
scope the tester to the target application and the two confirmed actor UUIDs
before enabling any write control; reject other selections. Retain one UUID/body
pair per logical send and reconcile retries against the original receipt.

Proposed narrow approval, to be explicitly supplied by CH/KZ; both participant
UUIDs are now confirmed. This text is a request, not an approval:

> CH and KZ approve enabling the debug-only Chat tester for application
> fb352472-8a41-45cf-a9a6-5e70e25e66e8 only, using seeker
> fb66cc74-1a4f-44e0-ae4f-6831c7a39b8f and employer
> 50c0d35f-c1cd-4fa1-b864-6f6e1e833fd0 only. CH will
> manually create/reuse at most one conversation, send at most two agreed messages
> (one per participant), replay each using its identical UUID/body, and update only
> these participants' read cursors in that conversation. We approve the normal
> server-generated generic notifications to existing eligible recipients. Read-only
> history/pagination and Realtime observation may accompany this trial. No account,
> application/status, company, schema, SQL-guard or unrelated changes are approved.
> Codex may prepare the scoped tester but must not execute live writes.
> We acknowledge that current company restriction state is not independently
> verified; the deployed RPCs must enforce eligibility. Stop on access/read-only
> rejection without changing any business state to bypass it.

This is a proposed approval request, **not approval**. If no authorized employer
context or write eligibility is available, stop rather than change business state.
After approval: create/reuse, subscribe the recipient before the agreed send,
retrieve matching typed history, retry without another row/sequence/notification,
send the single agreed reply, test history pagination and own read cursors, then
export both profiles' evidence for review. Subscription status alone never proves
delivery. Two messages exercise history pagination; one conversation cannot prove
multi-conversation ordering/timestamp ties. Notification dedup needs separate
inbox observations; the current tester export does not establish it.

Outstanding remain: foreign/admin isolation unless observed, nonempty parsing and
pagination, messaging/notification acceptance, Realtime delivery/reconciliation,
concurrency, unencrypted pending storage, device restart/cross-tab acceptance,
and the earlier unconfirmed full rollback fingerprint comparison.

### Current fastest path: temporary debug Flutter tester

The existing seeker/employer logins and their shared application are now confirmed
by CH. A debug-only tester uses the actual `ChatRepository`, `SupabaseChatSource`
and typed models with the existing authenticated client. It does not replace the
visible demo or add a production menu destination. This supersedes Console setup
as the recommended acceptance workflow; the earlier blocked attempt below remains
historical evidence, not a claim that CH cannot sign in.

From the project root, with the existing `.env` unchanged:

```powershell
flutter run -d chrome --web-hostname=localhost --web-port=7357 --no-pub
```

1. Sign in normally in the Chrome window Flutter opens.
2. Open `http://localhost:7357/#/debug/chat-acceptance` in that same profile.
3. Click **Check account**, then **Load conversations**. Page size defaults to 1.
   Click a conversation, **Load history**, **Older messages** and
   **Check empty boundary (before 1)** as existing data permits. **Next
   conversations** follows the paired activity/UUID cursor. An empty page is a
   valid observed result, not proof that all accounts have no Chat data.
4. If empty, click **Load my applications — seeker** and select the existing
   application. Creation remains locked. Employer application loading is not
   added; the seeker selects their existing application for the future trial.
5. For a consenting known foreign conversation, paste its UUID, **Select UUID**,
   **Filtered lookup** (expected empty), then **Load history** (expected `42501`).
   Use an existing admin login for admin denial. Do not invent foreign data.
6. Optionally **Observe Realtime** for a selected conversation. Only actual
   subscription statuses and INSERT-message/UPDATE-conversation event metadata are
   recorded. “subscribed” is not delivery proof. Without separately approved
   external writes, delivery may remain unobserved. Refetch history to reconcile;
   no read-state feed, automatic message send or automatic read marking exists.
7. **Copy evidence JSON** and save the clipboard as a local UTF-8 `.json` file;
   tell the agent its path. Evidence contains actor/row IDs, types, counts,
   cursors, timestamps, capabilities and error codes, but no message bodies,
   names, tokens, headers, passwords or raw server error details. Actual message
   bodies are visible only in the signed-in screen. Copy evidence before logout;
   account changes clear results, selection, evidence and observers.

For two concurrent accounts, open the same running server URL in separate Chrome
profiles. No additional authentication system, dependency or browser attachment
is required; CH performs clicks and supplies the Dart-generated evidence.

All four business-write controls (create/send/same UUID-body retry/mark-read)
are disabled by a fixed false approval constant, backed by method-level guards.
There is no UI, URL or build flag to unlock them in this version. Separate CH/KZ
approval is required before enabling a later controlled write trial. No business
writes are authorized by launching the tester. Release/profile builds omit the
route via `kDebugMode`; the page itself also refuses initialization outside debug.
Normal GoRouter authentication redirects protect the debug URL while signed out.

No agent live runtime checks occurred during implementation. Runtime acceptance
is awaiting CH-run evidence. Unavailable foreign/admin contexts, nonempty history,
multiple-page/tied-time data, Realtime delivery, messaging/concurrency, unencrypted
pending storage, device restart/cross-tab behavior and the earlier full rollback
fingerprint comparison must remain explicitly unverified until observed.

Local tester verification: all **23 focused tests** passed (the existing 17 plus
six tester/controller/widget cases). `flutter analyze` reports only the same five
existing info-level findings, none in the added code. `flutter build web --release
--no-pub` succeeded, including its Wasm dry run; the generated JavaScript contains
neither `/debug/chat-acceptance` nor the tester title/banner. Narrow-layout widget
tests ran offline; live Chrome/Android acceptance was not executed. Hash checks
confirm the demo, normal route constants/sidebar navigation, notification source,
environment/dependencies and both guarded SQL candidates remain unchanged.

### Read-only acceptance attempt — 13 November 2026

**BLOCKED at the authenticated-runtime prerequisite; zero live RPC requests.**
The agent reviewed this procedure, the source/repository/models, the checked-in
SQL contracts and the CH-supplied deployment evidence. Tool discovery found no
browser execution or Supabase connector suitable for the signed-in app; connected
document-session discovery returned `executors: []` / “No connected Codex document
sessions were found.” No existing-account credentials, authenticated runtime or
consenting relationship/conversation IDs were supplied for this attempt. Personal
browser credential stores were not searched. Public project configuration alone
does not provide a participant session.

| Read-only runtime check | Status | Actual evidence / missing prerequisite |
| --- | --- | --- |
| Employer and seeker conversation list | BLOCKED | No accessible authenticated participant contexts; no requests issued |
| Real response compatibility and strict Dart parsing | BLOCKED | No real response payloads received; offline tests are not live evidence |
| Existing conversation/message retrieval | BLOCKED | No authenticated access or identified consenting existing conversation/history |
| Foreign relationship denial and account isolation | BLOCKED | Requires participant sessions plus known consenting foreign conversation ID |
| Admin has no blanket access | BLOCKED | No authorized existing admin test context available |
| Conversation paired keyset, message sequence cursor, full/final-page boundaries | BLOCKED | No runtime access or existing pages; do not create data to fill pages |
| Empty results and invalid-cursor/limit/error responses | BLOCKED | No authenticated execution; no HTTP status/SQLSTATE observed |

Local source review finds the two retrieval RPC parameter/return-field names
aligned with the checked-in SQL. This is not proof of the deployed contracts or
real-value parser compatibility; no live mismatch can be confirmed or excluded.
The previous 17 offline tests remain separate evidence and were not rerun for this
documentation-only attempt.

To resume, CH must make existing consenting seeker/employer signed-in contexts
available through an accessible runtime, with their real application/conversation
IDs and existing history if present. An existing unrelated relationship/admin
context is needed for those specific checks; otherwise record them unavailable.
Do not send passwords, JWTs, refresh tokens or service-role credentials in chat.
If direct authenticated runtime access cannot be provided, CH can execute only
the read-only helper calls below and save complete response JSON plus request
parameters/statuses to an agreed protected local file for offline Dart parsing.
Redact credentials entirely; preserve field types/nulls/timestamps/cursors needed
for parsing. Such supplied evidence must be labeled CH-executed, not agent-executed.
Absent existing conversations/history, keep those cases blocked or skipped rather
than call get-or-create or manufacture records.

`get_or_create_chat_conversation`, `send_chat_message` and
`mark_chat_conversation_read` are excluded from this read-only phase, including
foreign-application probes. Mark-read writes state. No write-approval helper was
enabled. Messaging acceptance is not cleared by this attempt; resolve and review
read-only acceptance before a separate messaging approval.

Outstanding: unencrypted pending message storage, native/browser device restart,
cross-tab coordination/acceptance, Realtime observation, authenticated messaging
and concurrency, and the unconfirmed earlier full rollback fingerprint comparison.
No business writes, database changes, SQL/guard changes or UI integration occurred.

Create one `ChatRepository.authenticated(Supabase.instance.client, projectUrl:
dotenv.env['SUPABASE_URL']!)` in the real signed-in workspace when integrating
the UI. Use the existing initialized client/public URL; no service-role key.
Dispose the repository with its owner. Construction performs no fetch or send.

| Repository/source operation | Exact RPC parameters | Parsed result |
| --- | --- | --- |
| `getOrCreate(applicationId)` | `get_or_create_chat_conversation(p_application_id)` | scalar conversation UUID |
| `conversations(...)` | `list_my_chat_conversations(p_limit, p_before_activity_at, p_before_conversation_id, p_conversation_id)` | conversation rows |
| `messages(conversationId, ...)` | `list_chat_messages(p_conversation_id, p_limit, p_before_sequence)` | message rows, descending sequence |
| `sendPending(pending)` | `send_chat_message(p_conversation_id, p_client_request_id, p_body)` | exactly one confirmed message row |
| `markRead(conversationId, messageId)` | `mark_chat_conversation_read(p_conversation_id, p_message_id)` | scalar positive bigint read cursor |

Conversation fields: `conversation_id, application_id, job_id, job_title,
company_name, worker_name, application_status, created_at, activity_at,
last_message_preview?, last_message_at?, last_sequence, unread_count, can_send,
read_only_reason?`. History fields: `message_id, conversation_id, sender_id,
sender_name, body, sent_at, sequence`. Send has those message fields **except
sender_name**; its model makes the name nullable. Nullable keys must still exist.
UUID, boolean, timestamp, integer and page/order consistency checks fail closed.
Bigint values outside Web's exact integer range fail instead of rounding.

Limits are 1–100. Conversation cursor is the last row's **paired** activity time
and UUID; history uses the last sequence exclusively. Full pages expose a next
cursor, possibly leading to an empty final page. On new activity/reconnect,
refresh page one and deduplicate by conversation/message ID; conversation activity
can move between pages. Render history ascending only in the UI, preserving the
descending wire cursor. Backend `can_send`/`read_only_reason` are authoritative.

Call `prepareSend(conversationId, exactBody)` before `sendPending`. Preparation
saves and reads back a UUID/body pair before any network dispatch. On uncertain
transport/parse outcomes, keep the record and retry **that same pair** explicitly.
`restorePending()` recovers owner records after restart but never sends them.
A different body is blocked while that conversation has an unresolved pending
record. No discard/re-key flow is provided that could accidentally duplicate an
ambiguous send. A validated receipt alone confirms persistence; cleanup failure
returns `retryRecordRetained=true`, so reconcile the original pair rather than
create another. No optimistic “sent” state is stored.

Automatic transport retry is disabled. Repository retries only `55P03` and
`40001`, at most three attempts with 100/200 ms delays. `42501`, `55000`, `22023`,
authentication and transport failures do not automatically retry. Use `chatError`
for safe display text; never display/log raw exceptions or pending bodies.
Account changes/logout clear memory and invalidate stale futures, including an
A→B→A switch. UI must also clear its own caches on auth changes. Owner-scoped
pending records intentionally remain on disk for owner-only explicit recovery.

Pending text uses Supabase Flutter's installed generic local storage under
dedicated project/account keys, separate from Auth keys. It is **unencrypted**
device/browser storage, not a secure vault. One shared store serializes operations
within its instance. Cross-tab/device atomic draft coordination is not provided;
do not initiate the same logical send from multiple independent workspaces.
Clearing browser/app storage loses local retry identity. Native durable storage
and browser restart behavior still need device acceptance; offline tests use
in-memory storage with simulated reconstruction/failures.

Bodies preserve exact whitespace/Unicode, count code points (maximum 4000), and
reject the backend's Unicode White_Space-only text, NUL and malformed UTF-16.
No notification insert, direct Chat table write, receipt/typing/presence fiction,
attachment, push, edit/delete or administrator access has been added.

## Minimal manual runtime acceptance

Use existing consenting employer and seeker accounts, each in a separate browser
profile/private window, with an existing real application. Record account roles
and relationship IDs privately. Do not change statuses to create cases. If a
required relationship/account/listener is unavailable, record **SKIPPED** and why.
No SQL Editor postgres/service-role context substitutes for these sessions.

Because Messages is still the demo, these checks can use the existing app's
authenticated browser session and direct RPC calls in DevTools. This is a manual
acceptance aid, not a second UI or another backend. Open JobMate, freshly sign in
normally, then open DevTools Console on that app's origin. Use the **existing
public** URL/publishable key from the app configuration in the two placeholders
below. Never paste a JWT, refresh token or service-role credential into commands,
reports or chats. The helper reads the current local session without printing it.
The installed Supabase Flutter version stores its session JSON under the default
`sb-<project-ref>-auth-token` key. If missing/customized, stop; do not search other
origins or inspect/export the token. Reauthenticate normally if expired.

Paste this helper once per profile (it dispatches nothing until called):

```js
var jmChat = (() => {
  const url = 'EXISTING_PUBLIC_SUPABASE_URL'.replace(/\/$/, '');
  const key = 'EXISTING_PUBLIC_PUBLISHABLE_KEY';
  const authKey = `sb-${new URL(url).hostname.split('.')[0]}-auth-token`;
  const session = () => JSON.parse(localStorage.getItem(authKey) || 'null');
  const owner = session()?.user?.id;
  if (!owner) throw Error('Sign in normally first.');
  const reads = new Set(['list_my_chat_conversations', 'list_chat_messages',
    'list_my_notifications']);
  const writes = new Set(['get_or_create_chat_conversation', 'send_chat_message',
    'mark_chat_conversation_read']);
  let approved = false;
  return {
    approveRealWrites() { approved = true; }, // Only after separate CH/participant approval.
    async rpc(name, params) {
      if (!reads.has(name) && !(approved && writes.has(name))) {
        throw Error('Operation not approved.');
      }
      const s = session();
      if (s?.user?.id !== owner || !s?.access_token ||
          !s?.expires_at || s.expires_at * 1000 <= Date.now()) {
        throw Error('Session changed/expired; sign in and recreate helper.');
      }
      const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
        method: 'POST', headers: {apikey: key, Authorization: `Bearer ${s.access_token}`,
          'Content-Type': 'application/json'}, body: JSON.stringify(params)
      });
      const value = await response.json();
      if (session()?.user?.id !== owner) throw Error('Account changed; discard response.');
      if (!response.ok) throw Error(`HTTP ${response.status}; code ${value?.code || 'unknown'}`);
      return value;
    }
  };
})();
```

Do not share Console/Network captures containing authorization headers, session
objects, message bodies or other users' private data. Record only sanitized
outcomes and agreed IDs/sequences. The helper has no automatic retries.

1. **Read-only, both accounts:**
   `await jmChat.rpc('list_my_chat_conversations', {p_limit:50,
   p_before_activity_at:null,p_before_conversation_id:null,p_conversation_id:null})`.
   Expect only accessible relationships; `[]` is valid before explicit creation.
   For an accessible existing ID, call `list_chat_messages` with
   `{p_conversation_id:'ID',p_limit:50,p_before_sequence:null}`.
2. **Read-only isolation:** with a consenting known foreign conversation ID from
   an existing unrelated relationship, history must reject `42501`; filtered
   conversation list for that ID must return `[]`. An existing admin-only account
   must get `42501` from conversation list/history, not blanket access. Skip if
   unavailable. There is no read-only application Chat access RPC: foreign
   `get_or_create` is a write-capable probe, so defer it to the approved step below.
3. **Stop for separate real-message approval.** Agree one real message and exact
   application, sender and recipient(s). Coordinate a quiet observation interval.
   Read both participants' notification inboxes before writes using
   `list_my_notifications` with `{p_limit:50,p_offset:0}`; keep returned IDs locally.
   Existing employer memberships may mean several eligible employer recipients.
4. After explicit approval, call `jmChat.approveRealWrites()` only in participating
   profiles. Sender calls `get_or_create_chat_conversation` with
   `{p_application_id:'EXISTING_ELIGIBLE_APPLICATION_ID'}`. Call again: same scalar
   UUID, one conversation per application. Do not create from page loads. If an
   unrelated application probe is separately approved, its `get_or_create` must
   reject `42501`; otherwise record this case SKIPPED.
5. Save the new conversation ID in a local Console variable `jmConversation`.
   Prepare one immutable pair before sending. Use a dedicated local key (replace
   OWNER_ID with this profile's own user ID, not a credential):

   ```js
   var jmPendingKey = `jobmate.manual.chat.v1.OWNER_ID.${jmConversation}`;
   if (!localStorage.getItem(jmPendingKey)) {
     localStorage.setItem(jmPendingKey, JSON.stringify({
       p_conversation_id: jmConversation, p_client_request_id: crypto.randomUUID(),
       p_body: 'REPLACE WITH THE ONE AGREED REAL MESSAGE'
     }));
   }
   var jmPending = JSON.parse(localStorage.getItem(jmPendingKey));
   if (jmPending.p_conversation_id !== jmConversation) throw Error('Wrong saved request');
   var jmSent = await jmChat.rpc('send_chat_message', jmPending);
   ```

   Review the saved body locally before the last call. Keep the pair if a timeout
   or lost response occurs. Never generate another UUID to “retry”. A successful
   response is one row; retain `message_id`, sequence and time privately.
6. Recipient retrieves history: same message ID/body/sender/sequence. Sender repeats
   `send_chat_message` with **jmPending unchanged**: identical result, no extra row
   or sequence. Send `{...jmPending,p_body:jmPending.p_body+' changed'}` with the same
   UUID: `22023`. This rejection probe is part of the separate messaging approval.
   Reload history and confirm only one agreed message. Once confirmed, remove the
   manual local record; do not alter the data layer's separate pending keys.
7. Recipient calls `mark_chat_conversation_read` with the retrieved conversation
   and message IDs. Result is at least that message's sequence. Repeat: cursor
   cannot decrease; filtered conversation list reflects updated unread count.
   If older existing messages are available, mark one and confirm no regression.
   Never mark a message merely because a background notification arrived.
8. Re-read notification inboxes. Exactly one new generic `chat_message` / `New
   message` notification per eligible non-sender recipient, no body/deep link;
   no extra notification on identical retry. Sender gets no notification for its
   own send. The RPC exposes no per-message link: use quiet-window IDs and both
   snapshots. Page through offsets if 50 rows are insufficient. With concurrent
   traffic, missing consenting recipients or ambiguous correlation, record
   UNCONFIRMED rather than assert dedup. Flutter never creates notifications.
9. Reconnect/reload and freshly sign in normally if needed, recreate the helper,
   then read persisted history: same message. This proves persistence/recovery,
   **not** Realtime. The demo has no live Chat listener. Mark Realtime observation
   **SKIPPED pending authenticated listener/UI integration** unless an existing
   authorized listener is available. With one, subscribe before the agreed send
   to `public.chat_messages` INSERT filtered by conversation and to authorized
   `public.chat_conversations` changes; confirm the event, reconcile via the RPC,
   unsubscribe on switch/logout. Foreign/admin listeners must expose no private
   rows. No `chat_read_states` subscription. Reconnect must resubscribe and refetch,
   deduplicating RPC/event overlaps by ID; event arrival alone is not persistence.

These minimal checks do not prove concurrent writers, membership/status races,
all RLS paths or lifecycle combinations. Use existing history-only relationships
to inspect `can_send=false` when available; do not manufacture terminal/restricted
states or send extra test messages. Record each case PASS/FAIL/SKIPPED/UNCONFIRMED,
actual SQLSTATE and sanitized evidence; ask CH/KZ to review before UI integration.

## Next real UI integration (not implemented here)

Existing `Phase3Store` powers `lib/features/chat/chat_page.dart`; retain the demo
until acceptance review. Existing routes/gates in `lib/main.dart`,
`lib/shared/navigation/app_routes.dart` and
`lib/features/applications/module2_widgets.dart` already distinguish worker
`/messages`, `/messages/:conversationId` and employer `/employer-messages`,
`/employer-messages/:conversationId`. Do not add a parallel demo or route tree.

1. Compose the repository from the existing Supabase client in the workspace;
   replace demo data in `chat_page.dart` after review. Keep
   `lib/shared/widgets/app_workspace.dart` and
   `lib/shared/navigation/workspace_destinations.dart` consistent with real labels.
   Two panes depend on available content constraints, not inferred platform;
   narrow list/thread uses existing GoRouter routes, safe pop/fallbacks, browser
   history/direct URLs, Web sidebar and Android contextual/system Back.
2. Add explicit Message Employer to
   `lib/features/applications/my_applications_page.dart` /
   `my_application_details_page.dart`, and Message Applicant to
   `lib/features/applications/employer_applicants_page.dart`. Use application ID;
   invoke get-or-create only on deliberate Message, then navigate to returned ID.
   No employer/worker draft/status workflow changes or duplicate eligibility logic.
3. Show loading/empty/error/denied/history-only states from authoritative responses.
   Preserve draft exit guards, accessible composer, Unicode validation, immutable
   pending retries, pagination and safe unread/read marking only for visible
   confirmed history. A read cursor is not a peer read receipt.
4. Add authenticated, authorized Realtime subscriptions with RPC reconciliation,
   account generation/disposal guards and reconnect recovery. Review pending
   Realtime acceptance before removing demo labels; verify Web and Android.

Messaging starts after application, not only hiring. Active pre-hire and hired
relationships follow backend capabilities. Rejected/declined/withdrawn retain
history only; restricted pre-hire relationships are history-only; hired Option B
rights survive job/company restriction, closed postings and completed hired work
as defined by the deployed backend. One conversation per application. No new
client security rules, shifts-based threads or administrator dispute access.

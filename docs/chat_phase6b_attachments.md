# Chat Phase 6B: attachment preparation and UI polish

Current active implementation: [Supabase-only basic attachments](chat_basic_attachments.md),
with 5 MiB JPG/PNG/PDF/DOCX/XLSX support and no antivirus claim or external worker.

Historical initial preparation, 13 November 2026. The foundation/prototype status
and unresolved v2 design below are superseded by
[the local backend/Flutter completion](chat_phase6b_backend_completion.md), which
records implemented candidates and remaining deployment/real-service gates.

Initial state: **Attachments are NOT implemented end to end or deployable.**
No live SQL, uploads, messages, Storage inspection or deployment occurred. The
existing QA conversation and text RPCs are unchanged. This document supplements,
not replaces, the [Phase 5 evidence review](chat_phase5_runtime_review_and_phase6_ui.md).

## Inspected sources and findings

- `resume_page.dart` already uses `file_selector`/`XFile`, pre-reads length, keeps
  bytes in memory, confirms dirty exit and retries the same upload identity.
- `resume_repository.dart` uses immutable `uploadBinary(upsert:false)` to a
  private owner-scoped path and 60-second signed download links, checking actor
  before and after asynchronous operations. A basic PDF header check is not AV.
- `20261103000100_profile_assets.sql` defines `jobmate-resumes` (private, 5 MiB,
  PDF) and metadata-backed read policies. Its save RPC trusts Storage metadata
  size/MIME; that is insufficient for Chat's required server content validation.
- Verification/work/dispute files have separate purpose-specific policies. They
  must not be repurposed for conversation files. Live bucket/policy configuration
  has not been freshly inspected; catalogue source is not proof of live state.
- Existing dependencies already include file_selector, image_picker, mime,
  url_launcher and uuid; no dependency or environment configuration was added.
- `chat_messages.body` has the deployed nonblank 1–4000-codepoint CHECK. Existing
  send/list RPCs and Dart strict parsers expect valid nonempty bodies. Replacing
  a missing caption with a fabricated text marker would break required semantics.
- Existing eligibility/locking helpers enforce current actor, application,
  membership, company verification and restrictions. Reuse those helpers and
  locking order, not a client participant allowlist or duplicated eligibility.
- Realtime invalidates and reconciles through the authorized repository. Existing
  notification dispatch/dedup and sequence allocation belong to the atomic send.

## Local implementation

`chat_attachment_draft.dart` validates extension, filename, 1–10,485,760 bytes and
basic image/PDF/OLE/ZIP headers; copies bytes into a read-only memory buffer.
DOC/XLS share an OLE header and DOCX/XLSX share ZIP: **these checks do not distinguish
their actual contents and must never be treated as server verification**.
No raw bytes, file paths or signed URLs are persisted. Memory is released by
removal/account change/disposal; this is not cryptographic memory erasure.

Chat's **debug-only** paperclip explicitly says **Preview attachment (upload unavailable)**.
Release builds retain the UI polish but exclude the unfinished picker entry.
One local selection displays name/size/image thumbnail or document icon. Cancel
keeps the previous selection; replacement requires a valid new file. It supports
removal and guards exits, including while a picker is pending. Late picker
results are discarded after actor/thread changes. Selected files block text send,
Ctrl+Enter and saved-send retry, including attachment-only drafts. No upload API
or progress percentage is presented as working. Text sending resumes after
removal and retains the existing repository's persistent UUID/body retry.

UI polish: selected conversation border/background, name/preview hierarchy,
activity timestamp, compact unread badge; flatter spaced message bubbles,
incoming-only explicit read buttons, inline paperclip/input/Send. Blank/invalid
text cannot enable Send. Existing route exit, platform navigation, read-only,
pending/error and backend-authoritative states are preserved.

## Proposed complete backend protocol (NOT implemented contracts)

Keep the five current RPC signatures and all existing rows compatible. Do not
wire the proposed names below into Flutter until implemented and validated:

1. Authenticated `reserve_chat_attachment_v2(conversation, request UUID,
   attachment UUID, name, size, SHA-256, requested MIME)` reserves immutable
   metadata for exactly that actor/conversation/request. Use participant and
   application eligibility locks before reservation. Limit one attachment per
   message, active reservations per actor, byte quota, expiry (e.g. one hour),
   and rate limits. Same UUID plus identical fields returns existing reservation;
   any differing body/file identity is rejected, including text/v2 collisions.
2. Authenticated upload Edge Function streams at most 10 MiB into private
   quarantine. Derive canonical path server-side; never accept a caller bucket
   or path. No user Storage INSERT/UPDATE/DELETE or reusable upload token. Enforce
   full actual byte count/hash and authorization independently of claimed headers.
   Per-reservation locking prevents competing upload bodies; immutable upload,
   no overwrite. Client cancellation aborts transfer, not proof that bytes were
   never stored; reconcile reservation on retry before resuming.
3. Trusted worker validates real file contents and scans bytes. Detect PNG/JPEG
   through bounded decode; check PDF structure; parse OLE streams to distinguish
   Word/Excel; parse OOXML package relationships/content types, ZIP expansion and
   nesting limits. Reject executable/polyglot, malformed, encrypted/uninspectable,
   unsupported and macro-bearing content, external active content where feasible.
   Reject mismatched actual/claimed MIME. Store actual MIME/size/hash, scanner
   engine/signature version and verdict using a server-only function. A client
   cannot set `clean`, bypass scanning or download quarantine. Timeout/unavailable
   scanner fails closed. Header sniffing alone cannot satisfy this step.
4. `send_chat_message_v2(conversation, request UUID, optional caption, attachment
   UUID)` atomically binds one **clean** owned reservation to one message, assigns
   sequence and sends generic notifications once. Reuse current shared locks
   before final eligibility check; lock recipients in the existing order. Same
   committed request/body/file returns the same receipt even if sending becomes
   read-only, after rechecking history authorization. Changed requests fail.
   Failed binding rolls back message/activity/notifications together. SQL cannot
   atomically commit a Storage HTTP upload; the reservation state bridges that gap.
5. Add v2 history/list projections returning nullable caption + typed attachment
   metadata. Old text RPCs remain unchanged. The concrete compatibility decision
   for old clients must be reviewed: recommended separate v2 message envelope
   keyed into the shared sequence, with old projections excluding attachment-only
   rows and deriving internally consistent cursors/previews/unread counts. This
   requires careful versioned list/read/realtime behavior and is **unresolved**;
   do not relax the current CHECK or strict Dart parser in isolation. No fake
   attachment placeholder may be inserted into existing text bodies.
6. Downloads authorize **current** active participants and committed binding before
   granting 60-second links or an authenticated stream. Use attachment ID only,
   never caller paths. Links are bearer capabilities until expiry; participant
   revocation cannot retract an already issued link. For stricter immediate
   revocation use an authenticated streaming handler, not signed links. Serve
   documents as downloads with safe filename and `nosniff`; never inline HTML or
   untrusted Office content. Keep signed URLs out of disk, logs and evidence.
7. Cleanup worker reconciles old uncommitted reservations under locks. Delete bytes
   through Storage API, never direct `storage.objects` DELETE; mark expired only
   with correct ownership/state. Retry deletion failures without reusing paths.
   Never collect a committed attachment. Quarantine/clean-without-send are orphans
   eligible after grace period; audit scanner/cleanup failures without filenames
   or payloads in ordinary client logs.

The proposed `jobmate-chat-files` bucket is private, maximum 10 MiB, MIME allowlist.
Paths are `<conversation>/<sender>/<attachment>/file`, not original filenames.
Metadata carries original filename/MIME/size/hash/state, request and exact
message/sender/conversation association. RLS must combine current participant
access with committed/clean status, plus restrictive Storage boundaries against
unrelated permissive rules. Service-role access is a trusted bypass and stays
server-only. Membership/restriction changes must be exercised, not inferred from
folder names. Existing Storage policies must be freshly inspected before approval.

## SQL draft and rollback plan

`supabase/candidates/chat_phase6b_attachment_foundation.sql` is a **guarded,
incomplete schema/policy foundation**, deliberately outside deployment migrations.
It drafts the metadata relation, composite binding key, private bucket and
restrictive client-write/read boundaries; it defines **no** reserve/scan/send/list
RPC and has no privileged uploader. It ends in ROLLBACK and unconditionally raises
before DDL. It is not a runnable attachment migration and has not been PostgreSQL
compiled/tested. Both original Chat guards/migration hashes remain unchanged.

Before a final additive migration exists: resolve v2 envelope compatibility and
trusted scanner implementation; then add pinned live preflight, exact source
fingerprints, guarded rollback-only test and catalogue/security assertions.
No guard should be removed based on this document.

Rollback plan for later approved isolated validation: execute entire candidate in
one transaction ending ROLLBACK; compare pre/post fingerprints, including all
Storage rules/buckets. Permanent release: prefer disabling new attachment entry
points and retaining delivered files/metadata. Destructive rollback only if no
committed rows or object bytes exist, after separate review: remove only new
policies/functions/table/key/bucket in dependency order, never original text
objects. A populated bucket requires an independently approved retention/export
and cleanup plan; do not silently delete attachments or fabricate a down script.

## Validation and outstanding gates

**168 focused regression tests passed**, including 15 new selection/widget tests:
all eight extensions, header mismatch/unsupported/path filenames, empty and exact
10 MiB/oversize boundary, immutable bytes, three responsive selected-file layouts,
caption-send/shortcut blocking, cancellation/error retention, incoming-only read
controls, file-only exit protection and late-picker account-switch isolation.
The existing text repository/source/debug tester/application/navigation tests
also passed. **Four Chat render checks passed** (390/1440 normal, 320/text 1.6,
568/text 1.3); wide/narrow output was visually inspected. These are offline VM
tests, not live Chrome/Android acceptance. `flutter analyze --no-pub` reports only
the five pre-existing informational findings, no new findings/errors/warnings.
`flutter build web --release --no-pub` passed (50.1 seconds, Wasm dry run also
passed). The release JS bundle contains none of the debug tester route/title,
QA application UUID, fixed QA message strings or unfinished attachment-picker
tooltip. Browser interaction and native Android build were not tested here.

Changed files in this pass: `README.md`, `lib/features/chat/chat_page.dart`, new
`lib/features/chat/chat_attachment_draft.dart`, new
`test/chat_attachment_draft_test.dart`, this document,
`docs/chat_phase5_runtime_review_and_phase6_ui.md`, and new
`supabase/candidates/chat_phase6b_attachment_foundation.sql`. No other application,
SQL, dependency or authentication file was edited. The existing standalone and
rollback candidates still hash respectively to
`8704715E62DE895324A651C41BFD55CC2A756D2C739FDED85B624FB4AB5FA0E7` and
`84DDF9AB9F30B2FC1930C3F68CFE7371B730C0AE1ADFECEBA859D070368EC099`;
both original approval guards remain intact. pubspec.yaml/lock hashes also match
their pre-change values. No Git operations were performed.

Offline picker/header
tests do not prove actual full-format validation, malware detection, Storage/RLS,
atomic attachment-only send, upload cancellation/retry, duplicate prevention or
remote account isolation. Those remain BLOCKED until the backend exists and has
isolated real-PostgreSQL/Storage/worker security tests. Existing text retry tests
continue to cover the unchanged text path only.

Required security tests before enabling uploads: anonymous/foreign/Admin/revoked
actor, account switch during each await, forged paths/sender/reservation/hash,
cross-conversation association, conflicting UUID/body/file replay, concurrent
upload/finalize/cleanup, restriction changes during send, malformed/oversized/
encrypted/macro/polyglot/decompression-bomb inputs, scanner outage, interrupted
upload/lost finalize response, expired signed links, no quarantine downloads,
no plaintext persistence and old text-client regression.

Malware scanning reduces risk, does not guarantee safe files. Use maintained
engine/signatures, bounded parsers in an isolated worker, quarantine, no inline
Office execution, optional content disarm/reconstruction for high-risk documents,
rate limits and abuse handling. No scanner service/configuration is present in
this checkout; choosing and provisioning one needs a separate team decision.

Outstanding historical items remain explicit: unencrypted text pending storage;
restart/cross-tab coordination; foreign/Admin isolation; reconnect/gap and
concurrency runtime acceptance; full notification dedup coverage; historical
5761-record rollback fingerprint comparison unconfirmed. Attachment bytes must
remain memory-only until an encrypted, reviewed durable strategy exists. Local
prototype selection is lost on restart; unknown remote outcomes eventually need
server reservation recovery and user file reselection/hash match, never a new UUID.

## Next actions and approval boundary

CH can review text UI polish and local file previews without sending anything.
Minimum unblock: agree on a trusted file-validation/scanner execution environment
and v2 envelope compatibility, complete the server protocol and regression/security
tests above, review a complete guarded migration/worker and only then seek live
deployment approval. No existing QA authorization covers this expansion.

Later approval should name the reviewed migration/worker hashes, private bucket,
application `fb352472-8a41-45cf-a9a6-5e70e25e66e8`, conversation
`e08aee68-59d5-40eb-aaf8-bc5676d19f7f`, seeker/employer UUIDs, exact non-sensitive
test files (SHA-256/type/size), captions, maximum sends/uploads/retries and cleanup
retention. Deployment and controlled attachment writes are separate explicit
CH/KZ approvals, not authorized by this local preparation. No approval is sought
for deploying this incomplete foundation.

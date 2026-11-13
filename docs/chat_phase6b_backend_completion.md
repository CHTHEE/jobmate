# Chat Phase 6B local backend and Flutter completion

**Future scanner enhancement.** The active controlled university-demo design is
now [Supabase-only basic attachments](chat_basic_attachments.md). It does not
require the worker/hosting described below and does not claim antivirus protection.
These scanner backend artifacts remain preserved, separate and undeployed.

13 November 2026. Supersedes the initial foundation/prototype portions of
[attachment preparation](chat_phase6b_attachments.md). Local implementation is
prepared, **not deployed or production accepted**. Both original Chat SQL guards
and source hashes are unchanged. No live SQL, uploads, messages or conversations
were executed/created by the agent. No accounts, packages, hosting or Git changes.

## Recommended scanner and cost

Use Supabase Auth + Edge orchestration + private Storage + one **team-controlled
Node/ClamAV Linux worker**. Reuse an authorized university VM if one is available;
none is evidenced in this checkout. Otherwise budget approximately **€6–15/month**
for a small 4–8 GiB VM, plus regional/tax/IPv4 differences and existing Supabase
Storage/egress/Edge usage. This is a budget estimate, not a purchased service or
guaranteed regional quote; prefer 8 GiB for signature reload headroom.

ClamAV is an [open-source antivirus engine](https://www.clamav.net/about.html),
with [3–4 GiB recommended RAM](https://docs.clamav.net/). Supabase Edge has a
[256 MB memory limit](https://supabase.com/docs/guides/functions/limits); Edge
does not itself supply antivirus. The VM budget is an estimate; confirm current
availability, regional pricing, tax and privacy requirements before ordering.

| Option | Assessment |
| --- | --- |
| Edge + commercial private scanning API | Simple operations, but an additional processor receives full documents; requires pricing, confidentiality/retention agreement and region review. No provider/credentials are currently available; not selected |
| Team-controlled ClamAV worker | Selected; no per-file scanner licence fee, one VM/patching/signature-update responsibility; private files stay within Supabase and the team's chosen host |
| Existing resume/document infrastructure | Reuse picker, immutable upload, authenticated client and short download URLs. Existing MIME/size/header validation is **not malware scanning** and cannot approve Chat files |

No public malware-analysis service is used. Worker receives file bytes and
filename/MIME over HTTPS, not Supabase keys or user tokens. It holds bytes in
process memory; ClamAV may use OS temporary storage, so use private temporary
storage and disable swap/core dumps as appropriate to host policy. No request
payload logging or sample submission. The hosting operator still processes
documents: CH/KZ must select an acceptable location and retention policy.

## Implemented backend

`supabase/candidates/chat_phase6b_attachment_foundation.sql` is now a complete
**guarded additive migration candidate** outside auto-deployment migrations.
The new unconditional guard prevents execution; no unguarded copy is prepared.
An owner-only backend release row also defaults **off**, independently of both
Flutter and Edge. It can restrict writes to exactly the approved conversation
and two actor UUIDs during acceptance. Participants/service-role cannot change
that row. A later unrestricted release is a separate explicit decision.
The generated rollback-validation copy uses the **exact same guarded DDL body**,
adds catalogue/ACL/MAINTAIN assertions and ends ROLLBACK. The reviewed six-hook
PostgreSQL 17.11 event baseline is copied exactly from the original validation
source; changed live hooks/version must stop deployment for fresh review.

Compatibility is resolved without changing old source, RPC signatures, message
constraints, sequences or notification code: v2 attachment send calls the existing
`send_chat_message` inside the same transaction, then binds its approved file.
Caption-only semantics stay explicit. With no caption, the v1 body is the visible
description `Attachment: <original filename>`; v1 clients display that description.
This is documented compatibility content, not a caption or an attachment parser.
V2 supplies the actual nullable caption and typed file separately. Old list,
pagination, unread/read cursors and Realtime remain internally consistent because
every attachment is a real row in the existing ordered message table.

New participant RPCs: `reserve_chat_attachment_v2`, `get_chat_attachment_v2`,
`prepare_chat_attachment_upload_v2`, `prepare_chat_attachment_scan_v2`,
`send_chat_attachment_v2`, `list_chat_messages_v2`,
`list_pending_chat_attachments_v2`. Trusted service-only RPCs:
`finish_chat_attachment_scan_v2`, `claim_expired_chat_attachments_v2`,
`complete_chat_attachment_cleanup_v2`. All definer functions pin empty search_path,
revoke default PUBLIC/anon access, and retain current participant/application
eligibility helpers and locking. The old deployed SQL source is not replaced.

- Private `jobmate-chat-files` bucket holds opaque quarantine chunks and final
  objects; no direct client INSERT/UPDATE/DELETE. Restrictive policies protect
  against unrelated permissive Storage rules. Pending/scanning/approved-but-unsent
  and rejected files are unreadable to recipients. Final access requires committed
  metadata and **current** participant authorization. No public bucket/path.
- One attachment per message. Reservation fixes actor, conversation, request/file
  UUIDs, nullable caption, filename/MIME/size and full-file SHA-256. Replays with
  different metadata/hash fail; text-UUID collisions cannot retrofit attachments.
- Edge verifies the real Auth session and SQL eligibility, then stores immutable
  256 KiB chunks. Repeated chunks must be byte-identical by SHA-256. SQL leases
  each upload for 10 minutes to prevent cleanup racing a hosted Edge request;
  cleanup waits beyond all leases. The scan lease is two minutes and token-bound.
- Scan assembles exact-length bytes, verifies reservation hash and invokes the
  real configured worker. No mock configuration exists in production adapters.
  Missing URL/secret, stale signatures, timeout, malformed response, busy worker
  or unexpected scan results cannot approve/send a file.
- State flow: pending → scanning → approved/rejected → committed (approved only).
  Uncommitted records expire after one hour. Quotas: eight outstanding reservations,
  100 new reservations/day/actor, 160 chunk attempts and four scan attempts per
  reservation. No automatic new identity after an uncertain result.
- Worker performs bounded structural validation (PNG CRC/dimensions, JPEG marker/
  dimension checks, PDF header/catalog/pages/end/active-content heuristics, bounded
  ZIP/OOXML structure/CRC and OLE directory/main-stream checks), then ClamAV
  INSTREAM. Signatures/type checks and **actual antivirus scanning are separate**.
  ClamAV socket error/limits/unexpected responses fail closed; known findings
  reject. The adapter also checks database-file age (48-hour maximum) and engine
  version. FreshClam + clamd reload and health monitoring remain host obligations.
- Final send rechecks current authorization/eligibility through the existing send
  RPC. Message/sequence/notifications/attachment binding commit atomically in SQL;
  approved replay after uncertain acknowledgement returns the same stored receipt.
  Upload is a separate Storage HTTP operation and is reconciled by reservation.
- Cleanup claims expired records under locks, deletes through Storage API and
  retries failed deletion; keeps tombstones, never reuses identities. For committed
  attachments it removes only temporary chunks after expiry/leases, retaining the
  delivered final file and metadata. Scheduler is server-only and separately secret.

## Flutter integration

`JOBMATE_CHAT_ATTACHMENTS` defaults **false**. Current default builds use existing
text history/RPCs; debug builds retain the local preview. Do not enable the flag
against live Supabase until deployment/acceptance approval. After approval, the
flag switches history to v2 and wires the actual authenticated attachment gateway.
The data/controller path is prepared locally; no credentials or new auth system.

- Actual installed Supabase Functions client transfers binary chunks with
  acknowledged-byte progress and an abort signal. Cancel/account switch aborts
  transport; a server request can still finish, so retry reconciles the same
  reservation. Cancellation is not a guarantee of remote rollback.
- Composer supports one file plus optional valid 4000-codepoint caption, memory
  previews/removal before reservation, upload/scan/rejection/error status and
  explicit retry. Once reserved the caption/file identity is locked. Rejected or
  expired drafts may be dismissed; uncertain outcomes must be reconciled.
- Server-side pending requests can be recovered without sending automatically.
  Pending uploads require reselecting the same filename/MIME/size/**hash**; approved
  ones can finish without keeping the original bytes. Missing recovery results
  show a retry state. No bytes, signed URLs, attachment captions or file IDs are
  added to existing plaintext pending-send storage.
- Strict typed history checks message/attachment sender, conversation, message ID,
  caption and canonical path. Approved document cards and image thumbnails use
  current-session authorized 60-second Storage links, kept only in memory.
  Documents use explicit downloads. Signed links remain bearer capabilities until
  expiry, including after a later participant revocation; immediate revocation
  would require a streaming gateway rather than links.
- Existing Realtime events reconcile v2 history after the atomic commit. No new
  publication member, notification emitter, optimistic sent receipt or QA message
  constant is introduced into production. Draft exit and account clearing remain.

## Real limitations and validation gates

Structural validation is deliberately conservative, not a complete PDF/Office
renderer or proof of harmless content. It may reject unusual valid documents;
legacy CFB/DIFAT, encrypted/macro-bearing packages and active content have restricted
support. No antivirus guarantees detection of unknown malware or all active
content. Require the reviewed ClamAV configuration: macro/encryption/limit/broken
media alerts, bounded recursion/expansion and maintained signatures. Keep documents
as downloads and software updated; optional content disarm/reconstruction is a
future stronger mitigation. Do not describe a mock, extension check or structural
acceptance as real AV acceptance.

Node tests inject clearly named **test-only mocks** and use synthetic buffers/
loopback services. No real ClamAV daemon or Deno runtime is installed here; no
database/Storage test was executed. PostgreSQL compilation, actual RLS/Storage
HTTP enforcement, exact old-RPC definition fingerprints, concurrent locking/
cleanup, notification dedup and real malware/clean fixtures remain **UNVERIFIED**
until isolated integration testing. The SQL security test candidate is guarded
and documents fixture inputs; its trusted verdict is explicitly a SQL mock.

Historical outstanding items remain: full 5761-row rollback fingerprint comparison,
foreign/Admin runtime isolation, unencrypted existing text pending storage,
restart/cross-tab/concurrency and full Realtime reconnect/notification-dedup
acceptance. No claim that attachment mocks close those checks.

## Configuration for CH/KZ after infrastructure approval

1. Provide an approved Linux VM (prefer 8 GiB), current Node and ClamAV/FreshClam,
   restricted Unix clamd socket, HTTPS reverse proxy and a service user. Review
   `tools/chat_scanner/clamd.conf.example` and `.service.example`; no installations
   were performed. Set server-only `CHAT_SCANNER_SECRET` (at least 32 random
   characters), `CLAMD_SOCKET`, `CLAMAV_DATABASE` (actual daily.cld/daily.cvd file),
   optional PORT (default 8788). Worker binds loopback only. Public endpoint is the
   authenticated reverse-proxied `/scan`, never the ClamAV socket. Match proxy
   10 MiB limit/60-second timeout; disable payload/header logging, swap/core dumps
   as required; patch and monitor updates/reloads, memory and 48-hour cutoff.
2. Edge uses existing server `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
   `SUPABASE_SERVICE_ROLE_KEY`; add server secrets `CHAT_SCANNER_URL` (HTTPS
   endpoint including `/scan`), `CHAT_SCANNER_SECRET`,
   `CHAT_ATTACHMENT_CLEANUP_SECRET` (separate 32+ random characters),
   `CHAT_ATTACHMENT_ALLOWED_ORIGIN` (exact approved app origin), and
   `CHAT_ATTACHMENTS_ENABLED` (leave unset/false until approved). None belongs in
   Flutter `.env`. Keep gateway JWT verification enabled. Each normal operation
   additionally verifies Auth user and uses their JWT for participant RPCs.
3. Schedule POST `chat-attachments?op=cleanup` hourly using server service-JWT
   Authorization and `x-cleanup-secret`. The service JWT and separate secret must
   both match. No browser cleanup control or broad client service permission.
4. Capture fresh baseline including deployed text RPC/helper definitions, ACLs,
   six hooks, Storage policies/buckets and table constraints; compare exactly
   before/after isolated rollback trial. Review additive key/bucket/policy costs.
   `chat_phase6b_readonly_preflight.sql` returns the ten original routine definitions,
   normalized ACLs (including grantor/options), a compact MD5 change fingerprint,
   and existing policies/buckets. Review and preserve the complete output; MD5 here
   is a catalogue comparison aid, not authentication. The candidate requires the
   reviewed value as transaction-local `jobmate.chat_reviewed_backend_md5` and uses
   the exact shared fingerprint CTE. Missing/different value blocks DDL. The value
   is not supplied/auto-approved by Codex. After separate approval the execution
   copy must set it after BEGIN; never infer a prior historical match from it.

## Approval sequence and rollback

First obtain isolated test approval and configure real scanner there. Compile the
candidate, exercise the guarded catalogue and semantic tests plus Storage HTTP,
two actors and foreign/Admin cases, clean/malware/timeout fixtures and concurrent
cleanup. Do not use the shared production QA application for isolated destructive
testing. Record hashes/results and fix any discrepancy before deployment review.

Only then CH/KZ can approve the exact reviewed migration, Edge/worker/config hashes
and private bucket for the existing project, with fresh baseline and quiet schema
window. Request that approval separately; this turn authorizes local preparation
only. No guard is removed and no execution copy is prepared now. Permanent
execution must use a separately reviewed transaction and post-deployment catalogue
checks, with default-off Flutter and Edge flags retained initially.

Controlled attachment testing approval must name application
`fb352472-8a41-45cf-a9a6-5e70e25e66e8`, existing conversation
`e08aee68-59d5-40eb-aaf8-bc5676d19f7f`, seeker
`fb66cc74-1a4f-44e0-ae4f-6831c7a39b8f` and employer
`50c0d35f-c1cd-4fa1-b864-6f6e1e833fd0`, an exact manifest of non-sensitive test
files (name/type/bytes/SHA-256), captions, maximum uploads/sends/retries and retention.
Suggested narrow scope: one file of each supported format (JPG, PNG, PDF, DOC,
DOCX, XLS, XLSX), seven total sends across those actors, identical retries only,
one approved scanner-outage attempt with no message, normal server notifications,
history/pagination/read marks and Realtime observation; no new conversations or
accounts and no unrelated writes. Malware signature fixtures belong only in the
isolated environment, never normal user conversations.

Rollback: before deployment, use the generated guarded validation candidate ending
ROLLBACK and preserve before/after catalogue comparison. After deployment, disable
new upload flags first and keep delivered metadata/files. The guarded empty-only
rollback candidate refuses any metadata or Storage objects, removes only additive
objects without CASCADE, and never deletes file bytes. A populated deployment
requires a separately approved retention/forward-repair plan.

## Local verification and exact changed files

Actual local results:

- **183 focused Flutter tests passed**: attachment model/controller/transport,
  existing Chat source/repository/debug tester/UI and application/navigation
  regressions. After the final stricter caption-key check, all **27 affected
  model/controller/transport tests passed** again. These counts are overlapping,
  not 210 independent tests. Upload/scanner/commit outcomes are fake or loopback.
- **Four Chat render checks passed**, including 320/text 1.6 and short landscape;
  enabled attachment composer/document cards additionally tested at 320/1440.
- **19 Node worker/Edge protocol tests passed**, using synthetic PDF/Office/image
  structures and test-only scanner responses. Include outage, rejection, malformed
  content, hash mismatch, immutable replay, cleanup and authorization failures.
- SHA-256 standard vectors passed natively and in **compiled JavaScript executed
  with Node**, including empty/abc/million-a. This found and corrected a dart2js
  Uint64 accessor incompatibility. This is not a Chrome interaction test.
- Original Chat checker: **187 offline structural/scope checks PASS**. New checker:
  protected original hashes, guarded migration body equality, shared routine
  fingerprint CTE equality, exact six-trigger baseline, secured RPCs, leases,
  default-off release gate and catalogue assertions **PASS**. No SQL compilation
  or runtime is implied by structural checks.
- `flutter analyze --no-pub`: only five pre-existing informational findings in
  company management, sign-up and work engagement closure; no new warnings/errors.
- Edge TypeScript entry passes Node syntax checking. **Deno type checking and
  actual Edge deployment remain UNVERIFIED**, because Deno is unavailable here.
- Final `flutter build web --release --no-pub` **PASS** (47.2 seconds), including
  Wasm dry run. Default-off release JS excludes debug route/title, QA application
  ID/fixed messages, local-preview tooltip and attachment retry controls. The
  earlier build also passed; this result is for the last model change. No Chrome
  interaction, Android build or standalone Wasm runtime acceptance is inferred.

Standalone structural checks never substitute for executing the SQL in an isolated PostgreSQL project.

Modified: `README.md`, `docs/chat_phase6b_attachments.md`,
`docs/chat_phase5_runtime_review_and_phase6_ui.md`,
`supabase/candidates/chat_phase6b_attachment_foundation.sql`,
`lib/features/chat/chat_attachment_draft.dart`, `chat_models.dart`, `chat_source.dart`,
`chat_dependencies.dart`, `chat_page.dart`, `test/chat_source_test.dart`.

Created: this document; `lib/features/chat/chat_attachment_models.dart`,
`chat_attachments.dart`, `chat_attachment_card.dart`, `chat_file_digest.dart`;
`supabase/functions/chat-attachments/index.ts`,
`supabase/functions/_shared/chat_attachments/protocol.mjs`;
`supabase/candidates/chat_phase6b_rollback_validation_candidate.sql`,
`chat_phase6b_security_tests.sql`, `chat_phase6b_empty_rollback_candidate.sql`;
`supabase/candidates/chat_phase6b_readonly_preflight.sql`;
`supabase/candidates/chat_phase6b_catalog_verification.sql` (read-only checks of
the initial disabled deployment, generated from the same catalogue assertions);
`tools/chat_scanner/validate.mjs`, `server.mjs`, `scanner.test.mjs`, `prepare_sql.mjs`,
`check_sql.mjs`, `digest_web_check.dart`, `clamd.conf.example`,
`jobmate-chat-scanner.service.example`, `manifest.mjs`;
`test/chat_attachments_test.dart`, `test/chat_attachment_transport_test.dart`.
Generated review manifest: `docs/chat_phase6b_artifact_hashes.json`; all backend
artifact SHA-256 values and a deterministic bundle hash are recorded there.

Approval wording, **only after isolated integration gates pass**:

> CH and KZ approve permanent deployment only of the Phase 6B migration,
> Edge adapter, private worker and reviewed configuration identified by the exact
> backend bundle SHA-256 in chat_phase6b_artifact_hashes.json. We have preserved
> and reviewed the fresh catalogue/Storage baseline and isolated test evidence.
> Deploy with backend release row, Edge and Flutter attachment flags disabled.
> No attachment uploads/messages or unrestricted feature activation are authorized
> by this deployment approval. Preserve both original SQL guards/source files.

Separate controlled trial wording:

> CH and KZ approve enabling the attachment backend release row only for
> conversation e08aee68-59d5-40eb-aaf8-bc5676d19f7f and the two participant UUIDs
> listed above, the scanner/Edge flag and CH's local Flutter acceptance build.
> We approve only the reviewed seven-file manifest with its exact hashes/captions,
> at most seven logical requests/messages, at most two identical full upload passes
> and two identical send retries per request, and one no-send scanner-outage
> attempt on one of those same requests; own read cursors, normal notifications, history/pagination and Realtime
> observation are included. No new accounts/conversations or unrelated writes.
> Codex may prepare the scoped execution/tester setup but must not execute live writes.

These are review templates, not approvals received or instructions to deploy now.
The populated release row must retain `trial_conversation` and exactly those two
`participant_ids`; enabling it globally is outside the trial scope. Actual file
manifest and test evidence must be concrete before CH/KZ approve either step.

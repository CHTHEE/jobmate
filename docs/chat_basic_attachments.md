# Basic Chat attachments — Supabase-only university demonstration

**Option B decision, 14 November:** defer automatic hourly cleanup for the demo.
No cleanup Cron job is registered per CH's checks. Keep both transport blockers,
original security prechecks, diagnostics, guards, Vault entries and extensions
unchanged. Authorized manual Edge cleanup remains available; abandoned uploads
may accumulate until maintenance runs. Automatic cleanup must be resolved before
production use. See the activation runbook and preserved compatibility review.

**14 November update:** CH reports live Web image send/enlarged recipient preview,
PDF reply/recipient download and text exchange PASS after the HTTP 204 fix.
The local [final UI polish](chat_ui_polish.md) now uses one-click downloads,
compact bubbles, navigation unread dots and viewport-gated automatic reads. It
supersedes the older two-click/manual-read UI descriptions below. Cleanup and
mobile acceptance remain outstanding; no backend/Edge changes accompany the polish.

**Current activation status:** CH reports permanent database/Storage/Edge deployment
and independent verification complete; CH/KZ have approved general activation and
the short image/PDF/text acceptance check. The Flutter flag now defaults true.
Codex has not activated remote gates or executed live writes. Follow
[the concise activation and cleanup runbook](chat_basic_activation.md).
Earlier disabled/default-off statements below are historical preparation records.

The first hosted PNG was reported validated but its Edge reply failed on parsing
a successful void RPC's empty body. The targeted index.ts fix and original-request
retry are documented in [the incident resolution](chat_basic_validation_failure_20261113.md).
Deploy only the corrected entry point; no validator, protocol, schema or gate
change is part of that fix. Hosted retry acceptance remains pending CH's evidence.

13 November 2026. This is the active attachment design. It supersedes the scanner
requirement for the **controlled university demonstration only**. No antivirus or
malware-free verdict is provided. Public production release requires a separate
security review and suitable malware protection.

**13 November update:** CH reports successful corrected r1 DDL/catalogue trial,
confirmed rollback/transaction termination and exact original/post-failure/post-r1
baseline/preflight equality (2652 records, ten routines, 78 policies, eight buckets).
Codex verified the local trial hash and exact permanent/trial DDL equality.
Permanent deployment and attachment QA are still separately unapproved; every
release gate remains off. See [deployment preparation and separate approvals](chat_basic_deployment_preparation.md)
for evidence, hashes, configuration, verification and five-file QA requirements.
Earlier unexecuted/blocked descriptions below describe the original preparation;
the linked dated deployment record supersedes their rollback-validation status.

## Implemented and reused

Uses existing Supabase Auth/session, private Storage, PostgreSQL RPCs and one Edge
Function (`chat-basic-attachments`). No worker, ClamAV, external scanning API,
Docker, WSL, VM, paid hosting, package installation or new Flutter dependency.
Only the existing Supabase plan's Storage/egress/Edge usage applies.

Reused the attachment picker/preview, typed models/controller, immutable chunk
transport, full-file SHA-256 retry binding, cancellation, server recovery, message
binding, notification transaction, Realtime reconciliation, download cards,
account isolation and responsive composer. Existing five text RPC signatures and
the deployed Chat migration are unchanged. Attachment-only messages use the
documented v1 compatibility body `Attachment: <filename>`; the basic history RPC
returns the actual nullable caption and typed file separately.

Supports **JPG/JPEG, PNG, PDF, DOCX and XLSX**, one file/message, optional caption
with the existing 4000-codepoint rule. Limit is **5 MB = 5,242,880 bytes (5 MiB)**
at picker, model, SQL constraint, bucket and trusted Edge validation. DOC, XLS,
DOCM/XLSM, executable/unsupported formats are rejected.

Scanner sources under `tools/chat_scanner`, `supabase/functions/chat-attachments`,
`supabase/functions/_shared/chat_attachments` and all previous Phase 6B SQL
candidates are preserved byte-for-byte against their existing hash manifest.
They are a future enhancement, not a dependency or a fallback that returns a
fake successful scan. Basic code uses separate `chat_basic_attachments` metadata,
`jobmate-chat-basic-files` bucket, `_basic_v1` RPCs and `basic_attachment_release`
gate. It cannot approve or send an old scanner reservation. Active Flutter is
wired to the basic API; future scanner UI activation requires an explicit review.

## Security and workflow

1. Reserve immutable request/file UUIDs, caption, name, MIME, size and SHA-256.
   Existing participant/application/company/membership/restriction helpers apply.
   Owner-only backend release switch, Edge flag and Flutter flag all default off.
   The backend gate can restrict acceptance writes to one conversation/two UUIDs.
2. Authenticated Edge receives immutable 256 KiB chunks; direct client Storage
   INSERT/UPDATE/DELETE is denied. Each upload is leased against orphan cleanup.
   Replaying a chunk requires identical bytes. Progress shows acknowledged bytes;
   cancellation aborts transport, while uncertain remote outcomes retain identity.
3. Edge reconstructs exact-length bytes, checks the full reservation hash and
   runs **real bounded file-type/content checks locally in Supabase**. PNG has
   signature/chunk/CRC/dimension checks; JPEG has marker/dimension/scan boundaries;
   PDF has header/catalog/pages/end and active-content heuristics; DOCX/XLSX have
   ZIP structure, CRC, expansion limits, content types and expected main parts.
   Reject encrypted/macro/nested executable/unsafe relationship packages and
   malformed, mismatched or oversized content. No client-only MIME approval.
4. `pending → validating → validated/rejected → committed`. Metadata explicitly
   records `basic-type-validation-no-antivirus-v1`. Only the service-role Edge
   validator may record results; participants cannot set `validated`. No `clean`,
   `malware_free`, scanner approval or antivirus outcome is manufactured.
5. A validated file is still inaccessible to recipients until atomic message
   commit. Existing text sender assigns sequence and notifications once, and
   attachment binding commits in the same transaction. Identical retry returns
   the original receipt; changed caption/file/hash or text-request collisions fail.
6. Current authorized participants can retrieve committed files through private
   Storage RLS with 60-second download URLs. Only images have thumbnails.
   Documents have **Download file**, use download disposition and are never
   automatically executed or rendered inline by the Chat UI. No caller-supplied
   bucket/path. Service credentials stay server-side; no file bytes/URLs are added
   to existing plaintext pending-message storage.
7. Hourly server-only cleanup expires incomplete/unsent uploads after one hour
   and active leases, retries failed deletion via Storage API, and keeps identity
   tombstones. For committed messages it deletes temporary chunks only, preserving
   the final file. Cleanup outages can extend retention; monitor them. Quotas
   remain eight outstanding/100 reservations per day, 160 chunk attempts and four
   validation attempts per reservation. Nothing auto-replays after restart.

Structural checks are conservative, not complete Office/PDF renderers and **not
antivirus**. They cannot guarantee harmless content, detect every polyglot, active
feature or malware, or replace patched viewers. Some complex valid files may be
rejected. The composer says files are not virus-scanned. Use only non-sensitive,
trusted demonstration files. Signed links are bearer capabilities until expiry;
browser downloads/history/cache may retain files/URLs independently of the app.
Attachment bytes remain memory-only until send, so interrupted uploads may require
reselecting the exact same file/hash. Existing unencrypted text pending storage,
restart/cross-tab/concurrency, foreign/Admin runtime isolation, full notification
dedup/Reconnection testing and historical 5761-record rollback fingerprint equality
remain explicitly outstanding.

Built-in `node:buffer`/`node:zlib` APIs perform local structural checks within Edge;
they do not start a Node host or install a package. Supabase documents
[Node built-in support](https://supabase.com/docs/guides/functions/dependencies),
and Deno documents [the zlib API](https://docs.deno.com/api/node/zlib/).
Deno compilation and resource-limit behavior still require validation on the
actual Supabase Edge runtime. Validation exceptions/timeouts fail closed.

## Configuration and shortest controlled release path

Cross-platform review: shared Chat uses file_selector XFile bytes, in-memory image
preview, Supabase binary upload and private signed download URLs; no dart:html,
dart:js or dart:io is imported by shared Chat. Picker filters include extensions,
Android MIME types and iOS uniform type identifiers. Android's main manifest now
includes INTERNET so release builds can reach the same HTTPS Supabase project.
No broad storage/camera permissions, emulator host rewriting or device-specific
Supabase secrets are needed. Native no-Origin Edge requests still authenticate
and use the same participant RPCs and private bucket. Mobile downloads use the
external system browser/download UI; files are not opened in an embedded document
renderer. A capable browser/viewer and network access are required on the device.
On Web use Prepare download, then Download file: the second direct gesture avoids
popup blocking after asynchronous signing, with a 50-second local URL freshness
limit. iOS compilation/device QA requires a Mac and remains unverified here;
Android emulator/physical-device picker, download and hosted upload QA also remain
unverified until scoped attachment QA approval. No additional Edge revision beyond
the documented protocol CORS update is required by this platform review.

Final presentation: sent and received JPG/JPEG/PNG attachments share the same
in-bubble thumbnail component. Tap to open a responsive zoomable image dialog;
each opening requests a fresh participant-authorized 60-second URL. Account
changes remove the dialog image. Close via the explicit close button or normal
modal dismissal. Download remains available on the image's bubble. PDF/DOCX/XLSX
show format-specific icons, filename, size and download controls, never a
dedicated in-app document viewer. Both roles use the same component and private
Storage gateway. This presentation adds no dependency or Edge/SQL change.
31 focused local attachment tests passed, including preview reauthorization,
account-switch hiding and the three document cards. Actual hosted image decoding,
browser downloads and mobile device acceptance remain controlled QA items.

Local platform-review verification: 27 focused attachment VM tests passed and
the default-off release web build passed. Flutter analysis reports only the same
five pre-existing informational findings outside Chat. A Chrome widget-test run
remained at its loading stage and was stopped without a test result; the new Web
download gesture flow must not be reported browser-accepted from this run.
No Android/iOS build, emulator/device attachment acceptance or live upload was
performed. Source compatibility and a web build do not prove mobile runtime QA.

No new external service or machine. Edge uses existing server
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, plus:

- `CHAT_BASIC_ATTACHMENTS_ENABLED`: unset/false until separate QA approval.
- `CHAT_BASIC_ALLOWED_ORIGIN`: exact canonical production web origin, without a
  trailing slash/path; leave unset until a production origin is known. HTTP
  `localhost` and `127.0.0.1` are additionally accepted on ports 1..65535 (or
  default HTTP port), so `flutter run -d chrome` needs no fixed port or secret
  updates. No subdomains, shorthand IPs, credentials, paths or arbitrary origins
  are accepted. Only validated origins receive CORS allow-origin headers;
  preflight is read-only and permitted while attachment release is disabled.
  Native/server requests without Origin still require normal authentication.
  Loopback CORS is intended for this controlled demo; public production security
  review must revisit development-origin access. CORS is not authorization.
- `CHAT_BASIC_CLEANUP_SECRET`: separate 32+ random character server secret.

Keep gateway JWT verification enabled. Every normal operation also checks the
Auth user and executes participant RPCs under that user's JWT. Hourly scheduled
cleanup POSTs to `chat-basic-attachments?op=cleanup` with server service-JWT
Authorization and `x-cleanup-secret`; both must match. No keys/secrets in Flutter
`.env`, console instructions or evidence files. No scanner URL/secret is required.

1. Review this basic design and exact artifacts in `chat_basic_attachment_hashes.json`.
   CH captures/reviews the existing read-only
   `supabase/candidates/chat_phase6b_readonly_preflight.sql` output. The basic
   candidate pins the same ten-routine fingerprint, six hooks and PostgreSQL
   17.11 environment. Missing/drifted baseline stops DDL; do not alter hooks.
2. Separately approve/run the guarded basic rollback-only catalogue candidate,
   preferably in an existing isolated Supabase test project. No Docker/install is
   needed. If CH/KZ choose the shared project for the DDL-only trial, that needs
   explicit joint approval, a quiet schema window and complete before/after
   fingerprints. Prepare an execution copy only after approval, removing only
   its new basic approval guard and setting the reviewed backend fingerprint in
   that transaction. Final ROLLBACK and catalogue equality are mandatory.
3. After successful review/validation, separately approve permanent basic SQL and
   Edge deployment. Apply the same reviewed guarded migration via an approved
   copy; leave all release gates off. Run `chat_basic_catalog_verification.sql`
   and confirm original text definitions/fingerprints and policies changed only
   as expected. No scanner migration or original SQL guard is modified.
4. Approve the exact QA fixture/file manifest below. Only then enable the backend
   gate scoped to that conversation/two actors, the basic Edge flag and a local
   Flutter build with `--dart-define=JOBMATE_CHAT_BASIC_ATTACHMENTS=true`.
   Sign in → Messages → existing QA conversation → paperclip → choose file →
   optional caption → Send. Test recipient download/history, identical retry,
   cancellation, pagination, read cursors and Realtime. Current normal launch
   without that define keeps live attachments disabled.
5. Record actual results before final acceptance/Git review. Public unrestricted
   activation is outside demonstration approval. No commit/push is performed now.

Guarded candidates include permanent migration, exact-body rollback validation,
SQL semantic/security test fixture and empty-only rollback. SQL tests are not
executed here. The trusted verdict in SQL-only tests is explicitly a test fixture;
Node tests exercise the real validator. Storage HTTP/RLS, concurrent behavior and
real Edge execution remain unverified. The empty rollback refuses existing
metadata or bytes; populated deployments require forward repair/retention review,
not deleting files or existing text messages.

## Exact approvals needed (templates, not approvals received)

First validation approval:

> CH and KZ approve preparing a temporary execution copy of the exact basic
> rollback-validation artifact identified in chat_basic_attachment_hashes.json,
> removing only its new basic approval guard. CH may manually run the complete
> DDL/catalogue trial ending ROLLBACK on the explicitly named project after
> preserving/reviewing the complete baseline and coordinating no schema changes.
> No uploads, business messages, original guard changes or agent live execution.

After that passes, deployment approval:

> CH and KZ accept this university-demo basic validation design without antivirus
> and approve only the exact basic migration/Edge bundle SHA-256 in the review
> manifest for the named Supabase project, with all attachment gates disabled.
> Preserve existing text Chat and both original guards. This does not approve
> uploads, messages, unrestricted activation or public production release.

Separate QA approval:

> CH and KZ approve enabling basic attachment writes solely for application
> fb352472-8a41-45cf-a9a6-5e70e25e66e8, conversation
> e08aee68-59d5-40eb-aaf8-bc5676d19f7f, seeker
> fb66cc74-1a4f-44e0-ae4f-6831c7a39b8f and employer
> 50c0d35f-c1cd-4fa1-b864-6f6e1e833fd0. We approve the concrete non-sensitive
> five-file manifest (JPG, PNG, PDF, DOCX, XLSX: exact names/sizes/hashes/captions),
> at most five logical requests/messages, at most two identical upload passes and
> two identical send retries per request, own read cursors and normal server
> notifications. History, pagination, downloads and Realtime observation are
> included. No new accounts/conversations or unrelated writes. Codex may prepare
> the scoped setup but must not execute live writes.

The file manifest and project identifier must be filled/reviewed before approval;
no private file or credential is requested in chat. JPEG is covered by the JPG
format; include an additional JPEG fixture only if explicitly approved. Existing
two-message QA approval does not cover any of these new attachment writes.

## Exact files and local verification

Modified: `README.md`, `docs/chat_phase6b_backend_completion.md`,
`docs/chat_phase6b_attachments.md`; `lib/features/chat/chat_attachment_draft.dart`,
`chat_attachment_models.dart`, `chat_attachments.dart`, `chat_source.dart`,
`chat_attachment_card.dart`, `chat_page.dart`;
`test/chat_attachment_draft_test.dart`, `chat_attachments_test.dart`,
`chat_attachment_transport_test.dart`, `chat_source_test.dart`.

Created: this document; `docs/chat_basic_attachment_hashes.json`;
`tools/chat_basic/prepare.mjs`, `check.mjs`, `basic.test.mjs`;
`supabase/functions/chat-basic-attachments/index.ts`;
`supabase/functions/_shared/chat_basic/protocol.mjs`, `validate.mjs`;
`supabase/candidates/chat_basic_attachment_migration.sql`,
`chat_basic_rollback_validation_candidate.sql`, `chat_basic_security_tests.sql`,
`chat_basic_empty_rollback_candidate.sql`, `chat_basic_catalog_verification.sql`.

The generator derives new basic sources without editing the scanner templates.
The checker confirms separate namespaces, 5 MiB enforcement, honest validation
scope, Dart/Edge RPC names, exact guarded DDL equality, original routine CTE and
six-hook equality, and all unchanged scanner artifact hashes. It is structural,
not a PostgreSQL compiler. No live SQL or Storage/Edge request was made.

Actual tests: **181 focused Flutter tests passed** (two legacy DOC/XLS selection
cases intentionally removed), **four render checks passed**, **15 real basic
validator/protocol Node tests passed**, original Chat static checker **187 checks
passed**. Analysis reports only five existing informational findings, no new
warnings/errors. Node syntax checking passes for the Edge TypeScript entry;
Deno type-check/runtime, PostgreSQL compilation, actual role/Storage enforcement,
Chrome interaction and Android runtime acceptance are **UNVERIFIED** locally.
`flutter build web --release --no-pub` **passed** (49.3 seconds), including Wasm
dry run. Default-off JS excludes the debug tester route/title, QA application
UUID/fixed messages, attachment preview/retry controls and the basic Edge endpoint.
No browser/Android interaction or actual hosted Edge validation is inferred.

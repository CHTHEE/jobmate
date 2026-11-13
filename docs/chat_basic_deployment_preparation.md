# Basic attachments: disabled backend deployment preparation

## Current CORS revision — supersedes the fixed-port instructions below

CH requested normal `flutter run -d chrome` support after the disabled deployment
approval. Only Edge `_shared/chat_basic/protocol.mjs` changed: strict HTTP
localhost/127.0.0.1 origins with any port 1..65535 (or default HTTP), plus one
exact canonical production origin from `CHAT_BASIC_ALLOWED_ORIGIN`. Leave that
setting unset until a production origin is known, or retain a valid exact origin;
local ports never require secret changes. No wildcard, arbitrary reflection,
suffix hosts, shorthand IPs, URL credentials or paths. Invalid origins get 403
without allow-origin. Allowed preflight gets 204 without auth/RPC/Storage work,
including while release is off; disabled POST still gets 503. Requests without
Origin retain native/server support and unchanged authentication requirements.

Replace only the Dashboard protocol.mjs contents before deploying. index.ts,
validate.mjs, all SQL and both original guards are unchanged. Revised protocol
SHA-256: `6492afd10ac3f538d896602c0f7bc288b56b5929fae19cbaa0bf6ca49c346700`.
Current bundle SHA-256:
`1b5a1f0109d542225e9f0296dd777b166643acb2f196377837bd235687ca6d8c`;
see [current hashes](chat_basic_attachment_cors_hashes.json). The previous manifest
and approval text below remain historical; do not identify revised code by the
old protocol/bundle hashes. The SQL execution copy remains
`tmp/chat_basic_deployment_APPROVED_20261113.sql`, SHA-256
`4fa283c317dec6a75894bb1aca3c24337e3c91f4bb8bcb264785df22d5d48546`.
Earlier preparation scripts pinned to the old whole bundle should fail closed
and must not be rerun to regenerate old code or overwrite historical manifests.

Local validation: 18 validator/protocol/CORS tests, seven artifact/SQL regressions
and 187 structural checks PASS. No Flutter code changed. Hosted CORS/gateway
preflight and uploads remain unverified. All three release gates stay disabled;
ordinary Flutter launch does not activate attachments. Public production security
review must revisit development-origin access; CORS does not replace authorization.

13 November 2026. **Prepared, not approved for permanent deployment.** No live
SQL, Edge deployment, activation, upload or message was performed by Codex.
The Supabase-only university demonstration provides content/type validation,
not antivirus protection. All three release gates must remain disabled.

## Completed r1 rollback evidence

CH reports the following completed live trial and recovery verification. Codex
verified the local execution file hash, but did not connect to Supabase or inspect
the complete exported results independently in this task.

| Evidence | Reported result |
| --- | --- |
| Execution SHA-256 | `e3624aed3771626a2aca92444ff597c3a32574a61b35f42224177ab5b27a37ac` |
| Assertion marker | `CHAT_ATTACHMENTS_CATALOG_ASSERTIONS_PASSED_ROLLBACK_PENDING` |
| Validation backend / isolation | `2907987` / `read committed` |
| Attachment trial catalogue | Returned successfully |
| Independent observer | `2908033` |
| Other client open/unknown transactions | `[]` |
| Possible failed-trial backends | `[]` |
| Post-rollback records / unique keys | `2652` / `2652` |
| Five attachment absence checks | All `PASS` |
| Baseline MD5 | `9117d06648f2fe2c85ac5d3131faee1f` |
| Original Chat routine count / MD5 | `10` / `a5d682393de3f9ffc66f01c5264ec7c1` |

CH confirms the original, post-failure and post-r1 baseline/preflight exports
are byte-for-byte identical: all 2652 catalogue records, ten routine definitions,
78 policies and eight buckets match. Together with transaction observations this
completes the **basic attachment rollback phase on CH's evidence**. The earlier
historical 5761-record Chat rollback comparison remains independently unconfirmed;
it is a different baseline.

## Reviewed sources and exact differences

All entries in [the unchanged r1 manifest](chat_basic_attachment_r1_hashes.json)
were rehashed locally. The permanent migration's transaction body, from `BEGIN`
through its last DDL statement, is identical to the r1 rollback candidate before
`DO $attachment_catalog_assertions$`, including its guard and pinned preflight.
The original basic permanent migration and r1 permanent migration are also
byte-for-byte identical. Both original text-Chat SQL guards remain unchanged.

The permanent source ends with `COMMIT` and does **not** include the rollback
candidate's post-DDL assertions or PID/catalogue SELECT. The rollback source
includes those read-only checks and ends with `ROLLBACK`. The successful temporary
trial additionally removed only the new attachment guard and set the reviewed
backend MD5 locally. No DDL discrepancy was found.

| Artifact | SHA-256 |
| --- | --- |
| Reviewed r1 bundle | `52e68790f64b6f566bac30a871899b6130c6c6b1ad65606b23100a6e6e9fa317` |
| `supabase/candidates/chat_basic_attachment_migration_r1.sql` | `96213f66af7639710eab1431373c70486dda92873577de7781ad010cb9ab09b2` |
| `supabase/candidates/chat_basic_rollback_validation_r1_candidate.sql` | `4fb01897ba657df5118046b31d6f41994bfbfa0093f980976bbe4824d47ac010` |
| `supabase/candidates/chat_basic_catalog_verification_r1.sql` | `7e1d956d5e0e6beb2b2ee3bf9533820b39d4c80bef57f13ceee3111d028626c3` |
| Edge `chat-basic-attachments/index.ts` | `c7abf9adca9ec15ed1b77ae9f614b1e132f839f113b2c2520a1e966199e0b606` |
| Shared `chat_basic/protocol.mjs` | `43027b80fb9e40aff0c6d7334d32f5339c8624be69dd67f85b3396a949ca5782` |
| Shared `chat_basic/validate.mjs` | `af15016da95e12090761f02f9d107a334a474b8b59e018cf5f816bb34b774f2d` |

## Separate permanent deployment approval

CH/KZ may approve the following statement; this document does not supply approval:

> CH and KZ approve Codex preparing, and CH manually executing, one disabled basic
> attachment backend deployment in the existing shared JobMate Supabase project.
> Reviewed r1 bundle SHA-256:
> 52e68790f64b6f566bac30a871899b6130c6c6b1ad65606b23100a6e6e9fa317.
> Permanent migration SHA-256:
> 96213f66af7639710eab1431373c70486dda92873577de7781ad010cb9ab09b2.
> Reviewed r1 assertions source SHA-256:
> 4fb01897ba657df5118046b31d6f41994bfbfa0093f980976bbe4824d47ac010.
> In a separate ignored tmp/ permanent execution copy only, remove the new
> attachment approval guard, set the transaction-local reviewed backend MD5
> a5d682393de3f9ffc66f01c5264ec7c1, and insert the exact reviewed r1 post-DDL
> assertion block and PID/catalogue SELECT immediately before the permanent
> migration's COMMIT. Change only the SELECT marker to
> CHAT_BASIC_ATTACHMENT_DEPLOYMENT_ASSERTIONS_PASSED_COMMIT_PENDING.
> Preserve all DDL, pinned hook checks, runtime OID checks and timeouts.
> CH may deploy only the three hashed Edge modules above with JWT verification
> retained, and configure their required server-side settings. Backend release
> enabled=false, no trial conversation/participants, Edge flag=false and Flutter
> flag=false must remain. Authenticated read-only post-deployment checks and an
> empty-body disabled Edge health request are permitted. No activation, file
> upload, message, fixture, account change or Codex live execution is approved.
> Both original guards and all reviewed repository artifacts remain unchanged.

Only **after** that approval, prepare and hash
`tmp/chat_basic_attachment_deployment_APPROVED_20261113.sql`; no such copy has
been prepared by this task. Verify its DDL matches the permanent source and its
added assertions match r1 exactly. Do not use `supabase db push`, remove guards
from repository files or repurpose the approved rollback copy as a deployment.

## Shortest manual deployment sequence, after approval

1. Coordinate a quiet window with KZ: no concurrent schema, RPC, permission,
   event-hook or bucket configuration changes. Rehash reviewed sources. In fresh
   SQL Editor queries run `supabase/diagnostics/chat_basic_rollback_baseline.sql`
   and `supabase/candidates/chat_phase6b_readonly_preflight.sql`. Preserve complete
   results. Require the values in the evidence table, postgres/postgres,
   PostgreSQL 17.11, origin replication, and the reviewed six-hook baseline.
   Stop on any drift; do not override a fingerprint to force acceptance.
2. Open the newly approved permanent execution copy in a fresh query and run the
   **whole batch once** on one session. Retain READ COMMITTED, 1s lock timeout,
   15s statement timeout, 60s idle transaction timeout, 90s transaction timeout,
   check_function_bodies, all pinned safety checks, assertions and final COMMIT.
   For the known private release-control-table warning choose **Run without
   RLS**; do not let the Editor append unreviewed RLS changes. The migration
   creates the private bucket and its exact policies; no separate Dashboard bucket
   creation or policy editing is needed.
3. Preserve the commit-pending marker, PID and catalogue snapshot. A marker is
   not proof of COMMIT. In a fresh session run
   `supabase/candidates/chat_basic_catalog_verification_r1.sql`; expect
   `CHAT_ATTACHMENTS_DISABLED_DEPLOYMENT_CATALOG_VERIFIED`. Independently run
   `supabase/diagnostics/chat_basic_failed_trial_cleanup_inspection.sql`, checking
   the deployment PID/transaction state. An idle connected backend is not an
   open transaction; do not require that every pooled connection disappear.
4. Configure Edge secrets in the existing project's Dashboard, server-side only:
   `CHAT_BASIC_ATTACHMENTS_ENABLED=false`, `CHAT_BASIC_ALLOWED_ORIGIN` equal to
   the exact future QA browser origin (scheme/host/port, no wildcard), and a
   securely generated `CHAT_BASIC_CLEANUP_SECRET` of at least 32 characters.
   The existing platform-provided `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
   `SUPABASE_SERVICE_ROLE_KEY` are also required; never copy service credentials
   to Flutter, a public .env, screenshots or chat. Record configuration names
   and flags only. Do not enable a cleanup schedule while the endpoint is off.
5. Deploy `chat-basic-attachments` with its **entire three-module import graph**,
   preserving the relative `../_shared/chat_basic/` imports and both shared files.
   Keep gateway JWT verification enabled. The Dashboard route is Edge Functions
   -> Deploy a new function -> Via Editor, using the reviewed file contents.
   Confirm its editor supports the required shared paths before deploying; pasting
   index.ts alone is insufficient. If it cannot preserve this import graph, stop
   this step and report the limitation rather than silently rewriting/bundling
   reviewed source. No Supabase CLI or Deno was found on this machine's PATH;
   no installation is authorized. An already-equipped CH/KZ machine can instead
   deploy the same reviewed modules using its installed CLI and explicit existing
   project target, after checking that CLI version's deploy help. No Docker or
   new hosting is required. Keep the Flutter flag false and do not publish a
   flag-enabled client yet.

Dashboard deployment and built-in request testing are documented in the
[official Dashboard guide](https://supabase.com/docs/guides/functions/quickstart-dashboard).
Shared-module packaging in this project's Dashboard and hosted Deno import/runtime
compatibility remain unverified; resolve them before calling Edge deployment ready.

## Failure handling and post-deployment verification

- If SQL fails before COMMIT, issue `ROLLBACK;` on the original established
  connection if available. A new tab's ROLLBACK does not clean up another session.
  Use the independent cleanup observer, preserve full errors/PID and establish
  transaction termination. If connection/COMMIT outcome is uncertain, inspect
  installed catalogue state first; never rerun blindly or terminate unrelated
  sessions. Unexpected remaining transactions require CH/KZ investigation.
- If nothing committed, require the original complete baseline and preflight to
  match before retry. If SQL committed but Edge fails, leave every gate disabled;
  repair only after review. Do not run the guarded destructive down script or
  drop a populated table/bucket as an improvised recovery.
- After successful COMMIT, rerun and preserve the complete baseline and original
  Chat preflight, plus the r1 installed-catalogue verification. The original ten
  routines/MD5 must remain unchanged. Six existing event hooks and existing
  publication membership must remain unchanged. Verify installed disabled gate,
  private 5 MiB bucket/allowed MIME types, metadata RLS, RPC ACLs including
  MAINTAIN exclusions, and restrictive Storage policies from the reviewed DDL.
- **Do not demand the old full baseline MD5/count or five absence PASS results
  after permanent deployment:** approved new objects now exist. Compare all
  pre-existing `(category, object_identity)` records, allowing only changes
  explained by exact reviewed DDL: the new chat_messages binding unique
  constraint/index, new foreign-key internal RI triggers on referenced existing
  tables, and expected absence-status changes. Check each new RI trigger through
  its pg_constraint linkage to the exact reviewed attachment/release foreign key;
  an arbitrary new trigger on an existing table is not acceptable. New records
  must correspond only to the two new tables, helpers/RPCs, their dependent
  objects, six Storage policies and one bucket in the migration. No unexpected
  changed/deleted existing records, policies, buckets, grants or definitions are
  acceptable. Preserve complete exports for this comparison; raw count equality
  is insufficient. No final post-deployment record count is asserted in advance.
- Use both existing signed-in participants to load current conversations and the
  existing two QA text messages through the normal repository, without sending
  or marking read. Verify pagination/typed parsing and normal text UI unchanged.
  Confirm Flutter flag false and no attachment picker in the normal build.
- With deployment approval, a Dashboard empty JSON POST using authorized local
  authentication and matching Origin may check the disabled handler returns its
  expected unavailable 503 response. A gateway 401 does not test handler loading;
  a generic platform 503 can indicate an import failure. A 503 alone also cannot
  prove the flag value: inspect the configuration and database gate separately.
  Do not call reservation/send RPCs just to test that they reject while disabled.

Catalogue assertions establish structure, not actual participant HTTP Storage
authorization, hosted file validation, upload/download correctness or messaging.
These and cleanup execution/cron configuration remain later runtime gates.

## Five-file manifest and separate controlled QA approval

Prepare five **non-sensitive** local files, without uploading. No resumes,
credentials, personal documents, macros or active content. One file per format:

| Format | Expected MIME |
| --- | --- |
| JPG | image/jpeg |
| PNG | image/png |
| PDF | application/pdf |
| DOCX | application/vnd.openxmlformats-officedocument.wordprocessingml.document |
| XLSX | application/vnd.openxmlformats-officedocument.spreadsheetml.sheet |

For each record, list local filename, exact byte length (1..5242880), SHA-256,
actual format/MIME, exact caption or explicit null, sender participant UUID,
stable client-request UUID and attachment UUID. Assign at least one file to
each participant. Hash files locally with `Get-FileHash -LiteralPath '<file>'
-Algorithm SHA256`; use `Get-Item -LiteralPath '<file>'` for Length. Preserve and
hash the complete five-record manifest. Do not invent file hashes or silently
substitute content. A JPEG extension variant, negatives, cancellation/orphan
fixtures or additional files require explicit scope beyond these five.

Only after disabled deployment verification, CH/KZ can approve this separate
statement with real manifest values filled in:

> CH and KZ approve scoped basic attachment QA for the five exact files and
> request identities in manifest [path], SHA-256 [actual manifest hash]. Scope:
> existing application fb352472-8a41-45cf-a9a6-5e70e25e66e8,
> conversation e08aee68-59d5-40eb-aaf8-bc5676d19f7f,
> seeker fb66cc74-1a4f-44e0-ae4f-6831c7a39b8f and employer
> 50c0d35f-c1cd-4fa1-b864-6f6e1e833fd0 only. CH may manually enable the backend
> trial gate for exactly this conversation/two participants, the Edge flag and
> one local QA Flutter build, without general-user activation. At most five
> attachment messages total, one per manifest file, with approved captions;
> permit at most two identical upload passes and two identical send replays per
> file, participant viewing/downloading, own read cursors, history/pagination,
> Realtime observation and normal generated notifications. No new conversations,
> accounts, applications, status/membership changes or unrelated writes. Preserve
> eligibility checks and stop on access/read-only rejection. Codex prepares only;
> CH performs live operations. Restore release gates off after QA.

Before activation, also review/approve the concrete hourly orphan-cleanup schedule
within existing Supabase (server-side credentials via approved secret storage),
or an explicitly bounded manual cleanup procedure for this trial. Do not expose
service credentials or cleanup secrets in client requests, SQL history or evidence.
The current disabled endpoint cannot execute cleanup. Cleanup, activation and
uploads are **not** authorized by the permanent deployment statement above.

Outstanding beyond catalogue validation: hosted Edge compatibility and validation,
real private Storage participant/foreign-user boundaries, five-format rendering
and downloads, retries/notification deduplication, cleanup, attachment Realtime,
restart/cross-tab and concurrency, foreign/Admin isolation, and unencrypted
pending local storage. The historical full text-Chat rollback fingerprint
comparison remains independently unconfirmed. Do not mark these PASS from SQL
structure or earlier text-message evidence. Public release still needs separate
security review and appropriate malware protection.

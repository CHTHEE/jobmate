# PNG validation failure — targeted investigation, 13 November 2026

**Follow-up, 14 November:** CH confirms the corrected Edge entry point is deployed
and real Web acceptance passed: seeker image -> employer enlarged preview,
employer PDF -> seeker download, and normal text exchange. This resolves the
reported validation reply failure on CH's evidence. Later pending/awaiting-retry
statements below are historical; no additional live verification was run by Codex.

## Resolution prepared after CH's read-only inspection

CH reports attachment `cf32f92f-953f-4502-9b70-7324430b9d0e`, client request
`243fd84f-ea3e-424d-9ce7-94e752f11152`, state validated, size 66898, image/png,
one upload and one validation attempt, final file catalogued, not expired or
collected, and no linked message. validated_at is 2026-11-13T15:24:21.685002+00:00.
The trusted finalization RPC returns void, is executable by service_role and not
authenticated. This demonstrates successful finalization before the failed reply
and supports the confirmed empty-response parsing defect described below.

Only runtime change: index.ts rpc() checks HTTP success first, accepts 204/empty
success only for the two known void RPCs, and otherwise parses JSON strictly.
No catch was widened and no validation/security/SQL/gate/Flutter runtime changed.
Replace only Dashboard `chat-basic-attachments/index.ts` with the local file;
retain both shared modules and Verify JWT. New index SHA-256:
`0d3489760f530a7a18d63b62d92035e5a7be83e5add40d6b46b72ab375b15bc8`.
Current backend hash manifest: `chat_basic_attachment_rpc_fix_hashes.json`.
Earlier manifests are preserved historical records, not hashes of the new index.

After CH manually deploys that single-file replacement, in the existing signed-in
seeker UI press **Retry same attachment request** once. Do not remove the file,
start a new request or reset/delete the reservation. Existing Flutter code fetches
status first: validated skips upload/validation and calls the idempotent send RPC
with the same attachment identity. Inspect the resulting single image message and
recipient preview. If status is now expired/rejected or access is denied, stop;
do not bypass that result or create replacement records without approval.

Local verification: seven actual-entry-point HTTP stub tests, 18 validator/protocol
tests and eight artifact/SQL preservation regressions PASS (33 Node tests total);
19 Flutter attachment/transport tests PASS, including lost-validation-response
recovery and repeated same-identity retry with one upload/validation/message/
notification. 187 structural checks PASS. Hosted redeployment/retry remains CH's
manual action and is not yet a verified PASS. No live requests/writes were made.

## Earlier investigation (before inspection result)

CH reports first QA seeker PNG upload POST 200, validation POST 503 at
2026-11-13 15:24:21 UTC, execution 2072 ms. This is not accepted messaging.
Codex inspected local sources corresponding to the reported deployment, not the
live Dashboard modules or their actual loaded bytes. No live request/SQL was run.

Flutter intentionally sends `{}` (2 bytes) for validate; x-attachment-id carries
the reservation identity. Its client request UUID, hash and caption are already
bound by the original database reservation. Retry preserves those identities.

Local handler 503 JSON sizes are 36 bytes for disabled release and 79 bytes for
the shared catch. The observed log reports 99 bytes but not actual response body
or encoding, so it cannot uniquely identify a branch or prove platform failure.
The shared catch covers authentication, context RPC, claim/lease, Storage read,
chunk integrity, hashing/validator execution, immutable final Storage write,
trusted finalization and final context RPC. Missing/invalid identity returns 400;
read-only/rejected/expired context returns 403. Normal structural PNG rejection is
a rejected receipt, not inherently a thrown 503. ES256 is not itself an error;
the handler asks Supabase Auth to validate the supplied session.

One concrete local defect: index.ts rpc() always invokes response.json(), but
finish_chat_attachment_validation_basic_v1 and complete_chat_attachment_cleanup_basic_v1
return void. PostgREST returns HTTP 204 for void RPCs; parsing its empty body throws.
Locally reproduced with new Response(null,{status:204}).json(). A reservation
already in validated/rejected state without a message can corroborate this path.
This is not yet confirmed as the cause of CH's particular request. Do not claim
Storage HTTP download, service key correctness or Deno PNG compatibility passed
from upload success; the upload and validation execute different paths.

CH's next action: run only
`supabase/diagnostics/chat_basic_validation_failure_inspection.sql` as postgres.
It reads up to eight matching QA reservations around the incident plus two RPC
signatures/grants. Output omits file contents/names/paths/hashes and lease tokens.
Storage catalogue existence does not prove a physical object can be downloaded.

- validated + final file + no message: finalization succeeded; inspect/fix the
  void-response parse. Retrying the original request should reconcile validated
  state, without repeating validation, before the existing idempotent send.
- validating: claim succeeded, later stage failed; the generic error does not
  identify Storage, processing, runtime termination or finalization failure.
- pending with zero validation attempts: claim did not complete.
- rejected: do not bypass validation or repeatedly upload the same rejected file.
- expired/cleanup_done: original reservation may no longer be retryable; do not
  delete it or reset counters/leases. Report its state before attempting anything.

No runtime source, Flutter code, hashes, guards or migration was changed in this
investigation. Await actual diagnostic state/response JSON before identifying the
runtime cause and choosing a Dashboard replacement. Avoid repeated retries: at
most four validation claims are allowed, with a two-minute lease. Keep the pending
selection/request; do not remove/reselect it to create a fresh identity.

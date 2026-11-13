# Approved basic Chat attachment activation

**Current status, 14 November 2026:** CH reports activation and real Web image/
preview, PDF download and text acceptance complete. Do not rerun the historical
activation steps below. Option B is selected: automatic hourly cleanup is
**deferred for the university demo**. No cleanup Cron job is registered according
to CH's reported checks. Manual authorized maintenance remains available through
the existing cleanup Edge endpoint. Vault secrets and installed extensions remain
unchanged. Abandoned uploads may accumulate until authorized cleanup is performed;
automatic cleanup is a known limitation to resolve before production use.

CH reports database/Storage/Edge deployment and independent checks complete, and
CH/KZ jointly approved general activation and the short image/PDF/text UI check.
The local Flutter default is now true. Codex has not executed live SQL, activated
remote gates, uploaded files, committed or pushed. The basic validator is not AV.

Local checks after enabling the default: 49 attachment/Chat UI tests PASS; release
web build PASS. Flutter analysis has the same five pre-existing informational
findings outside Chat and no new findings. Injected Chat controllers now require
their own attachment gateway instead of silently using the global authenticated
Supabase client; normal production routes retain the existing authenticated path.

## 1. Hosted compatibility check, before activation

Keep Edge Function **Verify JWT enabled**. In Dashboard Test, POST `{}` to
`chat-basic-attachments` with authorized authentication retained locally. Expect
HTTP 503 and exactly `{"error":"Attachments unavailable."}` while the Edge flag
is false. This establishes module loading, not actual validation. Gateway 401 or
generic platform 503 is not a pass. Do not share authentication headers or tokens.

## 2. CH runs activation SQL once

The existing gate supports general availability without DDL/RPC changes:

```sql
BEGIN;
SET LOCAL lock_timeout = '1s';
SET LOCAL statement_timeout = '15s';
DO $activate$
DECLARE changed integer;
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Run as postgres.';
  END IF;
  UPDATE jobmate_chat_private.basic_attachment_release
  SET enabled = true,
      trial_conversation = NULL,
      participant_ids = ARRAY[]::uuid[]
  WHERE singleton;
  GET DIAGNOSTICS changed = ROW_COUNT;
  IF changed <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one release-control row.';
  END IF;
END;
$activate$;
SELECT enabled, trial_conversation, participant_ids
FROM jobmate_chat_private.basic_attachment_release;
COMMIT;
```

Expect true / NULL / {}. On SQL failure, ROLLBACK the original connection before
investigating. Do not repeat completed migrations. In Edge Functions -> Secrets,
set `CHAT_BASIC_ATTACHMENTS_ENABLED` to `true` and save. Retain Verify JWT on.
Keep the existing 32+ character `CHAT_BASIC_CLEANUP_SECRET` unchanged. Keep
`CHAT_BASIC_ALLOWED_ORIGIN` as the exact production origin if known; localhost
and 127.0.0.1 HTTP ports are independently supported, so no per-developer changes.
Native requests without Origin still authenticate normally.

No Edge code needs replacement if the deployed CORS protocol hash is
`6492afd10ac3f538d896602c0f7bc288b56b5929fae19cbaa0bf6ca49c346700`.
`JOBMATE_CHAT_BASIC_ATTACHMENTS` now defaults true; restart normally:

```powershell
flutter run -d chrome
```

Rebuild/reinstall mobile clients as usual; no new permissions beyond the already
added Android INTERNET permission. Explicit build-time `false` still overrides
the local default for an emergency client build.

## 3. Hourly cleanup using existing Supabase only

**Option B — deferred, not a registration instruction.** Preserve the original
precheck and historical scripts below. pg_net remains blocked because normal
database roles can read its HTTP request queue and postgres cannot revoke the
supabase_admin grants. The synchronous http alternative remains blocked pending
confirmation of safe redirects and supported configuration in the hosted http
1.6 build. Do not register either job, weaken checks, remove extensions, or change
Vault secrets as part of this deferral. See the existing review and diagnostics.

For manual maintenance, a trusted operator may use the existing authenticated
`chat-basic-attachments?op=cleanup` endpoint only under the approved maintenance
scope, retaining Verify JWT, the exact service-role JWT and matching cleanup
secret. Keep credentials out of chat, source, screenshots and pg_net. Never
manually delete bucket rows/files as a substitute. A 200 cleaned count is actual
cleanup evidence; availability of the endpoint is not evidence it has been run.

**14 November: scheduling remains BLOCKED.** The pg_net precheck below correctly
rejects the reported PUBLIC queue access and remains unchanged. CH enabled http
1.6 for the approved synchronous replacement preparation, but version-specific
source review found forced POST redirects plus DEBUG2 header logging in upstream
1.6.x. No safe synchronous job has been registered or prepared as runnable SQL.
Follow [the compatibility review and read-only next step](chat_basic_cleanup_http_review.md).
Do not execute the historical pg_net registration below or bypass its precheck.

Use existing Supabase Cron (pg_cron), pg_net and Vault. If missing, CH enables
these built-in integrations in the Dashboard first; no external host/software.
In **Vault's Dashboard UI**, create three uniquely named secrets without placing
their values in SQL, source, screenshots or chat:

- `jobmate_chat_project_url`: existing HTTPS Supabase project URL, no final slash.
- `jobmate_chat_service_role_jwt`: the exact existing legacy service-role JWT used
  by Edge `SUPABASE_SERVICE_ROLE_KEY`, not an anon key or `sb_secret_...` key.
- `jobmate_chat_cleanup_secret`: same value as Edge `CHAT_BASIC_CLEANUP_SECRET`.

Edge secrets are not automatically available to Postgres; these Vault entries are
the scheduler's server-side copies. Keep access to Vault and pg_net request queues
restricted to trusted database operators. pg_net temporarily queues decrypted
HTTP headers; the precheck below refuses API-role access to that queue or Vault.
If it fails, stop and review permissions; do not weaken JWT/cleanup checks.

After Edge activation, CH runs this **one-time job registration** as postgres:

```sql
BEGIN;
DO $cleanup_precheck$
DECLARE role_name text;
BEGIN
  IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Run as postgres.'; END IF;
  IF (SELECT count(*) FROM vault.decrypted_secrets
      WHERE name IN ('jobmate_chat_project_url',
                     'jobmate_chat_service_role_jwt',
                     'jobmate_chat_cleanup_secret')) <> 3
     OR (SELECT count(DISTINCT name) FROM vault.decrypted_secrets
      WHERE name IN ('jobmate_chat_project_url',
                     'jobmate_chat_service_role_jwt',
                     'jobmate_chat_cleanup_secret')) <> 3 THEN
    RAISE EXCEPTION 'Three unique named Vault entries required.';
  END IF;
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF (pg_catalog.has_schema_privilege(role_name,'vault','USAGE')
        AND pg_catalog.has_table_privilege(role_name,'vault.decrypted_secrets','SELECT'))
       OR (pg_catalog.has_schema_privilege(role_name,'net','USAGE')
        AND pg_catalog.has_table_privilege(role_name,'net.http_request_queue','SELECT')) THEN
      RAISE EXCEPTION 'Scheduler secret access boundary requires review.';
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname='jobmate-chat-basic-cleanup-hourly') THEN
    RAISE EXCEPTION 'Cleanup job already exists; inspect rather than duplicate.';
  END IF;
END;
$cleanup_precheck$;
SELECT cron.schedule(
  'jobmate-chat-basic-cleanup-hourly',
  '0 * * * *',
  $job$
  SELECT net.http_post(
    url := (SELECT decrypted_secret FROM vault.decrypted_secrets
            WHERE name='jobmate_chat_project_url')
           || '/functions/v1/chat-basic-attachments?op=cleanup',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer ' || (SELECT decrypted_secret
        FROM vault.decrypted_secrets WHERE name='jobmate_chat_service_role_jwt'),
      'x-cleanup-secret',(SELECT decrypted_secret
        FROM vault.decrypted_secrets WHERE name='jobmate_chat_cleanup_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
  $job$
);
COMMIT;
```

The endpoint handles up to 50 expired reservations per run, respects active leases
and retains committed final files. Monitor backlog if usage exceeds this bounded
hourly batch. Check Cron history **and Edge HTTP result** after the first hour:
expect HTTP 200 with `{"cleaned":N}`. Cron success alone only proves HTTP enqueueing;
it does not establish cleanup success. Do not manually delete bucket contents.
No cleanup execution has been tested by Codex against the hosted project.

Official platform references: [scheduling](https://supabase.com/docs/guides/functions/schedule-functions)
and [Vault](https://supabase.com/docs/guides/database/vault). This implementation
retains its reviewed JWT-plus-cleanup-secret contract; do not copy an example
that turns off JWT or substitutes a publishable key.

## 4. Short approved acceptance, then Git review

Use existing QA conversation `e08aee68-59d5-40eb-aaf8-bc5676d19f7f`, with its existing
seeker/employer. Send one non-sensitive JPG/PNG and one PDF (each <=5 MiB) plus one
text. As the recipient, confirm thumbnail -> zoom preview -> close, PDF card ->
download (one-click Download file), and text receipt. Confirm
history in both accounts and check the same workflow on Android when available.
Record actual outcomes without signed URLs, tokens or personal file contents.
Do not label missing device/format checks PASS.

If acceptance fails, set Edge flag false and owner-only backend enabled=false;
do not drop tables/files or repeat the migration. Existing signed links remain
valid for their remaining short lifetime. Report the actual error, not secrets.

After acceptance, CH reviews the working tree and explicitly stages only reviewed
Chat/attachment changes, documents and required Android manifest change. Exclude
tmp/, credentials and unrelated teammate work. Commands below are instructions,
not actions executed by Codex; replace the staging placeholder with actual paths:

```powershell
git status --short
git add -- <explicit-reviewed-Chat-paths>
git diff --cached
git commit -m "Complete basic Chat attachments"
git push origin HEAD
```

Outstanding independently: hosted acceptance/cleanup until evidence supplied,
DOCX/XLSX and iOS/device checks not covered above, foreign/Admin isolation,
restart/cross-tab, concurrency and unencrypted pending local storage. The historical
5761-record text-Chat rollback fingerprint comparison remains independently
unconfirmed. General activation is approved for the university demonstration;
public production still requires security review and appropriate malware protection.

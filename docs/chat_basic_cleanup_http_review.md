# Synchronous cleanup scheduler review — BLOCKED on redirect safety

**Decision, 14 November 2026: Option B.** Automatic hourly cleanup is deferred
for the university demo; no Cron job is registered according to CH's reported
checks. Both pg_net and synchronous-http blockers documented below remain open.
Existing Vault secrets, extensions, diagnostics, security prechecks and guards
are preserved. The authorized cleanup Edge endpoint remains available for manual
maintenance; abandoned uploads may accumulate until that occurs. Resolve
automatic cleanup before production use. This decision does not claim cleanup
was executed and does not approve any permission/authentication workaround.

14 November 2026. CH approved local preparation, reports http catalog version 1.6
in extensions, pg_cron 1.6.4, pg_net 0.20.4 and Vault 0.3.1, three named secrets
and no cleanup job. No live SQL/HTTP, deployment, permission change or job creation
has been performed by Codex. Existing attachment functionality remains unchanged.

## Genuine blocker found in the requested version-specific review

The earlier synchronous-http recommendation was incomplete: upstream http 1.6
does not satisfy the requested no-redirect requirement for a secret-bearing POST.

- In [v1.6.0 C source](https://github.com/pramsey/pgsql-http/blob/v1.6.0/http.c),
  the request function sets CURLOPT_FOLLOWLOCATION=1 and MAXREDIRS=5 for every
  non-HEAD request, after constructing/resetting the handle. The same behavior
  exists in [v1.6.3](https://github.com/pramsey/pgsql-http/blob/v1.6.3/http.c).
- The 1.6 configurable-option allowlist omits FOLLOWLOCATION and MAXREDIRS.
  http_set_curlopt with those names raises an error. Resetting options does not
  prevent the request function from enabling redirects again. Inspecting the
  final HTTP status happens after potential credential forwarding.
- Libcurl's protections for Authorization across origins must not be assumed to
  protect the custom x-cleanup-secret header. HTTPS certificate validation does
  not make forwarding that header to another HTTPS host acceptable.
- The same C sources log complete optional request headers at DEBUG2. Generic
  exception handling alone cannot suppress a C debug log already emitted.
- v1.6.0 supports CURLOPT_CONNECTTIMEOUT (seconds), TIMEOUT_MS and the SSL
  verification options through http_set_curlopt. CONNECTTIMEOUT_MS is present
  in later 1.6.x builds, not in the reviewed 1.6.0 allowlist. Do not assume that
  newer per-option http.curlopt_* GUC examples work in 1.6.

Catalog extversion=1.6 is a SQL extension version, not proof of an exact hosted
C binary/patch set. Source review establishes an incompatibility in upstream
1.6.x, not independent inspection of Supabase's loaded binary. Actual installed
signatures can be inspected safely, but signatures do not attest redirect policy.
The intended pinned destination remains exactly:
`https://ibbyejgpjboearzhvwlr.supabase.co/functions/v1/chat-basic-attachments?op=cleanup`.

**No runnable registration script has been created.** Registering a secret-bearing
POST now would violate the review requirements. No fake no-follow option or
post-response check is substituted. The original pg_net precheck stays intact
and its shared queue transport remains blocked. No extension upgrade, owner
change, HEAD cleanup, auth weakening or new Edge endpoint is authorized here.

## Exact next manual SQL — read only

Run `supabase/diagnostics/chat_basic_cleanup_http_compatibility.sql` as postgres.
It returns extension/API/type metadata, safe logging settings, unique Vault-name
counts, effective API-role Vault access and job metadata. It does not request
HTTP, read secret values, inspect credential-bearing queue rows, or set options.
No secrets should be pasted into chat. Expected current job list is empty; any
job requires investigation before further preparation. Each named Vault entry
must occur once, and no API role may both use Vault and select decrypted values.
Even otherwise matching results leave redirect safety UNCONFIRMED.

Request Supabase's confirmation of the loaded http library build/source and a
supported version/patch that does not force redirects for POST. If the hosted
platform offers a newer extension, review its actual request implementation and
supported upgrade path before approving an upgrade; do not run ALTER EXTENSION,
drop/recreate extensions or change queue grants speculatively. No external host,
Docker or worker is required by this investigation.

## Required design once no-follow support is established

Keep one postgres-owned SQL Cron job at `0 * * * *`, with no public RPC wrapper:

1. Verify postgres role, exact supported extension/schema/API, no duplicate job,
   three uniquely named Vault entries, and effective Vault table/column access.
2. At each run, before decrypting credentials, fail closed for DEBUG logging,
   unsafe parameter/audit/nested-plan logging, or an unreviewed transport build.
   Inspect the Cron session's effective settings, not just the registration session.
   No SQL literals or logged bind parameters may contain credentials. Do not
   enable verbose curl traces or dump raw error contexts/headers/responses.
3. Use the version's real APIs to reset options, enforce peer/host verification,
   turn redirects off and verify that policy, set 5-second connection and bounded
   request timeouts. Do not pass unsupported options. With legacy http.timeout_msec,
   ensure it cannot override the bound. No arbitrary proxy/credential curl options.
4. Read credentials only inside the execution session, pin the exact project
   HTTPS destination above and POST {} using existing Authorization and
   x-cleanup-secret. Retain Edge Verify JWT and both cleanup checks unchanged.
5. Require status 200 and a JSON object whose only field is cleaned, an integer
   0..50. Return only a fixed success marker/count/time, or a fixed sanitized
   failure. Suppress raw SQLERRM/PG_EXCEPTION_CONTEXT/header/body output.

The exact registration SQL and local regression fixture depend on confirming a
safe transport. They have not been represented as implemented, compiled or run.
If no supported no-follow transport is available, report that constraint and
review a separate cleanup-only authentication alternative before changing Edge
code. Existing credentials must not be sent through pg_net as a workaround.

## Verification and rollback plan (no job exists yet)

After separately reviewed registration becomes possible, verify one postgres job,
schedule and safe command digest without exposing headers. Observe one natural
hourly run: Cron success must follow a verified HTTP 200 plus integer cleaned
receipt, and the matching Edge log must show cleanup POST 200. Avoid additional
manual cleanup calls or unrelated attachment acceptance. Current synchronous
cleanup itself has not been tested; it removes expired uploads/temporary chunks,
never committed final files or Chat messages.

No rollback is currently needed because nothing was registered. To disable a
future job after verifying its identity/owner, CH may review:

```sql
SELECT cron.alter_job(jobid, active := false)
FROM cron.job
WHERE jobname = 'jobmate-chat-basic-cleanup-hourly'
  AND username = current_user;
```

Confirm no invocation remains active before subsequently unregistering:

```sql
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'jobmate-chat-basic-cleanup-hourly'
  AND username = current_user;
```

Unscheduling does not cancel an already running HTTP call or restore deleted
expired temporary objects. Keep extensions/Vault entries and normal attachments
unchanged. No destructive attachment rollback/down script applies to scheduling.

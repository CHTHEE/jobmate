# Basic attachments: manual rollback-only validation preparation

13 November 2026. **Preparation only; CH/KZ execution approval is still required.**
No live SQL/Storage call, deployment, activation, upload or business RPC was run.
No execution copy or guard removal is prepared in this turn. This trial validates
DDL/catalogue behavior, not working attachment delivery or antivirus protection.

## Reviewed sources and hashes

All **eight** files in `chat_basic_attachment_hashes.json` match their recorded
SHA-256 values. Its bundle hash also recomputes correctly; the manifest was not
regenerated. All five basic SQL candidates were reviewed, including their grants,
gates and transaction endings. Reviewed Chat schema means the checked-in source
of the reportedly deployed backend; its current live state must be checked by CH.

| Artifact | Verified SHA-256 |
| --- | --- |
| Basic backend bundle | `15beba70d5fcedc33a9f48a0f28ad843c6fca744a8300d26dacd81bf2d1d1a1e` |
| `chat_basic_attachment_migration.sql` | `96213f66af7639710eab1431373c70486dda92873577de7781ad010cb9ab09b2` |
| `chat_basic_rollback_validation_candidate.sql` | `05b7ea04ef94caaf7086e012d0641f628e332a8114c7e933249fe3f1a3481957` |
| `chat_basic_catalog_verification.sql` | `17c4a9b130325a08a8a540f7e4a010185cec7385f5ad3512cf4cdf60ea041a2b` |
| `chat_basic_security_tests.sql` | `b875a41c7021e51b7468b50c5fec7693ff9f0bbf4ac60c0c4ebc8bf79e606b72` |
| `chat_basic_empty_rollback_candidate.sql` | `771d917c4b6c4f72e62c06f1ad987621f8ca31961ee4a9b73720baa809c7ad96` |

The three Edge/module hashes are listed in the unchanged manifest and were also
verified. Future scanner artifacts match their existing manifest. Both original
Chat SQL files, including their unconditional guards, remain byte-identical:

- Standalone: `8704715e62de895324a651c41bfd55cc2a756d2c739fded85b624fb4ab5fa0e7`.
- Original rollback candidate: `84ddf9ab9f30b2fc1930c3f68cfe7371b730c0ae1adfeceba859d070368ec099`.

The basic trial contains the exact guarded migration body, then catalogue
assertions, success marker and explicit ROLLBACK. It has no executable COMMIT or
business RPC invocation. Its only top-level data inserts initialize the disabled
new release configuration and private bucket configuration, inside the rollback
transaction. No application/message/test-data rows are inserted.

## Short manual order

**First file to open: `supabase/diagnostics/chat_basic_rollback_baseline.sql`.**

1. Coordinate with KZ: no schema, RPC, grants, bucket/policy, publication or event
   hook changes until the after-baseline comparison finishes. Confirm the existing
   JobMate project in the Dashboard against the app's public configuration. Use
   `postgres`, database `postgres`, PostgreSQL **17.11**, replication role `origin`.
   Keep Flutter/Edge attachment flags off. No session credentials are exported.
2. In a fresh SQL Editor query, run the entire **read-only baseline** above.
   Preserve the **complete single result row**, preferably as a JSON or CSV export
   named `chat_basic_before.json` or `.csv`. Require all five absence checks PASS,
   `record_count = unique_key_count = actual baseline array length`, and the
   expected context. Save the result, not merely its count or digest. The query
   includes deployed text Chat, private helpers, relation/column ACLs, constraints,
   indexes, internal/user triggers, policies, schema/default privileges, routines,
   enums, six event hooks, publications/membership and bucket configuration across
   the relevant schemas. It reads no business rows or `storage.objects` rows.
   This new baseline has no expected fixed count; **5761 is historical, not a
   requirement for this different query**. It does not retroactively verify that
   older baseline comparison.
3. Run `supabase/candidates/chat_phase6b_readonly_preflight.sql` unchanged in a
   fresh query. Save the full result. Expect **routine_count = 10**, a non-null
   32-hex `reviewed_backend_md5`, and the same postgres/17.11/origin context. Review
   the returned original five public RPC and five private helper definitions,
   owners, settings and ACLs against their approved Chat source. Existing policies
   and bucket settings are returned for review. The **first baseline** supplies
   broader catalogue coverage; this preflight supplies the exact routine MD5
   required by the guarded trial. Do not substitute the overall baseline MD5 or
   SHA-256 artifact hash for that routine MD5.
4. Obtain the exact joint approval below. **Do not run the checked-in guarded
   candidate as-is**: it intentionally raises an exception. After approval, have
   Codex prepare/review a separate temporary execution copy of
   `supabase/candidates/chat_basic_rollback_validation_candidate.sql`. Only the
   new `$attachment_approval_guard$` block may be removed; insert the reviewed
   `SET LOCAL jobmate.chat_reviewed_backend_md5 = '<reviewed 32-hex value>';`
   after BEGIN/timeouts and before preflight. A read-only PID/context SELECT and
   the read-only inspection below may also be included as explicitly approved
   instrumentation. Do not change DDL, assertions, six-hook checks, original
   guards or final ROLLBACK. Record the execution-copy hash and verify its diff
   before CH runs it. No such copy exists yet.
5. In a **fresh** SQL Editor query, CH runs that complete approved execution copy
   **as one batch on one database session**, with nothing selected. Never run
   fragments, the permanent migration, or the semantic/security fixture on the
   shared project. Record the validation PID/context, outputs and any errors.
   Retain `READ COMMITTED`, lock timeout **1s**, statement **15s**, idle transaction
   **60s**, transaction **90s**, and `check_function_bodies=on`.
6. Require marker
   **`CHAT_ATTACHMENTS_CATALOG_ASSERTIONS_PASSED_ROLLBACK_PENDING`**, followed by
   successful completion of final **ROLLBACK**. The marker only proves that the
   preceding DDL/catalogue checks passed; it is not independent proof of rollback.
   Confirm the original transaction ended as described below.
7. In a genuinely fresh session, rerun the **same baseline file from step 2**
   unchanged and save `chat_basic_after.json` or `.csv`. Rerun the routine preflight
   from step 3: all ten original routine definitions/ACLs and reviewed MD5 must
   match. All five basic absence checks must again PASS. Compare the full exported
   baseline key/value maps locally:

   ```powershell
   node tools/chat_basic/compare_baselines.mjs "<complete before export>" "<complete after export>"
   ```

   The tool reads JSON or proper quoted CSV, parses the complete JSON field,
   checks one data row, counts, unique keys, five absences and context, then
   compares **every** `(category, object_identity)` value. PASS also reports both
   original file SHA-256 values. Count/digest equality alone is insufficient.
   Missing/truncated exports or any difference means stop, preserve evidence,
   and investigate before another trial or deployment.

If the SQL Editor cannot submit the complete batch on one connection, expose the
required marker/results, or let CH confirm cleanup, **stop**. A fresh query tab
does not by itself prove a fresh database session. Do not split BEGIN/DDL/ROLLBACK
across pooled requests or install new tooling to work around this preparation.

## What the transaction can actually establish

The existing candidate asserts: no basic-object/bucket/public-RPC collision; ten
unchanged original routine fingerprints; exact reviewed six-hook metadata/ACLs;
new table RLS/owner; new release row disabled and owner-only; private 5 MiB bucket;
ten SECURITY DEFINER public RPCs with empty search_path and postgres owner;
anonymous/default PUBLIC/grant-option denial; participant versus service-role
execute separation; no ordinary metadata mutation privileges, including MAINTAIN;
five restrictive Storage policy boundaries. Reviewed DDL creates metadata columns,
size/type/state/hash/path constraints, composite message binding and indexes.

These are catalogue checks. In particular, the candidate checks the count and
restrictive status of the five named Storage boundaries, **not their complete
runtime behavior or every policy expression/role**. In the temporary copy,
after the existing assertions and before its existing marker/ROLLBACK, include
this read-only snapshot for CH's exact-definition review:

```sql
SELECT pg_catalog.jsonb_build_object(
 'bucket',(SELECT pg_catalog.jsonb_build_object('id',id,'public',public,
   'max_bytes',file_size_limit,'mime_types',allowed_mime_types)
   FROM storage.buckets WHERE id='jobmate-chat-basic-files'),
 'columns',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY ordinal_position)
   FROM information_schema.columns c WHERE table_schema='public' AND table_name='chat_basic_attachments'),
 'constraints',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
   'table',conrelid::regclass::text,'name',conname,'definition',pg_catalog.pg_get_constraintdef(oid,false)) ORDER BY conname)
   FROM pg_catalog.pg_constraint WHERE conrelid IN ('public.chat_basic_attachments'::regclass,
     'jobmate_chat_private.basic_attachment_release'::regclass) OR
     (conrelid='public.chat_messages'::regclass AND conname='chat_messages_basic_attachment_binding_key')),
 'policies',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY schemaname,tablename,policyname)
   FROM pg_catalog.pg_policies p WHERE (schemaname='public' AND tablename='chat_basic_attachments') OR
     (schemaname='storage' AND policyname LIKE 'chat_basic_files_%'))
) AS attachment_trial_catalogue;
```

Expect only JPEG/PNG/PDF/DOCX/XLSX MIME types plus opaque octet-stream **quarantine
chunks**, size 5242880, private bucket, committed/current-participant SELECT rules
and restrictive client insert/update/delete/anonymous denial. Compare the
snapshot to the reviewed DDL, including constraints and policy roles/expressions;
unexpected output is a stop condition. No MIME behavior, file-byte check or actual
download is inferred from these definitions.

`check_function_bodies=on` provides creation-time validation, but PL/pgSQL's embedded
SQL branches may only be planned when invoked. This trial does not execute send,
reserve, mark-read, validation or cleanup business RPCs, and cannot establish all
their runtime semantics. Existing text compatibility here means original
definitions/ACLs/catalogue fingerprints survive unchanged, not a new messaging test.

| Check | This DDL-only transaction? |
| --- | --- |
| DDL creation, SQL function signatures, catalogue/ACL/RLS definitions, disabled gate | Yes, if trial succeeds |
| Original routines, constraints, grants, policies, hooks, publication and bucket configuration restored | Full before/after comparison after cleanup |
| Reservation/replay, actual constraint rejection, state transitions, atomic attachment send and notification dedup | Possible in an independently approved **isolated** transaction; not in this shared DDL-only scope |
| Existing `chat_basic_security_tests.sql` | **Do not run here**: enables the trial gate and invokes send/notification paths with a test-only trusted verdict; isolated fixture approval required |
| Actual participant/foreign/Admin Storage upload/download enforcement and signed URLs | Separate authenticated hosted/isolated Storage HTTP testing |
| Actual content validation on Edge, upload cancellation/retry, thumbnails, download disposition, Realtime and concurrency | Separate hosted runtime acceptance with approved non-sensitive files |

`chat_basic_catalog_verification.sql` expects a **persistently installed disabled
deployment**; do not run it after rollback when the objects must be absent. Its
assertions are already embedded in the trial. `chat_basic_empty_rollback_candidate.sql`
is a guarded recovery script containing DROP/DELETE/COMMIT, **not cleanup for this
trial**. `chat_basic_attachment_migration.sql` contains COMMIT and is not approved
for execution in this phase.

## Failure and transaction cleanup

Approved instrumentation inside the trial should record:

```sql
SELECT pg_catalog.pg_backend_pid() AS validation_pid,
       pg_catalog.clock_timestamp() AS observed_at,
       pg_catalog.current_setting('transaction_isolation') AS isolation;
```

On any error, timeout, disconnect, missing marker or uncertain completion, stop.
If the **original connected session** is still available, issue explicit
`ROLLBACK;` there, even if the transaction is aborted. A ROLLBACK in an unrelated
pooled request does not clean up the original session. Do not blindly rerun the
trial, remove timeouts, disable hooks, alter privileges or run the empty down script.

From an independent observer session, use the recorded numeric PID:

```sql
SELECT pg_catalog.pg_backend_pid() AS observer_pid,
 (SELECT pg_catalog.jsonb_build_object('pid',pid,'state',state,
   'xact_start',xact_start,'backend_xid',backend_xid)
  FROM pg_catalog.pg_stat_activity WHERE pid=<recorded_validation_pid>) AS validation_backend;
```

Require observer PID different from the recorded validation PID. A missing target
row, or an existing idle backend with null `xact_start`, confirms that the original
transaction is no longer open. If target is active/idle-in-transaction or ambiguous,
do not declare rollback; identify original-session cleanup with CH/KZ and observe
again. Timeouts provide bounds but are not evidence by themselves. Do not terminate
other backends. Then require the complete post-baseline absence/equality checks.

## Narrow joint approval to return

> CH and KZ approve **preparing a temporary execution copy and CH manually running
> one rollback-only DDL/catalogue trial** in our existing shared JobMate Supabase
> project. Reviewed backend bundle SHA-256:
> `15beba70d5fcedc33a9f48a0f28ad843c6fca744a8300d26dacd81bf2d1d1a1e`.
> Reviewed rollback candidate SHA-256:
> `05b7ea04ef94caaf7086e012d0641f628e332a8114c7e933249fe3f1a3481957`.
> We will preserve/review the complete fresh baseline, supply the reviewed
> ten-routine MD5, and coordinate no concurrent schema/permission/hook changes.
> The copy may remove only its **new basic attachment approval guard**, insert
> that transaction-local reviewed MD5 and the read-only PID/catalogue inspection
> statements specified in this preparation document. Preserve all other DDL,
> preflight/assertions/timeouts and final explicit ROLLBACK. Both original SQL
> guards remain untouched. No attachment activation, business RPCs, uploads,
> messages, fixtures, Edge/permanent deployment or agent live execution is approved.
> A successful marker alone is insufficient: confirm transaction end and exact
> complete before/after catalogue equality before proceeding.

Deployment and controlled file-upload approvals remain separate. No additional
infrastructure or architecture change is required by this preparation.

## Local preparation checks and files

`node tools/chat_basic/review_validation.mjs`: PASS for eight recorded artifact
hashes, bundle, future scanner hashes, original protected hashes, exact guarded
DDL copy, timeouts, marker, final ROLLBACK and no executable COMMIT/business RPC.
This review script is read-only and does not regenerate the hash manifest.
Original Chat static checker: **187 PASS**. Local export comparator self-test:
PASS for JSON/CSV equivalence, embedded commas/quotes/newlines, row/count/identity
checks and rejection of duplicates, truncation and failed absence checks.

Created only: this runbook, `supabase/diagnostics/chat_basic_rollback_baseline.sql`,
`tools/chat_basic/review_validation.mjs`, `tools/chat_basic/compare_baselines.mjs`.
Baseline source SHA-256: `5f022b4070e1d37aeb0432ad4ea5029c2b9800d439af77af68a1374ac6c650d1`.
New baseline SQL is locally reviewed but **not PostgreSQL-executed**; if it errors,
stop and report before any trial. No Flutter/Edge/SQL candidate/manifest change,
no guard removal, no execution copy, no live SQL, no Git operation.

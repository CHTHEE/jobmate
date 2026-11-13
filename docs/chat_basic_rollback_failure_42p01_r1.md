# Failed basic attachment rollback trial: 42P01 and guarded r1

**Latest status, 13 November 2026:** CH reports recovery complete and corrected r1
rollback trial successful, followed by confirmed transaction termination and
exact complete before/after baseline/preflight equality. The original failed
copy remains historical and must not be rerun. See the [completed r1 evidence and
disabled deployment preparation](chat_basic_deployment_preparation.md). The
FAILED/INCOMPLETE status and cleanup instructions below record the earlier
incident, not the current r1 outcome. Permanent deployment is not approved.

13 November 2026. **FAILED/INCOMPLETE. Original transaction termination and
rollback are UNCONFIRMED. Do not rerun the old approved copy.** No live SQL,
deployment, activation, uploads or business writes were performed by Codex.
All original reviewed files and the failed execution file are preserved.

## Diagnosis: confirmed facts and remaining uncertainty

The preserved failed file is
`tmp/chat_basic_rollback_validation_APPROVED_20261113.sql`, SHA-256
`c0728eb0d85bcce6a9a14468022eb00e70c456a3b8553e4ae1d2bacc027ce767`.

| Location in failed copy | Statement | Finding |
| --- | --- | --- |
| 129 | `CREATE TABLE jobmate_chat_private.basic_attachment_release (...)` | Correctly precedes its helper and assertions |
| 141 | SQL helper reads that table | After table creation; no forward-order defect found |
| 462–505 | Post-DDL catalogue assertion DO | Reads release configuration after DDL; table-privilege checks also resolve relation names |
| 507–520, especially **515** | Added read-only catalogue snapshot, constraint filter `'jobmate_chat_private.basic_attachment_release'::regclass` | Explicit early-bound name-to-OID cast, which raises missing-relation errors when resolved without that table |

The exact hazardous expression is:

```sql
FROM pg_catalog.pg_constraint
WHERE conrelid IN ('public.chat_basic_attachments'::regclass,
                  'jobmate_chat_private.basic_attachment_release'::regclass)
```

The original guarded rollback candidate creates the table at line 130; the
permanent migration creates it at line 129. Both order table creation before
dependent helpers. The extra top-level snapshot was added to the execution copy
from the runbook; it is absent from the original permanent migration.

PostgreSQL documents literal `regclass` early binding and `to_regclass` runtime
lookup in [object identifier types](https://www.postgresql.org/docs/17/datatype-oid.html).
However, **the supplied 42P01 message contains no position, line, context or PID**.
Multiple statements name the release table. Therefore the cast is a confirmed
hazard and a plausible failure site, **not a proven identification of the server's
actual failing statement**. Under normal sequential execution, successful table
creation first should make the later cast work. The error alone cannot prove that
the client preplanned that SELECT, that all statements executed on one session,
or that preceding DDL completed. Do not present this as a reproduced PostgreSQL
ordering bug. If r1 still fails, its explicit post-DDL checkpoint distinguishes
missing DDL visibility; preserve the full server error/CONTEXT if available.

A second confirmed usability problem: current pg-meta source returns the last
nonempty result set from a batch ([db.ts](https://github.com/supabase/postgres-meta/blob/master/src/lib/db.ts)).
The old early PID SELECT can therefore be hidden by the final marker result.
On an error the response may expose no result rows at all. This is not evidence
that the original backend ended; it explains why cleanup cannot depend on a PID
being visible in that failed response. The exact deployed Dashboard version is
not independently inspected here.

## Safe manual cleanup — first action now

1. If CH still has the **original established database connection**, run only:

   ```sql
   ROLLBACK;
   ```

   This is appropriate even for an aborted transaction. A new SQL Editor tab or
   pooled request is not proof of the original connection; a ROLLBACK there does
   not establish original-session cleanup. Do not run the empty rollback/down
   script, manually create the missing table or repeat any DDL.
2. From an independent observer connection, if the trial PID was recorded, run:

   ```sql
   SELECT pg_catalog.pg_backend_pid() AS observer_pid,
     (SELECT pg_catalog.jsonb_build_object('pid',pid,'state',state,
       'xact_start',xact_start,'backend_start',backend_start)
      FROM pg_catalog.pg_stat_activity WHERE pid=<recorded_validation_pid>) AS target;
   ```

   Observer PID must differ. Missing target, or idle target with null xact_start,
   confirms no open transaction on that backend. Active/idle-in-transaction/unknown
   state is unresolved; stop and have CH/KZ identify the original session. Do not
   terminate arbitrary backends or infer cleanup just from an elapsed timeout.
3. **If PID/original connection is unavailable**, CH opens and manually runs
   `supabase/diagnostics/chat_basic_failed_trial_cleanup_inspection.sql`. It is
   SELECT-only and returns observer/context, other client transactions and a
   possible-trial boolean; it never exposes query text or cancels/terminates
   sessions. It includes all client roles because current_user can differ from
   session user. Query-text matching is only a hint and may fail if truncated.
   A missing matching hint alone is not proof of cleanup.
4. Coordinate a quiet window with KZ. Require visible activity data and an empty
   `other_client_open_or_unknown_transactions` array before relying on the
   PID-unavailable path. Unknown/redacted states or unrelated active transactions
   mean cleanup is not yet established from that observation; investigate/recheck
   rather than kill sessions. Combined with the fresh exact catalogue checks
   below, an empty array establishes there is no remaining client transaction
   from the failed trial **at that observation**, without recovering its old PID.
   It does not prove the old script's final explicit ROLLBACK statement executed.

Do not claim the failed trial passed after cleanup. It remains failed/incomplete.
If the SQL Editor cannot provide a genuinely independent observer or enough
information to resolve cleanup, stop and report that limitation. No new software
installation, infrastructure or blanket session-termination action is prescribed.

## Fresh baseline and preflight are mandatory

After cleanup, CH runs these original read-only queries again in fresh sessions:

1. `supabase/diagnostics/chat_basic_rollback_baseline.sql` — require record count
   **2652**, unique key count **2652**, baseline MD5
   **`9117d06648f2fe2c85ac5d3131faee1f`**, five absence checks PASS and the complete
   export. Compare the full before/after maps using the existing local comparator:

   ```powershell
   node tools/chat_basic/compare_baselines.mjs "<preserved original before export>" "<fresh cleanup export>"
   ```

   Count or digest alone does not replace the exact keyed comparison.
2. `supabase/candidates/chat_phase6b_readonly_preflight.sql` — require postgres
   role/database, PostgreSQL **17.11**, origin replication role, **10** routines,
   reviewed backend MD5 **`a5d682393de3f9ffc66f01c5264ec7c1`**, and complete result.

Any mismatch/error/truncation is a STOP condition. Do not automatically accept a
new fingerprint, change hooks/grants or reuse the stale values merely to pass.
The failed trial's before/after comparison and historical 5761-record comparison
remain unconfirmed until their respective actual evidence is reviewed.

## Local r1 changes — all guarded, no execution copy

- `chat_basic_attachment_migration_r1.sql` is **byte-identical** to the original
  permanent migration. No equivalent top-level instrumentation exists there and
  no DDL dependency/order defect was found. Its hash remains unchanged. No new
  table is manually created and no business/security behavior is altered.
- `chat_basic_rollback_validation_r1_candidate.sql` preserves every pre-assertion
  source byte, including its unconditional approval guard, DDL, pinned ten-routine
  fingerprint, exact six-hook check and all timeouts. The assertion block resolves
  metadata/release OIDs with `to_regclass` after DDL, explicitly raises **55000**
  if either is absent, then performs the same old checks using those OIDs. This
  prevents a null lookup silently weakening assertions.
- The final **single marker row** includes PID, timestamp, isolation and the
  catalogue snapshot. Snapshot relation-name casts become `to_regclass` runtime
  lookups. New relation names are not early-bound top-level `regclass` literals.
  Final ROLLBACK remains. PID is visible with the marker on success; an earlier
  error can still suppress it, so the PID-unavailable cleanup path remains needed.
- `chat_basic_catalog_verification_r1.sql` contains the same safer assertions and
  consolidated evidence for a future installed disabled deployment. It must not
  be run after rollback when the objects should be absent.

No old runbook/snapshot/preparer is updated in place. The old runbook and failed
copy are historical evidence, **not retry instructions**. A later approved r1
execution copy must be created only in JobMate's ignored `tmp/`, remove only the
new r1 approval guard, and insert the newly reviewed transaction-local backend
MD5. Do **not** re-add the old snapshot or run the old preparation script. The
safe snapshot/PID are already part of this newly reviewed guarded candidate.

## Corrected reviewed hashes and new approval

Full manifest: `docs/chat_basic_attachment_r1_hashes.json`.

| Artifact | SHA-256 |
| --- | --- |
| r1 bundle | `52e68790f64b6f566bac30a871899b6130c6c6b1ad65606b23100a6e6e9fa317` |
| r1 guarded rollback | `4fb01897ba657df5118046b31d6f41994bfbfa0093f980976bbe4824d47ac010` |
| r1 permanent migration (unchanged bytes) | `96213f66af7639710eab1431373c70486dda92873577de7781ad010cb9ab09b2` |
| r1 read-only catalogue verification | `7e1d956d5e0e6beb2b2ee3bf9533820b39d4c80bef57f13ceee3111d028626c3` |

**After cleanup and fresh matching results**, return this new approval:

> CH and KZ confirm the failed trial transaction has ended and complete fresh
> catalogue/preflight results match the expected 2652/2652 baseline, five PASS
> absences, baseline MD5 9117d06648f2fe2c85ac5d3131faee1f and ten-routine backend MD5
> a5d682393de3f9ffc66f01c5264ec7c1. We approve preparing a new temporary execution
> copy in JobMate tmp/ and CH manually running one rollback-only DDL/catalogue
> trial on the existing shared JobMate Supabase project, using r1 bundle SHA-256
> 52e68790f64b6f566bac30a871899b6130c6c6b1ad65606b23100a6e6e9fa317 and guarded rollback
> SHA-256 4fb01897ba657df5118046b31d6f41994bfbfa0093f980976bbe4824d47ac010. Only its new
> approval guard may be removed and the fresh reviewed transaction-local MD5
> inserted. Preserve its consolidated read-only evidence, checks, timeouts and
> final ROLLBACK. Neither original SQL guard changes. No deployment, activation,
> business RPCs, files, messages, fixtures or Codex live execution are approved.

The old approval is **not reused**. After the new manual trial: require marker
`CHAT_ATTACHMENTS_CATALOG_ASSERTIONS_PASSED_ROLLBACK_PENDING`, PID/isolation/catalogue
evidence, confirmed transaction end, fresh absence/fingerprint equality and the
unchanged ten-routine MD5. Storage HTTP authorization, Edge validation, concurrency
and delivery still require separately approved runtime acceptance; this DDL trial
and the SQL-only trusted fixture cannot prove them or antivirus protection.

## Actual local verification and files

- **6 r1 regression tests PASS**: preserved original bundles/failed copy/guards;
  new manifest; identical permanent bytes and complete DDL/preflight; post-DDL
  fail-closed existence checks; all old assertions preserved after reversing only
  runtime OID substitutions; safe consolidated final marker/PID and ROLLBACK.
- **15 existing real basic-validator/protocol tests PASS**; original Chat checker
  **187 structural checks PASS**; original eight-artifact read-only review PASS.
- No PostgreSQL client/server is available locally and no installation/live SQL
  was authorized. **PostgreSQL compilation/runtime reproduction remains UNVERIFIED**.
  These structural regressions are not proof of the precise original server
  execution path or that r1 has passed live validation. No Flutter code changed;
  prior Flutter/build results are not rerun or newly claimed here.

Created only: this incident/runbook; `docs/chat_basic_attachment_r1_hashes.json`;
`supabase/candidates/chat_basic_attachment_migration_r1.sql`,
`chat_basic_rollback_validation_r1_candidate.sql`, `chat_basic_catalog_verification_r1.sql`;
`supabase/diagnostics/chat_basic_failed_trial_cleanup_inspection.sql`;
`tools/chat_basic/prepare_r1.mjs`, `tools/chat_basic/r1_regression.test.mjs`.
All original candidates, manifests, guards, reviewed baseline/preflight queries,
failed execution copy, Flutter/backend code and dependencies remain unchanged.
No unguarded r1 copy exists, and no live SQL, installs, commits or pushes occurred.

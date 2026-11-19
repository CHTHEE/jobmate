# Work assignment workplace coordinates · Stage 2B.2

Review only. The migration is based on the 12 RPC and eight enabled trigger
records in the November 19, 2026 production catalog exports.

The migration adds nullable `numeric(9,6)` workplace coordinates to the
assignment and creation-request tables. Each table checks paired nullability
and geographic bounds. Existing rows receive no backfill. The insert copies
the reviewed shift workplace and coordinates. Later edits to the posting
have no effect on the saved shift. Attendance coordinates and workflows
remain separate.

## RPC and compatibility contract

| RPC | Arguments in order | Return |
| --- | --- | --- |
| `reserve_work_assignment_request_v2` | application UUID, start/end timestamptz, workplace text, latitude/longitude numeric | Request UUID |
| `create_work_assignment_request_v2` | request UUID followed by reservation arguments | Assignment UUID |
| `create_work_assignment_v2` | Same as reservation | Assignment UUID |
| `list_my_work_assignments_lifecycle_v2` | None | SETOF jsonb |
| `list_company_work_assignments_lifecycle_v2` | Company UUID | SETOF jsonb |

Both coordinate arguments are required at the RPC boundary and may jointly
be SQL NULL. Reservation and finalization validate the raw pair first, then
round to six decimals. They compare the normalized pair and trimmed address
before returning an existing request or assignment. Changing either field on
the same idempotency key is a conflict. Coordinate-bearing and text-only
requests cannot be used interchangeably. Finalization copies the pair from
the locked reservation. Direct v2 goes through the same reservation and
finalization protocol in one transaction.

The three legacy write signatures, original bodies and grants remain in place
with pinned-request guards. Legacy reservation rejects reuse of a pinned
request, legacy finalization rejects it before linked-ID replay, and legacy
direct creation rejects a matching active pinned request owned by the caller.
Existing text-only clients continue using the same RPCs. The read-only lookup
keeps its existing access checks and return shape.

Application locking precedes posting and request locking. The existing
schedule checks, insert triggers, exclusion constraint, shift claims,
cancellation RPCs, and attendance-resolution guards remain in force. The
v2 reserve/finalize paths explicitly reject cancelled requests. Lifecycle
reads enrich only assignment IDs returned by the existing authorized
projections and retain their result order and attendance-resolution JSON.

New write EXECUTE grants mirror authenticated and service_role grants on
the existing writes. New reads mirror the authenticated lifecycle grants.
The private insert helper has no client EXECUTE grant. No table grants or RLS
changes are included. All new functions have an empty search path.

### Follow-up review

- The baseline guard checks each exported RPC's raw ACL, owner and definition.
  The final ACL guard rejects unexpected direct grants contributed by default
  privileges. Verify effective role membership and schema usage separately.
- Explicit null predicates prevent half-null pairs from passing a SQL CHECK.
  Exact boundaries pass. v2 rejects values just outside a boundary before
  rounding, even if they would round back into range. Invalid numeric strings
  fail while decoding or casting the numeric arguments. Numeric NaN and
  infinities fail the range comparisons. These are static findings pending QA.
- A cancelled pinned request is rejected by the legacy reservation/finalizer
  and the v2 request paths. Legacy direct creation still reaches the existing
  cancellation trigger for a cancelled request owned by its caller. Linked
  pinned requests cannot use legacy replay. For identical v2 replay, the
  normalized payload must match before the existing assignment ID is returned.
- Request identity remains actor-scoped. A different authorized representative
  can compete for the same application and slot under existing scheduling
  rules. The duplicate/overlap guards determine the winner and the other
  request may require audited cancellation. QA should cover this scenario
  explicitly. Neither actor can finalize the other actor's request.
- The private helper receives the pin from the locked reservation. It runs
  with the owner privileges, checks caller and company through the original
  insert logic, and uses the normal protected assignment insert path. No
  public direct-v2 path calls it without reserve/finalize.

Local execution is unavailable on this workstation. The PostgreSQL 18
installation lacks `postgres.bki`, and Docker, Supabase CLI and a WSL
distribution are unavailable. On an approved disposable host, use a complete
PostgreSQL installation matching the target version or a local Supabase stack.
Use a new loopback-only cluster and a schema-only approved baseline with
synthetic fixtures. Match the exported owners, signatures, raw ACLs and
triggers, and apply via `psql -X -v ON_ERROR_STOP=1` against the explicitly
verified local database. Exercise two independent local sessions for contention
and use local authenticated user JWTs against PostgREST for argument decoding,
exposed schema and cache behavior. Do not point the test client at production.

## Deployment and verification after approval

1. Recheck production for signature or trigger drift and compare table
   constraints and grants with the reviewed baseline. Schedule a quiet
   database window for the ALTER TABLE locks and constraint scans. Apply
   `20261119000200_work_assignment_workplace_coordinates.sql` once as the
   existing `postgres` owner. Definition, exported ACL or trigger drift aborts the
   transaction. A five-second lock timeout bounds DDL waits. Review timeouts
   and catalog mismatches before retrying.
2. Run `supabase/diagnostics/work_assignment_workplace_coordinates_postflight.sql`.
   Expect four nullable numeric (9,6) columns, two validated CHECKs, denied
   PUBLIC/anon EXECUTE, the documented effective role grants, and no normal
   client access to the protected tables. Expect no pinned assignments or
   pending pinned requests before enabling v2 writers. Check Data API schema
   cache availability separately.
3. In explicitly approved isolated QA, run the following cases with synthetic
   authorized and unauthorized accounts. Do not use the production postflight
   as an integration test.

| Case | Expected outcome |
| --- | --- |
| Legacy reserve/finalize/direct against text-only payloads | Existing behavior and NULL pair |
| v2 two-null, ordinary pair, and both signed boundary pairs | Accepted and returned on scoped reads |
| Half-null, out-of-range before rounding, NaN, infinities | Rejected before any new request or shift |
| Identical payload after rounding, then changed address or pair | Same ID on identical replay, conflict before replay on change |
| Legacy reserve, finalizer and same-actor direct against an active pinned request | Error without discarding or unlinking its pin |
| Cancel before finalization, link before cancellation, close engagement | Cancelled request stays terminal, linked request cannot cancel, closed engagement cannot create a new shift |
| Concurrent matching replay, conflicting pairs, duplicate and overlapping shifts | One linked assignment on matching replay, conflict or existing duplicate/overlap guard otherwise |
| Cross-company writes, another worker's reads, anon and inactive users | Existing ownership and role denial or caller-scoped empty read |
| Several shifts under one hire and a later posting edit | Each shift retains its own saved address and coordinates |
| Existing attendance, evidence, resolution, verification and downstream assignment references | Existing IDs, timestamps, GPS, audit and workflow behavior |

4. Roll out the coordinate-aware Flutter client only after database verification.
   No UI rollout is included here.

## Data-preserving rollback

Stop new v2 creation in the client and keep both columns, legacy guards and
v2 RPCs in place. This lets authorized callers reconcile outstanding request
IDs, finalize with the original payload, or use the existing audited cancel
RPC where the request is still eligible. Legacy text-only clients can run
during this rollback. Never downgrade a pinned request to a text-only request.

If retiring v2 is later required, first quiesce writers and drain or explicitly
cancel every pending pinned request. Verify an aggregate pending count of zero
and confirm that saved pins still have an authorized read path. Review a
separate function-retirement migration. Keep the columns and legacy guards
while pin-bearing records remain, including linked requests that may be
replayed. Do not drop columns, rewrite coordinates, or restore unguarded
legacy bodies as a rollback.

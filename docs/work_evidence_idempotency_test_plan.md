# Work evidence idempotency: draft review and isolated manual tests

> Historical review/test plan: deployment statements below describe an earlier
> implementation, not current release instructions. As confirmed by the project
> owner on 2026-11-06, follow-ups 20261105000300, 20261106000100, 20261106000200 and
> 20261106000300 are deployed and catalog-verified in the shared Supabase database.
> Runtime/security QA and coordinated client release remain separate gates.
> Do not reapply them or deploy the excluded 20261105000200 prototype. See
> [current deployment status and QA gates](work_evidence_workflow.md).


**Step 101G draft only. This plan has NOT been executed.**

Migration: `supabase/migrations/20261105000200_work_evidence_submission_idempotency.sql`.
The original deployed migration is unchanged. No production deployment, SQL,
uploads, fixtures or attendance actions are authorized by this document.

## Prerequisites

This checkout has no isolated PostgreSQL/pgTAP test harness or complete local
Supabase setup. Do not use the shared Supabase project as a substitute. Before
execution, provision an explicitly approved disposable Supabase-compatible
database with the prerequisite application/auth/Storage schema, roles, functions
and extensions. Do not reset or seed the real project.

Use synthetic workers, an employer, an unrelated worker, an inactive worker,
synthetic checked-out eligible assignments and private Storage fixtures. Include
both `not_submitted` and `more_evidence_required` cases. Test authenticated RPC
roles/JWT claims, not just superuser calls; use an independent administrative
connection only for fixture setup and verification. Do not use real user tokens.

The deployment role must be trusted, own or have sufficient authority over the
protected table, and be able to execute the legacy security-definer function.
The two new functions must have a trusted owner with the same intended protected
table access as the legacy RPC. Verify owners, RLS and ACLs before deployment.

## Manual test matrix (NOT RUN)

Record counts in `work_evidence`, `work_evidence_submissions` and
`work_verification_history`, plus the assignment status, before and after each
case. Inspect protected tables only through the isolated administrative verifier.

| Case | Action | Required result |
| --- | --- | --- |
| Legacy compatibility | Apply draft over synthetic existing legacy submissions; call original RPC on an eligible synthetic assignment | Existing rows retain both new fields NULL; legacy RPC, grants and history still work |
| New keyed submission | Submit a fresh UUID, valid description and 1-5 previously uploaded synthetic paths | One round and one history action; all file rows present; request fields recorded on exactly that worker/assignment/round; `pending_review` |
| Normalized replay | Repeat the same key and ordered paths, with only outer spaces changed in description | Original round returned; all counts and assignment timestamps unchanged |
| Changed payload | Change description, reorder paths, add/remove/replace a path with the same key | Safe conflict; no writes; original request remains intact |
| Malformed input | Try NULL key/description/paths, empty or >5 paths, duplicate/NULL paths, multidimensional or non-1-based SQL arrays, invalid folder/extension | Rejection; no partially registered request or evidence |
| Legacy validation | Try missing attendance, ineligible status, foreign/missing Storage object, wrong MIME/size and previously registered path | Existing rejection behavior preserved; no request association or partial writes |
| Ownership/role | Use anonymous, unrelated worker, inactive worker or employer identity, including a known request UUID | No submission or historical round disclosure; safe authorization error |
| Scope isolation | Try another assignment's request key and paths; reuse the UUID on a second eligible assignment with its own valid paths | No cross-assignment replay; second legitimate scope is independent |
| Replay after verification | Verify the synthetic assignment through the existing employer workflow; then replay as its active assigned worker | Original round; no second round/history/status mutation; employer verification remains intact |
| Authorization after commit | Deactivate synthetic worker or change its role, then replay and look up | Access denied despite a previously valid request |
| Lookup | Call `get_my_work_evidence_request` for committed and unknown scoped keys | Committed key returns only UUID, round and timestamp; unknown key returns zero rows, which is not proof of failure |
| ACL/RLS regression | Inspect function owners/ACLs, table privileges/RLS and Storage policies; try direct authenticated table access | Only authenticated EXECUTE on new functions, no anonymous/PUBLIC EXECUTE; direct table access still denied; existing Storage policies and legacy RPC grants unchanged |

## Concurrent sessions (NOT RUN)

Use two separate database sessions with the same synthetic worker identity.

1. Session A begins a transaction, calls the keyed RPC, and holds the transaction
   open without committing. Session B calls it with the same key and payload.
   B must wait on the assignment lock. Commit A: B must return A's original round
   at READ COMMITTED; exactly one submission/history action exists.
2. Repeat, but roll back A: B may perform the one successful submission.
3. Repeat with a changed payload in B: after A commits, B must raise conflict.
4. Race different keys for the same eligible assignment: after the first commits,
   the other must respect the resulting ineligible `pending_review` state.
5. Run concurrent legacy and keyed submissions: the shared assignment row lock
   must preserve one eligible submission. A legacy success has no request ID and
   must not be retrospectively claimed by a keyed call.
6. Repeat under REPEATABLE READ/SERIALIZABLE. A serialization failure is allowed;
   retry the complete failed transaction with the same key and payload. Never
   translate such an error into success or generate a replacement key.

## Atomic rollback / crash outcomes (NOT RUN)

- In the disposable database only, use a temporary test trigger to reject an
  UPDATE assigning `request_id`. A new keyed RPC must fail and leave no evidence,
  submission, history or status changes from the nested legacy call. Remove the
  trigger before other cases. This tests failure AFTER the legacy writes.
- Call in an explicit transaction and roll it back: no request metadata or
  submission writes survive. Retry the same key normally to confirm success.
- Simulate lost response after a confirmed database commit: same-key replay
  returns the original round. Lookup returns committed metadata.
- While A's request is uncommitted, an ordinary authorized lookup may return no
  row. Assert that this is treated as inconclusive, not permission to rekey.

## Remaining integration and deployment risks

- No database parser/runtime or concurrency validation has yet run. Review the
  actual deployed prerequisite definitions, ownership, PostgreSQL isolation and
  any additional triggers/policies before approving deployment.
- Adding columns/constraints takes table locks; the unique index build may block
  writes. Schedule a suitable deployment window after assessing table size.
- The wrapper delegates the existing private object, MIME, size, attendance and
  eligibility checks without changing their implementation. It relies on that
  prerequisite contract remaining compatible.
- A successful replay intentionally bypasses NEW-submission eligibility and
  Storage checks, but never current worker ownership/active-role checks.
- Existing `list_work_evidence` ordering is not a request-payload identity. The
  new stored path array is compared exactly and is not exposed by the lookup.
- The legacy RPC remains callable and has no keyed replay semantics. Its grants
  require a separate compatibility review before any retirement.
- Idempotency protects only the same key and canonical payload. No server
  reservation, restart key/payload recovery or durable client marker is added.
  Missing lookup results remain inconclusive. Production Submit Evidence stays
  disabled; Flutter still calls the legacy RPC until a separately approved step.

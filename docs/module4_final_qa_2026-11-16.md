# Module 4 final QA record — 16 November 2026

This is the current acceptance record; it supersedes the provisional fixture/count
and pending-Correct-Attendance statements in earlier planning/UI reports. No
application/backend change, migration, deployment or database write was performed
by the agent during this documentation/pre-commit pass.

## Evidence provenance

- Manual Chrome observations below were supplied by the owner, not independently
  repeated by the agent.
- Database results below were supplied by the owner after executing the prepared
  read-only query as postgres. Both identities resolved uniquely, one match each,
  in the same application/company/worker scope. The agent has no live SQL tool.
- The fixture-specific query and private baseline receipt are retained locally,
  excluded from the staging proposal. They contain exact assignment identities and
  B's saved hashes. No coordinates or credentials were exported to this report.

## Scenario A — late checkout: PASSED

QA TEST – Event Setup Assistant, ABC Company. The scheduled interval was
**16 November 2026, 2:20–2:25 PM MYT**. The worker checked in normally with GPS
granted, saw Check-out Overdue after scheduled end, and retained ordinary checkout.
Checkout with GPS granted succeeded, the UI showed Attendance Recorded / Late
checkout and an unapproved-payable-time disclaimer. Evidence round 1 was submitted
and employer verification completed. Final UI state was Work Verified, with
original timestamps/GPS status still visible and no payment approval.

Owner-supplied database verification:

| Field | Stored value, Malaysia time |
|---|---|
| Check-in | 16 Nov, 2:15:57.983905 PM MYT |
| Checkout | 16 Nov, 2:29:41.670743 PM MYT |
| Verified | 16 Nov, 2:33:26.677858 PM MYT |
| Exact recorded interval | 13 minutes 43.686838 seconds |
| Displayed whole minutes | 13 |
| Assignment / verification | completed / verified |
| Check-in and checkout GPS | granted; coordinates present and in range |
| Evidence | one submission, latest round 1, one attempt, one round-1 verification history entry |
| Attendance resolution | none |
| Historical initial evidence target | 17 Nov, 2:29:41.670743 PM MYT |

`a_matches_reported_database_state=true`. The rounded 2:15/2:29 labels do not imply
an exact 14-minute interval; stored seconds explain the 13-minute display.
Ordinary checkout cutoff was scheduled end +24h (17 Nov, 2:25 PM); the evidence
advisory target is actual checkout +24h (17 Nov, 2:29:41.670743 PM). They are separate.

**Preservation limitation:** A had no pre-checkout fingerprints. Its stored state,
GPS shape and post-verification fingerprints were checked, but database-level
before/after immutability was **not** proved. Historical unchanged check-in/GPS is
an owner UI observation. Current fingerprints are only a reference for future
comparisons; they must not be relabelled as pre-checkout evidence.

## Closure-blocking QA: PASSED; successful closure still pending

The owner added both new QA shifts to the existing engagement, rather than the
separate application suggested in the original plan. Record the actual state:
**five shifts — three verified, one confirmed absent, one non-terminal**.
The read-only database result confirms those counts and `engagement_closed=false`.

Worker UI shows Open and Not yet eligible for closure. Request closure is
unavailable; requirements correctly state that every shift must be verified,
confirmed absent or have an audited cancellation. This is a passed blocking test,
not a passed successful-closure test. Count totals alone do not independently prove
all closure checks (reservations, disputes, membership and audits).

## Shift B — preserved baseline; cutoff QA pending 17 November

Scheduled **16 November, 2:30–2:35 PM MYT**. Database check-in is
**2:16:26.066697 PM MYT**, with granted GPS and coordinates present/in range.
The earlier check-in is inside the existing 60-minute check-in window. State is
active / not_submitted, with no checkout, checkout GPS, evidence or resolution.
`b_unchecked_out_unresolved_baseline=true`.

The server-derived state on 16 November is **Check-out Overdue**, not yet
Incomplete Attendance. Ordinary cutoff is **17 November 2026, 2:35 PM MYT
(06:35 UTC), inclusive**. Leave B untouched until strictly afterward; use
**2:36 PM MYT / 06:36 UTC** as a practical buffer and refresh from the server.

Saved pre-correction fingerprints:

- Raw attendance: `1d8adc77f3ea9f7fd2df076e41cb40fc`
- Original check-in/GPS: `11d95d11b5c21f9d110c3cc7e57b334c`

Exact B/A identities and the private receipt are in:

- `supabase/diagnostics/module4_cutoff_qa_nov16_readonly.sql`
- `tmp/module4_cutoff_qa_baselines_2026-11-16.json`

The current fixture-specific query now pins the owner-confirmed UUIDs and also
checks schedules, job/company and application. It preserves A's missing-prior-hash
limitation and includes B's saved hashes plus a correction-audit comparison for
tomorrow. This updated query was prepared locally; its updated version has not
been executed by the agent. Expected today: identities resolve, A matches final
verified state, B matches saved raw/check-in hashes, and B audit comparison is
NULL until a correction exists. It does not invoke write RPCs.

## Automated / deployed-contract evidence

- **Six local automated cutoff tests passed:** two UI availability tests and four
  lifecycle tests. Exactly end+24h remains available; one microsecond after it is
  unavailable/incomplete. These use supplied server snapshots, not a changed clock.
- Owner reports **seven deployed contracts found**, inclusive predicate
  `server_time <= scheduled_end + interval '24 hours'`, checkout cutoff check before
  attendance writes and expired rejection SQLSTATE `22023`.
- Owner reports all eight inspected scheduling/attendance-preservation triggers
  enabled. Earlier Batch 2 owner deployment verification passed 34/34 catalog checks.
- These are not a live expired-checkout RPC rejection or database concurrency test.
  The guarded pure PostgreSQL boundary query has not been reported executed.

## Tomorrow's live QA — NOT PASSED YET

1. After B's cutoff + buffer, refresh worker UI: Incomplete Attendance and no
   ordinary checkout. Recheck B's saved raw/check-in fingerprints read-only first.
2. Only after explicit approval, fill/review the exact B identity, worker identity
   and fresh checkout-definition MD5 in the local rollback rejection probe.
   Run the whole approved script, require the exact cutoff rejection and unchanged
   rows, and roll back. Do not execute it in this pre-commit review. This is an
   emulated-identity server probe, not genuine GPS evidence or browser-auth proof.
3. Employer corrects B with documented actual QA-session times and reason through
   Review Attendance. Confirm correction; raw check-in/GPS and raw attendance must
   still match the saved hashes, and the audit's original snapshot must match.
   No automatic verification/payment approval may occur.
4. Worker submits evidence; employer verifies. Expect four verified shifts and one
   confirmed absence (five total), with originals and correction audit retained.
5. Refresh closure eligibility. If all server requirements pass, worker requests
   closure, employer reviews/confirms, and both see Closed. Closure is immutable;
   no payment or unrelated evaluation action is part of this QA. Until this runs,
   successful closure remains pending.

No rollback probe, attendance correction, evidence submission, closure or cleanup
was performed by the agent. Implementation can undergo Git review now with these
live acceptance limitations explicit; staging/commit/push still require approval.

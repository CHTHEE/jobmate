# Remaining late-checkout / 24-hour cutoff QA

**Current status after owner QA on 16 November:** Scenario A and closure-blocking
QA passed, with owner-supplied read-only database confirmation. Both new shifts
were actually added to the existing engagement; it now has five shifts, three
verified, one confirmed absent and one unresolved. B has a saved baseline and
must remain untouched until after 17 November, 2:35 PM MYT. Expired checkout,
rollback rejection, B correction/evidence/verification and successful closure
remain pending. The [current QA record](module4_final_qa_2026-11-16.md) supersedes
the earlier separate-application proposal and provisional counts below. Do not
create more fixtures or attempt closure using the old three-shift assumptions.

Preparation only, 16 November 2026. No database query/write, fixture creation,
clock change, migration, deployment, staging, commit or push was performed by the
agent. Existing verified/corrected QA shifts must not be reused or reset.

## Current evidence and read-only receipts

The owner subsequently ran the separate queries as postgres and reported all seven
contracts found, the inclusive deployed predicate, cutoff rejection with SQLSTATE
22023 before attendance writes, and enabled scheduling/preservation triggers.
Candidate discovery at **2026-11-16 06:06:33.7812 UTC (14:06:33.7812 MYT)** returned
zero matches and an empty array. These are owner-supplied live inspection results;
the agent has no connected SQL tool and did not independently execute them.
The two receipt queries remain available if needed, each with one SELECT/result:

1. `supabase/diagnostics/module4_cutoff_qa_contracts_readonly.sql`
   — seven explicit signatures, full deployed definitions, hashes, ACLs and
   ownership. All seven `found` results were reported true.
2. `supabase/diagnostics/module4_cutoff_qa_candidates_readonly.sql`
   — always returns one row: count, discovery result and `candidate_rows` JSON.
   An empty `[]` explicitly means no match under the current title/scope/window
   hints, not proof no suitable record exists anywhere. No mutation candidate is
   currently approved. Names alone prove nothing.

No suitable expired fixture was found under the inspected hints. The prepared
rollback probe therefore cannot presently run: it requires an approved naturally
expired fixture and the inspected checkout definition MD5. No backdating, trigger
disabling, clock changes or accepted-record edits are proposed.

## Shortest same-day route

1. Complete Scenario A on a dedicated short future shift in a separate QA
   application, through normal worker check-in/checkout with real GPS. Allow the
   scheduled end to pass, then check out well before end+24h. See the outcomes
   below. Do not attach this new shift to the accepted three-shift engagement.
2. Record Scenario B as **live expired-checkout RPC/manual flow not exercised**.
   The six local boundary tests passed and the owner inspected the deployed guard.
   Optionally run the guarded read-only PostgreSQL predicate query for exact
   before/at/after-cutoff evidence. This does not replace a real expired RPC test.
   A new naturally expired B fixture needs over 24 hours; rollback cannot shorten
   that elapsed time. Do not force this result merely to finish today.
3. Closure QA can use the existing QA TEST – Event Setup Assistant engagement
   (two verified, one confirmed absent), if the owner intends to finalize that
   test engagement. Worker refreshes, confirms Open + Eligible for closure, submits
   Request closure with a QA reason; both roles refresh and see Closure requested.
   Employer opens the pending request and uses Review and close, reviews the reason
   and explicitly confirms. Both roles refresh and see Closed; the original two
   verified and one absent records remain unchanged. New shifts are unavailable
   for that engagement; closure does not approve payment. Do not create a shift,
   payment or evaluation merely to test the closed-state UI.
4. Final successful closure is immutable. If the owner wants that QA engagement
   kept open, stop before final close or use the supported decline-request flow;
   document successful-closure QA as incomplete rather than claiming it passed.

No closure, request, fixture or attendance action is executed by this plan.

## Reviewed contract behavior to confirm against the fresh export

- Ordinary checkout locks the assignment, validates the authenticated active
  worker and location payload, captures `clock_timestamp()`, and calls
  `private.attendance_resolution_checkout_allowed(scheduled_end, actual_time)`.
  The reviewed predicate is `actual_time <= scheduled_end + interval '24 hours'`.
- At the exact cutoff checkout is allowed; strictly after it the reviewed RPC
  raises SQLSTATE `22023` with:
  `Checkout recovery window ended. Ask your employer to review attendance.`
- Checkout records actual server time, not scheduled end or device time.
- Employer correction requires ended, unverified eligible work, a matching hired
  relationship, open engagement, no existing resolution, no evidence records,
  submissions or **any** preparation attempt, and no unresolved related dispute.
  Correction preserves the raw attendance/GPS and records a separate immutable
  audit. It does not verify work or approve payment.
- Scheduling/duplicate/overlap guards remain enabled. Inspect the returned live
  scheduling validator too; do not bypass it to manufacture historical shifts.

## Fixture selection — fastest safe path

Use two **different** independently certified dedicated QA shifts, never the
accepted three-shift engagement or the accepted 8 November corrected Event Crew
Assistant shift. Controlled ownership and QA-only provenance must be confirmed
by the owner. Existing approved accounts can be used; no new accounts are needed.

Both must have valid relationships, active worker, verified company, an authorized
employer membership, active assignment, `not_submitted`, non-null recorded
check-in, null raw checkout, null verified timestamp, no evidence/preparations,
no resolution, no closed engagement/pending closure request or unresolved dispute.
`structurally_suitable_only=true` is necessary but **not permission to use a row**.
Do not clear blocked preparations or disputes to make a candidate qualify.

- **A:** scheduled end is past, cutoff is still future. Prefer at least 30 minutes
  of safety margin so the normal click/request cannot cross the cutoff in transit.
- **B:** server time is strictly after scheduled end +24 hours. Require documented
  actual QA-session times if attendance will be corrected; do not infer actual
  attendance from the schedule. Unknown provenance/times means choose another row.

Save a private manifest: A/B assignment IDs, application/company/worker IDs,
employer test account, provenance confirmation, scheduled times/cutoffs and
baseline fingerprints. Never paste tokens or GPS coordinates.

### If no suitable existing QA shifts exist

The compliant fallback is a fresh dedicated QA job/hired application through the
existing normal UI (or another independently certified empty QA application).
Do not add shifts to the accepted engagement: that would change its counts and
closure eligibility. Use clearly labelled job/workplace text such as
`QA ONLY — Module 4 cutoff rehearsal — A/B — <date>`; this is test-session data,
not genuine worker attendance, work approval or payable hours.

Using the server timestamp as the planning reference N, create non-overlapping,
future-start, same-Malaysia-day short shifts, for example:

- A: N+5 minutes to N+7 minutes.
- B: N+9 minutes to N+11 minutes.

Adjust for the actual UI validations, creation time, existing worker bookings and
midnight; use a later valid same-day window if needed. Actually perform the QA
check-ins with the worker account and capture real device GPS or its honest
permission outcome. Never insert invented check-ins/GPS or backdate an existing
shift. Record the observed test-session interval privately. Finish A normally;
deliberately leave B unchecked out and return after **B's server cutoff +60
seconds**. A new B fixture necessarily requires over 24 hours of real elapsed
time. If created on 16 November, this is ordinarily a 17 November follow-up.
There is no same-day shortcut consistent with unchanged time rules.

No SQL fixture setup is proposed: historical INSERT/retiming/trigger disabling
would bypass the existing scheduling safeguards. If existing data is unsuitable,
use the normal UI/elapsed-time path rather than silently relaxing rules. No base
users, memberships, applications or verified shifts are directly altered by SQL.

## Before either scenario

Fill the independently approved A/B UUIDs in
`supabase/diagnostics/module4_cutoff_qa_verify_readonly.sql`. Run it and save:
`server_as_of`, `current_attendance_hash`, `current_checkin_hash`, raw/effective
times, resolution and verification state. Copy baseline hashes into that script;
for A also copy the last pre-checkout `server_as_of` to `checkout_observed_after`.
It is one read-only SELECT in a read-only transaction and returns two rows.
NULL comparison flags mean missing baseline/input, not a pass. No coordinates
are exported. Before-state hashes can also come from the discovery query.

## Short manual steps and pass/fail criteria

### A — normal late checkout inside recovery window

1. Worker refreshes My Work Shifts. Confirm **Check-out Overdue**, recorded
   check-in, missing checkout and an enabled Check out action. Recheck the server
   cutoff margin in the read-only query before proceeding.
2. Use the normal checkout confirmation/GPS workflow. Grant actual device GPS for
   this GPS-specific acceptance test; do not simulate coordinates or permissions.
   Retry if the normal workflow offers it. If GPS is honestly denied/unavailable,
   preserve that outcome, but do not claim a granted-GPS test passed.
3. Refresh and inspect details/evidence. Checkout is marked late, real server
   checkout is after scheduled end but within cutoff, assignment awaits evidence,
   verification is not submitted, and no work/payment approval was created.
   Open the evidence form to establish eligibility, then cancel without uploading
   or confirming if evidence submission is not part of this remaining QA.
4. Rerun read-only verification. Require `original_checkin_gps_unchanged=true`,
   `checkout_in_observed_server_window=true`, `raw_late_checkout_within_cutoff=true`,
   valid checkout GPS shape, granted status/coordinates present for the GPS case,
   complete effective attendance and `awaiting_evidence_not_auto_verified=true`.
   A's whole raw-attendance hash **changes normally** because checkout was added.

### B — after cutoff, then employer correction

1. Worker refreshes after server cutoff +60 seconds. Confirm **Incomplete
   Attendance**, missing raw checkout, and no ordinary Check out action.
2. Server rejection must be proved separately from a hidden button. After fresh
   contract review and explicit approval of the exact fixture/hash, the owner may
   run `module4_cutoff_qa_rejection_rollback.sql` (classification below). Require
   the exact cutoff exception and unchanged assignment/attendance, then rollback.
   A different error (including authorization) is a failure, not cutoff proof.
3. Employer refreshes Work Verification, opens Review Attendance for B and selects
   Correct attendance. Enter the documented actual QA-session interval and a
   reason explicitly identifying the intentional QA omission. Check the preview,
   then Confirm correction. Do not substitute assumed scheduled working hours.
4. Worker refreshes and checks Corrected Attendance plus reason/date/originals.
   Rerun read-only verification **before** preparing evidence. Require raw checkout
   still null, `raw_attendance_unchanged=true`,
   `original_checkin_gps_unchanged=true`,
   `resolution_preserved_original_snapshot=true`, corrected effective timestamps,
   complete effective attendance and `awaiting_evidence_not_auto_verified=true`.
   `verified_at` stays null. Work Evidence must permit the existing next step;
   no automatic verification/payment or closure may occur.

Stop on unexpected results and retain evidence; do not reset/retry a different
resolution, mutate accepted records or delete immutable audits. Keep QA fixtures
labelled and retained; no cleanup/delete/closure is part of this plan.

## SQL classifications and approval boundary

| File | Classification | Expected result |
|---|---|---|
| `module4_cutoff_qa_contracts_readonly.sql` | Read-only metadata SELECT | Seven found signatures, definitions/ACLs for review |
| `module4_cutoff_qa_candidates_readonly.sql` | Read-only discovery SELECT | One row including count and JSON array, even if empty |
| `module4_cutoff_qa_boundary_readonly.sql` | Read-only guarded pure predicate test | Three `passed=true`, all `all_checks_passed=true` |
| `module4_cutoff_qa_verify_readonly.sql` | Read-only record comparison | Two selected fixture rows; compare stage-specific flags above |
| `module4_cutoff_qa_rejection_rollback.sql` | **Not read-only; approval required**, business RPC inside rollback | No errors; optional `CUTOFF_REJECTION_PASS` notice; ROLLBACK succeeds |

The rejection probe defaults to NULL IDs/hash and approval=false and therefore
fails closed before invoking an RPC. Supply the exact approved B/worker UUIDs and
fresh deployed checkout definition MD5 only after review. Pause activity on these
fixtures during it. It locks the selected application/assignment/attendance,
emulates that worker under the authenticated database role, and sends a synthetic
locationless protocol request with no coordinates. This is **not actual attendance
or GPS evidence**. It requires the exact cutoff rejection, compares before/after
rows, and rolls the transaction back. If checkout unexpectedly succeeds, it raises
and the transaction must be rolled back; no result may be committed. On any error,
run `ROLLBACK` in the same session and report it. Do not run only fragments.
SQL Editor may show only `Success. No rows returned.` at the final ROLLBACK; every
test condition is asserted and any SQL error is failure even if a later rollback
succeeds. No permission is implied by the file existing.

## Automated boundary evidence

Executed locally for this plan:

```powershell
flutter test --no-pub test/work_attendance_lifecycle_pages_test.dart --plain-name 'ordinary checkout recovery is inclusive at end+24h' --reporter expanded
flutter test --no-pub test/work_attendance_lifecycle_test.dart --plain-name 'checked-in recovery classification' --reporter expanded
```

**2/2 UI boundary tests and 4/4 lifecycle tests passed.** They explicitly cover
checkout available at exactly end+24h and unavailable one microsecond after,
using server-snapshot inputs, not the device clock.

The separate guarded PostgreSQL predicate query tests one microsecond before,
exactly at and one microsecond after cutoff. It uses synthetic *function
arguments*, never changes real clocks/rows, and must return true/true/false.
It has **not been executed by the agent**. It proves the deployed pure predicate
when run, not the entire real checkout RPC. Timing an actual browser click at a
microsecond boundary is not a practical acceptance method. The rollback probe
adds real server-RPC rejection evidence after the cutoff, under the stated
identity emulation; browser QA uses the real signed-in worker/employer accounts.

Current pending gates: tomorrow's live B cutoff/rejection/correction/evidence/
verification and successful closure. Scenario A and closure blocking are now
owner-reported passes, with read-only database receipts recorded separately.
No live PostgreSQL predicate/probe result is claimed by the agent. Final Git
review remains a separate step; no staging/commit/push approval is implied.

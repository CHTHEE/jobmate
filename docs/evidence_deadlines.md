# Evidence deadlines and overdue handling: Phase 6

## Verified source contracts

This is a local source audit and UI change, not a live database verification.
No SQL, migrations, policies, RPCs or triggers were changed or executed.

`check_out_work_assignment` in
`supabase/migrations/20261105000100_work_attendance_verification.sql` locks the
assignment and attendance, checks worker authorization and a prior check-in,
assigns `check_out_at := clock_timestamp()`, and changes the assignment to
`awaiting_verification`. Both assignment-list RPCs return that recorded checkout.
`WorkAssignment.checkOutAt` parses the timestamptz with a mandatory zone into UTC.
The attendance repository reloads authoritative rows after a clock action; the
RPC acknowledgement alone is not projected as a successful local checkout.

This allows a deterministic initial suggested target: **actual recorded checkout
plus 24 elapsed hours**. Scheduled shift end is never substituted. The target is
per assignment, not per hired application or group. A later checkout gives that
shift a later target, even when other shifts belong to the same application.

The inspected submission functions require active worker ownership, completed
attendance, correct assignment/verification state, valid private files and
submission-round identity. They contain no elapsed-time deadline test:

- Base `submit_work_evidence`: initial `not_submitted` or subsequent
  `more_evidence_required`, only while `awaiting_verification`; stores submissions,
  file metadata and history and sets `pending_review`.
- `20261105000300_work_evidence_attempt_reservations.sql`:
  `prepare_my_work_evidence_submission` and `submit_work_evidence_idempotent`
  serialize assignment/round reservations, check completed attendance and
  validate immutable payloads; replay returns the existing attempt. No 24-hour
  cutoff or reservation-expiry/extension API is defined.
- `20261106000300_work_evidence_workflow.sql`: exposes authorized lifecycle/history
  and round-bound employer review. A request for more evidence sets
  `more_evidence_required`; verification records history and completes the shift.
  Legacy public submit/review grants are cut over to the guarded workflow.

`WorkEvidenceWorkflowSnapshot.canSubmit` and the submission controllers use server
lifecycle/attendance/round eligibility, not local time. Submission, reservation,
review and file/history timestamps record their respective events; they are not
alternative checkout anchors. No deadline, extension, overdue-failure status or
authoritative server-now field is exposed in these list/workflow contracts.
Late submission and resubmission are therefore **not time-blocked by the inspected
backend code**, while all other eligibility/security checks still apply. This
does not claim an uninspected live function has identical behavior.

## Implemented advisory display

Worker shift cards, employer shift cards and both evidence detail views reuse
`EvidenceDeadlineSummary` and its presentation-only calculator. Dates are fixed
Malaysia time (MYT, UTC+08:00), independent of device timezone; arithmetic uses UTC
instants and supports overnight/month/year rollover.

| Loaded server state / local timing | Display |
| --- | --- |
| Scheduled or active, no checkout | Evidence timing starts after recorded checkout |
| Awaiting initial evidence, more than four hours remain | Not yet due |
| Awaiting initial evidence, four hours or less remain, before target | Due soon |
| Awaiting initial evidence, at or after target | Overdue |
| Pending review | Submitted, irrespective of elapsed target |
| More evidence required | More Evidence Required; original initial target only, no invented new resubmission deadline |
| Verified | Verified, irrespective of elapsed target |
| Cancelled/disputed or completed without a verified outcome | Timing not assessed; existing lifecycle remains authoritative |
| Missing/inconsistent completed attendance or device time before checkout | Timing unavailable; do not invent a date from the schedule or classify overdue |

The four-hour Due soon threshold is an initial presentation choice, not a backend
rule. Exactly checkout+24h is Overdue **only for an otherwise eligible initial
submission**. Submitted work is not called overdue while waiting for employer
review. More Evidence Required is not treated as failure or as a new missed
deadline; the original date, when available, is explicitly labelled initial.
No on-time/late outcome is inferred from file upload time or a resubmission round.

The widget recalculates once per minute while open and on app resume. It reflects
the last loaded server status and responds to refreshed assignment rows; the
timer does not fetch or mutate backend data. Relative labels can lag a boundary
by up to the next minute tick. Existing page refresh/navigation and post-action
reloads continue to supply authoritative status.
On evidence pages with the real workflow panel, the summary uses its freshly
loaded workflow status rather than an older page-header projection, including
when Refresh verification status is used independently.

There is no server-now contract, so relative labels explicitly say they are
advisory and use the device clock. Timezone conversion does not fix clock skew.
A device clock before recorded checkout is detected as unavailable; an otherwise
plausible clock running ahead/behind cannot be detected offline. The absolute
checkout-derived target remains the reliable part. No eligibility, button,
submission, review, RLS or backend mutation depends on the local calculation.
No overdue status is persisted. No rejection, extension gate, penalty, payment,
trust-score change, shift cancellation or arrangement termination is introduced.

## Reminders: backend design required, not implemented

The [Phase 5 notification audit](shift_scheduling_notifications_audit.md) records
the six-field list/read contract, missing event identity/assignment targets,
absent verified shift emitter and the historical mark-read SQL mismatch. The
checkout contains no verified evidence-deadline reminder scheduler, durable
deduplication contract or notification dispatch function for this use case.
Client timers must never be used to deliver reminders: they stop on tab/app
closure and can duplicate across sessions. Notification UI/permissions remain
owned by the existing module owner and were not modified.

A later reviewed reminder design should:

1. Establish a versioned server policy anchored to the saved checkout instant.
   Return server-now/eligibility with due metadata if authoritative relative
   labels are wanted. Do not turn this UI target into a hard cutoff implicitly.
2. Use an approved server scheduler to select checked-out assignments with no
   initial submission and eligible status. Proposed milestones are one Due soon
   reminder and one Overdue reminder; frequency/grace policy requires agreement.
   Do not remind for pending review, verified, disputed/cancelled work, or treat
   employer-requested additional evidence as an initial non-submission.
3. Lock and recheck the assignment and formal submission state before atomically
   recording a durable event/inbox item or approved outbox entry. Coordinate with
   submission's assignment lock. A reminder committed just before submission may
   legitimately become outdated; opening it must load fresh authorized status.
   Recheck eligibility at delayed dispatch when using an outbox.
4. Deduplicate per assignment, milestone and that assignment's stored deadline
   policy identity. A job rerun, worker restart or deployment must not generate
   the same milestone again. Policy changes must not automatically reissue old
   reminders. Resolve the worker from trusted assignment/application data.
5. Preserve recipient-only read/mark-read controls and use an owner-approved
   allowlisted target to the existing worker assignment/evidence route. Format
   the target time explicitly in MYT and include no private Storage URLs.
6. Test scheduler retries/concurrency, lost responses, submission/reminder races,
   eligibility changes, recipient authorization and event uniqueness in an
   approved isolated database. No scheduler/migration/RPC/RLS work is delivered
   in this phase. No Dashboard steps are required now.

## Extension and resubmission recommendations

Keep the initial 24 hours as a suggested target until a server policy is agreed.
Allow late evidence through the existing eligibility workflow; do not require an
extension request to submit. Preserve employer feedback/resubmission and existing
records. No extension workflow is available or needed for this advisory display.

If a formal extension or resubmission deadline is later required, agree who may
grant it, the reason, effective time, revision/concurrency handling and an immutable
audit. Return the server's effective target to both roles; retain the original
target and every grant/decision. A new deadline for additional evidence would need
an agreed rule tied to the actual review/request round and server timestamp,
not automatic reuse of checkout+24h. Coordinate any dispute implications with KZ;
do not impose automatic failure, rejection or financial/trust consequences.

## Validation scope

Focused tests cover exact 20/24-hour boundaries, UTC/MYT rollover, missing and
contradictory attendance, device-clock reversal/resume, server-status precedence,
independent grouped shifts, enabled late actions and actual controller submission/
resubmission against local fakes. Layout tests include 320/840/1440 widths with
enlarged text. These do not establish live RPC acceptance, RLS, Storage, physical
Android or browser/device-clock acceptance. No live records were accessed.

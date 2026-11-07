# Final Module 2/4 UI polish

## JOB-001: Apply after application submission

Root cause: `JobDetailsPage` observed only the published-job repository. Its Apply
button depended on posting availability, not the owning worker's application
list, and closing the submission dialog with Done returned no navigation route
and skipped any application-state refresh.

The page now loads the existing owned `list_my_job_applications` contract through
a route-owned `MyApplicationsRepository`. Unknown/loading and failed lookups do
not enable Apply. A matching job ID shows the real status and View Application
using the existing details route. All eight supported statuses are recognized.
The newest returned matching application is used if historical matches exist.
Submission success immediately records its confirmed ID for this page/account
and refreshes the list; the confirmed result is not undone by a temporarily
stale empty list. Entry, explicit refresh, resume, dialog closure and return
navigation refresh lookup state. Account changes invalidate pending list reads.

No reapplication permission was invented for Rejected, Declined or Withdrawn.
The actual Module 2 SQL/reapplication policy remains absent from the checkout;
these states therefore retain View Application rather than exposing another
submission. The page uses the existing list projection, not a new per-job RPC or
table query. Deployed list completeness and duplicate enforcement still require
backend acceptance; server duplicate protection is unchanged.

## UI-002: Precise shift time input

Root cause: time fields offered the default circular Flutter time picker despite
already having a strict, device-timezone-independent MYT `HH:mm` parser.

Start/End time now use their existing editable 24-hour fields directly, with
HH:mm hints, examples and Next keyboard actions. Calendar pickers remain for
dates. No clock-face dialog or dependency was added. Validation rejects invalid
hours/minutes, incomplete input and non-two-digit formatting. Existing trimming,
date validation, end-after-start and overnight conversion remain unchanged.

## SHIFT-003: Conflict confirmation

Root cause: the repository returned a generic rejected result for a known
duplicate/overlap, but the dialog still offered Confirm creation. Repeated
clicks were already blocked by preflight/server constraints; the visible action
misrepresented the result as confirmable.

Results now carry an explicit schedule-conflict indicator for the existing
complete company-list preflight and structured backend exclusion/unique
violations (`23P01`/`23505`). A conflict removes Confirm creation, explains that
creation is blocked, and retains Edit/Close. Edit preserves the selection by
application/job ID from fresh authorized candidates rather than comparing old
object identity, which previously lost the selection after preflight reload.
Editing and reviewing again still runs full preflight and server enforcement.

Network/ambiguous results are not classified as safe or as definite overlap.
Their original ledger lock and Phase 7 Check current assignment action remain.
No cross-company assignment details are exposed: Flutter sees only the selected
company, while the existing database exclusion protects worker overlap globally.
No constraint, RPC, trigger, RLS, migration or live data was changed.

## ATT-004: Attendance failure feedback

Root cause: `_clock` refreshed server state and retained its safe page error, but
only successful outcomes had prominent feedback. Failure returned to small text
above the shift cards.

Failures now show one scrollable, dismissible error dialog while action controls
remain locked. The outside-window dialog uses the actual scheduled start in MYT
and a neutral Check-in unavailable title. The server's message covers both sides
of the permitted window and exposes no early/late reason or server-now value;
the UI does not guess from device time or hardcode window length. Denied access,
authentication, structured rejection, uncertain/network outcomes and accepted
requests whose refresh failed have distinct appropriate wording. Unknown raw SQL
details are not rendered. GPS denied/unavailable still offers the existing retry
or explicit continuation; captured GPS does not imply server attendance success.

The last actual exception is retained only in the repository's session-scoped
in-memory `actionFailure` for diagnostics. It is not logged, persisted or shown
raw, and is cleared on a new action/account change. Account changes invalidate
dialog details. There is no automatic retry or new write; authoritative list
refresh, success snackbars and server attendance timestamps remain unchanged.

## Verification and remaining acceptance

- Focused Module 2/4/job-browsing suite: 730 passed.
- Analysis: four baseline informational lints; no errors, warnings or new issues.
- Full Flutter suite: 1,288 passed; the same five admin baseline failures remain
  (admin-sidebar ink, company-review logo previews at 320/1440, pagination and
  retryable Storage permission errors). No new failures. Added 22 passing tests.
- Changed Dart files formatted; documentation links and `git diff --check` passed.
  Git reports LF-to-CRLF notices for edited Dart files.
- Added regression coverage for every existing application status, unknown/error
  lookup, immediate submission success, route return and stale-account reads;
  invalid/precise minute input and overnight UTC mapping; local/backend conflicts
  and Edit recovery; GPS capture plus outside-window rejection, authorization,
  network/server failure, diagnostics clearing and accepted-but-unrefreshed state.
- Existing non-conflicting creation, uncertain/reopened request recovery, GPS
  fallback, successful attendance, grouped-shift/evidence/deadline and responsive
  tests remain part of the regression runs. No live Supabase calls were tested.

Final Chrome/Android acceptance should verify focus/keyboard/touch behavior, actual
application list/duplicate policy, GPS and successful attendance within the server
window, followed by the full real evidence-verification cycle. The user's earlier
Chrome results are context, not newly executed acceptance tests. Deferred editing/
cancellation, arrangement termination, notifications and reminders remain deferred.

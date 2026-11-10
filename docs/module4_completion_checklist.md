# CH Module 4 finishing sprint

November 10 final implementation update: closure inbox now prevents duplicate
responses during confirmation/submission, discards replaced-gateway completions,
and reloads authoritative requests after successful or uncertain responses.
Closure RPC automatic retries are disabled. Dart formatting and scoped diff
whitespace checks passed; no additional tests/analyzer were run. The earlier
passing test results below predate these edits. Current manual sequence and
specific remaining lock/API blockers are in `module4_release_execution.md`.
Historical fixture/backup setup recommendations below are superseded by the
owner's latest instruction: no new users, production fixture mutations, second
database or local backups. No deployment has occurred in this sprint.

| Status | Item | Exact next action / evidence |
| --- | --- | --- |
| DONE | Shift creation no longer dereferences a cleared selection after account changes during closure preflight | Captured candidate and actor recheck before dispatch; regression verifies zero reservations/creates and no exception. |
| DONE | Closure refresh failure cannot retain stale close controls | Clear old status, expose read retry; generation check ignores old application responses; changed gateway is actually used. |
| DONE | Closure reason dialog cannot dispatch against a changed application/gateway | Captured context checked after dialog and completion; regression verifies no close call. |
| DONE | Focused Flutter checks | Three-file run: 36 passed, 0 failed. Final closure-controls run after additional regression: 4 passed, 0 failed. Focused four-file analyzer: no issues. No full suite. |
| DONE | Routing/network integration audit | Reviewed production attendance/verification/evidence routes, shared destination registration, creation/closure, attendance/location and evidence workflow/upload/preview paths. Existing GoRouter gates/company resolution preserved. No production TODO/FIXME/unimplemented network stub found by targeted search; mock/QA/demo code remains separate. No KZ code or API contract changes. This is a static audit, not Web/Android acceptance. |
| DONE | Scheduling rollback compilation candidate | `supabase/diagnostics/work_shift_schedule_enforcement_rollback_compilation_check.sql`: temporary A0→security A1→scheduling B1 in ONE transaction, exact allowlisted DDL hook, 2-second lock timeout, body validation and final ROLLBACK. NOT executed. |
| NEEDS LIVE TEST | Security authorization/runtime | Provision only the two NEW dedicated identities and fixture graph per `closure_security_new_fixture_setup_and_runtime.md`; use the prepared rollback runtime candidate. No existing records/fixtures are authorized. |
| PREVIOUS CANDIDATE PASSED; REVISED CANDIDATE NEEDS LIVE CHECK | Scheduling installation/metadata | In a verified project and paused DDL/Module 4 write window, human reviews/runs the entire new rollback compilation file. Require B1 31/31 INSIDE, then A0 31/31 again AFTER rollback. Embedded PL/pgSQL SQL and actual writes are not validated just by installation. |
| NEEDS LIVE TEST | Actual authenticated PostgREST isolation | User-reported catalog/editor defaults are READ COMMITTED with no overrides. Verify actual RPC execution/hook/pool behavior; SQL Editor simulation is not API evidence. Do not remove the scheduling isolation gate. |
| IMPLEMENTED; NEEDS LIVE RACE CHECK | Direct rescheduling versus cancellation | UPDATE application-row locks now use NOWAIT: contention fails with 55P03 instead of forming the assignment/application wait cycle. Cancellation/authorization unchanged. Revised rehearsal and two-session verification pending; no arbitrary multi-row deadlock guarantee. |
| BLOCKED | Recovery/fixture cleanup | Confirm backup/PITR and restore access, operator and approved dedicated-fixture retention/cleanup. No verified backup/restore method or dedicated fixture UUIDs supplied. Do not hard-delete immutable audits or bypass RESTRICT FKs. |
| NEEDS LIVE TEST | Web/Android acceptance | Check real account switch during confirmation, failed status-refresh recovery, attendance GPS denied/unavailable/granted, private evidence upload/preview/review and direct-route Back/refresh. No device/browser acceptance executed in this sprint. |
| BLOCKED | Live completion/deployment claim | Security and scheduling remain NOT DEPLOYED. KZ approved the separate security fix and concurrent-revocation limitation; runtime/recovery gates still apply. Never use code rollback to claim data/audit activity was reversed. |

Shortest remaining path: approve NEW fixtures and recovery → focused security
runtime rollback test → scheduling rollback installation check → actual API and
two-session critical checks → human-approved security deployment/check A1 →
human-approved scheduling deployment/check B1 → Web/Android acceptance. No full
31-scenario run, automatic deployment or Git merge changes are required here.

Deferred scope remains explicit: future shift edit/cancel and scheduling-notification
audits describe work not implemented by this sprint. Lost reservation-response
recovery remains the documented authorized support path, not self-service retry.
Confirm FYP acceptance scope with the owner; do not present those as completed UI.

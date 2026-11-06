# Module 4 pre-commit UI review

> Historical review/test plan: deployment statements below describe an earlier
> implementation, not current release instructions. As confirmed by the project
> owner on 2026-11-06, follow-ups 20261105000300, 20261106000100, 20261106000200 and
> 20261106000300 are deployed and catalog-verified in the shared Supabase database.
> Runtime/security QA and coordinated client release remain separate gates.
> Do not reapply them or deploy the excluded 20261105000200 prototype. See
> [current deployment status and QA gates](work_evidence_workflow.md).


No live writes, migrations, RLS changes, new dependencies, commits or branch
changes are part of this cleanup. The reported real QA happy path was performed
by the user, not by automated tests. Existing uncommitted work is retained.

## Completed UI work

1. Application success keeps the returned UUID internally, with friendly copy.
2. Applicant status uses the authoritative enum's one human-readable label.
3. Status success titles/messages follow the actual transition and applicant name.
4. Shared account-menu sign-out captures the root GoRouter before async logout,
   replacing nested routes with Home/login instead of using page-specific push
   callbacks. Signed-out job forms permit exit; signed-in dirty guards remain.
5. Assignment creation hides application UUIDs, retains RPC UUID arguments and
   confirmation names, and offers built-in date/time pickers alongside validated
   editable fields. MYT wall time still converts explicitly to UTC+08:00/UTC.
6. Attendance success is action-specific. Check-out confirmation no longer quotes
   the check-in window. One-time actions and the absence of a minimum duration
   follow the deployed SQL; buttons use returned status and attendance timestamps.
7. Evidence displays attendance times, description, round, MIME and submission
   time. Authorized employer applicant RPCs resolve names when available; missing
   or ambiguous names use a neutral label, never invented names or direct user
   profile/protected-table queries. Worker names also appear on employer shifts.
8. QA review labels/confirmations use job/name context, identify QA-only mode,
   explain no-retry/restart limitations, and show verified success only after a
   confirmed RPC and fresh verified status. Uncertain results never show success.
9. Shared navigation groups expand/collapse, with active-child highlighting and
   automatic parent expansion. Dashboard, routes, role destinations, Android tabs,
   Web sidebar/drawer and all demo/sandbox labels remain available.

## Private previews

Open View PDF/View image on a submitted evidence card. Fresh authorized assignment
and evidence RPC reads select the file; can_read_work_evidence_file independently
checks its path. Only then does the private work-evidence bucket mint a 90-second
signed URL through its existing SELECT policy. No public URL or service-role key
is used. Account changes/stale responses/expiry clear the in-app preview. Images
render inline, with missing-file feedback and cache eviction on preview disposal;
PDFs open through the project's existing browser/native PDF opener. The second
Open PDF click is a user gesture, avoiding a popup after async authorization.

Manually verify Web popup/PDF handling, Android's available PDF app, actual image
rendering/CORS, denied access, expiry and sign-out during a preview. Signed links
are bearer capabilities until expiry; an external tab or a file already viewed
cannot be recalled by logging out. Browser/device caches are not a secure erase
facility. URLs are not printed or displayed as permanent links.

## General production actions remain blocked

The safety decisions are independent; neither general flow was enabled:

- **Worker submission:** the deployed RPC is non-idempotent and app-lifetime
  locks do not survive restart or coordinate devices. The server-reservation
  draft still needs independent SQL review, isolated concurrency/rollback/auth
  tests, a blocked-attempt recovery decision, a verified backup/restore plan and
  coordinated legacy-entry-point cutover. Then integrate and mock-test durable
  reservation/recovery before replacing QA gates with fresh per-worker eligibility.
- **Employer review:** existing authorization is reusable, but the deployed RPCs
  accept no expected submission round or durable decision identity. A delayed old
  request-more/verify call can affect a later eligible round. Fresh reads narrow
  but do not atomically close that race. General release needs an independently
  reviewed expected-round/decision contract and restart/uncertain recovery; it
  must not silently remove the QA restriction. No such backend change was made.
- **History:** no authorized verification-history read RPC is deployed. The UI
  truthfully says history is not available here; submission rounds are actual
  evidence metadata, not fabricated verification history.

The existing supervised QA controls and running-session blocks remain intact.
Never restart/reopen to retry an uncertain write. No draft SQL was applied.

## Pre-commit review

Review the current diff and all untracked Module 4 files without discarding them.
Confirm private previews on Web/Android and application/logout/navigation flows
with test accounts, without modifying the original cafe assignment. Check that
normal submission/review remain disabled outside the QA assignment, no secrets
or permanent file links are present, and all relevant fake tests pass. The
existing authentication Radio deprecations and unused profile field are unrelated
analyzer diagnostics, not part of this cleanup. Commit only after user review.

## Files changed by this cleanup

Existing changes in other files, including main.dart, app_routes.dart, migrations
and other Module 4 sources/tests, predate this cleanup and were retained.

Application and form sources:
- lib/features/applications/job_application_form.dart
- lib/features/applications/employer_applicants_page.dart
- lib/features/applications/employer_status_change_form.dart
- lib/features/applications/my_application_details_page.dart
- lib/features/jobs/job_form_page.dart

Shared navigation sources:
- lib/shared/widgets/workspace_account_menu.dart
- lib/shared/widgets/app_workspace.dart
- lib/shared/navigation/workspace_destinations.dart

Module 4 sources:
- lib/features/work_attendance/work_assignment_creation_dialog.dart
- lib/features/work_attendance/work_assignment_people.dart (new)
- lib/features/work_attendance/work_verification_pages.dart
- lib/features/work_attendance/work_attendance_pages.dart
- lib/features/work_attendance/work_attendance_repository.dart
- lib/features/work_attendance/work_evidence_pages.dart
- lib/features/work_attendance/work_evidence_preview.dart (new)
- lib/features/work_attendance/work_evidence_qa_review.dart

Tests:
- test/job_application_form_test.dart
- test/my_application_details_test.dart
- test/employer_status_update_test.dart
- test/work_assignment_creation_dialog_test.dart
- test/work_attendance_actions_test.dart
- test/work_verification_pages_test.dart
- test/work_evidence_pages_test.dart
- test/work_evidence_qa_review_test.dart
- test/workspace_test.dart
- test/support/workspace_navigation_test_helper.dart
- test/work_evidence_preview_test.dart (new)
- test/work_evidence_preview_source_test.dart (new)
- test/work_assignment_people_test.dart (new)
- test/ui_cleanup_regression_test.dart (new)

Documentation: README.md and this new review note.

## Validation

- Full Flutter suite: 1,129 tests passed. A subsequent message-only review polish
  was verified with all 11 targeted review tests passing.
- Flutter analyze: three existing diagnostics only: deprecated groupValue and
  onChanged in sign_up_page.dart (320/336), unused _user in
  verify_password_page.dart (28).
- Flutter Web build succeeded; Wasm dry run also succeeded. No deployment.
- Formatting applied to changed Dart files; git diff --check passed.
- Teammate attendance/demo directories have no tracked diff.
- Real browser/device behavior, live private Storage previews and PDF-app
  handling remain manual checks; tests use fakes/loopback, not live Supabase.

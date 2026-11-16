# Final consolidated Attendance & Work Verification UI polish

16 November 2026 — local implementation only.

Historical implementation report. The [current QA record](module4_final_qa_2026-11-16.md)
and [pre-commit review](module4_precommit_review_2026-11-16.md) supersede provisional
manual-QA gaps and staging suggestions below. Correct Attendance and Scenario A
have since passed owner QA; live B cutoff/successful closure remain pending.
The UUID-only Application details section was subsequently removed as approved.

## Outcome and scope

The approved shell, assignment creation flow, filters, grouping and server-derived
lifecycle remain in place. The owner-reported QA engagement (Event Setup Assistant,
Alex Thee, ABC Company: three shifts, two verified and one confirmed absent) was
not queried, reset, changed or closed by this work. The supplied manual QA results
remain owner-reported acceptance evidence, not newly executed agent tests.

Completed changes:

- Shared verification tones use amber for pending review and more evidence,
  success for verified work, red for unresolved missed/incomplete attendance and
  neutral for confirmed absence. The worker resubmission action is emphasized
  within amber styling and explicit action-required copy. Active feedback styling
  disappears after resubmission; historical feedback remains.
- Duplicate verified badges were removed where attendance and verification mean
  the same completed result. Recorded attendance and evidence review remain
  distinct. Company Workers' verified count uses the existing success color.
- Initial/resubmission forms have appropriate titles, upcoming round and actual
  employer feedback, required-field asterisks, interaction-driven validation,
  disabled invalid submission, a scrollable body and a bottom action area.
  Progress, selected files, removal, retry, uncertain-result recovery and dirty
  draft protection remain. The 1–5 supported-file/10 MiB limits are unchanged.
- Employer verification/request-more-evidence uses one dialog with internal
  confirmation and Edit, preserving round, reason and authorized worker/shift
  context. Final buttons identify the selected action. Existing controller calls,
  stale-round protection, idempotency and duplicate-write locks remain.
- Attendance review uses a compact worker/job/MYT summary, secondary original
  attendance/GPS/cutoff/ID details, decision-specific reason hints and worker-
  visible audit guidance. Review is disabled until valid. Confirmation uses
  Confirm absence/Confirm correction; success says Attendance resolved and shows
  outcome, reason, timestamp and Done without repeating the technical form.
- Confirmed-absent/unresolved missed cards retain View Full Record instead of an
  empty-evidence action. GPS actions are omitted when the available attendance
  projection contains no device record. Recorded GPS remains accessible. The
  full-record route retains access to any existing evidence even when the card
  uses a general full-record label.
- Resolution reason/date and original preservation remain visible in read-only
  records. Snapshot and stored-state diagnostics are secondary. Natural absence
  wording makes clear that neither work nor payment is approved.
- Engagement Open is separate from Eligible for closure. Eligibility comes only
  from the existing server result; eligible worker details include real counts
  from the loaded shift group. Ineligible records show the actual blocking reason
  and informational requirements action. No automatic closure was introduced.
- Safe filename presentation is shared with private previews. Images use a
  contained viewport and existing authorized Open image/Open PDF/Close actions.
  Signed access still lasts 90 seconds. Reviewer/submission UUIDs are secondary
  audit details when an authorized display name is unavailable.

## Limitations and deliberately unchanged behavior

- Production review has no Flag work RPC/action. Flag Work (demo) exists in
  `lib/features/attendance/attendance_pages.dart`, a separate demo module. No new
  production flagging policy or backend call was invented, and the demo was not
  modified. Consequently no new production Confirm flag action was added.
- The upload/submission contract does not persist original local filenames.
  Meaningful safe names already present in metadata are displayed; generated UUID
  names use Evidence PDF/Image fallbacks. Historical originals cannot be recovered
  by cosmetic Flutter changes. Object keys, MIME types, IDs and records remain.
- No new name lookup was added. Existing authorized names are reused; unavailable
  names use Assigned worker and audit identities remain accessible secondarily.
- Cancelled counts describe loaded cancelled records. They do not independently
  certify cancellation audits; the server still checks audited cancellation and
  minimum verified-work requirements before closure.
- Snapshot freshness and server authority are unchanged. Refresh remains required
  to obtain updated lifecycle/eligibility data.

## Exact files changed in this pass

Production files (all under `lib/features/work_attendance/`):

1. `company_workers_page.dart`
2. `engagement_closure_controls.dart`
3. `employer_work_evidence_summary.dart`
4. `work_attendance_lifecycle.dart`
5. `work_attendance_pages.dart`
6. `work_attendance_resolution_dialog.dart`
7. `work_evidence_draft_page.dart`
8. `work_evidence_pages.dart`
9. `work_evidence_preview.dart`
10. `work_evidence_workflow_panel.dart`
11. `work_shift_ui.dart`
12. `work_verification_pages.dart`

Tests:

- `test/engagement_closure_controls_test.dart`
- `test/work_attendance_lifecycle_test.dart`
- `test/work_attendance_lifecycle_pages_test.dart`
- `test/work_attendance_resolution_dialog_test.dart`
- `test/work_evidence_draft_page_test.dart`
- `test/work_evidence_workflow_test.dart`
- `test/work_verification_grouping_test.dart`

Documentation: `README.md` and this report. Earlier approved local changes also
exist in several of these files; a diff against HEAD includes those earlier edits.
Ignored `tmp/polish_*.mjs` and `tmp/consolidated_*` are local editing/validation
artifacts, not proposed commit content.

## Executed validation

The final focused run passed **185 tests** across these files:

```powershell
flutter test --no-pub test/work_evidence_workflow_test.dart test/work_evidence_draft_page_test.dart test/work_attendance_resolution_dialog_test.dart test/work_attendance_resolution_test.dart test/engagement_closure_controls_test.dart test/work_attendance_pages_test.dart test/work_attendance_lifecycle_test.dart test/work_attendance_lifecycle_pages_test.dart test/work_evidence_pages_test.dart test/work_verification_grouping_test.dart test/work_evidence_preview_test.dart test/work_evidence_preview_source_test.dart test/company_workers_page_test.dart test/work_attendance_routes_test.dart --reporter expanded
flutter analyze --no-pub
flutter build web --release --no-pub
flutter build web --release --no-pub --no-tree-shake-icons
```

`flutter analyze` reported **No issues found**; no remaining pre-existing or new
analyzer findings were reported. Focused `git diff --check` passed, with Git's
existing LF/CRLF conversion notices. The normal release build was blocked by
Windows Application Control when Flutter launched `font-subset.exe` for Cupertino
icons. Windows security settings were not changed. The supported alternate build
disables icon subsetting and bundles full fonts. The final-source alternate build
**succeeded: Built build/web (exit 0)** in 59.9 seconds, with only the informational
successful Wasm dry-run suggestion. Full icon fonts make this artifact larger
than an icon-subset build. The standard icon-subsetting build remains blocked by
the machine policy; it was not claimed to pass. The final amber resubmission styling was followed by **25/25
workflow tests passing**. The final correction-field feedback/closure cleanup was
followed by **11/11 dialog/closure tests passing** and another clean full analysis.
No Android build/device acceptance was performed.

Coverage includes enabled/disabled draft actions, file limits and dirty draft
protection; one-dialog review/Edit/confirmation at narrow and desktop widths;
retained reasons and rounds; lost responses, stale rounds and account changes;
resolution validity/version checks, action-specific confirmation and success;
neutral absence without empty GPS/evidence actions; preserved recorded GPS;
private preview authorization, expiry and retry; evidence history; History-aware
route exits; and distinct open/eligible closure presentation.

### Correct Attendance, cutoff and closure coverage limits

Existing executed Dart tests cover:

- MYT AM/PM correction controls, chronological payloads and server eligibility;
  invalid inputs/versions/assignment scopes fail closed.
- Effective corrected attendance, preserved originals, historical checkout after
  the ordinary cutoff, no automatic verification/payment and retained evidence
  eligibility.
- Same-request recovery after a lost resolution response, competing audit
  rejection, duplicate taps and account-change handling.
- Exactly scheduled-end +24 hours retains ordinary checkout; one microsecond
  after it removes that UI action using the server snapshot.
- Closure UI accepts the authoritative eligibility response, displays the server
  blocking reason, and prevents stale-context UI actions.

These use fake sources/controllers or presentation models. They do **not** prove
PostgreSQL locking, real cross-company authorization, concurrent database writes,
actual cutoff enforcement by the deployed RPC, corrected attendance through real
Storage/evidence/verification, or all-absent rejection in a live transaction.
Correct Attendance and late-checkout/cutoff manual QA remain outstanding, as the
owner specified. The earlier owner-reported 34/34 deployment catalog checks are
not a substitute for those functional checks. No new database test writes or SQL
were run in this UI pass.

## Targeted remaining manual QA

1. Read-only inspect the existing three-shift QA engagement: two verified, one
   neutral confirmed absence, zero unresolved issues, Open and eligible for
   closure. Check reason/date and preserved originals. Do not request closure.
2. Check amber more-evidence feedback/resubmission controls and pending-review
   copy on both roles. Inspect resubmission title, feedback, round, untouched form,
   required labels, selected files and bottom actions at desktop and narrow widths.
3. On separately approved QA data, inspect employer review/Edit/confirmation:
   one visible dialog, retained reason/round, correct final action and no duplicate
   submission while busy. Verify previous rounds/history remain accessible.
4. Inspect private image/PDF preview spacing, friendly names, contained images,
   Open/Close and expiry/retry. Do not rerun the entire accepted evidence workflow
   merely for cosmetic acceptance.
5. Correct Attendance remains a functional gap: use a separately approved test
   shift, not the accepted three records. Check actual corrected times/bounds,
   disabled invalid review, confirmation, resolved success, original GPS and
   timestamps, then real evidence submission and employer verification.
6. Late checkout/cutoff remains a functional gap: with approved test records,
   exercise before/exactly/after end+24h and refresh. Verify actual RPC behavior
   and historical employer recovery without modifying accepted QA attendance.
7. Actual database concurrency and all-absent successful-closure rejection remain
   unverified here. Any follow-up writes require a controlled approved QA plan.

## Git status and proposed staging scope — nothing executed

The index is empty. The existing stash remains:
`stash@{0}: On main: Preserve unrelated local changes before Chat rebase`.
The working tree contains the earlier Module 4 implementation plus unrelated
modified phase/workspace tests, shared route files, local launch configuration,
reputation fixture and other documents/artifacts. They were not reset or staged.

Proposed UI-polish scope: the twelve production files, seven tests and two docs
listed above. Three of the changed tests are ignored by the existing `*test*`
rule and require explicit force-add when staging is approved:

```powershell
# Proposed only — do not execute before review/approval.
git add -f -- test/work_attendance_lifecycle_test.dart test/work_attendance_lifecycle_pages_test.dart test/work_attendance_resolution_dialog_test.dart
```

The other four changed tests are already tracked. The shared presentation,
lifecycle, resolution-dialog and employer-summary sources are presently untracked
and must be included explicitly; ignore rules must not be broadened.

After reviewing the prerequisites below, the proposed UI additions are:

```powershell
# Proposal only; no staging command has been executed.
git add -- README.md docs/module4_final_consolidated_ui_report.md
git add -- lib/features/work_attendance/company_workers_page.dart lib/features/work_attendance/engagement_closure_controls.dart lib/features/work_attendance/employer_work_evidence_summary.dart lib/features/work_attendance/work_attendance_lifecycle.dart lib/features/work_attendance/work_attendance_pages.dart lib/features/work_attendance/work_attendance_resolution_dialog.dart
git add -- lib/features/work_attendance/work_evidence_draft_page.dart lib/features/work_attendance/work_evidence_pages.dart lib/features/work_attendance/work_evidence_preview.dart lib/features/work_attendance/work_evidence_workflow_panel.dart lib/features/work_attendance/work_shift_ui.dart lib/features/work_attendance/work_verification_pages.dart
git add -- test/engagement_closure_controls_test.dart test/work_evidence_draft_page_test.dart test/work_evidence_workflow_test.dart test/work_verification_grouping_test.dart
# Plus the three exact force-add tests above.
```

This UI list is **not a standalone commit against the current HEAD**: earlier
Batch 1/2 model, repository, resolution controller, creation, GPS and route changes
remain uncommitted dependencies. For a final combined Module 4 commit, review the
explicit existing [Batch 2 staging manifest](module4_batch2_deployment_handoff.md#targeted-staging-preparation--commands-not-executed),
then add this pass's source/tests/report. It includes the already deployed Batch 2
SQL artifacts and four force-added lifecycle/resolution tests. Staging an existing
SQL artifact is not permission to run it again. Do not reapply Batch 1/2.

Review `lib/main.dart` and `lib/shared/navigation/workspace_destinations.dart` by
hunk; stage only the Module 4 route/navigation changes. Do not blindly stage their
entire mixed diffs. Exclude `.vscode/launch.json`, credentials, `build/`, `tmp/`,
temporary QA/inspection output, unrelated diagnostics/plans, phase/workspace
tests and the reputation fixture. No `git add .` or broad force-add is proposed.

Suggested message for the eventual combined commit:
`Complete attendance resolution and polish work verification workflows`

## Deployment and security

No new migration, RPC, Storage, RLS, Edge Function, authorization, payment,
reputation or closure-policy change is required by this polish. No live data,
engagement closure, deployment, commit or push was performed. Local Chrome and
Android acceptance of the new visual details remains the final UI gate.

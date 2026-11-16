# Application details runtime fix

Local fix, 16 November 2026. No backend or QA-data writes.

Subsequent owner-approved cleanup removed the UUID-only Application details
section entirely. Its historical PageStorage diagnosis remains below; the current
group regression checks that the section stays absent while group controls and
internal identities remain. See [current QA](module4_final_qa_2026-11-16.md).

## Reproduction and exact cause

A new widget regression reproduced the reported exception before the production
change, using two normal application groups, opening Application details and
removing/recreating the expansion via its parent group toggle:

```text
type 'bool' is not a subtype of type 'double?' in type cast
#0 ScrollPosition.restoreScrollOffset (package:flutter/src/widgets/scroll_position.dart:538:90)
#1 new ScrollPosition (package:flutter/src/widgets/scroll_position.dart:203:7)
#2 new ScrollPositionWithSingleContext
#3 ScrollController.createScrollPosition (package:flutter/src/widgets/scroll_controller.dart:307:12)
#4 ScrollableState._updatePosition (package:flutter/src/widgets/scrollable.dart:634:44)
#5 ScrollableState.didChangeDependencies (package:flutter/src/widgets/scrollable.dart:674:5)
```

This was captured from the Flutter widget runtime, not a new Chrome manual run.
The temporary diagnostic error handler forwarded every error to Flutter's
original handler and was removed from the final regression test. No exception
suppression remains.

`ExpansionTile`/`Expansible` stores a boolean under its PageStorage identity:
`application-reference-<applicationId>`. Its child `SelectableText` owns an internal
scrollable. With no separate PageStorage key, that scrollable inherited the same
identity and `ScrollPosition.restoreScrollOffset` read the saved expansion boolean
using `readState(...) as double?`. This is a storage-identity collision, not an
attendance-model, corrected-time, height or other layout value mismatch. It affects
ordinary groups as well as groups containing corrected attendance.

The fix gives the selectable text its own stable, per-application PageStorage key:
`application-reference-text-<applicationId>`. The tile retains its existing key and
boolean persistence. Application ID content, selection/copy behavior and the
expansion remain intact. Neither state persistence nor the section was removed.

## Focused polish

- Original attendance & correction rules stretches and left-aligns its children.
- Corrected check-in/out controls have 12-pixel spacing.
- The actual-attendance checkbox is leading, top-aligned and vertically spaced.
- Evidence verification confirmation uses a left-aligned summary column.
- Review instructions now refer to the latest submitted evidence files, including
  images, rather than PDF/files. Required asterisks and semantic colors remain.

## Exact changed files

- `lib/features/work_attendance/work_verification_pages.dart`
- `lib/features/work_attendance/work_attendance_resolution_dialog.dart`
- `lib/features/work_attendance/work_evidence_workflow_panel.dart`
- `test/work_verification_grouping_test.dart`
- `test/work_attendance_resolution_dialog_test.dart`
- `test/work_evidence_workflow_test.dart`
- `docs/module4_application_details_runtime_fix.md`

## Validation

```powershell
flutter test --no-pub test/work_verification_grouping_test.dart test/work_attendance_resolution_dialog_test.dart test/work_evidence_workflow_test.dart --reporter expanded
flutter analyze --no-pub
flutter build web --release --no-pub --no-tree-shake-icons
```

- Before fix: the new persisted-expansion regression failed with the exact
  bool-to-double runtime exception and stack above.
- After fix: **46/46 focused tests passed**, including the original reproducer,
  both application groups, persisted expanded/collapsed states, separate numeric
  text-scroll state, retained content and existing narrow/desktop dialog workflows.
- The regression explicitly checks that writing `0.0` for text scroll state leaves
  the expansion's saved `true` unchanged. No `tester.takeException()` is ignored;
  each retrieved exception is asserted null.
- Dialog tests check left alignment and checkbox placement, alongside their
  existing correction/confirmation safety checks.
- Full Flutter analysis: **No issues found**.
- Focused `git diff --check`: passed; Git emitted existing LF/CRLF notices.
- Release web build uses the previously successful full-icon-font option because
  Windows Application Control blocked the font-subsetting executable in the prior
  batch. **Succeeded: Built build/web, exit 0, 48.9 seconds**, with the
  informational successful Wasm dry-run suggestion. Windows security settings
  were not changed.

No backend contract, model, RPC, Storage, migration, authorization, cutoff,
verification or payment policy changed. No migrations, live QA writes, staging,
commit, push or engagement closure were performed. The index remains empty and
the existing stash remains intact.

## Manual QA status

The owner reports Confirm Absence and Correct Attendance passed, including the
8 November Event Crew Assistant shift corrected to **5:32 PM–5:58 PM MYT (26
minutes)**, worker audit visibility, overdue advisory evidence submission and
employer verification of round 1. Those results are preserved; they were not
repeated or independently claimed as live tests by this fix. Original attendance
and GPS remain untouched, and verification does not approve payment.

Remaining targeted manual checks:

1. In Chrome, open/collapse Application details in two groups, then hide/show each
   parent group and confirm restored state and selectable ID content without errors.
2. Inspect the requested dialog alignment/spacing without resubmitting an already
   completed resolution or changing the accepted QA records.
3. Late-checkout and the inclusive 24-hour cutoff manual QA remain outstanding
   before the final commit. This UI fix does not claim they passed.

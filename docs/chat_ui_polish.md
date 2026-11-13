# Final Chat UI polish — 14 November 2026

**Final targeted visual pass:** compact separated conversation rows now show real
name initials, bold names/right-aligned muted times, teal job labels and a separate
ellipsized latest-message line. Header shows the real participant, job and status
with a narrow-screen conversation-list action. Empty desktop detail has the
specified Select a conversation illustration/text. Sent bubbles use accessible
dark teal/white text; received bubbles are white/bordered on a subtle grey area.
Actual local message dates are grouped once per loaded day, and bubbles show the
actual time. Existing attachment/download, unread/read, retry and navigation logic
is unchanged. Screenshot assets were not present with the request, so this follows
the written visual specification rather than a verified screenshot comparison.

Final-pass checks: 62 focused Chat/attachment/unread/transport tests and 11 cleanup/
artifact-preservation checks PASS. Release Web build and Wasm dry-run compilation
PASS; analysis has only the same five pre-existing informational findings outside
Chat. New checks cover real initials/rows and empty state, long 320px headers for
both roles, and day separators remaining unique when a loaded day is extended.
This is local validation, not a new hosted or native-device acceptance claim.
This targeted pass changed only chat_page.dart, chat_attachment_card.dart,
test/chat_ui_test.dart, README.md, chat_basic_activation.md,
chat_basic_cleanup_http_review.md, chat_basic_attachments.md and this document.

**Option B:** automatic hourly cleanup is deferred for the university demo, with
no registered Cron job according to CH's checks. Preserve the blocked pg_net and
http reviews/prechecks. The existing authorized Edge cleanup endpoint is available
for manual maintenance; abandoned uploads can accumulate until cleanup is run.
Existing secrets/extensions remain unchanged; automatic cleanup is a production
limitation to resolve separately. Next: visual approval, mobile acceptance, Git review.

CH reports the previously deployed Web image send/recipient enlarged preview,
PDF reply/recipient download and normal text exchange PASS. The HTTP 204 Edge fix
is deployed and working according to CH. This evidence precedes the UI polish;
the new one-click gesture, automatic reads and unread dots still need brief live
UI confirmation. Codex has made no live requests, uploads, SQL or Git operations.

## Local changes

- Compact right-aligned teal/light-green sent bubbles and left neutral received
  bubbles, no repeated sender names/manual read buttons, smaller timestamps and
  responsive widths. Desktop split view omits the redundant Conversations link;
  narrow view retains it. Detail routes pass their actual path into the workspace
  so the sidebar Messages destination remains a usable exit. Existing router exit
  guards and native contextual Back remain intact.
- Images retain natural aspect ratio within rounded thumbnail bounds, without
  filename cards. Existing zoomable dialog and fresh authorized preview URL remain.
  A small download icon is available alongside file size; bubble timestamp is
  shared with normal messages. Documents retain format icons/name/size/download.
- Download is one click. Conditional SDK-only browser interop opens about:blank
  synchronously, removes its opener, obtains the signed URL through the current
  account gateway, then navigates the tab. Failure/account change closes the tab.
  No async popup opening, arbitrary URL input, service credential or document viewer
  is added. Native uses existing url_launcher. Storage remains private; links keep
  the existing 60-second validity. Browser popup policy must allow the immediate
  user-initiated tab; failures are shown with retry rather than public access.
- Navigation Messages icons show a dot for any incoming unread count from the
  existing typed list RPC, including conversations beyond page one. The controller
  stops at the first unread result. Realtime refreshes new-message changes; local
  successful read invalidations refresh immediately. Existing SQL does not publish
  chat_read_states: another tab's reads repair on resume/30-second refresh. No
  schema/publication change is required. No background read-cursor writes occur.
- Auto-read measures laid-out bubbles after a frame against the history viewport,
  screen and keyboard bounds. It requires active route, foreground lifecycle and
  visible browser document, skips own messages and offscreen cached rows, and
  deduplicates monotonic targets. Incoming images wait for their first decoded
  thumbnail frame. Large messages can be acknowledged when their ending is visible.
  No read is issued merely by repository fetch/pagination or navigation badge work.
- Attachment warning moved to tappable help tooltip. Selection/removal/captions,
  attachment-only sending, cancellation/progress, original-identity retry and
  unsaved-input guards are preserved. No dependencies, backend or Edge edits.

## Local validation

229 focused Chat, attachment, unread and responsive navigation tests passed.
Release Web build and its Wasm dry-run compilation passed.
Flutter analysis reports only the same five pre-existing informational findings
outside Chat. Eight artifact-preservation checks passed, confirming every reviewed
Edge/SQL artifact and both original SQL guards unchanged. Browser popup/download
behavior and real unread/read transitions are not claimed live-accepted from these
offline results. No new package, database or Edge deployment is needed.

## Files changed

- `lib/features/chat/chat_page.dart`
- `lib/features/chat/chat_attachment_card.dart`
- `lib/features/chat/chat_ui_controller.dart`
- `lib/features/chat/chat_download.dart`
- `lib/features/chat/chat_download_native.dart`
- `lib/features/chat/chat_download_web.dart`
- `lib/features/chat/chat_unread.dart`
- `lib/features/chat/chat_read_events.dart`
- `lib/shared/widgets/app_workspace.dart`
- `test/chat_ui_test.dart`
- `test/chat_unread_test.dart`
- `test/chat_attachments_test.dart`
- `test/chat_attachment_draft_test.dart`
- `test/fixtures/chat_ui.dart`
- `README.md`
- `docs/chat_basic_attachments.md`
- `docs/chat_basic_validation_failure_20261113.md`
- `docs/chat_ui_polish.md`

## Brief manual confirmation

Launch `flutter run -d chrome`. In the existing accounts/conversation, check bubble
alignment/image preview, one-click PDF download, unread dot on another screen,
and clearing after viewing incoming messages. Keep the recipient tab hidden for
one approved message and confirm it stays unread until visible. These are manual
instructions, not extra live sends performed by Codex. Respect existing approved
test data/message scope; obtain approval for additional QA writes if required.

Automatic cleanup is deferred under Option B; finish native device acceptance
and then a focused Git review/push. Existing outstanding foreign/Admin isolation, restart/
cross-tab/concurrency, unencrypted pending storage, untested Office/iOS workflows
and the historical unconfirmed full text-Chat rollback fingerprint comparison are
not promoted to PASS. Basic content validation remains explicitly not antivirus.

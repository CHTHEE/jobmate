# Chat Phase 5 evidence review and Phase 6 UI

Phase 6B follow-up: [attachment preparation and UI polish](chat_phase6b_attachments.md).
Latest: [local attachment backend/Flutter completion and release gates](chat_phase6b_backend_completion.md).
The production text UI now offers explicit read marking only on incoming
messages; a local attachment preview is debug-only and cannot upload/send files.
All Phase 5 live evidence below remains historical and unchanged.

13 November 2026. CH performed the authenticated live trial; the agent inspected
the complete original JSON exports locally. No agent live business writes,
database calls, schema changes or new fixtures were performed.

## Phase 5 evidence

| Original local file | Records | SHA-256 |
| --- | ---: | --- |
| `tmp/chat_readonly_acceptance/seeker_messaging.json` | 24 | `62942A4AD595E9D2C225518FDE30DB410AC9F83D80DF4F1D3596FF2B7836D1A8` |
| `tmp/chat_readonly_acceptance/employer_messaging.json` | 17 | `9BDFB444C589DC36E30A84ECAA00A34382F9FFA744AEA1B425EEF837C54D786C` |

Both JSON documents parse completely; actors/roles match the approved active
seeker/employer, `trial_stopped=false`, and all recorded operations completed
without error outcomes. Application: `fb352472-8a41-45cf-a9a6-5e70e25e66e8`.
Both creation/reuse records bind it to conversation
`e08aee68-59d5-40eb-aaf8-bc5676d19f7f`.

| Check | Result | Actual evidence / limits |
| --- | --- | --- |
| Same approved conversation created/reused | PASS | Both records return the same UUID and approved application binding |
| Two-way send and strict typed send/history parsing | PASS | Seeker message `0624e006-95ab-447e-aaa1-56019af4fbb3`, sequence 1; employer message `6e7d8558-bba7-4063-9aa6-4a8242ea34c0`, sequence 2; both histories contain those IDs/senders, descending `[2,1]` |
| Exact agreed text displayed | PASS (CH observation) | Export omits bodies; typed histories report 35 and 45 code points. Scoped send parsing checked the response against the fixed request body; CH confirms matching displayed text |
| Identical UUID/body replay and no duplicate message | PASS | Seeker request `e15622be-a154-5a9f-9c0f-92f2c105a4a1`, employer request `15f36f51-621b-5138-8552-0f84bf392281`; replay receipts retain original ID/sequence and `same_receipt_as_previous=true`; subsequent histories remain two rows |
| History first-page limit and descending order | PASS | Both limit-10 pages contain `[2,1]`; seeker limit-1 page contains `[2]` with next cursor available |
| Older-page cursor traversal | UNVERIFIED | No recorded request with `before_sequence=2`; UI implementation must be covered offline and rechecked manually |
| Empty history boundary | PASS (seeker) | `before_sequence=1`, limit 1 returns `[]`, no next cursor; employer boundary unrecorded |
| Own read-cursor updates | PASS | Seeker marks message sequence 2 and receives cursor 2; employer marks incoming sequence 1 and receives cursor 1 |
| Cursor non-regression / refreshed unread counts | UNVERIFIED | No later older-message mark or post-mark conversation-count snapshot |
| Actual Realtime INSERT and UPDATE delivery | PASS | Both actors record both message INSERT IDs/sequences and conversation UPDATE events; IDs match later typed history, including each recipient's incoming message |
| Realtime reconnect/gap recovery and foreign feed isolation | UNVERIFIED | No disconnect/reconnect or unauthorized listener observations |
| Notification delivery to the two observed accounts | PASS (quiet-window observation) | Seeker 12→13, employer 15→16; each gains one `chat_message` notification at the corresponding incoming send time; exports are below limit 50 |
| Notification dedup after employer reply replay | PASS (observed seeker inbox) | Seeker retains notification `642cc068-8bc8-44d0-885e-9f828308d1b7` after the employer replay |
| Notification dedup after seeker replay / all eligible employer recipients | UNVERIFIED | Employer's last snapshot at 04:58:12.840Z predates seeker replay at 04:58:15.911Z; other eligible employer recipients were not observed |
| Generic notification body/title/privacy contract | UNVERIFIED by export | JSON intentionally omits title/body and has no per-message link; delivery correlation is not an independent transactional proof |
| Multi-conversation keyset ordering/timestamp ties | UNVERIFIED | Only one real conversation used |

No FAIL outcome or blocking correctness/security issue was found in the supplied
essential fixture evidence. This supports proceeding with the authorized UI
implementation, not declaring all security/concurrency/release acceptance complete.
Hired eligibility was accepted by the deployed RPC at the observed trial time;
no independent company restriction-row export or later-state guarantee is inferred.

## Phase 6 behavior

The existing `/messages[/<conversationId>]` and
`/employer-messages[/<conversationId>]` routes now use the real typed repository
and current authenticated client. Sidebar labels are **Messages**. Existing role
gates and backend checks remain. There is no production import of QA scope/message
constants, no new auth/config/dependency, no direct Chat table writes and no
notification emission from Flutter.

- `ChatUiController` holds account-scoped conversations, drafts, confirmed history,
  pending requests, cursors and errors. Account changes clear memory, invalidate
  in-flight work, stop listeners and send the old role route back to Home.
- Content constraints choose two panes when at least 840 pixels remain after the
  workspace/sidebar; narrow screens show list or routed thread. Web keeps the
  sidebar/drawer without an inferred back arrow; Android detail has contextual
  Back, with a conversation-list fallback for direct URLs.
- My Applications, its detail page and Employer Applications have explicit
  **Message Employer / Message Applicant** actions. Only that deliberate action
  invokes get-or-create. Listing/opening Chat never creates a conversation.
  Terminal/history-only outcomes remain backend-authoritative.
- Composer validates backend-compatible Unicode code-point rules. Ctrl+Enter or
  Send is deliberate; Enter adds a line. No attachments, edit/delete, typing,
  presence, calls, push or peer read receipts are introduced.
- Pending UUID/body is saved before dispatch. Unconfirmed sends preserve their
  exact pair and lock editing; explicit **Retry saved message** reconciles it.
  Restored sends never automatically replay. Failed local recovery blocks sends.
  Production pages share one serialized pending store per project origin, avoiding
  in-process page-to-page lost updates; it caches no account rows. This is not
  cross-tab/device synchronization or encryption.
  A confirmed reply with retained retry storage is shown as confirmed with a
  cleanup/reconciliation notice, not as a second logical send.
- History and conversation pages use the deployed cursors and deduplicate by ID.
  Realtime INSERT/UPDATE notifications are invalidations only: selected messages
  and authorized conversations are reconciled through the RPCs. Subscribe/resume
  refresh repairs gaps; a gap exceeding a page restarts from the latest page.
  Hidden routes/app lifecycle stop listeners; resuming refetches data.
- **Mark read** is an explicit button on a displayed, typed message. It updates
  the current user's cursor and refreshes backend unread counts. Merely opening
  a thread, receiving an event or browsing history performs no read-state write.
- Route exit prompts protect unsent text/in-flight sends. Saved unknown-outcome
  sends remain owner-scoped on disk on exit. Account logout intentionally clears
  memory; ordinary unsent drafts are memory-only and do not survive browser
  refresh/tab closure. This limitation is not described as durable draft storage.

## Local validation and changed files

- **153 focused regression tests passed** across Chat models/source/repository,
  the scoped tester, new production controller/widgets, applications and affected
  navigation. The new UI's 18 cases include shared project-store identity, retry reconstruction, account-reset
  isolation, denial/read-only recovery, keyset/sequence paging, reconciliation
  gaps, draft exit and explicit lazy creation. No live Supabase calls were used.
- **Four Chat render tests passed** at 390×1000, 1440×1000, 320×720/text 1.6 and
  568×320/text 1.3; output is under `build/phase52-review/`. Wide/narrow renders
  were inspected locally. These VM renders exercise native platform behavior;
  content width, text scale and keyboard constraints are also unit-tested.
- `flutter analyze --no-pub`: five existing info-level findings in company
  management, sign-up and engagement closure; no new findings/errors/warnings.
- `flutter build web --release --no-pub` passed, including its Wasm dry run.
  The final JavaScript bundle excludes the debug route/title, QA application UUID
  and both fixed QA message strings. Release compilation is not a claim of live
  browser or standalone Wasm runtime acceptance.
- A separate `flutter test --platform chrome --no-pub test/chat_ui_test.dart`
  attempt stalled at loading and was stopped. It is **UNVERIFIED**, not a passing
  Web runtime test. Final real-browser and Android review remains required.
- Legacy demo Chat widget expectations were replaced with real Chat fixtures.
  The existing Phase 3 menu assertion was stale for Attendance Review (demo);
  it now targets the already-existing Work Verification destination. No work
  attendance/verification application implementation was changed.

Changed implementation files:

| Area | Files |
| --- | --- |
| Production Chat | `lib/features/chat/chat_page.dart`, `chat_ui_controller.dart`, `chat_realtime.dart`, `chat_dependencies.dart`, `chat_routes.dart`, `chat_application_button.dart` |
| Existing routes/navigation | `lib/main.dart`, `lib/shared/navigation/workspace_destinations.dart` |
| Explicit application entry points | `lib/features/applications/my_applications_page.dart`, `my_application_details_page.dart`, `employer_applicants_page.dart` |
| Tests | `test/chat_ui_test.dart`, `test/fixtures/chat_ui.dart`, `test/phase3_test.dart`, `test/phase52_visual_test.dart` |
| Documentation | `README.md`, this file, `docs/chat_phase3_runtime_acceptance.md`, `docs/chat_phase2_backend_implementation.md`, `docs/chat_phase2_permanent_deployment_review.md` |

Existing Chat models/source/repository/pending storage, notification behavior,
dependencies, `.env`, both SQL guards and original evidence files are unchanged.
No commit or push was made.

## Manual review without new writes (steps)

Run `flutter run -d chrome --web-hostname=localhost --web-port=7357 --no-pub`.
Sign in separately as each participant and open **Messages**. View the existing
QA thread and its two messages, refresh/reopen the direct URL, check responsive
list/thread navigation and browse history. Type an unsent draft and verify the
leave confirmation (cancel to preserve it, or leave to discard it).

The prior scoped approval is exhausted for new logical test messages: it covers
only the existing agreed pair. Do not press production Send for another message,
start other application conversations or create new fixtures without separate
approval. No agent will execute these live writes. The debug tester remains
debug-only and fixed to its already-approved idempotent pair.

Final UI/device and security acceptance remains outstanding: foreign/admin
isolation, denied/read-only lifecycle cases using existing data, cursor
non-regression/unread refresh, complete notification dedup/recipients, reconnect,
multi-conversation ordering, concurrency, unencrypted pending storage,
native/browser restart and general cross-tab behavior. The historical complete
rollback fingerprint comparison remains unconfirmed and is not retroactively
proved by runtime success. Both SQL guards and deployed schema remain unchanged.

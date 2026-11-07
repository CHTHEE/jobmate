# Newly scheduled shift notifications: Phase 5 audit

## Outcome

**Audit only; notification delivery is not implemented.** The checked-in shift
creation functions do not insert notifications, and no verified shift-insert
notification trigger was found. A client call after creation cannot provide
atomic, durable delivery. No Flutter, notification UI, SQL, trigger, RPC, RLS or
migration changes were made. No SQL or commands accessed the shared database.

This establishes what local sources contain, not what all deployed triggers do.
Before implementing, obtain the actual notification functions/schema, all triggers
on assignments, and authorization helper definitions for offline review with the
notification owner. Existing deployed emissions must be identified to avoid a
second emitter. Phase 4 edit/cancel and Phase 3 arrangement termination remain
deferred; this design covers only newly inserted shifts.

## Existing architecture and verified local contracts

| Area | Evidence and behavior | Limit |
| --- | --- | --- |
| Storage | `20261031000100_admin_dashboard_and_review.sql` defines `public.notifications`: notification_id, user_id, notification_type, title, message, created_at, nullable read_at | No assignment/event identity, uniqueness key or deep-link fields in this definition |
| Permissions | That table has RLS enabled and direct PUBLIC/anon/authenticated grants revoked; list/read functions use active-account and owner checks | No general authenticated notification-write contract; do not add direct client INSERT grants |
| List | Flutter calls `list_my_notifications(p_limit: 50, p_offset: 0)`; six returned fields map to `JobMateNotification` | First 50 only; no assignment target, event payload or complete unread count |
| Read | Flutter calls `mark_notification_read(p_notification_id)` and requires boolean; either result reloads the list, false reports unavailable | Checked-in SQL instead defines `mark_my_notification_read(uuid)` returning void. The currently consumed mark-read definition is absent; do not rename/fallback without owner review |
| UI | `notifications_page.dart`: full page and embedded Web panel, server titles/messages, created time in device timezone, unread indicators, tap-to-mark-read | No event-specific navigation. A read notification is not tappable in the current implementation |
| Refresh/session | Repository discards stale account results; page reloads on entry, resume and return through navigation | No verified push/Realtime or immediate cross-session delivery guarantee |
| Other emitters | Company review, company-logo review and account-status SQL insert notifications inside their respective transactions | These are domain-specific writes, not a reusable worker scheduling emitter |
| Shift creation | `create_work_assignment` derives applicant_id/job/company from the application and requires Hired/company management | Inserts an assignment and returns its ID; no notification insert in its body |
| Creation identity | Reserve/create/lookup functions in `20261106000100_work_assignment_creation_idempotency.sql` protect payload/request identity; completed create returns its existing assignment ID | Reservation, replay and lookup are not new shifts and must not emit notifications |

`notification_type` is text in the inspected schema; no closed event enum or
verified scheduling event type is defined. Local SQL contains `company_review`,
`company_logo_review` and account action types; the notification test fixture uses
`application_submitted`. That fixture is not proof of its deployed emitter. No
checked-in source establishes a `shift_scheduled` type or a shift notification
already being delivered. A live trigger not represented here remains possible.

The README documents the consumed list/boolean mark-read contract. Mock HTTP tests
in `test/notifications_repository_test.dart` assert those exact calls; they cannot
reconcile the missing SQL definition or establish deployed authorization.

Shift creation is shared by first and additional shifts: the dialog calls
`WorkAssignmentCreationRepository`, which reserves a server request then calls
`create_work_assignment_request`. The latter calls `create_work_assignment`,
links the result and commits in one transaction. The legacy create function is
also granted authenticated execution in the inspected sources. Its assignment
worker_id is copied from the application's applicant_id; Flutter does not send a
worker recipient ID in the creation payload.

The client disables automatic transport retry for reservation/create, retains
uncertain request locks and reconciles through lookup. Local creation tests cover
duplicates, conflicts and uncertain results, but contain no durable notification
guarantee. Neither the creation ledger nor a success snackbar proves delivery.

## Proposed backend event — design only

Proposed event name: `shift_scheduled` (not an existing verified API/type).
Use one reviewed database-side emission point, preferably an **AFTER INSERT on
work_assignments** trigger, so both first/additional shifts and the existing
legacy creation path are covered. Do not emit on reservation, UPDATE, lookup,
response replay or Flutter refresh. Do not also emit from the outer creation RPC.

The trigger must insert one protected event identity and one worker inbox row in
the **same transaction** as the assignment and creation-request result. If event
or notification persistence fails, the entire creation transaction must roll back;
do not swallow errors or report a scheduled shift with successful notification
delivery. This proposal guarantees one durable in-app row, not that a worker has
seen it. External push/email is outside this phase.

Proposed event uniqueness is `(event_kind, assignment_id, recipient_user_id)` with
a database unique constraint. Application ID is too broad (multiple legitimate
shifts); request ID alone is insufficient (legacy and alternative creation paths).
Concurrent/replayed creation returns the same assignment and cannot create a
second event. Resolve an event-key conflict only after validating its immutable
identity and linked notification; never suppress unrelated integrity errors.
Keep deduplication durable across app restarts, reads and notification retention.
Do not reset read_at or rewrite a notification on replay.

An event ledger or equivalent explicit assignment/type identity and uniqueness
on notifications requires a separately reviewed migration. These fields/tables
are proposals, not assumed existing columns. Prefer an append-only protected
event-to-notification link; define retention with the notification owner so inbox
cleanup cannot turn a retry into duplicate delivery. Do not infer uniqueness from
title/message/time matching. Do not backfill old shifts or emit missing historical
events during lookup; any backfill needs a separate approved design.

Recipient and authorization requirements:

- Resolve the recipient from the inserted assignment worker_id and validate it
  against the linked application applicant_id. Resolve job/company from trusted
  stored relationships. Reject inconsistent identity rather than accepting
  arbitrary client-supplied IDs, titles or recipients.
- Preserve fresh Hired eligibility, employer company authorization, original
  request ownership and payload checks, duplicate claims and the cross-company
  overlap exclusion constraint. Review the actual `can_manage_company_jobs`
  definition, which is absent from the checkout. The emitter cannot become a
  general notification-send RPC available to authenticated clients.
- Keep direct inbox/event writes revoked, fixed safe search paths, qualified
  objects and minimal trusted-function/trigger permissions. Preserve recipient-only
  active-account reads and owner-scoped mark-read behavior. An unavailable recipient
  or identity mismatch must have a defined safe transactional failure outcome;
  never silently redirect to the employer or another worker.

## Payload, Malaysia time and navigation integration

The proposed server-owned event payload contains assignment/application/job/company
identities, worker recipient, event version, job title and company-name snapshots,
scheduled start/end UTC instants, and a creation timestamp. Do not include GPS,
resume data, private evidence paths, credentials or signed URLs. Snapshots describe
what was scheduled; future changes must not rewrite historical event identity.

Proposed inbox title: **New shift scheduled**. Message example using fictional
data: **Cafe Crew — Example Company. 10/11/2026 22:30 to 11/11/2026 02:15 MYT
(UTC+08:00).** Format both dates and 24-hour times explicitly from trusted stored
timestamps in Malaysia time, including overnight/date/year rollover; never use
the employer device timezone. If the present six-field projection is retained,
the server can supply this message. The notification's separate created_at label
currently uses device-local time; do not silently change other notification types.

A working existing target is `/work-attendance/<assignmentId>/evidence`. It opens
the assignment's evidence/details page even before any evidence exists, behind
the active Job Seeker gate and fresh owned-assignment lookup. It offers the
existing return path to attendance. `/work-attendance` is the existing general
attendance list; there is no verified dedicated `/work-attendance/<id>` route or
query-driven highlight contract. Do not invent one.

The current notification projection has no target field, and its UI only marks
unread rows read. Owner coordination is required to add an allowlisted semantic
assignment target through a compatible/versioned read projection and consumer.
Generate the route from a validated assignment UUID; do not open arbitrary URLs
from message text. Notification possession is never assignment authorization.
Foreign/missing assignments and switched/inactive accounts must fail safely using
existing route gates, unavailable states and exits. Both read and unread scheduling
notifications should support Open shift; preserve existing read semantics as a
separate concern and avoid marking read twice during navigation.

Treat the shared notification UI as owner-controlled for this work. Documented
integration is required with KZ/the notification owner before changing its model,
tap behavior or the Web panel. No shared navigation change is needed for the
existing target. No per-shift acceptance or rejection is proposed.

## Failure, replay and visibility

Failed validation, permission denial, overlap or rolled-back creation must leave
**zero committed notification/event rows** for that attempted shift. A committed
shift with a lost HTTP response already has its single committed notification;
lookup/replay returns existing identity without sending again. Concurrent first
and later distinct shifts each receive their own event. Different requests that
resolve to the same successful assignment must not duplicate it.

Do not retry a whole creation just because the inbox cannot refresh. Retain the
existing uncertain-outcome protections; missing lookup/inbox results do not prove
rollback. The inbox's 50-row cap, refresh timing, active-account requirement and
read filter can hide an existing row from the current view. Do not claim immediate
visibility or push delivery. A notification failure inside the atomic transaction
must be distinguishable from a committed creation whose response was lost, using
the existing request reconciliation contract.

## Required later implementation and tests

Before any implementation, inspect supplied deployed trigger/function definitions
offline to establish that another scheduler emitter is absent or coordinate one
canonical path. Resolve the mark-read SQL discrepancy with the owner without
replacing the currently consumed API. A later approved migration would introduce
the event uniqueness/link/payload, atomic emitter and compatible target projection,
with least-privilege grants/RLS where necessary; no broad client write policies.
Existing scheduling/overlap and notification read contracts must remain intact.

In an approved isolated database, test first/additional shifts; correct recipient
and trusted title/company/time snapshots; unauthorized/foreign employer attempts;
duplicate request responses; concurrent identical creation, distinct overlapping
creation and legacy-path attempts; restart/replay/lookup; and no rows on failed
or rolled-back creation. Inject notification persistence failure and assert the
assignment/request link/event/inbox all roll back. Verify one inbox row per
committed shift, recipient-only list/read access, unchanged read_at on replay,
retention/dedup behavior and no duplicate legacy trigger emission.

After owner-approved UI integration, use focused widget/mock contract tests for
known/unknown event types, read/unread behavior, newly scheduled empty-evidence
targets, direct URLs, sign-in/account changes, denied targets, repeated taps,
mark-read/refresh failures and responsive Web/Android controls. Test MYT formatting
on devices set to other timezones and across overnight/year boundaries. Existing
notification, creation and evidence-route tests are useful regressions, but do not
currently test shift event persistence or its navigation.

## Phase 5 validation

Documentation references and `git diff --check` were checked. No Dart code changed,
so formatting, analysis and Flutter suites were not rerun. The supplied previous
baseline is 1,235 passes, five known admin failures and four informational lints;
these are not newly executed results. No database, delivery, browser or device
acceptance tests ran. No Dashboard changes are requested by this audit.

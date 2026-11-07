# Application, offer and hired arrangement lifecycle — Phase 3

## Audit scope and evidence

This is a checkout audit, not a live Supabase inspection or deployment report.
No SQL was executed. The existing Flutter contracts are retained unchanged.

The production worker model is `MyApplicationStatus` in
`lib/features/applications/my_applications_repository.dart`. Its eight wire values
are `submitted` (displayed as Applied), `shortlisted`, `interview`, `offered`,
`hired`, `rejected`, `declined` and `withdrawn`. Both worker and employer models,
filters, badges and history use this model. Declined and Withdrawn have separate
labels even though the badge reuses existing color styling. `completed` groups
terminal recruitment outcomes, including Hired; it does **not** mean shifts or
employment are completed.

`ApplicationStage` in `module2_repository.dart` is an older demo model, with no
Declined value. The demo `ApplicationActions` maps decline to Withdrawn and allows
employer hiring. Those are **not** production transitions: `ApplicationsPage`
routes to `MyApplicationsPage` or `EmployerApplicantsPage`, and worker details
use `MyApplicationDetailsPage`. The demo model is left unchanged in this phase.

Production adapters call:

- `submit_job_application`: job ID, optional resume ID and cover note.
- `list_my_job_applications`, `list_application_history(p_application_id)`.
- `list_job_applicants(p_job_id)` after employer company/job access checks.
- `respond_to_job_application(p_application_id, p_action)`, with existing actions
  `accept_offer`, `decline_offer` and `withdraw`.
- `update_job_application_status(p_application_id, p_new_status, p_note)` for the
  six existing employer transitions below.

The definitions of these Module 2 RPCs, the creation/constraints of
`job_applications`, and application notification/history triggers are **absent**
from the checked-in Supabase sources. Their exact database transition guards,
ownership checks, locking, constraint values and side effects cannot be verified
here. Client tests and README descriptions establish the consumed contracts,
not deployed database enforcement. An existing RPC name alone is not evidence
that it accepts a new status. No cancellation status or RPC has been invented.

Notifications remain server-owned: the README describes history/notification
side effects of employer updates; Flutter does not insert them. The notification
adapter only lists notifications and marks them read. Worker response notification
recipients, payloads and transactionality cannot be established without the
missing backend definitions. This phase retains the same RPCs and parameters,
adds no notification writes and makes no claims about delivery.

## Current versus Phase 3 transitions

| From | Actor/action | Result | Current client enforcement | Phase 3 |
| --- | --- | --- | --- | --- |
| No application | Worker submits application | Submitted/Applied via existing submit contract | Existing application form/repository; actual SQL unavailable | Unchanged |
| Submitted/Applied | Employer Shortlist or Reject | Shortlisted or Rejected | `JobApplicant.employerNext`, employer form and repository | Unchanged |
| Shortlisted | Employer Move to Interview or Reject | Interview or Rejected | Same employer gates | Unchanged |
| Interview | Employer Make Offer or Reject | Offered or Rejected | Same employer gates | Unchanged; clarify an offer is not a hire |
| Offered | Worker Accept Offer | Hired | `ApplicationResponseAction.allowed`, details UI and repository | Unchanged; confirmation explains post-hire boundary |
| Offered | Worker Decline Offer | Declined | Same worker gates | Unchanged; distinct explanation and confirmation |
| Submitted, Shortlisted, Interview, Offered | Worker Withdraw Application | Withdrawn | Same worker gates | Unchanged; explicitly pre-hire, distinct from decline/cancellation |
| Offered | Employer changes application status | None exposed | Empty employer transition list and repository rejection | Unchanged |
| Hired | Worker withdraws or declines; employer rejects/reverts | None exposed | No worker actions; no employer transitions; repositories reject dispatch | Unchanged; both roles see hired lifecycle explanation |
| Rejected, Declined, Withdrawn | Either actor reopens/repeats transitions | None exposed | No transition actions; repository rejection | Unchanged |
| Hired | Worker/employer ends hired arrangement | No supported contract found | No application cancellation action or adapter | **Not implemented. Backend design and review required.** |

For every Module 2 row above, database enforcement remains unverified because its
SQL is missing; the table does not claim the UI is an authorization boundary.

Worker details establish ownership from the current seeker's list before loading
history. Worker mutations validate the current session, owned application ID,
current status, allowed action and busy/loading state. Confirmation is bound to
the session and application snapshot. Employer mutations recheck authorized
company/job context before dispatch, and validate the current applicant/status.
Both paths lock duplicate/conflicting actions and reload authoritative records
after success or failure, without optimistic status changes. Account changes
discard stale responses. A second device/session still requires atomic backend
transition enforcement; Flutter locks cannot provide that guarantee.

## Module 4 dependencies and cancellation gap

`WorkAssignment` carries `applicationId`. Each assignment has independent
attendance/evidence/verification state. Worker and employer lists group by that
ID without combining work records. Additional-shift eligibility is discovered
from **Hired** applicants by `WorkAssignmentCreationRepository`, with fresh reads,
overlap checks and request reconciliation.

The checked-in `20261105000100_work_attendance_verification.sql` defines
assignment statuses `scheduled`, `active`, `awaiting_verification`, `completed`,
`cancelled`, `disputed`; these are **shift statuses**, not application statuses.
Its assignment FK references `job_applications` without an ON DELETE CASCADE.
Attendance, evidence and verification history reference assignments. Its worker
overlap exclusion constraint exempts cancelled shifts. That exemption is not
permission to cancel a shift or a hired arrangement.

The base creation function checks Hired eligibility and company management.
`20261106000100_work_assignment_creation_idempotency.sql` adds reservation/create
request functions, application/job locks, fresh Hired checks and request identity.
The new-request path requires Hired; an already committed matching request returns
its existing assignment ID for reconciliation. A future ended-arrangement design
must retain this distinction between reconciling a past write and creating work.

Check-in/out lock and validate the assignment and active worker identity. Evidence
submission/review/verification functions validate assignment eligibility and
actor access; their follow-up migrations preserve history and request handling.
Ending an application alone cannot safely coordinate those operations. No inspected
function implements hired-arrangement termination or an atomic cross-shift
cancellation policy. Changing Hired to Withdrawn would conflate recruitment and
work lifecycles, break scheduling assumptions, and leave shift handling undefined.

## Backend design required for review — not implemented

Before implementation, obtain the actual Module 2 RPCs, status type/check
constraints, triggers, grants/RLS and notification/history definitions through
the backend owner. Review them offline; this phase does not request live SQL.

Decide whether ending a hired arrangement needs a separate lifecycle record or
an explicitly supported application status. A separate lifecycle can retain Hired
as the recruitment outcome, but **all** creation/eligibility checks would then
need an authoritative active-arrangement check. Neither representation is assumed
to exist. Also decide whether either party may end it unilaterally, whether mutual
agreement is required, the required reason and effective date, and who may act for
an employer under existing company permissions.

The proposed minimum safe contract is an authenticated, explicitly confirmed,
idempotent server operation that:

1. Checks the owning active worker or an authorized employer and fresh arrangement
   state; serializes with scheduling/attendance using a reviewed lock order.
2. Returns an authoritative shift/record impact summary for review. Rechecks it
   atomically on confirmation so a concurrent new shift or check-in cannot bypass
   safeguards. Blocks new scheduling after an arrangement is ended, while allowing
   read-only reconciliation of earlier committed requests.
3. Conservatively refuses ending while any scheduled, active, awaiting-verification
   or disputed shift needs resolution. Future-shift handling must be decided in
   the separately reviewed shift-cancellation phase; no silent bulk cancellation.
   Existing dispute integration/record visibility needs coordination with KZ,
   without modifying that module here.
4. Preserves every application, assignment, attendance/GPS record, evidence file,
   verification/history record and audit trail. Completed/verified and already
   cancelled shifts remain unchanged. Authorized access to historical work and
   unfinished verification must not disappear when recruitment state changes.
5. Records actor, reason, effective time and immutable audit/request identity.
   Repeated or concurrent requests must not duplicate termination or side effects.
   Does not create penalties, trust changes or alter payment logic. Existing
   obligations remain outside this implementation and need owner review.

Future backend acceptance tests must cover worker/employer/foreign actor access,
company permissions, every shift state, concurrent creation/check-in, replay and
lost responses, record retention, historical access, and existing side effects in
an approved isolated database. Local fakes do not establish RLS/RPC security or
database retention. No migration, RPC, policy or cancellation UI is delivered here.

## Phase 3 client changes and validation boundaries

Both real roles share Offered/Hired/Declined/Withdrawn explanations. Worker action
labels and wire values remain distinct. Confirmation identifies job and company,
explains the result and post-hire boundary, and scrolls on small screens. Employer
Make Offer explains that worker acceptance is needed for Hired. Existing loading,
retry, session invalidation, action locks, history refresh and notification calls
remain unchanged. No Module 4 write path was added.

Focused tests cover transition guards, conflicting actions while refreshing,
ownership/session failures, consistent role presentation and rejected post-hire
actions leaving local work fixtures unchanged. Browser/device behavior and actual
SQL enforcement/record retention require separate acceptance testing.

# Application Management integration plan

Planning only. None of the structures below is an assertion that a deployed
table, policy, bucket, RPC or API exists. No migrations were generated/executed.

## Current Flutter implementation to reuse

- `features/applications/browse_jobs_page.dart`: search/location/type/arrangement,
  sort, saved filter, job cards and navigation.
- `job_details_page.dart`: `JobDetailsPage`, `JobFacts`, `ApplyDemoForm`, cover-note
  drafts, duplicate prevention, missing resume/profile explanation and feedback.
- `applications_page.dart`: seeker/employer lists, summaries, search/tabs/status,
  `ApplicationDetailsPage`, `ApplicationActions`, `TransitionForm` and timelines.
- `module2_repository.dart`: immutable `BrowseJob` presentation projection,
  `ApplicationStage`, `DemoApplication` and isolated observable `Module2Repository`.
  This repository is entirely fictional/local. Do not rename it into a production
  service or silently mix its IDs with Supabase users/postings. Retain an explicit
  demo entry until real integration has passed acceptance tests.
- `module2_widgets.dart`: real active-role gate, responsive modal, status badge,
  safe Back fallback and error states. Reuse GoRouter routes in `app_routes.dart`.
- Existing profile/company implementations own real identity, avatar/logo,
  verification and membership behavior. Existing job display/validation utilities
  and the employer repository own posting field meanings and lifecycle rules.

## Existing real posting reads and the public-read gate

`JobPostingsRepository.loadAccess()` checks the real authenticated active employer,
company membership and verification before access. `list(companyId)`/`get` are
company-scoped employer reads. They are not a reviewed public Job Seeker contract.
No approved Job Seeker read service or checked-in public salary-safe projection
has been established. Browse remains demo-only today.

Before integration, inspect the actual deployed schema/policies with the team.
Define a safe published-job projection that omits hidden salary values on the
server, including detail, search/filter/sort payloads and responses. RLS filters
rows; it does not redact salary columns. The existing `BrowseJob` projection
strips hidden salary for presentation but cannot secure values already received.
If unauthorized clients can read hidden salary, fix that server gap before release.
Public listings must exclude draft/closed records. Submission must recheck current
publication state and deadline server-side, including a job closed after viewing.

## Proposed storage (names and types require team agreement)

| Proposed logical entity | Purpose / important constraints |
| --- | --- |
| Application | Stable ID, real job/user references, canonical stage, note, resume/profile snapshot references, submitted/updated timestamps; unique job + seeker constraint and idempotent submission. Define whether a withdrawn applicant may reapply; current demo does not model a new cycle. |
| Application history | Append-only stage events, server actor/time, allowed transition, optional public explanation. Seeker-visible events must exclude private employer notes. No client-authored authoritative timestamps. |
| Private employer application note | Separate employer-authorized storage and projection. Never return these fields in seeker/detail/event payloads; UI hiding is insufficient. Scope reads/writes to authorized company members. |
| Offer / decision | Versioned terms, expiry, issuer and recipient decision events; atomic acceptance/decline, concurrent update protection and explicit hiring/assignment semantics. Do not treat local button clicks as a signed contract. |
| Saved job | Unique seeker + job relation; private to that seeker. Handle unavailable/deleted jobs without exposing drafts. |
| Resume metadata / profile snapshot | Owner, private object reference, version/type/size, consent and retention; describe what the employer receives at submission and whether later profile edits change it. |

## Status contract

Reuse `ApplicationStage`: Applied → Shortlisted / Reviewing → Interview → Offered
→ Hired. Employer rejection is allowed from nonterminal employer-managed stages.
Seeker withdrawal is currently allowed from Applied, Shortlisted and Interview;
current demo decline of an Offered application maps to Withdrawn. Hired, Rejected
and Withdrawn are terminal; All/Active/Completed derives from this same model.
`Reviewing` and `Shortlisted` are aliases of one stage in the UI, not two database
states. Agree canonical stored enum values before building an adapter. Do not infer
them from display strings. Decide whether production needs separate Offer Declined,
Offer Expired or Review states and document an explicit migration/mapping later.
Enforce actor-specific transitions, audit events and concurrency on the server.

## Authorization and privacy

- Seeker: active authenticated role, owns submitted identity, sees only their own
  applications/saves/eligible offers and public timeline. Derive seeker ID from
  server auth; reject arbitrary client identity, company, initial stage or timestamp.
- Employer: active authenticated account plus current membership in the posting's
  company, appropriate membership permissions, existing company verification and
  job ownership checks. Possessing an application/job ID or opening a route grants
  nothing. Recheck authority for every read/action; session/membership can change.
- Decide how company suspension, revoked membership and closed jobs affect access
  to historical applications. Do not broaden current ownership/RLS to make UI work.
- Duplicate protection needs a database uniqueness constraint and atomic insertion,
  not only a disabled submit button or an earlier SELECT. Retry safely after timeouts.
- Private resumes require authorized signed access, upload validation, bounded
  file types/sizes, malware review, consent/retention/deletion and access logging.
  Do not publish public bucket URLs, protected contact details or service-role keys.
- Agree resume/profile completeness rules. Current real profile has limited fields;
  a demo resume flag is not evidence of an uploaded file. Show actionable missing
  data before submit; avoid inventing a mandatory resume requirement without policy.
- Offers/internal notes/history require separate projections and tests for both
  roles. Admin access, if needed, requires specific server permissions/audit scope;
  no RLS bypass, UI role switch or private-message read is part of this plan.

## Recommended order and acceptance

1. Verify deployed schema, current RLS, public-read permissions and salary privacy;
   approve contracts with KZ before any database change.
2. Add a production job-read adapter alongside the demo repository; test salary
   omission, filtering, closed/deadline states and direct routes with real roles.
3. Agree profile/resume consent and private storage contracts; add uploads only
   after ownership/RLS/validation are reviewed.
4. Integrate atomic seeker submission + duplicate/idempotent handling + history;
   preserve cover notes on failure and expose truthful server errors/retry.
5. Integrate own-application list/detail/withdraw with server timelines and counts
   derived from the same queried source, including pagination/filter semantics.
6. Integrate employer company-scoped pipeline/profile reads and authorized stage
   commands, private notes, confirmations and concurrent-update handling.
7. Integrate offers/acceptance/decline and saved jobs after their business rules are
   approved. Realtime/notifications are optional later work, not prerequisites.
8. Test two seekers, two unrelated companies, revoked membership, suspended users,
   duplicate/racing requests, expired/closed jobs, hidden salary, resume leakage,
   unauthorized direct IDs, private notes, refresh/history and Android Back.

The UI is ready for adapter/contract work; production applications are not ready
until these backend, RLS and acceptance steps are completed. Employer posting and
`format-job-description`/Gemini are independent working integrations to preserve.

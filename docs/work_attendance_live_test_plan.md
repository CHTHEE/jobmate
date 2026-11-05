# Module 4 live attendance test plan

**Documentation only. Nothing in this plan has been executed by the agent.**
Approval to write this document is not approval to create fixtures or perform
attendance actions. Obtain separate approval for the fixture manifest and each
phase below. Use the existing main development project; coordinate with the
other developer. Do not deploy either Module 4 migration or enable evidence
submission. This plan tests the existing attendance RPCs only.

## Protected real records

Never modify, check in/out, cancel, delete or repurpose:

- Existing real assignment `5e103e8a-e51b-41e9-ba8d-6789cb09eea0`.
- Its existing Hired application and the published Part-Time Cafe Crew job.
- Their real worker, employer, company, memberships and related records.
- Any other existing real jobs, applications, assignments or attendance.

Do not change real schedules to open a test window. Record the protected job,
application and company UUIDs through authorized read-only inspection if they
are not already known; do not guess them from names. Use dedicated synthetic
accounts so the real assignment does not appear in the test worker's list.

## 1. Approve fixtures and record identities

Create nothing until the user approves this fixture list and permitted writes:

| Fixture | Required condition |
| --- | --- |
| Worker | Dedicated synthetic email/account; verified sign-in as an active `job_seeker` |
| Employer | Dedicated synthetic account; active employer with authorized company-management access |
| Company | Separate synthetic company, satisfying existing verification and membership rules; no changes to a real company |
| Job | Clearly named `MODULE4-ATTENDANCE-TEST` synthetic job, published through the existing approved workflow |
| Application | Synthetic worker applies to that synthetic job; authorized employer moves only that application to `hired` |
| Assignment | New assignment created using the RPC below; never reuse the protected real assignment |
| Negative-test worker | Separate active synthetic worker with no ownership of the test assignment |

Do not invent fixture INSERTs: prerequisite user/company/job/application schemas
are not fully defined in this checkout. Use existing supported application/admin
workflows. If any step is unavailable, stop and obtain a separately reviewed
fixture-creation procedure. Do not bypass verification or grant direct table
access to clients.

Maintain a local test manifest (no passwords, tokens or Supabase keys):

```text
Confirmed development project: __________________
Worker auth/public user UUID: __________________
Employer auth/public user UUID: __________________
Company UUID: __________________
Job UUID: __________________
Hired application UUID: __________________
Negative-test worker UUID: __________________
Planned shift start/end, ISO-8601 with timezone: __________________
Returned assignment UUID: __________________
Approved operator, test scope and date: __________________
```

Verify UUIDs from actual workflow responses/authorized records, not display
names. Confirm the application joins the intended worker, job and company and
is `hired`. Compare every action's assignment UUID with the manifest and the
protected UUID. Prefer separate browser profiles for employer and worker sessions.
Never paste access tokens into SQL, screenshots or this document.

## 2. Read-only deployed-contract preflight

Only after approval to inspect the intended project, run this SELECT in its SQL
Editor. It fetches definitions, not execution results. Expect four existing
functions with trusted owners, `SECURITY DEFINER`, empty search paths,
authenticated EXECUTE and no anon/PUBLIC EXECUTE. Review the returned definitions
against `20261105000100_work_attendance_verification.sql`; investigate any drift.

```sql
WITH required(signature) AS (
    VALUES ('public.create_work_assignment(uuid,timestamp with time zone,timestamp with time zone,text)'),
           ('public.check_in_work_assignment(uuid,text,numeric,numeric)'),
           ('public.check_out_work_assignment(uuid,text,numeric,numeric)'),
           ('public.list_my_work_assignments()')
)
SELECT q.signature, p.oid IS NOT NULL AS exists,
       pg_catalog.pg_get_userbyid(p.proowner) AS owner,
       p.prosecdef, p.proconfig,
       pg_catalog.pg_get_function_arguments(p.oid) AS arguments,
       pg_catalog.pg_get_function_result(p.oid) AS result_type,
       pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
       pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
       EXISTS (
           SELECT 1 FROM pg_catalog.aclexplode(
               COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) AS acl
           WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
       ) AS public_execute,
       pg_catalog.pg_get_functiondef(p.oid) AS definition
FROM required AS q
LEFT JOIN pg_catalog.pg_proc AS p
       ON p.oid = pg_catalog.to_regprocedure(q.signature);
```

Expected returns: create = UUID; check-in/out = timestamptz; list = the existing
worker assignment projection. Also review RLS, table privileges and unexpected
triggers using the existing read-only predeployment checklist. No client should
gain direct write access. Confirm `can_manage_company_jobs(uuid)` exists and the
test employer qualifies under its actual implementation.

Missing functions, mismatched contracts, unexplained owners/ACLs, uncertain
fixture identity or unapproved fixture changes block testing. Coordinate a
quiet window and confirm available database recovery arrangements; restoring a
backup is not routine test cleanup and could erase the other developer's work.

## 3. Create only the approved synthetic assignment

This is a FUTURE WRITE requiring separate approval. Call through an authenticated
test-employer client, not the SQL Editor's administrative identity and not a
service-role client. The RPC checks the application is hired and the caller can
manage its company. There is no production assignment-creation UI assumed here;
use a separately approved authenticated test client if needed.

Prepare a start near current server time (for example, approximately five minutes
ahead) and an end comfortably later (for example, thirty minutes after start).
Record explicit UTC or `+08:00` timestamps. Check-in must occur between start
minus 60 minutes and end, inclusive. Confirm a nonoverlapping schedule for the
synthetic worker; the deployed exclusion constraint rejects overlaps with
non-cancelled assignments. Do not shorten or move any real shift.

Exact client call template; replace manifest placeholders before execution:

```dart
final assignmentId = await authenticatedTestEmployerClient.rpc(
  'create_work_assignment',
  params: {
    'p_application_id': '<approved synthetic hired application UUID>',
    'p_scheduled_start': '<approved ISO-8601 start with timezone>',
    'p_scheduled_end': '<approved ISO-8601 end with timezone>',
    'p_workplace_location': 'Synthetic attendance test location',
  },
);
```

Record the returned UUID immediately. Through authorized company/worker reads,
confirm its application, worker, company and schedule match the manifest and its
state is `scheduled` with null attendance timestamps. Stop if any identity differs.
If assignment creation times out, inspect authorized company assignments for the
specific synthetic application/schedule before another creation attempt. This
RPC has no client request key; do not assume a lost response means no assignment.

## 4. Execute the worker attendance journey

Every write below requires approval. Sign in as the synthetic worker and open
**My Work Shifts** (`/work-attendance`), not the separate `/attendance` demo.
If the job title is ambiguous, verify identity through the authorized RPC result
and browser network request's `p_assignment_id` before confirming. Never export
authorization headers or tokens from developer tools.

| Step | Action | Expected authoritative result |
| --- | --- | --- |
| Initial read | Refresh worker assignments; verify manifest UUID | `scheduled`, check-in/out NULL; verification `not_submitted` |
| Cancel confirmation | Open Check in, then Cancel | No attendance write or timestamp |
| Check in | Confirm once inside the eligible server window | Server timestamp stored; assignment `active`; button becomes Check out |
| Refresh/direct entry | Refresh browser and reopen `/work-attendance` | Same recorded check-in; no action is repeated |
| Check out | Confirm once | Server check-out timestamp >= check-in; assignment `awaiting_verification`; check-out control disappears |
| Final read | Refresh worker and authorized employer assignment lists | Both reflect the synthetic assignment's persisted attendance/state; verification remains `not_submitted` |

Both attendance calls send exactly `p_assignment_id`,
`p_location_status: 'unavailable'`, `p_latitude: null`, `p_longitude: null`.
No location permission is requested or coordinates fabricated. UI times are MYT;
compare the underlying zoned timestamps, not formatted strings alone. Check-out
has no scheduled-end eligibility window in the inspected SQL, so no need to wait
until shift end. Do not submit evidence or perform employer verification.

## 5. Negative and lifecycle cases

Use only the synthetic assignment UUID, and approve intentional rejection calls:

- **Rapid duplicate UI actions:** double-tap a confirmed action while pending;
  observe disabled controls and one dispatched action. Do not simulate this by
  firing an uncontrolled batch of requests.
- **Duplicate server rejection:** the normal UI hides obsolete actions. If an
  approved authenticated test client is available, repeat check-in after it is
  recorded and check-out after completion. Expect rejection and unchanged
  timestamps/counts. Exact messages can reflect the assignment-status check.
- **Ownership denial:** the unrelated synthetic worker attempts the same test
  assignment action; expect denial and no change. Its normal assignment list
  should not reveal the other worker's assignment.
- **Expired/absent session:** use an isolated synthetic session that has genuinely
  expired, or a signed-out client with session refresh disabled. Do not publish
  or tamper with real tokens. Expect auth rejection/redirect and no write. Logout
  tests absence of a session, not proof of expired-token handling; report expiry
  untested if it cannot be reproduced safely.
- **Account switch during confirmation:** switch between synthetic accounts;
  confirmation must invalidate and must not dispatch as the new account.
- **Account switch during a pending action:** only with explicit approval and
  coordination; old feedback must not appear under the new account. Independently
  read the original test worker's state, since a dispatched action may commit.
- **Window rejection:** use a separately approved synthetic assignment outside
  the allowed window if this boundary case is required. Never alter the real
  assignment or an already-tested assignment to manufacture the case.

## 6. Timeout / uncertain outcome procedure

Do not blindly retry, generate replacement fixtures, or reset timestamps. A lost
response may follow a successful commit. The existing repository refreshes after
both success and failure, but the refresh itself may fail.

1. Stop action attempts and record which synthetic UUID/action was dispatched.
2. Restore the original authorized test session and read
   `list_my_work_assignments()`; an authorized employer can independently inspect
   its company list. These reads do not mutate attendance.
3. If the intended timestamp/state is present, treat that action as committed;
   do not repeat it. If reads fail, disagree, or show unchanged state while the
   original request might still execute, remain paused and investigate.
4. Resume only after the original request is resolved and current state is
   established. Never infer failure from one empty/unchanged read. Preserve the
   server's duplicate/state validation; do not bypass it with direct table writes.

## 7. Retention and cleanup

Attendance writes are persistent. No attendance-reset, assignment-delete or
synthetic-fixture cleanup RPC is provided by the inspected Module 4 migration.
Foreign keys and evidence/history dependencies make deletion order significant.

Retain clearly labeled synthetic fixtures and the manifest by default. Sign out
test sessions and coordinate how test records are kept out of operational use.
Do not assume closing a browser removes data. Do not delete Auth users, jobs,
companies or assignments, reset attendance, reopen shifts or restore a whole
project backup as casual cleanup. Any cleanup/archive procedure requires a
separate dependency review and explicit approval; preserve all real records.

Record each case as PASS / FAIL / NOT RUN with its synthetic UUID, observed
timestamps and sanitized error text. Keep evidence submission disabled. This
plan is not evidence of successful live testing or deployment approval.

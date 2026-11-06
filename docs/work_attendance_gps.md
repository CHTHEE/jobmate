# Attendance GPS: local implementation and deployment review

Workers capture a fresh device location only during attendance confirmation.
Granted coordinates and the `granted`, `denied` or `unavailable` status pass to
the existing check-in/check-out RPCs. Retry GPS and Continue without GPS remain
available. Attendance time comes from the server, never GPS or the device clock.
Android foreground fine/coarse location permissions already exist. Web device
geolocation requires HTTPS (or localhost) and browser permission. No background
tracking, geofence or map API key is introduced. Device capture uses `geolocator`.

The employer's **View attendance GPS** button opens a separate read-only view.
`read_employer_work_attendance_gps(company, assignment)` checks authentication,
the existing `can_manage_company_jobs` helper, active employer/membership/company
verification eligibility and the assignment's actual company.
It returns only that assignment's attendance timestamps, statuses and coordinates.
Direct table grants and existing assignment/evidence/write RPCs are unchanged.
Missing RPCs fail closed; old assignment listings cannot substitute for GPS data.
Account changes clear the view and invalidate in-flight reads, including switching
away and back. Refresh clears old coordinates before requesting new data.

Only valid coordinate pairs produce Google Maps search links. Opening a link
shares coordinates with Google; the dialog states this. Device-reported GPS can
be inaccurate or spoofed and does not prove attendance. Null historical statuses
are shown as not recorded; no previous records are backfilled or rewritten.

## Completed deployment and remaining QA

The project owner confirms that all four Module 4 follow-up migrations
(`20261105000300`, `20261106000100`, `20261106000200`, `20261106000300`)
are deployed and catalog-verified in the shared Supabase database as of
2026-11-06, over the existing base. Do not reapply them or deploy the alternative
`20261105000200` prototype. Deployment does not establish runtime security QA
or client release readiness; coordinate cutover and keep writes paused outside
separately approved synthetic-fixture QA.

`supabase/migrations/20261106000200_employer_attendance_gps.sql` is the deployed
GPS contract. The company-management helper's implementation is absent from this
checkout. The RPC explicitly enforces the active-employer, permitted-member
and verified-company rules used by the existing client company-access gate.
No new Dashboard secret is needed.
No deployment or remote verification was performed by this documentation cleanup.

Run `supabase/tests/work_attendance_gps.sql` only against an isolated database
with disposable authorized/unauthorized fixtures. SQL authorization and actual
Supabase execution are not established by Flutter mocks. Manually verify:

- Real browser/Android permission grant, denial, disabled services and timeout.
- Retry GPS, cancellation and continuing without GPS for both attendance actions.
- Stored statuses/coordinates and unchanged server timestamp/window enforcement.
- Authorized employer viewing; other companies, workers, revoked memberships,
  inactive employers, unverified companies and anonymous callers denied.
- Account switching during GPS capture/read, narrow layouts, large text and
  external Google Maps opening on Web/Android.

Do not use the original cafe assignment or previously verified QA assignment.
External map tabs and coordinates already viewed cannot be recalled on sign-out.

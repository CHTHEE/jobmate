# Payment Handling — Billplz Sandbox foundation

Status: local code and offline tests, **not a deployed end-to-end payment system**.
Billplz is selected; the user reports that the Sandbox Collection and both keys
are ready. The credentials have not been validated against Billplz. Real accepted
JobAssignment/Attendance/Dispute contracts are being developed by teammates and
are absent from this checkout. No payment migrations or remote changes were made.

## Confirmed rules — November 4, 2026

- Part-time/Temporary only; Full-time payroll is excluded.
- Assignment must be accepted, completed and work-verified. Unresolved disputes
  about work completion block checkout. Missing/unknown eligibility fails closed.
- Agreed assignment amount is the immutable minimum, not today's job posting
  salary or a browser amount. Employer may add a voluntary performance Bonus
  without worker acceptance. Total = agreed + nonnegative Bonus, in integer sen.
- Freeze base, Bonus, total, MYR and terms version per attempt. Genuinely failed/
  cancelled attempts remain in history; a new attempt can have a different Bonus.
  Do not create another Bill while an earlier attempt is Pending/Processing/unknown.
- SUCCEEDED means employer test payment confirmed, not worker bank receipt.
- No live processing, escrow, wallet, disbursement, refund or card-data collection.
  Adding a Bonus after a successful payment is outside this first payment flow.

## Implementation boundary

| Layer | Implemented | Still required |
| --- | --- | --- |
| Flutter | Role-specific lists/details, agreed amount/Bonus, attempts, status checks, redirect handling, popup recovery, draft exit guards | Actual service records |
| Client repository | Actor/session checks, new payment-handling contract, explicit integration-pending state | Deployed connected service |
| Server domain/service | Ownership, eligibility, integer amounts, reservation flow, unknown outcomes, verified status/callback processing | Authoritative AssignmentSource and durable PaymentStore |
| Billplz Sandbox adapter | Bill creation/read, fixed Sandbox host, HMAC callback verification, Collection/reference/amount checks | Account, server-injected credentials and real gateway tests |
| Edge entry points | Existing authenticated Supabase pattern and active-account checks | Deliberately fail closed until durable adapters are wired |
| Database | Contract/invariants below | Approved FK/schema, RLS, atomic RPCs, audit/notification transaction and database authorization tests |

Routes: `/payments`, `/employer-payments`, `/admin-payments`, each with
`/assignments/:assignmentId` and `/:paymentId`. `/payments/return?payment_id=...`
only rechecks Backend state. Old `/employer-payments/record` redirects to employer
Payments. Phase 4 external-record demo classes/tests remain, but are no longer
the main payment UI. The app does not replace missing Backend data with fixtures.

## Teammate AssignmentSource contract — proposed, not existing schema

Implement the port in `supabase/functions/_shared/payments/domain.ts` against the
actual approved tables. Translate actual names/enums in the adapter; do not rename
teammates' columns to match this DTO. Confirm real tables, UUID/FK types, accepted/
completed/verified values, dispute relations and accepted terms version first.

| Field | Server-owned meaning |
| --- | --- |
| assignment_id | Actual accepted JobAssignment UUID, never a sample ID |
| employer_id / job_seeker_id | Responsible payer and worker's existing public.users IDs |
| job_title / company_name / worker_name | Authorized display projection |
| employment_type | Canonical adapter value part_time / temporary / full_time |
| accepted / completed / work_verified | Explicit booleans from authoritative records |
| payment_blocked | True while relevant work-completion dispute is unresolved; failed queries cannot imply false |
| employer_authorized | Current active Employer, permitted Company membership, verified Company and assignment responsibility checks pass |
| amount_minor / currency | Agreed positive minimum in integer sen, MYR |
| terms_version | Stable accepted-terms version used under reservation locking |
| payer_name / payer_email | Actual authorized employer details for Billplz, not exposed to history UI |

Never infer Completed/Verified from a sample UI button, check-out time alone,
Phase3Store or payment status. Historical parties may still read their records;
new checkout additionally requires current Company authorization.

## Durable PaymentStore contract — required before enabling checkout

No runtime in-memory fallback is provided. The test store is **not deployable**.
Agree and review the payment migration once the actual JobAssignment FK exists.

1. Store one immutable row per payment_id with actual assignment FK, employer/
   worker FKs, agreed sen, Bonus sen, total sen, MYR, accepted terms version,
   provider bill reference, nullable method/failure/confirmation and timestamps.
   Keep all failed/cancelled attempts. Require base > 0, Bonus >= 0, total = base
   + Bonus, bounded safe integers (matching NUMERIC(12,2) if using decimal columns).
2. In `reserve`, lock the actual assignment row, recheck current eligibility,
   Company/dispute/terms and actor, then insert within one transaction. Never trust
   browser-provided parties, minimum, currency, eligibility or success status.
3. Stable request-ID replay returns the same reservation; reused ID with changed
   assignment/parties/Bonus is rejected. Concurrent calls reuse an active attempt.
   A partial unique constraint on assignment_id where status in
   (PENDING, PROCESSING, SUCCEEDED) prevents an active checkout alongside a success.
   Also enforce unique provider bill IDs. Locking must enforce final invariants.
4. `attachCheckout` binds exact provider/reference/Collection/amount and must
   tolerate a valid callback arriving before create returns without downgrading
   success. `rejectCreation` only changes a definitely rejected, unbound create
   request to FAILED. Timeout/5xx/unknown responses retain PENDING.
5. `applyVerified` is a single DB transaction: verify binding and exact amount,
   dedupe event ID, apply monotonic status, audit and notify both parties once on
   first SUCCEEDED. Any error rolls back the event and notification. Never
   downgrade success; never claim bank payout from a dispute resolution.
6. Reuse existing public.notifications fields user_id, notification_type, title,
   message. Example wording: "Employer sandbox payment confirmed for MYR 125.00".
   Failure notification is optional. No duplicate notification on recheck/callback.
7. RLS: active relevant employer/worker SELECT only their records; active Admin
   may read for support. No client INSERT/UPDATE/DELETE of attempts/events/success.
   Only trusted service methods mutate payments. No Admin manual-success control.
8. Unique event IDs, minimal safe metadata and audit times; no card data, API
   keys or unnecessary raw provider payloads. Database RLS/transaction tests are
   still required; fixture tests do not establish these deployed invariants.

## New application API contract

Authenticated POST to `payment-handling` using the existing Supabase user JWT.
Server loads role/status. Every successful response has environment=sandbox.

| action | Request fields | Response |
| --- | --- | --- |
| list_assignments | offset, limit (1–101) | Authorized assignments |
| get_assignment | assignment_id | Assignment, attempts, can_pay, can_resume_checkout, blocking_reason |
| get_payment | payment_id | Authorized assignment owning the attempt |
| create_checkout | assignment_id, request_id, bonus_minor (default 0) | assignment_id, payment_id, checkout_url |
| refresh_status | assignment_id | Server-verified Billplz results, updated assignment |

The UI never submits an agreed total or status. Attempts contain amount_minor,
agreed_amount_minor, bonus_minor, currency, PENDING/PROCESSING/SUCCEEDED/FAILED/
CANCELLED, ISO dates and nullable provider reference/method/checkout_url/confirmed_at.
Worker/Admin views are read-only; only the assignment Employer can create.
Their projections do not expose checkout links. Active attempt Bonus must match
the requested Bonus; the service rejects a mismatch instead of silently opening
a Bill with a different total. Resume permission is computed from current Company,
completion and dispute checks separately from permission to create a new Bill.

## Billplz behavior and operational limits

Bill endpoints use the documented Sandbox `/api/v3/bills` base, fixed in code;
there is no production switch or invented V4 Bills endpoint. Basic authentication
stays server-side. One Sandbox Collection is configured; reference_1 is the
reserved payment_id. Callback URL also identifies the reservation, but its query
alone is untrusted: HMAC and a server-read matching reference, Collection and exact
total are required. Paid status is never accepted from a browser redirect.

Form-encoded X Signature verification rejects tampering, duplicate keys and
oversized/malformed requests. Backend retrieves the Bill directly and commits
through the durable store. Callback-before-return and return-before-callback must
both work. Callback errors return non-2xx, never acknowledge uncommitted data.

An unpaid `due` Bill stays PENDING even after a failed bank transaction: resume
that Bill. A confirmed `deleted` Bill maps to CANCELLED. SUCCEEDED requires
paid=true, state=paid and exact paid_amount. Unknown method stays null. A definite
400/401/403/422 create rejection may be FAILED; timeouts/5xx never imply failure.

If create succeeded remotely but bill_id response was lost, retain PENDING and
reconcile reservation reference_1 through the Sandbox dashboard/support process.
Do not automatically create a replacement Bill or manually fake success. This
recovery is an operational limitation until a reviewed reconciliation flow exists.
An already-issued public Bill URL may remain payable outside JobMate even after
a new dispute appears. Before deployment, coordinate the Dispute lifecycle to
reconcile/delete unpaid bills (using Billplz's documented due-bill deletion) and
handle a payment racing that action. Current UI/read projections disable resume
when they receive a blocked state, but they do not revoke a previously issued
gateway link or provide real-time dispute updates. Callback processing must still
record a genuine provider payment honestly if one arrives during a dispute.

## Manual setup later — do not deploy the disabled webhook yet

1. Create a [Billplz Sandbox account](https://support.billplz.com/guide/create-a-sandbox-account),
   following that guide's dummy-information instructions and keeping Sandbox
   distinct from production.
2. Create a Sandbox Collection. Retrieve Collection ID, API Secret Key and
   X Signature Key. See [Secret Key guide](https://support.billplz.com/guide/get-your-secret-key)
   and [official API documentation](https://support.billplz.com/api).
3. In the existing Supabase project, open Edge Functions → Secrets. Add the four
   settings below. These are new names implemented by `_shared/payments/config.ts`;
   existing unrelated secrets should not be changed. No Flutter .env changes.

   | Secret name | Value to enter privately in the Dashboard |
   | --- | --- |
   | BILLPLZ_SANDBOX_API_KEY | Billplz Sandbox API Secret Key |
   | BILLPLZ_SANDBOX_X_SIGNATURE_KEY | Separate Billplz Sandbox X Signature Key |
   | BILLPLZ_SANDBOX_COLLECTION_ID | The Sandbox Collection ID |
   | JOBMATE_PAYMENT_RETURN_URL | `http://localhost:8765/#/payments/return` for local Web testing |

   The runtime already supplies SUPABASE_URL; do not add/replace it. The loader
   derives `/functions/v1/payment-webhook` on that project as the callback URL.
   It trims clipboard whitespace, validates URLs and reports configuration names
   rather than sensitive values when a setting is missing/invalid.

   `billplzSandboxFromEnvironment()` reads the server settings and constructs the
   adapter without making an API call. It is prepared for the future bootstrap;
   the current disabled entry points do not instantiate it or enable checkout.
   Saving secrets alone does not verify their validity or deploy an integration.
   Do not paste real values in chat, commit them, or bundle them with Flutter.
4. Agree AssignmentSource and implement/review the actual FK/RLS/atomic-store
   migration. Validate cross-user denial, duplicates, fixed terms and transactional
   notifications against PostgreSQL before enabling the service.
5. Wire durable source/store and BillplzSandbox into PaymentService and both Edge
   entry points. Review before deploying to the existing project. Provider webhook
   needs access without a user JWT while retaining HMAC validation. Keep JWT
   authentication on payment-handling.
6. Configure a public HTTPS callback URL. Set returnUrl to the actual Flutter Web
   return route. This checkout uses default hash routing; a local example is
   `http://localhost:8765/#/payments/return`. The adapter supports hash/path routes
   and inserts payment_id correctly. A fixed local port can use
   `flutter run -d chrome --web-hostname localhost --web-port 8765` after configuration.
   On this Windows machine, port 8080 returned socket error 10013; temporary
   IPv4/IPv6 loopback bind tests succeeded for 8765. Keep the return URL's hostname
   and port identical to the browser's app origin. Changing ports/hostnames changes
   browser local-storage origin, so sign in again if needed. If a later run needs
   another port, update JOBMATE_PAYMENT_RETURN_URL to match that port as well.
   A subsequent Flutter Chrome run on localhost:8765 connected to its debug
   service and completed Supabase initialization; that verification run ended.
7. Only then point Billplz at the webhook and test actual success, unsuccessful
   payment, duplicate events, pending recovery, both callback/redirect orders,
   browser refresh and worker/employer history.

No remote account, secret, schema, bucket, policy or callback settings were changed.
The current Edge entry points intentionally return PAYMENT_INTEGRATION_PENDING
until adapters are wired; they are not ready for real Sandbox callbacks.

## Local checks

### Manual UI preview before teammates finish

Stop the current Flutter run with Ctrl+C so its port is free. From the project
root, launch this separate developer entry point:

```powershell
flutter run -d chrome --target test/support/payment_preview.dart --web-hostname localhost --web-port 8765
```

The persistent UI PREVIEW banner identifies fictional local data. No Supabase
initialization, real gateway request, credential read or persistent payment write
is performed by this preview. The standard lib/main.dart never imports these
fixtures. The production repository and disabled Edge entry points are unchanged.

1. Choose Ready — Part-time and Open Employer payment. Enter a Bonus such as
   20.00; the confirmation should show MYR 100.00 + MYR 20.00 = MYR 120.00.
2. Click Pay now → Continue → Open sandbox checkout. This opens a local simulation
   dialog, not the Billplz website. Choose Simulate paid — Confirmed, then click
   Check payment status. The resulting label is fictional, not verified payment.
3. Use Preview cases, then open Job Seeker or Admin history to inspect that same
   local attempt read-only. Role switches retain local attempts. Selecting another
   scenario or Reset selected scenario clears the preview records.
4. Try incomplete/unverified/disputed/Full-time scenarios: Pay now must be disabled.
5. Try Pending/Processing: resume the existing local checkout without creating a
   new attempt. Simulate due — Pending does not mark a failed bank attempt FAILED.
   Simulate deleted — Cancelled allows a new attempt after a status check.
6. Failed creation shows a retained FAILED attempt and permits another attempt.
   Lose create response records Pending without a checkout URL and blocks another
   attempt, illustrating uncertain-result recovery. Backend not connected shows
   the actual integration-pending state.

These screens test presentation and interactions, not real role authorization,
RLS, database transactions, notifications, Billplz credentials, HMAC delivery or
money movement. Actual API/service unit tests are run separately below. All local
preview state disappears on restart. To return to normal JobMate, stop the preview
and run `flutter run -d chrome --web-hostname localhost --web-port 8765`.

The teammate does not need to finish every screen first. End-to-end checkout
needs an agreed actual JobAssignment schema/FK and server-readable accepted terms,
parties, employment type, completion, verification and dispute state, plus the
durable PaymentStore/RLS/notification implementation described above. No fixture
is substituted for these in the normal app.

```powershell
flutter analyze
flutter test test/payment_handling_test.dart
flutter test test/payment_preview_test.dart
deno test supabase/functions/_shared/payments/payments_test.ts
deno test supabase/functions/_shared/payments/config_test.ts
deno check supabase/functions/payment-handling/index.ts supabase/functions/payment-webhook/index.ts
```

Offline gateway/storage fixtures do not prove real Billplz checkout, deployed RLS,
gateway delivery, notifications, bank settlement or physical-device acceptance.

Validation on November 4: 19 offline Deno payment tests pass; both Edge entry
points type-check. The final Payment/workspace/Admin-sidebar Flutter run passes
36 tests, including all 15 new Payment tests. Web build passes. Analysis has the
same eight pre-existing diagnostics. The broader Flutter run reports 409 passes
and two existing failures: registration's stale UI lookup and the default Counter
smoke test in widget_test.dart; neither was changed by this payment work.
The subsequent server configuration step adds 10 fixture-only tests (29 Backend
tests total), all passing. Configuration and both entry points type-check; Flutter
analysis still reports the same eight existing diagnostics. Actual secret values
have not been read, saved remotely or verified by the agent, and the loader has
not yet been wired into the disabled entry points.
The manual preview walkthrough adds four fixture/UI checks: those plus the 15
Payment module tests pass (19 total), including Employer Bonus → simulated result
→ Job Seeker read-only history at 320/1440 widths. The preview Web target compiles.
The walkthrough also corrected the real page's dirty-input guard so a loaded
confirmed payment no longer treats its saved Bonus as an unsaved draft.

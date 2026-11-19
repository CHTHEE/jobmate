# Workplace place search

Phase 2C.2 is prepared locally. Nothing has been deployed or configured. The manual picker remains available while search is unavailable.

## Request flow

1. Flutter sends an explicit search submission to `search-workplace-places` using the current Supabase session. The picker passes only the search query. It does not send the job form's address automatically.
2. The Edge Function handles browser preflight and validates a bearer token against the project's Auth user endpoint, following the checked-in Chat Edge pattern. It obtains the verified user ID and uses a user-scoped read of that ID's application profile to require `role = employer` and `status = active`. Confirm own-profile RLS with a real employer JWT before enabling the function. No company identity is needed for this read-only search. Posting saves retain their existing company and membership authorization.
3. Accept a POST JSON object containing one trimmed query string of 2–120 characters. Bound request size and reject malformed input before calling the provider. After authentication and validation, reserve a quota slot atomically using the verified user ID. If the reservation is denied or the store is unavailable, return immediately.
4. Read `GEOAPIFY_API_KEY` from Edge Function Secrets. Send one bounded-time HTTPS request to Geoapify Forward Geocoding with `filter=countrycode:my`, `limit=5`, and `format=json`. Parse the documented results array, discard invalid or out-of-range coordinate pairs, cap the output again, and return only name, formatted address, latitude and longitude. The function should emit no query text, provider key, full provider URL, or raw provider response to clients or logs. Never automatically retry a billed request.
5. Return consistent errors for invalid input, unauthenticated or forbidden callers, rate limits, timeout, and provider or limiter unavailability. Return a successful empty result only when the provider returns a usable response with no matching places. If all supplied results are malformed, report a service error.

## Quota and migration

The migration `supabase/migrations/20261118000100_workplace_place_search_quota.sql` creates a private schema and reservation table protected by RLS and explicit revocations. The only app-facing schema addition is an RPC with execution granted solely to `service_role`. The definer RPC uses an empty search path, schema-qualified objects and a second active Employer check.

The RPC serializes all reservations through one transaction-level advisory lock. In READ COMMITTED, its statements after the lock see preceding commits. Other isolation levels fail closed. It records at most 20 attempts per employer per rolling 24 hours, with a three-second cooldown, and at most 2,000 project attempts per rolling 24 hours and two per rolling second. Pruning happens on reservation and leaves at most 2,000 rows, containing only employer IDs and timestamps. Expired rows can remain until another eligible request arrives. Attempts are charged before dispatch, including failed and timed-out requests.

These caps govern JobMate reservations. Scheduling delays between a reservation and dispatch can shift upstream timing, so the function also handles provider 429 responses. The limiter cannot see other usage on the same Geoapify account. Confirm sufficient account-wide headroom before enabling search. An in-memory counter or Flutter cooldown cannot enforce either shared cap.

## Flutter integration

Keep the search state in the existing picker. Use a bounded, keyboard-accessible results list above the full-width MapLibre viewport. Selecting a valid result moves the camera to that point at workplace zoom. The employer can pan, zoom or fine-tune before confirming. Cancelling leaves the previously saved coordinates in place. Keep the authoritative address in the existing form and show a reminder to check it against the pin after selecting a result. Keep manual pin placement available when search fails. Show the required Geoapify link and data-source attribution with search results.

## Deployment and verification

After separate approval, review the migration and apply it in an isolated project first. Verify that anon and authenticated cannot access the schema or invoke the reservation RPC, and that a real active Employer JWT can only read its authorized profile. Exercise concurrent SQL sessions or concurrent Edge calls to verify the cooldown, both project caps, employer caps, and fail-closed behavior under RPC failure. Check effective grants as deployed.

For concurrency acceptance, hold a successful reservation transaction open and submit another reservation for the same employer from a second session. After the first session commits, the second should be rate limited within the cooldown. Repeat with different employers and three near-simultaneous reservations to exercise the shared one-second budget. Seed isolated fixtures just below the daily thresholds to verify the 20th and 2,000th reservations succeed and the next ones fail, and verify expired rows are pruned on the next authorized request.

Set `GEOAPIFY_API_KEY` only in Supabase Edge Function Secrets. The function uses the existing Supabase URL, anon key and service role environment values. For a hosted Web app, configure the exact origin in `WORKPLACE_SEARCH_ALLOWED_ORIGIN`; localhost behavior follows the existing Chat CORS helper. Verify the project gateway JWT settings before deployment. The handler validates the user token independently. Keep the Geoapify key out of Flutter, bundled environment files and Git.

After approved deployment, verify search for Mid Valley Megamall, KL Sentral, Pavilion Kuala Lumpur and Sunway Pyramid in a real browser and check Android. Confirm that a search selection moves the camera, manual movement updates the final point, cancellation preserves the old pin, and the posting address remains unchanged. To roll back, remove the Edge deployment before dropping the reservation RPC, then drop the private table and schema in a reviewed migration. This removes only quota history.

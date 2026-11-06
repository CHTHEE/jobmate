-- DANGER: DISPOSABLE, ISOLATED TEST DATABASE ONLY. NEVER shared/production Supabase.
-- Manual psql test, not a migration or production verification script.
-- Requires the base schema and 20261106000100 in the isolated database.
-- Supply psql variables employer_id and application_id for a disposable, hired,
-- authorized synthetic fixture. The schema is not fully bootstrapped by this repo;
-- fixture provisioning must use the team's actual schema. Never use cafe/QA rows.
-- Fixture worker/company must satisfy the real RPC checks, with no conflicting
-- shifts at the fixed 2098 intervals below. Keep populated manifests/logs private.
-- Use a trusted isolated-test operator able to SET ROLE authenticated and set
-- request.jwt.claim.sub; never grant these test permissions to application users.
-- RPCs INSERT/UPDATE reservations, assignments and shift claims. Full execution
-- ends in ROLLBACK; errors with ON_ERROR_STOP can stop before it. Roll back or
-- disconnect the test session; never COMMIT. Row locks can block other sessions
-- until transaction end; no explicit lock/statement timeouts are set here.
-- Rollback does not undo prior fixture provisioning or external trigger effects.
-- No Storage upload/cleanup is needed by this script. Dispose of the isolated
-- fixture database separately; never delete shared assignments as cleanup.
-- The connection and fixtures are operator-selected, not environment-guarded.
-- This does not test two-session concurrency.
\set ON_ERROR_STOP on
BEGIN;
SELECT set_config('test.employer_id', :'employer_id', true);
SELECT set_config('test.application_id', :'application_id', true);
SELECT set_config('request.jwt.claim.sub', :'employer_id', true);
SET LOCAL ROLE authenticated;
DO $$
DECLARE
 app uuid := current_setting('test.application_id')::uuid;
 req uuid; again uuid; first_id uuid; second_id uuid;
 start_at timestamptz := '2098-01-10 01:00:00+00';
 end_at timestamptz := '2098-01-10 09:00:00+00';
BEGIN
 req := public.reserve_work_assignment_request(app, start_at, end_at, 'Synthetic test');
 again := public.reserve_work_assignment_request(app, start_at, end_at, 'Synthetic test');
 IF req <> again THEN RAISE EXCEPTION 'Reservation identity was not stable'; END IF;
 IF public.lookup_work_assignment_request(req) IS NOT NULL THEN RAISE EXCEPTION 'Uncommitted request returned assignment'; END IF;
 BEGIN
  PERFORM public.reserve_work_assignment_request(app, start_at, end_at, 'Changed');
  RAISE EXCEPTION 'Changed reservation payload accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 first_id := public.create_work_assignment_request(req, app, start_at, end_at, 'Synthetic test');
 IF public.create_work_assignment_request(req, app, start_at, end_at, 'Synthetic test') <> first_id THEN
  RAISE EXCEPTION 'Duplicate request created another assignment'; END IF;
 IF public.lookup_work_assignment_request(req) <> first_id THEN RAISE EXCEPTION 'Request reconciliation failed'; END IF;
 BEGIN
  PERFORM public.create_work_assignment_request(req, app, start_at, end_at, 'Changed');
  RAISE EXCEPTION 'Changed creation payload accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.create_work_assignment(app, start_at, end_at, 'Legacy duplicate');
  RAISE EXCEPTION 'Legacy duplicate accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 again := public.reserve_work_assignment_request(app, start_at + interval '1 hour', end_at, 'Overlap');
 BEGIN
  PERFORM public.create_work_assignment_request(again, app, start_at + interval '1 hour', end_at, 'Overlap');
  RAISE EXCEPTION 'Overlap accepted';
 EXCEPTION WHEN exclusion_violation THEN NULL; END;
 IF public.lookup_work_assignment_request(again) IS NOT NULL THEN RAISE EXCEPTION 'Rejected overlap linked an assignment'; END IF;
 again := public.reserve_work_assignment_request(app, start_at + interval '1 day', end_at + interval '1 day', 'Repeat shift');
 second_id := public.create_work_assignment_request(again, app, start_at + interval '1 day', end_at + interval '1 day', 'Repeat shift');
 IF second_id = first_id THEN RAISE EXCEPTION 'Repeat shift reused first assignment'; END IF;
 PERFORM set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000000', true);
 BEGIN
  PERFORM public.lookup_work_assignment_request(req);
  RAISE EXCEPTION 'Other account read request';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.create_work_assignment_request(req, app, start_at, end_at, 'Synthetic test');
  RAISE EXCEPTION 'Other account dispatched request';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END;
$$;
ROLLBACK;
-- Separate required review: race same request in two sessions; race different
-- actors/legacy calls for identical and overlapping intervals; confirm one insert,
-- idempotent result for same ID, rejection otherwise, and rollback releases locks.

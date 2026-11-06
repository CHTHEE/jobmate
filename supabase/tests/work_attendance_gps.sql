-- DANGER: DISPOSABLE, ISOLATED TEST DATABASE ONLY. NEVER shared/production Supabase.
-- Manual psql authorization test, not a migration or production verifier.
-- Requires the new migration plus disposable fixture IDs supplied as psql vars:
-- employer_id, outsider_id, company_id, assignment_id. outsider_id must have no
-- company access. Use synthetic fixtures, never the cafe or verified QA rows.
-- Employer must be active, with permitted membership in the verified company;
-- assignment must belong to that company. Keep populated manifests/logs private.
-- Requires the base schema and 20261106000200 in the isolated database.
-- Operator needs initial SELECT on assignment/attendance tables, permission to
-- SET ROLE authenticated, and transaction-local JWT subject configuration.
-- Do not grant these administrative test capabilities to application users.
-- Baseline SELECT prints GPS JSON: use synthetic coordinates and protect logs.
-- No application writes are intended; this is NOT a READ ONLY transaction guard.
-- Final ROLLBACK discards local settings. ON_ERROR_STOP can stop before it;
-- roll back or disconnect on error, never COMMIT. Reads acquire relation locks;
-- no explicit lock/statement timeouts are set. Prior fixture setup is not undone.
-- No Storage operations or cleanup are needed. Dispose of isolated fixtures
-- separately, never shared records. No automatic environment isolation check.
\set ON_ERROR_STOP on
BEGIN;
SELECT set_config('test.company_id', :'company_id', true);
SELECT set_config('test.assignment_id', :'assignment_id', true);
SELECT set_config('test.outsider_id', :'outsider_id', true);
SELECT set_config('request.jwt.claim.sub', :'employer_id', true);

-- Before reducing privileges, establish the exact expected stored projection.
SELECT set_config('test.expected_gps', jsonb_build_object(
    'assignment_id', a.assignment_id, 'company_id', a.company_id,
    'check_in_at', att.check_in_at, 'check_out_at', att.check_out_at,
    'check_in_location_status', att.check_in_location_status,
    'check_out_location_status', att.check_out_location_status,
    'check_in_latitude', att.check_in_latitude,
    'check_in_longitude', att.check_in_longitude,
    'check_out_latitude', att.check_out_latitude,
    'check_out_longitude', att.check_out_longitude
)::text, true)
FROM public.work_assignments a
LEFT JOIN public.work_attendance att ON att.assignment_id = a.assignment_id
WHERE a.assignment_id = :'assignment_id'::uuid AND a.company_id = :'company_id'::uuid;

SET LOCAL ROLE authenticated;
DO $test$
DECLARE
    company uuid := current_setting('test.company_id')::uuid;
    assignment uuid := current_setting('test.assignment_id')::uuid;
    result jsonb;
    total integer;
BEGIN
    SELECT count(*), jsonb_agg(to_jsonb(g))->0 INTO total, result
    FROM public.read_employer_work_attendance_gps(company, assignment) g;
    IF total <> 1 OR result IS DISTINCT FROM current_setting('test.expected_gps')::jsonb THEN
        RAISE EXCEPTION 'Authorized GPS projection differs from stored attendance';
    END IF;
    BEGIN
        PERFORM public.read_employer_work_attendance_gps(company, gen_random_uuid());
        RAISE EXCEPTION 'Unscoped assignment was accepted';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    PERFORM set_config('request.jwt.claim.sub', current_setting('test.outsider_id'), true);
    BEGIN
        PERFORM public.read_employer_work_attendance_gps(company, assignment);
        RAISE EXCEPTION 'Unauthorized account read GPS';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    PERFORM set_config('request.jwt.claim.sub', '', true);
    BEGIN
        PERFORM public.read_employer_work_attendance_gps(company, assignment);
        RAISE EXCEPTION 'Anonymous account read GPS';
    EXCEPTION WHEN invalid_authorization_specification THEN NULL;
    END;
    IF has_function_privilege('anon', 'public.read_employer_work_attendance_gps(uuid,uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'Anonymous EXECUTE grant found';
    END IF;
END;
$test$;
ROLLBACK;
-- Repeat using granted, denied, unavailable and no-attendance synthetic fixtures.
-- Also verify revoked membership/inactive employer/unverified company fixtures.

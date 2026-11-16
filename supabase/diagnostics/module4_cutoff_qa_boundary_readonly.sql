-- READ ONLY. Exact PostgreSQL predicate boundary; no business RPC or records.
-- Uses the already reviewed Batch 2 predicate guard. No clock is changed.
BEGIN READ ONLY;
DO $guard$
DECLARE p record;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'Run as postgres.'; END IF;
 SELECT f.*,l.lanname INTO p FROM pg_catalog.pg_proc f
 JOIN pg_catalog.pg_language l ON l.oid=f.prolang
 WHERE f.oid=pg_catalog.to_regprocedure('private.attendance_resolution_checkout_allowed(timestamptz,timestamptz)');
 IF NOT FOUND OR p.lanname IS DISTINCT FROM 'sql' OR p.provolatile IS DISTINCT FROM 'i'::"char"
   OR p.prosecdef IS DISTINCT FROM false OR p.prorettype IS DISTINCT FROM 'pg_catalog.bool'::regtype
   OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
   OR pg_catalog.pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'
   OR pg_catalog.md5(replace(replace(p.prosrc,chr(13)||chr(10),chr(10)),chr(13),chr(10)))
      IS DISTINCT FROM '3987d98aab7a35f87250bc684a2fd0b5' THEN
   RAISE EXCEPTION 'Reviewed predicate missing or changed. Stop before invocation.';
 END IF;
END;
$guard$;
WITH cases(label,server_time,expected) AS (VALUES
 ('one microsecond before','2026-11-06T08:59:59.999999Z'::timestamptz,true),
 ('exactly end plus 24h','2026-11-06T09:00:00Z'::timestamptz,true),
 ('one microsecond after','2026-11-06T09:00:00.000001Z'::timestamptz,false)
), results AS (SELECT *,private.attendance_resolution_checkout_allowed('2026-11-05T09:00:00Z'::timestamptz,server_time) AS actual FROM cases)
SELECT label,server_time,expected,actual,actual IS NOT DISTINCT FROM expected AS passed,
 bool_and(actual IS NOT DISTINCT FROM expected) OVER() AS all_checks_passed FROM results ORDER BY server_time;
ROLLBACK;

-- REVIEW CANDIDATE ONLY. NOT EXECUTED. Batch 1 additive read contract.
-- Operator must verify target and current baseline using the existing independent
-- work_shift_release_catalog_checks.sql (B1 31/31) and read inspection first.
-- No attendance mutation, new enum, checkout cutoff or existing RPC replacement.
-- Existing security-definer listing RPCs remain the authorization boundary.
BEGIN;
SET LOCAL lock_timeout = '2s';
SET LOCAL statement_timeout = '30s';
SET LOCAL search_path = '';
DO $guard$
BEGIN
  IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Run as postgres.'; END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN
      ('list_my_work_assignments_lifecycle','list_company_work_assignments_lifecycle')) THEN
    RAISE EXCEPTION 'Read contract name occupied; stop without replacing.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid=pg_catalog.to_regprocedure('public.list_my_work_assignments()')
      AND pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))='f9446e58502bc3f39435048c5ff7ef20')
    OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid=pg_catalog.to_regprocedure('public.list_company_work_assignments(uuid)')
      AND pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))='1107b445d7dfdba875b21e551c886ab9') THEN
    RAISE EXCEPTION 'Authorized listing baseline differs; stop and review.';
  END IF;
END;
$guard$;

CREATE FUNCTION public.list_my_work_assignments_lifecycle()
RETURNS SETOF jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $body$
  SELECT pg_catalog.to_jsonb(a) || pg_catalog.jsonb_build_object(
    'attendance_as_of', pg_catalog.statement_timestamp())
  FROM public.list_my_work_assignments() a
$body$;

CREATE FUNCTION public.list_company_work_assignments_lifecycle(p_company_id uuid)
RETURNS SETOF jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $body$
  SELECT pg_catalog.to_jsonb(a) || pg_catalog.jsonb_build_object(
    'attendance_as_of', pg_catalog.statement_timestamp())
  FROM public.list_company_work_assignments(p_company_id) a
$body$;

REVOKE ALL ON FUNCTION public.list_my_work_assignments_lifecycle()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.list_company_work_assignments_lifecycle(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_my_work_assignments_lifecycle() TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_company_work_assignments_lifecycle(uuid) TO authenticated;
DO $acl$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
    WHERE p.oid IN ('public.list_my_work_assignments_lifecycle()'::regprocedure,
      'public.list_company_work_assignments_lifecycle(uuid)'::regprocedure)
    AND (a.grantee NOT IN (p.proowner,'authenticated'::regrole)
      OR (a.grantee<>p.proowner AND a.is_grantable))) THEN
    RAISE EXCEPTION 'Unexpected default ACL; abort installation.';
  END IF;
END;
$acl$;
NOTIFY pgrst, 'reload schema';
COMMIT;

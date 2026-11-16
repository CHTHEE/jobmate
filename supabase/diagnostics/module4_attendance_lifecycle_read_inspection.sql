-- READ ONLY. No user rows or application RPC invocation. Review before/after
-- installing the separately approved candidate. Existing independent B1 check
-- remains the schedule/security drift check; do not rerun migrations.
WITH expected(signature) AS (VALUES
  ('public.list_my_work_assignments()'),
  ('public.list_company_work_assignments(uuid)'),
  ('public.list_my_work_assignments_lifecycle()'),
  ('public.list_company_work_assignments_lifecycle(uuid)'),
  ('public.check_in_work_assignment(uuid,text,numeric,numeric)'),
  ('public.check_out_work_assignment(uuid,text,numeric,numeric)'))
SELECT e.signature, p.oid IS NOT NULL AS found,
  pg_catalog.pg_get_userbyid(p.proowner) AS owner,
  p.prosecdef AS security_definer, p.proconfig, p.proacl,
  pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) AS definition_md5,
  pg_catalog.pg_get_function_result(p.oid) AS result,
  pg_catalog.pg_get_functiondef(p.oid) AS definition
FROM expected e LEFT JOIN pg_catalog.pg_proc p
  ON p.oid=pg_catalog.to_regprocedure(e.signature)
ORDER BY e.signature;

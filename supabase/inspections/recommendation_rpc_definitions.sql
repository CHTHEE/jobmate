-- Run only after approval, in the intended Shared project's SQL Editor.
-- Catalog inspection only. This does not call either application RPC.
-- Review function definitions privately and redact before sharing.
WITH wanted(name) AS (
  VALUES ('list_published_jobs'), ('list_my_job_applications')
)
SELECT
  wanted.name AS requested_function,
  p.oid IS NOT NULL AS found,
  p.oid::regprocedure AS signature,
  p.pronargs AS input_argument_count,
  p.pronargdefaults AS defaulted_input_count,
  pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
  pg_catalog.pg_get_function_result(p.oid) AS return_type,
  p.prosecdef AS security_definer,
  p.proconfig AS function_settings,
  pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
    AS authenticated_can_execute,
  pg_catalog.pg_get_functiondef(p.oid) AS definition
FROM wanted
LEFT JOIN pg_catalog.pg_proc AS p
  ON p.proname = wanted.name
 AND p.pronamespace = 'public'::regnamespace
 AND p.prokind = 'f'
ORDER BY wanted.name, p.pronargs, identity_arguments;

-- Review the no-argument overloads and any called helpers or views.
-- Published jobs: publication, moderation, company status, date type, salary
-- masking, and any LIMIT/OFFSET, row-number filter, or bounded helper.
-- Applications: caller ownership, status/history coverage, and internal caps
-- that could hide a prior application before PostgREST applies a filter.

-- Historical correction. Already applied manually and verified on Shared.
-- Do not run there again. Kept outside the automatic migration directory.
-- Guard the exact old clause rather than reconstructing the RPC. A different
-- baseline requires review. No full pre-change definition was supplied.
BEGIN;
SET LOCAL search_path = pg_catalog;

DO $patch$
DECLARE
  target oid := to_regprocedure('public.submit_job_application(uuid,uuid,text)');
  old_clause constant text := $old$if v_job.application_deadline is not null and v_job.application_deadline<current_date then
  raise exception 'The application deadline has passed.';
end if;$old$;
  new_clause constant text := $new$if v_job.application_deadline is null then
  raise exception 'This job is not accepting applications.';
end if;

if v_job.application_deadline <
    (clock_timestamp() AT TIME ZONE 'Asia/Kuala_Lumpur')::date then
  raise exception 'The application deadline has passed.';
end if;$new$;
  definition text;
  patched text;
BEGIN
  IF target IS NULL THEN
    RAISE EXCEPTION 'Expected submit_job_application(uuid,uuid,text) is missing';
  END IF;
  definition := pg_get_functiondef(target);
  patched := replace(definition, old_clause, new_clause);
  IF strpos(definition, new_clause) > 0
      OR length(definition) - length(replace(definition, old_clause, ''))
          <> length(old_clause) THEN
    RAISE EXCEPTION 'Expected exactly one original deadline clause on an unpatched baseline';
  END IF;
  IF has_function_privilege('anon', target, 'EXECUTE')
      OR NOT has_function_privilege('authenticated', target, 'EXECUTE') THEN
    RAISE EXCEPTION 'Unexpected application RPC execute privileges';
  END IF;

  EXECUTE patched;

  IF pg_get_functiondef(target) IS DISTINCT FROM patched
      OR has_function_privilege('anon', target, 'EXECUTE')
      OR NOT has_function_privilege('authenticated', target, 'EXECUTE') THEN
    RAISE EXCEPTION 'Application RPC definition or privileges failed verification';
  END IF;
END;
$patch$;

COMMIT;

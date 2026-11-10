-- NOT DEPLOYED. Separate closure-response authorization security candidate.
-- Source: work_shift_schedule_catalog_export_20261110.csv (3392 rows).
-- Changes ONE function only; no changes to helper/membership/closure-recorder,
-- trigger definitions, data, owner, ACLs or function settings. No SQL executed.
-- Review docs/work_shift_schedule_implementation_review.md before manual approval.
-- Drain closure-response activity first: replacing a function does not cancel
-- invocations already running the old body. This is not scheduling deployment.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
SET LOCAL search_path='';

DO $contracts$
DECLARE v_expected record; v_proc pg_catalog.pg_proc; v_actual_hash text;
BEGIN
  IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Run only as the exported postgres owner role.'; END IF;
  FOR v_expected IN SELECT * FROM (VALUES
('private.record_job_engagement_closure(uuid, uuid, text)','eecdf7e6d167363639b505a7dbc8a6a0','definition','postgres','{postgres=X/postgres}','["search_path=\"\""]','p_application_id uuid, p_actor_id uuid, p_reason text','p_application_id uuid, p_actor_id uuid, p_reason text','timestamp with time zone','v','DEFINER','False','False','u','False'),
('public.can_manage_company_jobs(uuid)','7c41597c243580062e49efd25af2f9f0','definition','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','p_company_id uuid','p_company_id uuid','boolean','s','DEFINER','False','False','u','False'),
('public.respond_job_engagement_closure_request(uuid, text, text)','f02b6fef2e4ae491a9ce7e6e046eea6a','definition','postgres','{postgres=X/postgres,authenticated=X/postgres}','["search_path=\"\""]','p_request_id uuid, p_decision text, p_reason text','p_request_id uuid, p_decision text, p_reason text','timestamp with time zone','v','DEFINER','False','False','u','False')
  ) x(signature,expected_hash,hash_kind,owner_name,raw_acl,settings_json,identity_args,args_with_defaults,result_type,volatility,security_mode,is_strict,is_leakproof,parallel_mode,returns_set) LOOP
    SELECT * INTO v_proc FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(v_expected.signature);
    IF NOT FOUND THEN RAISE EXCEPTION 'Missing baseline function: %',v_expected.signature; END IF;
    v_actual_hash := CASE WHEN v_expected.hash_kind='body_lf'
      THEN pg_catalog.md5(replace(replace(v_proc.prosrc,chr(13)||chr(10),chr(10)),chr(13),chr(10)))
      ELSE pg_catalog.md5(pg_catalog.pg_get_functiondef(v_proc.oid)) END;
    IF v_actual_hash IS DISTINCT FROM v_expected.expected_hash
       OR v_proc.prokind <> 'f'
       OR pg_catalog.pg_get_userbyid(v_proc.proowner)::text IS DISTINCT FROM v_expected.owner_name
       OR v_proc.proacl::text IS DISTINCT FROM v_expected.raw_acl
       OR pg_catalog.to_jsonb(v_proc.proconfig) IS DISTINCT FROM v_expected.settings_json::jsonb
       OR pg_catalog.pg_get_function_identity_arguments(v_proc.oid) IS DISTINCT FROM v_expected.identity_args
       OR pg_catalog.pg_get_function_arguments(v_proc.oid) IS DISTINCT FROM v_expected.args_with_defaults
       OR pg_catalog.pg_get_function_result(v_proc.oid) IS DISTINCT FROM v_expected.result_type
       OR v_proc.provolatile::text IS DISTINCT FROM v_expected.volatility
       OR v_proc.prosecdef IS DISTINCT FROM (v_expected.security_mode='DEFINER')
       OR v_proc.proisstrict IS DISTINCT FROM v_expected.is_strict::boolean
       OR v_proc.proleakproof IS DISTINCT FROM v_expected.is_leakproof::boolean
       OR v_proc.proparallel::text IS DISTINCT FROM v_expected.parallel_mode
       OR v_proc.proretset IS DISTINCT FROM v_expected.returns_set::boolean THEN
      RAISE EXCEPTION 'Function/security drift: %. Stop and obtain reviewed definitions; do not restore grants.',v_expected.signature;
    END IF;
  END LOOP;
END;
$contracts$;

CREATE OR REPLACE FUNCTION public.respond_job_engagement_closure_request(p_request_id uuid, p_decision text, p_reason text)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_app_id uuid; v_status text; v_closed_at timestamptz;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='28000'; end if;
  if p_decision is null or p_decision not in ('close','decline') or p_reason is null or p_reason !~ '[^[:space:]]' or char_length(p_reason)>2000 then
    raise exception 'Choose close or decline and provide a reason of 1 to 2000 characters.';
  end if;
  select r.application_id into v_app_id from public.job_engagement_closure_requests r where r.request_id=p_request_id;
  if not found then raise exception 'Closure Request not found.'; end if;
  perform 1 from public.job_applications a where a.application_id=v_app_id for update;
  if not found then raise exception 'Job Application not found.'; end if;
  select r.status into v_status from public.job_engagement_closure_requests r
    where r.request_id=p_request_id for update;
  if not found or v_status is distinct from 'pending' then raise exception 'Closure Request is no longer pending.'; end if;
  -- Re-evaluate current company authority AFTER application/request lock waits.
  -- Company identity comes only from the locked application and its stored Job.
  if not exists (
    select 1 from public.job_applications a
    join public.job_postings j on j.job_id=a.job_id
    where a.application_id=v_app_id
      and public.can_manage_company_jobs(j.company_id) is true
  ) then
    raise exception 'Current Company Representative authorization is required.' using errcode='42501';
  end if;
  if p_decision='close' then
    v_closed_at:=private.record_job_engagement_closure(v_app_id,auth.uid(),p_reason);
    return v_closed_at;
  end if;
  update public.job_engagement_closure_requests set status='declined',processed_by=auth.uid(),
    processed_at=pg_catalog.clock_timestamp(),response_reason=btrim(p_reason)
    where request_id=p_request_id;
  insert into public.job_engagement_closure_request_events(request_id,actor_id,action,reason)
    values(p_request_id,auth.uid(),'declined',btrim(p_reason));
  return null;
end
$function$


;

DO $contracts$
DECLARE v_expected record; v_proc pg_catalog.pg_proc; v_actual_hash text;
BEGIN
  IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Run only as the exported postgres owner role.'; END IF;
  FOR v_expected IN SELECT * FROM (VALUES
('private.record_job_engagement_closure(uuid, uuid, text)','eecdf7e6d167363639b505a7dbc8a6a0','definition','postgres','{postgres=X/postgres}','["search_path=\"\""]','p_application_id uuid, p_actor_id uuid, p_reason text','p_application_id uuid, p_actor_id uuid, p_reason text','timestamp with time zone','v','DEFINER','False','False','u','False'),
('public.can_manage_company_jobs(uuid)','7c41597c243580062e49efd25af2f9f0','definition','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','["search_path=\"\""]','p_company_id uuid','p_company_id uuid','boolean','s','DEFINER','False','False','u','False'),
('public.respond_job_engagement_closure_request(uuid, text, text)','8558e154e5eae1e8ea7b09c3fed41103','body_lf','postgres','{postgres=X/postgres,authenticated=X/postgres}','["search_path=\"\""]','p_request_id uuid, p_decision text, p_reason text','p_request_id uuid, p_decision text, p_reason text','timestamp with time zone','v','DEFINER','False','False','u','False')
  ) x(signature,expected_hash,hash_kind,owner_name,raw_acl,settings_json,identity_args,args_with_defaults,result_type,volatility,security_mode,is_strict,is_leakproof,parallel_mode,returns_set) LOOP
    SELECT * INTO v_proc FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(v_expected.signature);
    IF NOT FOUND THEN RAISE EXCEPTION 'Missing baseline function: %',v_expected.signature; END IF;
    v_actual_hash := CASE WHEN v_expected.hash_kind='body_lf'
      THEN pg_catalog.md5(replace(replace(v_proc.prosrc,chr(13)||chr(10),chr(10)),chr(13),chr(10)))
      ELSE pg_catalog.md5(pg_catalog.pg_get_functiondef(v_proc.oid)) END;
    IF v_actual_hash IS DISTINCT FROM v_expected.expected_hash
       OR v_proc.prokind <> 'f'
       OR pg_catalog.pg_get_userbyid(v_proc.proowner)::text IS DISTINCT FROM v_expected.owner_name
       OR v_proc.proacl::text IS DISTINCT FROM v_expected.raw_acl
       OR pg_catalog.to_jsonb(v_proc.proconfig) IS DISTINCT FROM v_expected.settings_json::jsonb
       OR pg_catalog.pg_get_function_identity_arguments(v_proc.oid) IS DISTINCT FROM v_expected.identity_args
       OR pg_catalog.pg_get_function_arguments(v_proc.oid) IS DISTINCT FROM v_expected.args_with_defaults
       OR pg_catalog.pg_get_function_result(v_proc.oid) IS DISTINCT FROM v_expected.result_type
       OR v_proc.provolatile::text IS DISTINCT FROM v_expected.volatility
       OR v_proc.prosecdef IS DISTINCT FROM (v_expected.security_mode='DEFINER')
       OR v_proc.proisstrict IS DISTINCT FROM v_expected.is_strict::boolean
       OR v_proc.proleakproof IS DISTINCT FROM v_expected.is_leakproof::boolean
       OR v_proc.proparallel::text IS DISTINCT FROM v_expected.parallel_mode
       OR v_proc.proretset IS DISTINCT FROM v_expected.returns_set::boolean THEN
      RAISE EXCEPTION 'Function/security drift: %. Stop and obtain reviewed definitions; do not restore grants.',v_expected.signature;
    END IF;
  END LOOP;
END;
$contracts$;

COMMIT;

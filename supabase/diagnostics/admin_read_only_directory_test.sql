-- ROLLBACK-ONLY authorization test for a disposable Supabase project.
-- Requires the trusted JobMate baseline plus Phase 2B, Phase 2D and
-- 20261106000500_admin_read_only_directory_details.sql. Never run in production.
-- Create the three synthetic Auth users and a synthetic Company/membership first.
begin;
do $test$
declare
  v_read_admin uuid;
  v_manager uuid;
  v_seeker uuid;
  v_company uuid;
  v_failed boolean;
  v_count bigint;
  v_user jsonb;
  v_company_details jsonb;
begin
  select u.user_id into v_read_admin from auth.users a join public.users u on u.user_id=a.id
    where lower(a.email)='admin-readonly@example.invalid';
  select u.user_id into v_manager from auth.users a join public.users u on u.user_id=a.id
    where lower(a.email)='admin-directory-manager@example.invalid';
  select u.user_id into v_seeker from auth.users a join public.users u on u.user_id=a.id
    where lower(a.email)='directory-synthetic-seeker@example.invalid';
  select c.company_id into v_company from public.companies c
    where c.company_name='ADMIN DIRECTORY SYNTHETIC COMPANY';
  if v_read_admin is null or v_manager is null or v_seeker is null or v_company is null then
    raise exception 'Create the required synthetic Admins, Job Seeker and Company first.';
  end if;
  if exists(select 1 from public.administrator_profiles ap
      where ap.user_id=v_read_admin and (ap.can_manage_user_accounts or ap.can_manage_company_restrictions)) then
    raise exception 'Read-only Admin fixture unexpectedly has a management permission.';
  end if;
  if not exists(select 1 from public.administrator_profiles ap
      where ap.user_id=v_manager and ap.can_manage_user_accounts and ap.can_manage_company_restrictions) then
    raise exception 'Manager fixture must have both management permissions.';
  end if;

  perform pg_catalog.set_config('request.jwt.claim.sub',v_read_admin::text,true);
  perform pg_catalog.set_config('request.jwt.claim.role','authenticated',true);
  perform pg_catalog.set_config('request.jwt.claims',
    pg_catalog.jsonb_build_object('sub',v_read_admin,'role','authenticated')::text,true);

  select pg_catalog.to_jsonb(d) into v_user
  from public.get_admin_user_directory_details(v_seeker) d;
  if v_user is null or v_user ? 'email' or v_user ? 'phone_num' then
    raise exception 'Read-only user projection is missing or exposes private contact fields.';
  end if;
  select count(*) into v_count from public.list_user_accounts(null,null,31,0);
  if v_count < 1 then raise exception 'Active Admin could not read the limited user directory.'; end if;

  v_company_details:=public.get_admin_company_directory_details(v_company);
  if v_company_details is null
     or v_company_details ? 'restriction_reason'
     or (v_company_details->'members'->0) ? 'user_id'
     or (v_company_details->'members'->0) ? 'account_status' then
    raise exception 'Read-only Company projection is missing or exposes restricted fields.';
  end if;
  select count(*) into v_count from public.list_admin_company_directory(31,0);
  if v_count < 1 then raise exception 'Active Admin could not read Company directory.'; end if;

  v_failed:=false;
  begin perform * from public.get_user_account_details(v_seeker);
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'Read-only Admin accessed the protected user-management details RPC.'; end if;

  v_failed:=false;
  begin perform public.set_user_account_status(v_seeker,'suspend','Synthetic denial test');
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'Read-only Admin suspended an account.'; end if;

  v_failed:=false;
  begin perform public.set_company_restriction(v_company,'restrict','Synthetic denial test');
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'Read-only Admin restricted a Company.'; end if;

  raise notice 'Read-only directory projections and denied management actions passed for synthetic fixtures.';
end;
$test$;
rollback;

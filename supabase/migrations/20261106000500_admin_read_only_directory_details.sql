-- Phase 3A.1: Safe read-only Admin directory projections.
-- PREPARED ONLY; do not apply to a live project without isolated authorization
-- tests. Requires Phase 2B and Phase 2D tables/columns. Does not grant any
-- account-suspension, Company restriction, Company verification, or audit access.
begin;

do $preflight$
begin
  if pg_catalog.to_regclass('public.users') is null
     or pg_catalog.to_regclass('public.companies') is null
     or pg_catalog.to_regclass('public.company_memberships') is null
     or pg_catalog.to_regclass('public.company_restrictions') is null
     or pg_catalog.to_regclass('public.administrator_profiles') is null then
    raise exception 'Apply the existing JobMate user, company, Phase 2B and Phase 2D schema first.';
  end if;
  if pg_catalog.to_regprocedure('public.get_admin_user_directory_details(uuid)') is not null
     or pg_catalog.to_regprocedure('public.list_admin_company_directory(integer,integer)') is not null
     or pg_catalog.to_regprocedure('public.get_admin_company_directory_details(uuid)') is not null then
    raise exception 'A read-only Admin directory RPC already exists; inspect and reuse it.';
  end if;
end;
$preflight$;

create function public.get_admin_user_directory_details(p_user_id uuid)
returns table(
  user_id uuid,
  name text,
  role text,
  account_status text,
  verification_status text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if not exists (
    select 1 from public.users actor
    where actor.user_id=auth.uid()
      and actor.role='administrator'::public.user_role
      and actor.status='active'::public.account_status
  ) then
    raise exception 'An active administrator account is required.';
  end if;
  if p_user_id is null then raise exception 'User ID is required.'; end if;
  return query
  select u.user_id,u.name::text,u.role::text,u.status::text,
         u.verification_status::text,u.created_at
  from public.users u
  where u.user_id=p_user_id
    and u.role in ('job_seeker'::public.user_role,'employer'::public.user_role);
end;
$function$;

create function public.list_admin_company_directory(
  p_limit integer default 31,
  p_offset integer default 0
)
returns table(
  company_id uuid,
  company_name text,
  verification_status text,
  restriction_status text,
  restricted_at timestamptz,
  industry text,
  location text,
  created_at timestamptz,
  member_count bigint
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if not exists (
    select 1 from public.users u
    where u.user_id=auth.uid()
      and u.role='administrator'::public.user_role
      and u.status='active'::public.account_status
  ) then
    raise exception 'An active administrator account is required.';
  end if;
  if p_limit is null or p_limit not between 1 and 101
     or p_offset is null or p_offset < 0 then
    raise exception 'Invalid page size or offset.';
  end if;
  return query
  select c.company_id,c.company_name::text,c.verification_status::text,
         r.restriction_status,
         case when r.restriction_status='restricted' then r.changed_at end,
         c.industry::text,c.location::text,c.created_at,
         (select pg_catalog.count(*) from public.company_memberships m
          where m.company_id=c.company_id)
  from public.companies c
  join public.company_restrictions r on r.company_id=c.company_id
  order by pg_catalog.lower(c.company_name),c.company_id
  limit p_limit offset p_offset;
end;
$function$;

create function public.get_admin_company_directory_details(p_company_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare v_result jsonb;
begin
  if not exists (
    select 1 from public.users u
    where u.user_id=auth.uid()
      and u.role='administrator'::public.user_role
      and u.status='active'::public.account_status
  ) then
    raise exception 'An active administrator account is required.';
  end if;
  if p_company_id is null then raise exception 'Company ID is required.'; end if;

  select pg_catalog.jsonb_build_object(
    'company_id',c.company_id,
    'company_name',c.company_name,
    'company_description',c.company_description,
    'industry',c.industry,
    'location',c.location,
    'verification_status',c.verification_status,
    'restriction_status',r.restriction_status,
    'restricted_at',case when r.restriction_status='restricted' then r.changed_at end,
    'created_at',c.created_at,
    'members',coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object('name',u.name,'member_role',m.member_role)
        order by m.member_role,u.name
      )
      from public.company_memberships m
      join public.users u on u.user_id=m.user_id
      where m.company_id=c.company_id
    ),'[]'::jsonb)
  ) into v_result
  from public.companies c
  join public.company_restrictions r on r.company_id=c.company_id
  where c.company_id=p_company_id;

  if v_result is null then raise exception 'Company not found.'; end if;
  return v_result;
end;
$function$;

revoke all on function public.get_admin_user_directory_details(uuid),
  public.list_admin_company_directory(integer,integer),
  public.get_admin_company_directory_details(uuid) from public,anon;
grant execute on function public.get_admin_user_directory_details(uuid),
  public.list_admin_company_directory(integer,integer),
  public.get_admin_company_directory_details(uuid) to authenticated;

notify pgrst,'reload schema';
commit;

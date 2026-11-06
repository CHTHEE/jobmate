-- Phase 2B. Prepared only; do not apply before isolated authorization tests.
-- Reuses public.users.status and public.account_status. No auth.users writes.
begin;

alter table public.administrator_profiles
  add column can_manage_user_accounts boolean not null default false;

do $preflight$
begin
  if pg_catalog.has_column_privilege('authenticated', 'public.users', 'status', 'UPDATE')
     or pg_catalog.has_column_privilege('anon', 'public.users', 'status', 'UPDATE')
     or pg_catalog.has_column_privilege('authenticated', 'public.administrator_profiles', 'can_manage_user_accounts', 'UPDATE')
     or pg_catalog.has_column_privilege('anon', 'public.administrator_profiles', 'can_manage_user_accounts', 'UPDATE') then
    raise exception 'Client roles must not have UPDATE access to account status or User Management permission.';
  end if;
end;
$preflight$;

-- One append-only server-written record for account restrictions and grants.
create table public.admin_account_action_audit (
  action_id uuid primary key default pg_catalog.gen_random_uuid(),
  actor_user_id uuid not null references public.users(user_id) on delete restrict,
  target_user_id uuid not null references public.users(user_id) on delete restrict,
  action text not null check (action in (
    'suspended', 'reactivated', 'user_management_granted',
    'user_management_revoked'
  )),
  previous_status public.account_status,
  new_status public.account_status,
  previous_permission boolean,
  new_permission boolean,
  reason text,
  performed_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint admin_account_action_audit_shape check (coalesce((
    (action = 'suspended' and previous_status = 'active'
      and new_status = 'suspended' and previous_permission is null
      and new_permission is null and reason ~ '[^[:space:]]'
      and pg_catalog.length(pg_catalog.btrim(reason)) between 1 and 2000)
    or (action = 'reactivated' and previous_status = 'suspended'
      and new_status = 'active' and previous_permission is null
      and new_permission is null and reason ~ '[^[:space:]]'
      and pg_catalog.length(pg_catalog.btrim(reason)) between 1 and 2000)
    or (action = 'user_management_granted' and previous_status is null
      and new_status is null and previous_permission = false
      and new_permission = true and reason is null)
    or (action = 'user_management_revoked' and previous_status is null
      and new_status is null and previous_permission = true
      and new_permission = false and reason is null)
  ), false))
);
create index admin_account_action_audit_target_time
  on public.admin_account_action_audit(target_user_id, performed_at desc, action_id desc);
alter table public.admin_account_action_audit enable row level security;
revoke all on public.admin_account_action_audit from public, anon, authenticated, service_role;

do $audit_grant_preflight$
declare
  v_role text;
  v_privilege text;
begin
  for v_role in select unnest(array['anon', 'authenticated', 'service_role'])
  loop
    for v_privilege in select unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'])
    loop
      if pg_catalog.has_table_privilege(v_role, 'public.admin_account_action_audit', v_privilege) then
        raise exception 'Role % retains % on the account audit table; inspect inherited grants.', v_role, v_privilege;
      end if;
    end loop;
  end loop;
end;
$audit_grant_preflight$;

create or replace function private.prevent_admin_account_audit_changes()
returns trigger language plpgsql security definer set search_path to ''
as $function$
begin
  raise exception 'Admin account audit entries are append-only.';
end;
$function$;
revoke all on function private.prevent_admin_account_audit_changes()
  from public, anon, authenticated;
create trigger admin_account_audit_append_only
before update or delete on public.admin_account_action_audit
for each row execute function private.prevent_admin_account_audit_changes();
create trigger admin_account_audit_no_truncate
before truncate on public.admin_account_action_audit
for each statement execute function private.prevent_admin_account_audit_changes();

-- Only an active Superadmin may grant/revoke this dedicated permission.
create function public.set_admin_user_management_permission(
  p_target_user_id uuid, p_can_manage boolean
)
returns void language plpgsql security definer set search_path to ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_previous boolean;
begin
  if v_actor_id is null or p_target_user_id is null or p_can_manage is null
     or v_actor_id = p_target_user_id then
    raise exception 'A different administrator and permission value are required.';
  end if;

  perform u.user_id from public.users u
  where u.user_id in (v_actor_id, p_target_user_id)
  order by u.user_id for update;
  perform ap.user_id from public.administrator_profiles ap
  where ap.user_id in (v_actor_id, p_target_user_id)
  order by ap.user_id for update;

  if not exists (
    select 1 from public.users u
    join public.administrator_profiles ap on ap.user_id = u.user_id
    where u.user_id = v_actor_id
      and u.role = 'administrator'::public.user_role
      and u.status = 'active'::public.account_status
      and ap.can_manage_admin_permissions = true
  ) then
    raise exception 'Only the active Superadmin can manage administrator permissions.';
  end if;

  select ap.can_manage_user_accounts into v_previous
  from public.administrator_profiles ap
  join public.users u on u.user_id = ap.user_id
  where ap.user_id = p_target_user_id
    and u.role = 'administrator'::public.user_role
    and u.status = 'active'::public.account_status;
  if not found then
    raise exception 'Target must be an active administrator.';
  end if;
  if v_previous = p_can_manage then return; end if;

  update public.administrator_profiles
  set can_manage_user_accounts = p_can_manage
  where user_id = p_target_user_id;

  insert into public.admin_account_action_audit(
    actor_user_id, target_user_id, action, previous_permission, new_permission
  ) values (
    v_actor_id, p_target_user_id,
    case when p_can_manage then 'user_management_granted'
         else 'user_management_revoked' end,
    v_previous, p_can_manage
  );
end;
$function$;
revoke all on function public.set_admin_user_management_permission(uuid,boolean)
  from public, anon;
grant execute on function public.set_admin_user_management_permission(uuid,boolean)
  to authenticated;

-- Deliberately leaves existing list_admin_accounts_v2 signature unchanged.
create function public.list_admin_accounts_v3(
  p_limit integer default 21, p_offset integer default 0
)
returns table(
  user_id uuid, name text, email text, account_status text,
  can_manage_admin_permissions boolean, can_invite_admins boolean,
  can_review_companies boolean, can_manage_user_accounts boolean
)
language plpgsql stable security definer set search_path to ''
as $function$
begin
  if not exists (
    select 1 from public.users u
    join public.administrator_profiles ap on ap.user_id = u.user_id
    where u.user_id = auth.uid() and u.role = 'administrator'::public.user_role
      and u.status = 'active'::public.account_status
      and ap.can_manage_admin_permissions = true
  ) then
    raise exception 'Only the active Superadmin can manage administrator permissions.';
  end if;
  if p_limit is null or p_limit not between 1 and 101
     or p_offset is null or p_offset < 0 then
    raise exception 'Invalid page size or offset.';
  end if;
  return query
  select u.user_id, u.name::text, a.email::text, u.status::text,
         ap.can_manage_admin_permissions, ap.can_invite_admins,
         ap.can_review_companies, ap.can_manage_user_accounts
  from public.users u
  join public.administrator_profiles ap on ap.user_id = u.user_id
  join auth.users a on a.id = u.user_id
  where u.role = 'administrator'::public.user_role
  order by pg_catalog.lower(u.name), u.user_id
  limit p_limit offset p_offset;
end;
$function$;
revoke all on function public.list_admin_accounts_v3(integer,integer)
  from public, anon;
grant execute on function public.list_admin_accounts_v3(integer,integer)
  to authenticated;

create function public.get_user_account_details(p_target_user_id uuid)
returns table(
  user_id uuid, name text, email text, phone_num text, role text,
  account_status text, verification_status text, created_at timestamptz,
  company_id uuid, company_name text, member_role text
)
language plpgsql stable security definer set search_path to ''
as $function$
begin
  if not exists (
    select 1 from public.users u
    join public.administrator_profiles ap on ap.user_id = u.user_id
    where u.user_id = auth.uid() and u.role = 'administrator'::public.user_role
      and u.status = 'active'::public.account_status
      and ap.can_manage_user_accounts = true
  ) then
    raise exception 'User Management permission is required.';
  end if;
  if p_target_user_id is null then raise exception 'User ID is required.'; end if;
  return query
  select u.user_id, u.name::text, a.email::text, u.phone_num::text,
         u.role::text, u.status::text, u.verification_status::text,
         u.created_at, m.company_id, c.company_name::text, m.member_role
  from public.users u
  join auth.users a on a.id = u.user_id
  left join public.company_memberships m on m.user_id = u.user_id
  left join public.companies c on c.company_id = m.company_id
  where u.user_id = p_target_user_id
    and u.role in ('job_seeker'::public.user_role, 'employer'::public.user_role);
end;
$function$;
revoke all on function public.get_user_account_details(uuid) from public, anon;
grant execute on function public.get_user_account_details(uuid) to authenticated;

create function public.list_user_account_actions(
  p_target_user_id uuid, p_limit integer default 51, p_offset integer default 0
)
returns table(
  action_id uuid, action text, previous_status text, new_status text,
  reason text, performed_at timestamptz, actor_user_id uuid, actor_name text
)
language plpgsql stable security definer set search_path to ''
as $function$
begin
  if not exists (
    select 1 from public.users u
    join public.administrator_profiles ap on ap.user_id = u.user_id
    where u.user_id = auth.uid() and u.role = 'administrator'::public.user_role
      and u.status = 'active'::public.account_status
      and ap.can_manage_user_accounts = true
  ) then
    raise exception 'User Management permission is required.';
  end if;
  if p_target_user_id is null or p_limit is null or p_limit not between 1 and 101
     or p_offset is null or p_offset < 0 then
    raise exception 'Invalid history request.';
  end if;
  return query
  select h.action_id, h.action, h.previous_status::text,
         h.new_status::text, h.reason, h.performed_at,
         h.actor_user_id, actor.name::text
  from public.admin_account_action_audit h
  join public.users actor on actor.user_id = h.actor_user_id
  join public.users target on target.user_id = h.target_user_id
  where h.target_user_id = p_target_user_id
    and target.role in ('job_seeker'::public.user_role, 'employer'::public.user_role)
  order by h.performed_at desc, h.action_id desc
  limit p_limit offset p_offset;
end;
$function$;
revoke all on function public.list_user_account_actions(uuid,integer,integer)
  from public, anon;
grant execute on function public.list_user_account_actions(uuid,integer,integer)
  to authenticated;

create function public.set_user_account_status(
  p_target_user_id uuid, p_action text, p_reason text default null
)
returns text language plpgsql security definer set search_path to ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_target public.users%rowtype;
  v_reason text := nullif(pg_catalog.btrim(p_reason), '');
  v_new_status public.account_status;
begin
  if v_actor_id is null or p_target_user_id is null
     or p_target_user_id = v_actor_id then
    raise exception 'A different target account is required.';
  end if;
  if p_action not in ('suspend', 'reactivate') or p_action is null then
    raise exception 'Invalid account action.';
  end if;
  if v_reason is null or v_reason !~ '[^[:space:]]'
     or pg_catalog.length(v_reason) > 2000 then
    raise exception 'Account status changes require a reason of 1 to 2000 characters.';
  end if;

  perform u.user_id from public.users u
  where u.user_id in (v_actor_id, p_target_user_id)
  order by u.user_id for update;
  perform ap.user_id from public.administrator_profiles ap
  where ap.user_id = v_actor_id for share;
  if not exists (
    select 1 from public.users u
    join public.administrator_profiles ap on ap.user_id = u.user_id
    where u.user_id = v_actor_id and u.role = 'administrator'::public.user_role
      and u.status = 'active'::public.account_status
      and ap.can_manage_user_accounts = true
  ) then
    raise exception 'User Management permission is required.';
  end if;

  select * into v_target from public.users u
  where u.user_id = p_target_user_id;
  if not found or v_target.role not in
       ('job_seeker'::public.user_role, 'employer'::public.user_role) then
    raise exception 'Only Job Seeker and Employer accounts can be changed here.';
  end if;
  if (p_action = 'suspend' and v_target.status <> 'active'::public.account_status)
     or (p_action = 'reactivate' and v_target.status <> 'suspended'::public.account_status) then
    raise exception 'Account status changed. Refresh and try again.';
  end if;

  v_new_status := case when p_action = 'suspend'
    then 'suspended'::public.account_status
    else 'active'::public.account_status end;
  update public.users set status = v_new_status where user_id = p_target_user_id;
  insert into public.admin_account_action_audit(
    actor_user_id, target_user_id, action, previous_status, new_status, reason
  ) values (
    v_actor_id, p_target_user_id,
    case when p_action = 'suspend' then 'suspended' else 'reactivated' end,
    v_target.status, v_new_status, v_reason
  );
  insert into public.notifications(user_id, notification_type, title, message)
  values (
    p_target_user_id, 'account_' || p_action,
    case when p_action = 'suspend' then 'Account suspended'
         else 'Account reactivated' end,
    case when p_action = 'suspend'
      then 'Your JobMate account was suspended. Reason: ' || v_reason
      else 'Your JobMate account is active again. Reason: ' || v_reason end
  );
  return v_new_status::text;
end;
$function$;
revoke all on function public.set_user_account_status(uuid,text,text)
  from public, anon;
grant execute on function public.set_user_account_status(uuid,text,text)
  to authenticated;

-- Allows a suspended user to see the reason at the account gate, while the
-- normal notification RPC remains active-account-only.
create function public.get_my_account_restriction()
returns jsonb language sql stable security definer set search_path to ''
as $function$
  select case when u.status = 'suspended'::public.account_status then
    (select pg_catalog.jsonb_build_object(
       'reason', h.reason, 'performed_at', h.performed_at)
     from public.admin_account_action_audit h
     where h.target_user_id = u.user_id and h.action = 'suspended'
     order by h.performed_at desc, h.action_id desc limit 1)
  else null end
  from public.users u where u.user_id = auth.uid();
$function$;
revoke all on function public.get_my_account_restriction() from public, anon;
grant execute on function public.get_my_account_restriction() to authenticated;

notify pgrst, 'reload schema';
commit;

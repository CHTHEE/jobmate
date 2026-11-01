begin;

-- Superadmin assigns Company Review access explicitly. New administrators do
-- not receive this permission automatically.
alter table public.administrator_profiles
  add column can_review_companies boolean not null default false;

-- Permission changes are made through this function so an administrator
-- cannot use the client API to change their own permissions or promote others.
create or replace function public.set_admin_permissions(
  p_target_user_id uuid,
  p_can_invite_admins boolean,
  p_can_review_companies boolean
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_previous_invite boolean;
begin
  if v_actor_id is null then
    raise exception 'Please log in first.';
  end if;

  if p_target_user_id is null
     or p_can_invite_admins is null
     or p_can_review_companies is null then
    raise exception 'Target account and permission values are required.';
  end if;

  if p_target_user_id = v_actor_id then
    raise exception 'You cannot change your own administrator permissions.';
  end if;

  perform u.user_id
  from public.users as u
  where u.user_id in (v_actor_id, p_target_user_id)
  order by u.user_id
  for update;

  perform ap.user_id
  from public.administrator_profiles as ap
  where ap.user_id in (v_actor_id, p_target_user_id)
  order by ap.user_id
  for update;

  if not exists (
    select 1
    from public.users as u
    join public.administrator_profiles as ap on ap.user_id = u.user_id
    where u.user_id = v_actor_id
      and u.role = 'administrator'::public.user_role
      and u.status = 'active'::public.account_status
      and ap.can_manage_admin_permissions = true
  ) then
    raise exception 'Only the active Superadmin can manage administrator permissions.';
  end if;

  select ap.can_invite_admins
  into v_previous_invite
  from public.administrator_profiles as ap
  join public.users as u on u.user_id = ap.user_id
  where ap.user_id = p_target_user_id
    and u.role = 'administrator'::public.user_role;

  if not found then
    raise exception 'Target account is not an administrator.';
  end if;

  update public.administrator_profiles
  set can_invite_admins = p_can_invite_admins,
      can_review_companies = p_can_review_companies
  where user_id = p_target_user_id;

  -- Revoke every invitation that has not been accepted when the sender loses
  -- invite access. The Edge Function also checks permission before delivery.
  if v_previous_invite and not p_can_invite_admins then
    update public.admin_invitations
    set status = 'revoked',
        revoked_at = pg_catalog.now(),
        revoked_by = v_actor_id,
        revocation_reason = 'Invitation permission revoked by Superadmin.'
    where invited_by = p_target_user_id
      and status in ('preparing', 'pending')
      and accepted_at is null;
  end if;
end;
$function$;

revoke all on function public.set_admin_permissions(uuid, boolean, boolean)
  from public, anon;
grant execute on function public.set_admin_permissions(uuid, boolean, boolean)
  to authenticated;

-- Keep the existing client RPC compatible while enforcing the self-change
-- restriction and invitation revocation rule server-side.
create or replace function public.set_admin_invitation_permission(
  p_target_user_id uuid,
  p_can_invite boolean
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_can_review boolean;
begin
  if v_actor_id is null then
    raise exception 'Please log in first.';
  end if;
  if p_target_user_id is null or p_can_invite is null then
    raise exception 'Target user and permission are required.';
  end if;
  if p_target_user_id = v_actor_id then
    raise exception 'You cannot change your own administrator permissions.';
  end if;

  perform u.user_id
  from public.users as u
  where u.user_id in (v_actor_id, p_target_user_id)
  order by u.user_id
  for update;

  perform ap.user_id
  from public.administrator_profiles as ap
  where ap.user_id in (v_actor_id, p_target_user_id)
  order by ap.user_id
  for update;

  if not exists (
    select 1
    from public.users as u
    join public.administrator_profiles as ap on ap.user_id = u.user_id
    where u.user_id = v_actor_id
      and u.role = 'administrator'::public.user_role
      and u.status = 'active'::public.account_status
      and ap.can_manage_admin_permissions = true
  ) then
    raise exception 'Only the active Superadmin can manage administrator permissions.';
  end if;

  select ap.can_review_companies
  into v_can_review
  from public.administrator_profiles as ap
  where ap.user_id = p_target_user_id;

  if not found then
    raise exception 'Target account is not an administrator.';
  end if;

  perform public.set_admin_permissions(
    p_target_user_id,
    p_can_invite,
    v_can_review
  );
end;
$function$;

revoke all on function public.set_admin_invitation_permission(uuid, boolean)
  from public, anon;
grant execute on function public.set_admin_invitation_permission(uuid, boolean)
  to authenticated;

create or replace function public.list_admin_accounts_v2(
  p_limit integer default 21,
  p_offset integer default 0
)
returns table(
  user_id uuid,
  name text,
  email text,
  account_status text,
  can_manage_admin_permissions boolean,
  can_invite_admins boolean,
  can_review_companies boolean
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if not exists (
    select 1
    from public.users as u
    join public.administrator_profiles as ap on ap.user_id = u.user_id
    where u.user_id = auth.uid()
      and u.role = 'administrator'::public.user_role
      and u.status = 'active'::public.account_status
      and ap.can_manage_admin_permissions = true
  ) then
    raise exception 'Only the active Superadmin can manage administrator permissions.';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 101 then
    raise exception 'Invalid page size.';
  end if;
  if p_offset is null or p_offset < 0 then
    raise exception 'Invalid page offset.';
  end if;

  return query
  select u.user_id,
         u.name::text,
         a.email::text,
         u.status::text,
         ap.can_manage_admin_permissions,
         ap.can_invite_admins,
         ap.can_review_companies
  from public.users as u
  join public.administrator_profiles as ap on ap.user_id = u.user_id
  join auth.users as a on a.id = u.user_id
  where u.role = 'administrator'::public.user_role
  order by pg_catalog.lower(u.name), u.user_id
  limit p_limit
  offset p_offset;
end;
$function$;

revoke all on function public.list_admin_accounts_v2(integer, integer)
  from public, anon;
grant execute on function public.list_admin_accounts_v2(integer, integer)
  to authenticated;

create or replace function public.list_user_accounts(
  p_role text default null,
  p_status text default null,
  p_limit integer default 31,
  p_offset integer default 0
)
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
    select 1
    from public.users as u
    where u.user_id = auth.uid()
      and u.role = 'administrator'::public.user_role
      and u.status = 'active'::public.account_status
  ) then
    raise exception 'An active administrator account is required.';
  end if;
  if p_role is not null and p_role not in ('job_seeker', 'employer') then
    raise exception 'Invalid user role filter.';
  end if;
  if p_status is not null
     and p_status not in ('active', 'suspended', 'deactivated') then
    raise exception 'Invalid account status filter.';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 101 then
    raise exception 'Invalid page size.';
  end if;
  if p_offset is null or p_offset < 0 then
    raise exception 'Invalid page offset.';
  end if;

  return query
  select u.user_id,
         u.name::text,
         u.role::text,
         u.status::text,
         u.verification_status::text,
         u.created_at
  from public.users as u
  where u.role in (
          'job_seeker'::public.user_role,
          'employer'::public.user_role
        )
    and (p_role is null or u.role::text = p_role)
    and (p_status is null or u.status::text = p_status)
  order by u.created_at desc, u.user_id
  limit p_limit
  offset p_offset;
end;
$function$;

revoke all on function public.list_user_accounts(text, text, integer, integer)
  from public, anon;
grant execute on function public.list_user_accounts(text, text, integer, integer)
  to authenticated;

create or replace function public.list_company_review_requests(
  p_limit integer default 21,
  p_offset integer default 0
)
returns table(
  request_id uuid,
  company_id uuid,
  company_name text,
  submitted_by uuid,
  profile_snapshot jsonb,
  storage_path text,
  original_name text,
  mime_type text,
  size_bytes bigint,
  submitted_at timestamptz
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if not exists (
    select 1
    from public.users as u
    join public.administrator_profiles as ap on ap.user_id = u.user_id
    where u.user_id = auth.uid()
      and u.role = 'administrator'::public.user_role
      and u.status = 'active'::public.account_status
      and ap.can_review_companies = true
  ) then
    raise exception 'You do not have permission to review Companies.';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 101 then
    raise exception 'Invalid page size.';
  end if;
  if p_offset is null or p_offset < 0 then
    raise exception 'Invalid page offset.';
  end if;

  return query
  select r.request_id,
         r.company_id,
         c.company_name::text,
         r.submitted_by,
         r.profile_snapshot,
         r.storage_path,
         r.original_name::text,
         r.mime_type,
         r.size_bytes,
         r.submitted_at
  from public.company_verification_requests as r
  join public.companies as c on c.company_id = r.company_id
  where r.status = 'pending'::public.verification_status
  order by r.submitted_at, r.request_id
  limit p_limit
  offset p_offset;
end;
$function$;

revoke all on function public.list_company_review_requests(integer, integer)
  from public, anon;
grant execute on function public.list_company_review_requests(integer, integer)
  to authenticated;

create table public.notifications (
  notification_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(user_id) on delete cascade,
  notification_type text not null,
  title text not null,
  message text not null,
  created_at timestamptz not null default pg_catalog.now(),
  read_at timestamptz
);

alter table public.notifications enable row level security;
revoke all on table public.notifications from public, anon, authenticated;

create or replace function public.list_my_notifications(
  p_limit integer default 31,
  p_offset integer default 0
)
returns table(
  notification_id uuid,
  notification_type text,
  title text,
  message text,
  created_at timestamptz,
  read_at timestamptz
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if not exists (
    select 1 from public.users as u
    where u.user_id = auth.uid()
      and u.status = 'active'::public.account_status
  ) then
    raise exception 'An active account is required.';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 101 then
    raise exception 'Invalid page size.';
  end if;
  if p_offset is null or p_offset < 0 then
    raise exception 'Invalid page offset.';
  end if;

  return query
  select n.notification_id, n.notification_type, n.title, n.message,
         n.created_at, n.read_at
  from public.notifications as n
  where n.user_id = auth.uid()
  order by n.created_at desc, n.notification_id
  limit p_limit
  offset p_offset;
end;
$function$;

revoke all on function public.list_my_notifications(integer, integer)
  from public, anon;
grant execute on function public.list_my_notifications(integer, integer)
  to authenticated;

create or replace function public.mark_my_notification_read(
  p_notification_id uuid
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if p_notification_id is null then
    raise exception 'Notification ID is required.';
  end if;
  if not exists (
    select 1 from public.users as u
    where u.user_id = auth.uid()
      and u.status = 'active'::public.account_status
  ) then
    raise exception 'An active account is required.';
  end if;

  update public.notifications
  set read_at = coalesce(read_at, pg_catalog.now())
  where notification_id = p_notification_id
    and user_id = auth.uid();

  if not found then
    raise exception 'Notification was not found.';
  end if;
end;
$function$;

revoke all on function public.mark_my_notification_read(uuid)
  from public, anon;
grant execute on function public.mark_my_notification_read(uuid)
  to authenticated;

create or replace function public.review_company_request(
  p_request_id uuid,
  p_decision text,
  p_review_comment text default null
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_company_id uuid;
  v_submitted_by uuid;
  v_company_name text;
  v_comment text := nullif(pg_catalog.btrim(p_review_comment), '');
begin
  if v_actor_id is null then
    raise exception 'Please log in first.';
  end if;
  if p_request_id is null
     or p_decision is null
     or p_decision not in ('verified', 'rejected') then
    raise exception 'Choose a valid Company review decision.';
  end if;
  if p_decision = 'rejected' and v_comment is null then
    raise exception 'A rejection reason is required.';
  end if;
  if v_comment is not null and pg_catalog.length(v_comment) > 2000 then
    raise exception 'Review comments must be 2000 characters or fewer.';
  end if;
  if not exists (
    select 1
    from public.users as u
    join public.administrator_profiles as ap on ap.user_id = u.user_id
    where u.user_id = v_actor_id
      and u.role = 'administrator'::public.user_role
      and u.status = 'active'::public.account_status
      and ap.can_review_companies = true
  ) then
    raise exception 'You do not have permission to review Companies.';
  end if;

  select r.company_id, r.submitted_by, c.company_name::text
  into v_company_id, v_submitted_by, v_company_name
  from public.company_verification_requests as r
  join public.companies as c on c.company_id = r.company_id
  where r.request_id = p_request_id
    and r.status = 'pending'::public.verification_status
  for update;

  if not found then
    raise exception 'This Company request is no longer pending.';
  end if;

  perform c.company_id
  from public.companies as c
  where c.company_id = v_company_id
  for update;

  if not found then
    raise exception 'Company record was not found.';
  end if;

  update public.company_verification_requests
  set status = p_decision::public.verification_status,
      reviewed_at = pg_catalog.now(),
      reviewed_by = v_actor_id,
      review_comment = v_comment
  where request_id = p_request_id;

  update public.companies
  set verification_status = p_decision::public.verification_status,
      updated_at = pg_catalog.now()
  where company_id = v_company_id;

  insert into public.notifications (
    user_id,
    notification_type,
    title,
    message
  ) values (
    v_submitted_by,
    'company_review',
    case when p_decision = 'verified'
      then 'Company application approved'
      else 'Company application rejected'
    end,
    case when p_decision = 'verified'
      then pg_catalog.format(
        'Your Company application for %s has been approved.',
        v_company_name
      )
      else pg_catalog.format(
        'Your Company application for %s was rejected. Reason: %s',
        v_company_name,
        v_comment
      )
    end
  );

  return p_decision;
end;
$function$;

revoke all on function public.review_company_request(uuid, text, text)
  from public, anon;
grant execute on function public.review_company_request(uuid, text, text)
  to authenticated;

create or replace function public.get_admin_dashboard_summary()
returns table(
  registered_users bigint,
  pending_company_reviews bigint,
  administrator_accounts bigint
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if not exists (
    select 1
    from public.users as u
    where u.user_id = auth.uid()
      and u.role = 'administrator'::public.user_role
      and u.status = 'active'::public.account_status
  ) then
    raise exception 'An active administrator account is required.';
  end if;

  return query
  select (
           select pg_catalog.count(*)
           from public.users as u
           where u.role in (
             'job_seeker'::public.user_role,
             'employer'::public.user_role
           )
         ),
         (
           select pg_catalog.count(*)
           from public.company_verification_requests as r
           where r.status = 'pending'::public.verification_status
         ),
         (
           select pg_catalog.count(*)
           from public.users as u
           where u.role = 'administrator'::public.user_role
         );
end;
$function$;

revoke all on function public.get_admin_dashboard_summary()
  from public, anon;
grant execute on function public.get_admin_dashboard_summary()
  to authenticated;

-- Do not expose Company review details or private supporting files to
-- administrators who have not been granted review permission.
drop policy if exists companies_select_internal on public.companies;
create policy companies_select_internal
on public.companies
for select
to authenticated
using (
  exists (
    select 1
    from public.users as u
    where u.user_id = (select auth.uid())
      and u.status = 'active'::public.account_status
      and (
        exists (
          select 1
          from public.company_memberships as m
          where m.company_id = companies.company_id
            and m.user_id = u.user_id
        )
        or (
          u.role = 'administrator'::public.user_role
          and exists (
            select 1
            from public.administrator_profiles as ap
            where ap.user_id = u.user_id
              and ap.can_review_companies = true
          )
        )
      )
  )
);

drop policy if exists company_verification_requests_select
  on public.company_verification_requests;
create policy company_verification_requests_select
on public.company_verification_requests
for select
to authenticated
using (
  exists (
    select 1
    from public.users as u
    where u.user_id = (select auth.uid())
      and u.status = 'active'::public.account_status
      and (
        company_verification_requests.submitted_by = u.user_id
        or (
          u.role = 'administrator'::public.user_role
          and exists (
            select 1
            from public.administrator_profiles as ap
            where ap.user_id = u.user_id
              and ap.can_review_companies = true
          )
        )
      )
  )
);

drop policy if exists company_verification_files_select on storage.objects;
create policy company_verification_files_select
on storage.objects
for select
to authenticated
using (
  bucket_id = 'jobmate-company-verification'
  and exists (
    select 1
    from public.users as u
    where u.user_id = (select auth.uid())
      and u.status = 'active'::public.account_status
      and (
        (storage.foldername(objects.name))[1] = u.user_id::text
        or (
          u.role = 'administrator'::public.user_role
          and exists (
            select 1
            from public.administrator_profiles as ap
            where ap.user_id = u.user_id
              and ap.can_review_companies = true
          )
        )
      )
  )
);

notify pgrst, 'reload schema';
commit;

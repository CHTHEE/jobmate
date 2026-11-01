begin;

-- Stop before changing anything if historic membership data conflicts with the
-- permanent single-Owner rule.
do $$
begin
  if exists (
    select 1
    from public.company_memberships
    where member_role = 'owner'
    group by company_id
    having count(*) > 1
  ) then
    raise exception 'A Company has more than one Owner. Fix the membership data first.';
  end if;

  if exists (
    select 1
    from public.users u
    join public.company_memberships cm
      on cm.user_id = u.user_id
    where cm.member_role = 'owner'
      and u.role::text not in ('job_seeker', 'employer')
  ) then
    raise exception 'An existing Company Owner has an unsupported role.';
  end if;
end;
$$;

-- The earlier personal-account migration excluded employer. Remove only that
-- specific role check, then explicitly allow the three supported roles.
do $$
declare
  v_constraint record;
begin
  for v_constraint in
    select conname
    from pg_constraint
    where conrelid = 'public.users'::regclass
      and contype = 'c'
      and position('role' in pg_get_constraintdef(oid)) > 0
      and position('job_seeker' in pg_get_constraintdef(oid)) > 0
      and position('administrator' in pg_get_constraintdef(oid)) > 0
      and position('employer' in pg_get_constraintdef(oid)) = 0
  loop
    execute format(
      'alter table public.users drop constraint %I',
      v_constraint.conname
    );
  end loop;
end;
$$;

alter table public.users
  add constraint jobmate_users_account_role_check_v2
  check (
    role in (
      'job_seeker'::public.user_role,
      'employer'::public.user_role,
      'administrator'::public.user_role
    )
  );

-- Existing Company Owners are no longer Job Seekers.
update public.users u
set role = 'employer'::public.user_role
from public.company_memberships cm
where cm.user_id = u.user_id
  and cm.member_role = 'owner'
  and u.role = 'job_seeker'::public.user_role;

-- Signup metadata is a request, never a source of administrative authority.
-- Only job_seeker and employer are accepted from a client signup request.
create or replace function private.set_jobmate_personal_signup_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_requested_role text;
begin
  select lower(
    coalesce(a.raw_user_meta_data ->> 'requested_role', 'job_seeker')
  )
  into v_requested_role
  from auth.users a
  where a.id = new.user_id;

  if v_requested_role is null
     or v_requested_role not in ('job_seeker', 'employer') then
    v_requested_role := 'job_seeker';
  end if;

  new.role := v_requested_role::public.user_role;
  return new;
end;
$$;

-- Replace only triggers that call the earlier role-normalisation function.
do $$
declare
  v_trigger_name text;
begin
  for v_trigger_name in
    select tgname
    from pg_trigger
    where tgrelid = 'public.users'::regclass
      and not tgisinternal
      and tgfoid = 'private.set_jobmate_personal_signup_role()'::regprocedure
  loop
    execute format(
      'drop trigger %I on public.users',
      v_trigger_name
    );
  end loop;
end;
$$;

create trigger jobmate_set_signup_role
before insert on public.users
for each row
execute function private.set_jobmate_personal_signup_role();

-- A Company supporting document is accepted only from its active Employer.
create or replace function private.require_jobmate_employer_submission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_status text;
begin
  if auth.uid() is not null
     and new.submitted_by is distinct from auth.uid() then
    raise exception 'You can only submit your own Company verification request.'
      using errcode = 'P0001';
  end if;

  select u.role::text, u.status::text
  into v_role, v_status
  from public.users u
  where u.user_id = new.submitted_by;

  if v_role is distinct from 'employer'
     or v_status is distinct from 'active' then
    raise exception 'Only active Employer accounts can submit Company documents.'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists jobmate_require_employer_company_submission
  on public.company_verification_requests;

create trigger jobmate_require_employer_company_submission
before insert on public.company_verification_requests
for each row
execute function private.require_jobmate_employer_submission();

-- A Company has one immutable Owner. The existing user_id primary key on
-- company_memberships already prevents one user from owning multiple companies.
create unique index if not exists jobmate_one_owner_per_company_idx
on public.company_memberships (company_id)
where member_role = 'owner';

create or replace function private.protect_jobmate_company_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
begin
  if tg_op = 'delete' then
    if old.member_role = 'owner' then
      raise exception 'A Company Owner cannot be removed.'
        using errcode = 'P0001';
    end if;

    return old;
  end if;

  if tg_op = 'update'
     and old.member_role = 'owner'
     and (
       new.member_role is distinct from old.member_role
       or new.company_id is distinct from old.company_id
       or new.user_id is distinct from old.user_id
     ) then
    raise exception 'Company ownership cannot be transferred or changed.'
      using errcode = 'P0001';
  end if;

  if new.member_role = 'owner' then
    select role::text
    into v_role
    from public.users
    where user_id = new.user_id;

    if v_role is distinct from 'employer' then
      raise exception 'Only an Employer can become a Company Owner.'
        using errcode = 'P0001';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists jobmate_protect_company_owner
  on public.company_memberships;

create trigger jobmate_protect_company_owner
before insert or update or delete on public.company_memberships
for each row
execute function private.protect_jobmate_company_owner();

-- A current Company Owner must keep the Employer role.
create or replace function private.require_jobmate_owner_employer_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role::text <> 'employer'
     and exists (
       select 1
       from public.company_memberships cm
       where cm.user_id = old.user_id
         and cm.member_role = 'owner'
     ) then
    raise exception 'A Company Owner must keep the Employer role.'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists jobmate_owner_must_remain_employer
  on public.users;

create trigger jobmate_owner_must_remain_employer
before update of role on public.users
for each row
execute function private.require_jobmate_owner_employer_role();

-- created_by is an ownership audit field and must remain unchanged.
create or replace function private.protect_jobmate_company_creator()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.created_by is distinct from old.created_by then
    raise exception 'Company creator cannot be changed.'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists jobmate_protect_company_creator
  on public.companies;

create trigger jobmate_protect_company_creator
before update of created_by on public.companies
for each row
execute function private.protect_jobmate_company_creator();

-- This restrictive policy applies only to the Company-document bucket.
-- Other existing Storage buckets keep their own policies unchanged.
drop policy if exists "jobmate_company_document_uploads_require_employer"
  on storage.objects;

create policy "jobmate_company_document_uploads_require_employer"
on storage.objects
as restrictive
for insert
to authenticated
with check (
  bucket_id <> 'jobmate-company-verification'
  or exists (
    select 1
    from public.users u
    where u.user_id = (select auth.uid())
      and u.status::text = 'active'
      and u.role::text = 'employer'
  )
);

revoke all on function private.set_jobmate_personal_signup_role()
  from public, anon, authenticated;

revoke all on function private.require_jobmate_employer_submission()
  from public, anon, authenticated;

revoke all on function private.protect_jobmate_company_owner()
  from public, anon, authenticated;

revoke all on function private.require_jobmate_owner_employer_role()
  from public, anon, authenticated;

revoke all on function private.protect_jobmate_company_creator()
  from public, anon, authenticated;

notify pgrst, 'reload schema';

commit;

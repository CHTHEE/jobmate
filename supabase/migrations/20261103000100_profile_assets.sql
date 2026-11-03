-- PENDING USER REVIEW / MANUAL EXECUTION. Not applied by the coding agent.
-- Based on the supplied 2026-11-03 profile_assets_inspection results.
-- Additive resume storage; no legacy file/record is deleted or auto-verified.
begin;

create table public.personal_resumes (
  resume_id uuid primary key,
  user_id uuid not null references public.users(user_id),
  storage_path text not null unique,
  original_name varchar(255) not null check (char_length(btrim(original_name)) between 1 and 255),
  mime_type text not null check (mime_type = 'application/pdf'),
  size_bytes bigint not null check (size_bytes between 1 and 5242880),
  created_at timestamptz not null default clock_timestamp()
);
create index personal_resumes_user_created_idx
  on public.personal_resumes(user_id, created_at desc);
alter table public.personal_resumes enable row level security;
revoke all on public.personal_resumes from public, anon, authenticated;
grant select on public.personal_resumes to authenticated;

create policy personal_resumes_read_own on public.personal_resumes
for select to authenticated using (
  user_id = (select auth.uid()) and exists (
    select 1 from public.users u
    where u.user_id = (select auth.uid())
      and u.status::text = 'active' and u.role::text = 'job_seeker'
  )
);

-- Deliberately fail on a name collision rather than altering an unknown bucket.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('jobmate-resumes', 'jobmate-resumes', false, 5242880, array['application/pdf']);

create policy personal_resume_files_insert on storage.objects
for insert to authenticated with check (
  bucket_id = 'jobmate-resumes'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and array_length(storage.foldername(name), 1) = 2
  and (storage.foldername(name))[2] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and split_part(name, '/', 3) = 'document.pdf'
  and exists (
    select 1 from public.users u
    where u.user_id = (select auth.uid())
      and u.status::text = 'active' and u.role::text = 'job_seeker'
  )
);
create policy personal_resume_files_read on storage.objects
for select to authenticated using (
  bucket_id = 'jobmate-resumes' and exists (
    select 1 from public.personal_resumes r
    join public.users u on u.user_id = r.user_id
    where r.storage_path = objects.name and r.user_id = (select auth.uid())
      and u.status::text = 'active' and u.role::text = 'job_seeker'
  )
);
-- No UPDATE/DELETE permission: replacements get immutable new paths.

create function public.save_personal_resume(
  p_resume_id uuid, p_storage_path text, p_original_name text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_user public.users%rowtype;
  v_existing public.personal_resumes%rowtype;
  v_metadata jsonb;
  v_size bigint;
begin
  if v_uid is null then raise exception 'Please log in again.'; end if;
  select * into v_user from public.users where user_id = v_uid for update;
  if not found or v_user.status::text is distinct from 'active'
     or v_user.role::text is distinct from 'job_seeker' then
    raise exception 'An active Job Seeker account is required.';
  end if;
  if p_resume_id is null or p_original_name is null
     or char_length(btrim(p_original_name)) not between 1 and 255 then
    raise exception 'A resume ID and valid filename are required.';
  end if;
  if p_storage_path is distinct from v_uid::text || '/' || p_resume_id::text || '/document.pdf' then
    raise exception 'Invalid resume path.';
  end if;
  select * into v_existing from public.personal_resumes where resume_id = p_resume_id;
  if found then
    if v_existing.user_id = v_uid and v_existing.storage_path = p_storage_path
       and v_existing.original_name = btrim(p_original_name) then
      return p_resume_id;
    end if;
    raise exception 'This resume ID has already been used.';
  end if;
  select o.metadata into v_metadata from storage.objects o
  where o.bucket_id = 'jobmate-resumes' and o.name = p_storage_path;
  if not found then raise exception 'Upload the resume before saving.'; end if;
  v_size := coalesce((v_metadata ->> 'size')::bigint, 0);
  if v_size not between 1 and 5242880
     or (v_metadata ->> 'mimetype') is distinct from 'application/pdf' then
    raise exception 'The resume must be a PDF of at most 5 MiB.';
  end if;
  insert into public.personal_resumes(resume_id, user_id, storage_path, original_name, mime_type, size_bytes)
  values (p_resume_id, v_uid, p_storage_path, btrim(p_original_name), 'application/pdf', v_size);
  -- Do not update users.verification_status or create an approval request.
  return p_resume_id;
end;
$$;
revoke all on function public.save_personal_resume(uuid, text, text) from public, anon;
grant execute on function public.save_personal_resume(uuid, text, text) to authenticated;

-- Return new versions plus the user's legacy resumes, without approval labels.
create function public.list_personal_resumes(p_limit integer default 10)
returns table (
  resume_id uuid, storage_path text, original_name text, size_bytes bigint,
  uploaded_at timestamptz, bucket_id text, legacy boolean
) language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := auth.uid();
begin
  if not exists (
    select 1 from public.users u where u.user_id = v_uid
      and u.status::text = 'active' and u.role::text = 'job_seeker'
  ) then raise exception 'An active Job Seeker account is required.'; end if;
  if p_limit is null or p_limit not between 1 and 50 then
    raise exception 'Invalid page size.';
  end if;
  return query
  select f.id, f.path, f.filename, f.bytes, f.saved_at, f.bucket, f.is_legacy
  from (
    select r.resume_id as id, r.storage_path as path,
      r.original_name::text as filename, r.size_bytes as bytes,
      r.created_at as saved_at, 'jobmate-resumes'::text as bucket, false as is_legacy
    from public.personal_resumes r where r.user_id = v_uid
    union all
    select d.document_id, d.storage_path, d.original_name::text, d.size_bytes,
      d.created_at, 'jobmate-verification'::text, true
    from public.verification_documents d
    join public.verification_requests r on r.request_id = d.request_id
    where r.user_id = v_uid and r.role::text = 'job_seeker' and d.document_type = 'resume'
  ) f
  order by f.saved_at desc nulls last, f.id desc limit p_limit;
end;
$$;
revoke all on function public.list_personal_resumes(integer) from public, anon;
grant execute on function public.list_personal_resumes(integer) to authenticated;

-- Old clients must not create new resume review requests. Existing records stay.
create function private.stop_job_seeker_resume_review()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.role::text = 'job_seeker' then
    raise exception 'Resume review is no longer required. Update the app and use My Resume.';
  end if;
  return new;
end;
$$;
revoke all on function private.stop_job_seeker_resume_review() from public, anon, authenticated;
create trigger jobmate_stop_resume_review before insert on public.verification_requests
for each row execute function private.stop_job_seeker_resume_review();

-- Existing onboarding uploads retain their policy. A separate namespace allows
-- an active Company Owner to upload a new logo at any verification status.
create policy company_profile_logo_insert on storage.objects
for insert to authenticated with check (
  bucket_id = 'jobmate-company-logos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and array_length(storage.foldername(name), 1) = 2
  and (storage.foldername(name))[2] ~ '^profile-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and split_part(name, '/', 3) in ('logo.jpg', 'logo.png', 'logo.webp')
  and exists (
    select 1 from public.users u join public.company_memberships m on m.user_id = u.user_id
    where u.user_id = (select auth.uid()) and u.status::text = 'active'
      and u.role::text = 'employer' and m.member_role = 'owner'
  )
);

create function public.update_company_logo(
  p_company_id uuid, p_upload_id uuid, p_storage_path text, p_expected_logo_path text
) returns text language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_user public.users%rowtype;
  v_current_path text;
  v_metadata jsonb;
  v_size bigint;
  v_prefix text;
  v_expected_mime text;
begin
  if v_uid is null then raise exception 'Please log in again.'; end if;
  select * into v_user from public.users where user_id = v_uid for update;
  if not found or v_user.status::text is distinct from 'active'
     or v_user.role::text is distinct from 'employer' then
    raise exception 'An active Employer account is required.';
  end if;
  if p_company_id is null or p_upload_id is null or p_storage_path is null then
    raise exception 'Company, upload ID and logo path are required.';
  end if;
  perform 1 from public.company_memberships m
  where m.user_id = v_uid and m.company_id = p_company_id and m.member_role = 'owner'
  for share;
  if not found then raise exception 'Only the Company Owner may change its logo.'; end if;
  select c.logo_storage_path into v_current_path from public.companies c
  where c.company_id = p_company_id for update;
  if not found then raise exception 'Company not found.'; end if;
  v_prefix := v_uid::text || '/profile-' || p_upload_id::text || '/logo.';
  if p_storage_path not in (v_prefix || 'jpg', v_prefix || 'png', v_prefix || 'webp') then
    raise exception 'Invalid company logo path.';
  end if;
  if v_current_path = p_storage_path then return p_storage_path; end if;
  if v_current_path is distinct from p_expected_logo_path then
    raise exception 'The company logo changed elsewhere. Refresh the Company page before trying again.';
  end if;
  select o.metadata into v_metadata from storage.objects o
  where o.bucket_id = 'jobmate-company-logos' and o.name = p_storage_path;
  if not found then raise exception 'Upload the logo before saving.'; end if;
  v_size := coalesce((v_metadata ->> 'size')::bigint, 0);
  v_expected_mime := case when right(p_storage_path, 4) = '.jpg' then 'image/jpeg'
    when right(p_storage_path, 4) = '.png' then 'image/png' else 'image/webp' end;
  if v_size not between 1 and 2097152
     or (v_metadata ->> 'mimetype') is distinct from v_expected_mime then
    raise exception 'The logo must be JPG, PNG or WebP of at most 2 MiB.';
  end if;
  update public.companies set logo_storage_path = p_storage_path where company_id = p_company_id;
  -- Existing updated_at trigger runs. Ownership, details and verification stay.
  return p_storage_path;
end;
$$;
revoke all on function public.update_company_logo(uuid, uuid, text, text) from public, anon;
grant execute on function public.update_company_logo(uuid, uuid, text, text) to authenticated;

notify pgrst, 'reload schema';
commit;

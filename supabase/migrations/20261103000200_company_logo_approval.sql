-- UPGRADE after 20261103000100_profile_assets.sql. Review before manual execution.
-- Keeps all existing files/resumes. No historical-image browsing is granted.
begin;

create table public.company_logo_change_requests (
  request_id uuid primary key,
  company_id uuid not null references public.companies(company_id),
  submitted_by uuid not null references public.users(user_id),
  previous_storage_path text,
  storage_path text not null unique,
  mime_type text not null check (mime_type in ('image/jpeg','image/png','image/webp')),
  size_bytes bigint not null check (size_bytes between 1 and 2097152),
  status text not null default 'pending' check (status in ('pending','verified','rejected')),
  submitted_at timestamptz not null default clock_timestamp(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.users(user_id),
  review_comment text check (length(review_comment) <= 2000),
  check ((status = 'pending' and reviewed_at is null and reviewed_by is null)
    or (status <> 'pending' and reviewed_at is not null and reviewed_by is not null)),
  check (status <> 'rejected' or nullif(btrim(review_comment), '') is not null)
);
create unique index company_logo_one_pending on public.company_logo_change_requests(company_id)
where status = 'pending';
create index company_logo_queue on public.company_logo_change_requests(submitted_at, request_id)
where status = 'pending';
alter table public.company_logo_change_requests enable row level security;
revoke all on public.company_logo_change_requests from public, anon, authenticated;
grant select on public.company_logo_change_requests to authenticated;
create policy company_logo_requests_read on public.company_logo_change_requests
for select to authenticated using (
  exists (select 1 from public.users u where u.user_id = (select auth.uid())
    and u.status::text = 'active' and (
      (u.role::text = 'employer' and exists (
        select 1 from public.company_memberships m where m.user_id = u.user_id
          and m.company_id = company_logo_change_requests.company_id and m.member_role = 'owner'))
      or (u.role::text = 'administrator' and exists (
        select 1 from public.administrator_profiles ap
        where ap.user_id = u.user_id and ap.can_review_companies = true))
    ))
);

-- Audit records only: no client grants/policies, no history screen or public URLs.
-- Existing logos have unknown change/approval dates; never fabricate those dates.
create table public.company_logo_history (
  history_id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(company_id),
  previous_storage_path text,
  storage_path text,
  source text not null check (source in ('existing','other_change','approved_change')),
  change_request_id uuid unique references public.company_logo_change_requests(request_id),
  changed_by uuid references public.users(user_id),
  changed_at timestamptz,
  recorded_at timestamptz not null default clock_timestamp()
);
create index company_logo_history_company on public.company_logo_history(company_id, recorded_at desc);
alter table public.company_logo_history enable row level security;
revoke all on public.company_logo_history from public, anon, authenticated;
insert into public.company_logo_history(company_id, storage_path, source)
select company_id, logo_storage_path, 'existing' from public.companies
where logo_storage_path is not null;

create function private.record_company_logo_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_request public.company_logo_change_requests%rowtype;
begin
  if new.logo_storage_path is not distinct from old.logo_storage_path then return new; end if;
  select * into v_request from public.company_logo_change_requests r
  where r.company_id = new.company_id and r.storage_path = new.logo_storage_path
    and r.status = 'verified'
    and r.previous_storage_path is not distinct from old.logo_storage_path
    and not exists (select 1 from public.company_logo_history h where h.change_request_id = r.request_id);
  insert into public.company_logo_history(
    company_id, previous_storage_path, storage_path, source, change_request_id, changed_by, changed_at
  ) values (
    new.company_id, old.logo_storage_path, new.logo_storage_path,
    case when v_request.request_id is not null then 'approved_change' else 'other_change' end,
    v_request.request_id, coalesce(v_request.reviewed_by, auth.uid()), clock_timestamp()
  );
  return new;
end;
$$;
revoke all on function private.record_company_logo_change() from public, anon, authenticated;
create trigger jobmate_record_company_logo after update of logo_storage_path on public.companies
for each row execute function private.record_company_logo_change();

-- Close the previously deployed bypass. Keep the signature for an explicit old-client error.
create or replace function public.update_company_logo(
  p_company_id uuid, p_upload_id uuid, p_storage_path text, p_expected_logo_path text
) returns text language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'Logo changes now require Admin approval. Restart the app and submit a logo change request.';
end;
$$;
revoke all on function public.update_company_logo(uuid,uuid,text,text) from public, anon;
grant execute on function public.update_company_logo(uuid,uuid,text,text) to authenticated;

-- Immutable uploads: a proposed image must never replace a published/history object.
create policy company_logo_no_client_overwrite on storage.objects as restrictive
for update to authenticated using (bucket_id <> 'jobmate-company-logos')
with check (bucket_id <> 'jobmate-company-logos');
create policy company_logo_no_client_delete on storage.objects as restrictive
for delete to authenticated using (bucket_id <> 'jobmate-company-logos');

create function public.submit_company_logo_change(
  p_company_id uuid, p_upload_id uuid, p_storage_path text, p_expected_logo_path text
) returns text language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid(); v_current text; v_prefix text; v_mime text;
  v_metadata jsonb; v_size bigint; v_existing public.company_logo_change_requests%rowtype;
begin
  perform 1 from public.users u where u.user_id = v_uid
    and u.status::text = 'active' and u.role::text = 'employer' for update;
  if not found then raise exception 'An active Employer account is required.'; end if;
  if p_company_id is null or p_upload_id is null or p_storage_path is null then
    raise exception 'Company, upload ID and logo path are required.';
  end if;
  perform 1 from public.company_memberships m where m.user_id = v_uid
    and m.company_id = p_company_id and m.member_role = 'owner' for share;
  if not found then raise exception 'Only the Company Owner may change its logo.'; end if;
  select c.logo_storage_path into v_current from public.companies c
    where c.company_id = p_company_id for update;
  if not found then raise exception 'Company not found.'; end if;
  select * into v_existing from public.company_logo_change_requests r where r.request_id = p_upload_id;
  if found then
    if v_existing.company_id = p_company_id and v_existing.submitted_by = v_uid
      and v_existing.storage_path = p_storage_path
      and v_existing.previous_storage_path is not distinct from p_expected_logo_path then
      return v_existing.status; -- Same immutable request, including a lost response after review.
    end if;
    raise exception 'This logo request ID has already been used.';
  end if;
  if exists (select 1 from public.company_logo_change_requests r
    where r.company_id = p_company_id and r.status = 'pending') then
    raise exception 'A logo change is already waiting for review. Refresh to view its status.';
  end if;
  if v_current is distinct from p_expected_logo_path then
    raise exception 'The company logo changed elsewhere. Refresh the Company page first.';
  end if;
  v_prefix := v_uid::text || '/profile-' || p_upload_id::text || '/logo.';
  if p_storage_path not in (v_prefix || 'jpg', v_prefix || 'png', v_prefix || 'webp') then
    raise exception 'Invalid company logo path.';
  end if;
  select o.metadata into v_metadata from storage.objects o
    where o.bucket_id = 'jobmate-company-logos' and o.name = p_storage_path;
  if not found then raise exception 'Upload the logo before submitting.'; end if;
  v_size := coalesce((v_metadata ->> 'size')::bigint, 0);
  v_mime := case when right(p_storage_path,4) = '.jpg' then 'image/jpeg'
    when right(p_storage_path,4) = '.png' then 'image/png' else 'image/webp' end;
  if v_size not between 1 and 2097152 or (v_metadata ->> 'mimetype') is distinct from v_mime then
    raise exception 'The logo must be JPG, PNG or WebP of at most 2 MiB.';
  end if;
  insert into public.company_logo_change_requests(
    request_id, company_id, submitted_by, previous_storage_path, storage_path, mime_type, size_bytes
  ) values (p_upload_id, p_company_id, v_uid, v_current, p_storage_path, v_mime, v_size);
  -- Current logo, Company verification and job permissions stay unchanged.
  return 'pending';
end;
$$;
revoke all on function public.submit_company_logo_change(uuid,uuid,text,text) from public, anon;
grant execute on function public.submit_company_logo_change(uuid,uuid,text,text) to authenticated;

create function public.list_company_logo_review_requests(p_limit integer default 21, p_offset integer default 0)
returns table(request_id uuid, company_id uuid, company_name text, previous_storage_path text,
  storage_path text, original_name text, submitted_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.users u join public.administrator_profiles ap on ap.user_id = u.user_id
    where u.user_id = auth.uid() and u.role::text = 'administrator' and u.status::text = 'active'
      and ap.can_review_companies = true) then
    raise exception 'You do not have permission to review Companies.';
  end if;
  if p_limit is null or p_limit not between 1 and 101 or p_offset is null or p_offset < 0 then
    raise exception 'Invalid page size or offset.';
  end if;
  return query select r.request_id, r.company_id, c.company_name::text, r.previous_storage_path,
    r.storage_path, 'Company logo'::text, r.submitted_at
  from public.company_logo_change_requests r join public.companies c on c.company_id = r.company_id
  where r.status = 'pending' and c.created_by <> auth.uid() and not exists (
    select 1 from public.company_memberships m where m.company_id = r.company_id and m.user_id = auth.uid())
  order by r.submitted_at, r.request_id limit p_limit offset p_offset;
end;
$$;
revoke all on function public.list_company_logo_review_requests(integer,integer) from public, anon;
grant execute on function public.list_company_logo_review_requests(integer,integer) to authenticated;

create function public.review_company_logo_change(p_request_id uuid, p_decision text, p_review_comment text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid(); v_company_id uuid; v_company public.companies%rowtype;
  v_request public.company_logo_change_requests%rowtype;
  v_comment text := nullif(btrim(p_review_comment),'');
begin
  if p_request_id is null or p_decision is null or p_decision not in ('verified','rejected') then
    raise exception 'Choose a valid logo review decision.';
  end if;
  if (p_decision = 'rejected' and v_comment is null) or length(v_comment) > 2000 then
    raise exception 'Rejection needs a reason. Comments must be 2000 characters or fewer.';
  end if;
  perform 1 from public.users u where u.user_id = v_uid
    and u.status::text = 'active' and u.role::text = 'administrator' for share;
  if not found then raise exception 'An active administrator account is required.'; end if;
  perform 1 from public.administrator_profiles ap where ap.user_id = v_uid
    and ap.can_review_companies = true for share;
  if not found then raise exception 'Company Review permission is required.'; end if;
  select r.company_id into v_company_id from public.company_logo_change_requests r where r.request_id = p_request_id;
  if not found then raise exception 'Logo request not found.'; end if;
  select * into v_company from public.companies c where c.company_id = v_company_id for update;
  if v_company.created_by = v_uid or exists (select 1 from public.company_memberships m
    where m.user_id = v_uid and m.company_id = v_company_id) then
    raise exception 'You cannot review a Company you own or belong to.';
  end if;
  select * into v_request from public.company_logo_change_requests r where r.request_id = p_request_id for update;
  if v_request.status <> 'pending' then
    raise exception 'This logo request is no longer pending. Refresh the queue.';
  end if;
  -- A document resubmission may have changed the current logo after submission.
  if p_decision = 'verified' and v_company.logo_storage_path is distinct from v_request.previous_storage_path then
    raise exception 'The current logo changed. Reject this stale request and ask the Owner to resubmit.';
  end if;
  if p_decision = 'verified' and not exists (select 1 from storage.objects o
    where o.bucket_id = 'jobmate-company-logos' and o.name = v_request.storage_path
      and (o.metadata ->> 'mimetype') = v_request.mime_type
      and (o.metadata ->> 'size')::bigint = v_request.size_bytes) then
    raise exception 'The submitted image is missing or changed. Reject and request another upload.';
  end if;
  update public.company_logo_change_requests set status = p_decision, reviewed_by = v_uid,
    reviewed_at = clock_timestamp(), review_comment = v_comment where request_id = p_request_id;
  if p_decision = 'verified' then
    update public.companies set logo_storage_path = v_request.storage_path where company_id = v_company_id;
    -- Audit trigger records both paths and the reviewer in this same transaction.
  end if;
  insert into public.notifications(user_id, notification_type, title, message) values (
    v_request.submitted_by, 'company_logo_review',
    case when p_decision = 'verified' then 'Company logo approved' else 'Company logo rejected' end,
    case when p_decision = 'verified'
      then format('The new logo for %s has been approved.', v_company.company_name)
      else format('The new logo for %s was rejected. Reason: %s', v_company.company_name, v_comment) end
  );
  return p_decision;
end;
$$;
revoke all on function public.review_company_logo_change(uuid,text,text) from public, anon;
grant execute on function public.review_company_logo_change(uuid,text,text) to authenticated;

notify pgrst, 'reload schema';
commit;

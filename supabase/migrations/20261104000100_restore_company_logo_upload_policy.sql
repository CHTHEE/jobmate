-- Targeted repair, prepared for review/manual execution in the EXISTING project.
-- November 4 diagnostics: approval RPC exists; this INSERT policy is missing.
-- Does not replace any existing policy, change a bucket, or approve a logo.
begin;

do $check$
begin
  if to_regprocedure('public.submit_company_logo_change(uuid,uuid,text,text)') is null then
    raise exception 'The Company logo approval RPC is missing. Inspect deployment before applying this repair.';
  end if;
end;
$check$;

-- Match the immutable upload namespace already used by Flutter and the RPC.
-- A new file is allowed at any Company verification status, but publishing it
-- still requires review_company_logo_change and Company Review permission.
create policy company_profile_logo_insert on storage.objects
for insert to authenticated with check (
  bucket_id = 'jobmate-company-logos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and array_length(storage.foldername(name), 1) = 2
  and (storage.foldername(name))[2] ~ '^profile-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and split_part(name, '/', 3) in ('logo.jpg', 'logo.png', 'logo.webp')
  and exists (
    select 1 from public.users u
    join public.company_memberships m on m.user_id = u.user_id
    where u.user_id = (select auth.uid()) and u.status::text = 'active'
      and u.role::text = 'employer' and m.member_role = 'owner'
  )
);

commit;

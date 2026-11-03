-- READ ONLY. Run in the existing Supabase project's SQL Editor.
-- Returns configuration only: no user rows, files, credentials or policy changes.
select 'storage_insert_policies' as section,
       coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) as result
from (
  select policyname, permissive, roles, cmd, with_check
  from pg_policies
  where schemaname = 'storage' and tablename = 'objects'
    and cmd in ('INSERT', 'ALL')
  order by policyname
) p
union all
select 'logo_bucket', coalesce(jsonb_agg(to_jsonb(b)), '[]'::jsonb)
from (
  select id, public, file_size_limit, allowed_mime_types
  from storage.buckets where id = 'jobmate-company-logos'
) b
union all
select 'approval_rpc', jsonb_build_object(
  'submit_function_exists',
  to_regprocedure('public.submit_company_logo_change(uuid,uuid,text,text)') is not null
);

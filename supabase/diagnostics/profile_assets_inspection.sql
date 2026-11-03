-- READ ONLY. Run in the existing project's Supabase SQL Editor.
-- No user rows, email addresses, passwords, tokens or file contents are read.
-- This checks the existing contract before changing resume/logo permissions.
select 'columns' as section, jsonb_agg(to_jsonb(c)) as result
from (
  select table_name, column_name, data_type, udt_name
  from information_schema.columns
  where table_schema = 'public'
    and table_name in (
      'users', 'companies', 'company_memberships',
      'verification_requests', 'verification_documents'
    )
  order by table_name, ordinal_position
) c
union all
select 'policies', jsonb_agg(to_jsonb(p))
from (
  select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
  from pg_policies
  where (schemaname = 'public' and tablename in (
    'users', 'companies', 'company_memberships',
    'verification_requests', 'verification_documents'
  )) or (schemaname = 'storage' and tablename = 'objects')
  order by schemaname, tablename, policyname
) p
union all
select 'functions', jsonb_agg(to_jsonb(f))
from (
  select n.nspname as schema_name, p.proname as function_name,
         pg_get_function_identity_arguments(p.oid) as arguments,
         pg_get_functiondef(p.oid) as definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private')
    and p.prokind = 'f'
    and (
      p.proname in ('submit_verification_document', 'submit_company_for_review_v2')
      or p.proname ilike '%company%'
      or p.proname ilike '%resume%'
      or p.proname ilike '%verification%'
      or p.oid in (
        select t.tgfoid
        from pg_trigger t
        join pg_class c on c.oid = t.tgrelid
        join pg_namespace tn on tn.oid = c.relnamespace
        where not t.tgisinternal
          and tn.nspname = 'public'
          and c.relname in (
            'users', 'companies', 'company_memberships',
            'verification_requests', 'verification_documents'
          )
      )
    )
  order by n.nspname, p.proname
) f
union all
select 'triggers', jsonb_agg(to_jsonb(t))
from (
  select n.nspname as schema_name, c.relname as table_name,
         t.tgname as trigger_name, pg_get_triggerdef(t.oid) as definition
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where not t.tgisinternal and n.nspname = 'public'
    and c.relname in (
      'users', 'companies', 'company_memberships',
      'verification_requests', 'verification_documents'
    )
  order by c.relname, t.tgname
) t
union all
select 'buckets', jsonb_agg(to_jsonb(b))
from (
  select id, name, public, file_size_limit, allowed_mime_types
  from storage.buckets
  where id in ('jobmate-company-logos', 'jobmate-verification')
  order by id
) b;

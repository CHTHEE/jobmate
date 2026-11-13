-- READ ONLY. Manual CH/KZ inspection in the existing project's SQL Editor.
-- Not executed by the agent. No application rows, messages, tokens or secrets.
-- Preserve all result sets for offline review; no mutation RPC is invoked.

-- 1. Inventory public relations, including unexpectedly named chat objects.
select n.nspname as schema_name, c.relname, c.relkind,
       c.relrowsecurity, c.relforcerowsecurity, c.relacl,
       pg_catalog.pg_get_userbyid(c.relowner) as owner
from pg_catalog.pg_class c
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r','p','v','m','f')
order by c.relname;

-- 2. Column types/defaults/nullability; no assumed business-table columns.
select table_schema, table_name, column_name, ordinal_position, data_type,
       udt_schema, udt_name, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
order by table_name, ordinal_position;

-- 3. Keys, foreign keys, status checks, indexes and enum labels.
select c.relname, k.conname, k.contype,
       pg_catalog.pg_get_constraintdef(k.oid, true) as definition
from pg_catalog.pg_constraint k
join pg_catalog.pg_class c on c.oid = k.conrelid
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' order by c.relname, k.conname;
select schemaname, tablename, indexname, indexdef
from pg_catalog.pg_indexes where schemaname = 'public'
order by tablename, indexname;
select n.nspname, t.typname, e.enumlabel, e.enumsortorder
from pg_catalog.pg_enum e
join pg_catalog.pg_type t on t.oid = e.enumtypid
join pg_catalog.pg_namespace n on n.oid = t.typnamespace
where n.nspname = 'public' order by t.typname, e.enumsortorder;

-- 4. RLS includes ALL/permissive policies and Storage rules.
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_catalog.pg_policies where schemaname in ('public','storage','realtime')
order by schemaname, tablename, policyname;
select table_schema, table_name, grantee, privilege_type, is_grantable
from information_schema.table_privileges
where table_schema in ('public','storage','realtime')
order by table_schema, table_name, grantee, privilege_type;
select table_schema, table_name, column_name, grantee, privilege_type
from information_schema.column_privileges where table_schema = 'public'
order by table_name, column_name, grantee, privilege_type;

-- 5. Routine inventory catches unknown names, overloads and default PUBLIC ACLs.
select p.oid::regprocedure::text as signature, p.prosecdef, p.proconfig,
       p.proacl, pg_catalog.pg_get_userbyid(p.proowner) as owner,
       pg_catalog.pg_get_functiondef(p.oid) as definition
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prokind in ('f','p')
order by signature;

-- 6. Trigger bodies may contain notification or legacy chat emitters.
select n.nspname, c.relname, t.tgname,
       pg_catalog.pg_get_triggerdef(t.oid, true) as trigger_definition,
       pg_catalog.pg_get_functiondef(t.tgfoid) as function_definition
from pg_catalog.pg_trigger t
join pg_catalog.pg_class c on c.oid = t.tgrelid
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and not t.tgisinternal
order by c.relname, t.tgname;

-- 7. Realtime publication membership is not proof of subscriber authorization.
select pubname, puballtables, pubinsert, pubupdate, pubdelete, pubtruncate
from pg_catalog.pg_publication order by pubname;
select pubname, schemaname, tablename
from pg_catalog.pg_publication_tables order by pubname, schemaname, tablename;

-- 8. Bucket configuration only; do not query storage.objects/user files.
select id, name, public, file_size_limit, allowed_mime_types
from storage.buckets order by id;

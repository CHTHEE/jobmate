-- Step 101J: READ-ONLY PREFLIGHT, prepared but NOT executed by the agent.
-- Run sections in order in the intended MAIN DEVELOPMENT project's SQL Editor,
-- using the SAME trusted role intended to deploy 20261105000200. Independently
-- confirm the Dashboard project first; this script cannot identify that project.
-- No application RPC is invoked. Only catalog inspection and two aggregate/
-- existence reads of application tables are used; no user/file contents appear.
-- A passing preflight is NOT deployment approval or a concurrency/runtime test.
-- STOP on missing objects, unexpected definitions/ACLs, partial installation,
-- an unconfigured assignment check, or unexplained triggers/dependencies.

-- 1. Session/deployment role. Expect the intended trusted migration role, public
-- schema creation permission, auth/public usage and plpgsql usage. No passwords.
SELECT pg_catalog.current_database() AS database_name,
       current_user AS effective_role,
       session_user AS session_role,
       pg_catalog.current_setting('server_version') AS postgres_version,
       pg_catalog.current_setting('transaction_isolation') AS isolation_level,
       r.rolsuper AS role_superuser,
       r.rolbypassrls AS role_bypasses_rls,
       pg_catalog.has_schema_privilege(current_user, 'public', 'USAGE') AS public_usage,
       pg_catalog.has_schema_privilege(current_user, 'public', 'CREATE') AS public_create,
       pg_catalog.has_schema_privilege(current_user, 'auth', 'USAGE') AS auth_usage,
       pg_catalog.has_language_privilege(current_user, 'plpgsql', 'USAGE') AS plpgsql_usage
FROM pg_catalog.pg_roles AS r
WHERE r.rolname = current_user;

-- Both client roles must exist before privilege checks below are meaningful.
WITH required(role_name) AS (VALUES ('anon'), ('authenticated'))
SELECT q.role_name, r.oid IS NOT NULL AS exists
FROM required AS q
LEFT JOIN pg_catalog.pg_roles AS r ON r.rolname = q.role_name;

-- 2. Required relations. All must exist. All five work_* tables must have RLS.
-- Investigate unexpected owners/FORCE RLS before creating definer functions.
WITH required(schema_name, table_name) AS (
    VALUES ('public', 'work_assignments'), ('public', 'work_attendance'),
           ('public', 'work_evidence'), ('public', 'work_evidence_submissions'),
           ('public', 'work_verification_history'), ('public', 'users'),
           ('public', 'job_applications'), ('public', 'job_postings'),
           ('public', 'companies'), ('storage', 'objects'), ('storage', 'buckets')
)
SELECT q.schema_name, q.table_name, c.oid IS NOT NULL AS exists,
       c.relkind, pg_catalog.pg_get_userbyid(c.relowner) AS table_owner,
       c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS force_rls,
       CASE WHEN c.oid IS NULL THEN false ELSE
           me.rolsuper OR pg_catalog.pg_has_role(me.oid, c.relowner, 'USAGE')
       END AS effective_owner_capability
FROM required AS q
LEFT JOIN pg_catalog.pg_namespace AS n ON n.nspname = q.schema_name
LEFT JOIN pg_catalog.pg_class AS c
       ON c.relnamespace = n.oid AND c.relname = q.table_name
CROSS JOIN pg_catalog.pg_roles AS me
WHERE me.rolname = current_user
ORDER BY q.schema_name, q.table_name;

-- 3. Columns used by wrapper, lookup and legacy delegation. Expect every row OK.
-- Inspect the full inventory below too; this list targets submission contracts.
WITH required(table_name, column_name, expected_type, expected_not_null) AS (
    VALUES
        ('work_assignments', 'assignment_id', 'uuid', true),
        ('work_assignments', 'worker_id', 'uuid', true),
        ('work_assignments', 'company_id', 'uuid', true),
        ('work_assignments', 'status', 'text', true),
        ('work_assignments', 'verification_status', 'text', true),
        ('work_assignments', 'updated_at', 'timestamp with time zone', true),
        ('work_attendance', 'assignment_id', 'uuid', true),
        ('work_attendance', 'check_in_at', 'timestamp with time zone', false),
        ('work_attendance', 'check_out_at', 'timestamp with time zone', false),
        ('work_evidence_submissions', 'submission_id', 'uuid', true),
        ('work_evidence_submissions', 'assignment_id', 'uuid', true),
        ('work_evidence_submissions', 'submitted_by', 'uuid', true),
        ('work_evidence_submissions', 'submission_round', 'integer', true),
        ('work_evidence_submissions', 'description', 'text', true),
        ('work_evidence_submissions', 'file_count', 'integer', true),
        ('work_evidence_submissions', 'submitted_at', 'timestamp with time zone', true),
        ('work_evidence', 'evidence_id', 'uuid', true),
        ('work_evidence', 'assignment_id', 'uuid', true),
        ('work_evidence', 'submitted_by', 'uuid', true),
        ('work_evidence', 'submission_round', 'integer', true),
        ('work_evidence', 'description', 'text', true),
        ('work_evidence', 'storage_path', 'text', true),
        ('work_evidence', 'file_name', 'text', true),
        ('work_evidence', 'mime_type', 'text', true),
        ('work_evidence', 'created_at', 'timestamp with time zone', true),
        ('work_verification_history', 'assignment_id', 'uuid', true),
        ('work_verification_history', 'action', 'text', true),
        ('work_verification_history', 'previous_status', 'text', false),
        ('work_verification_history', 'new_status', 'text', true),
        ('work_verification_history', 'performed_by', 'uuid', true),
        ('work_verification_history', 'note', 'text', false),
        -- Baseline users nullability is not defined by the original migration.
        ('users', 'user_id', 'uuid', NULL::boolean),
        ('users', 'role', 'user_role', NULL::boolean),
        ('users', 'status', 'account_status', NULL::boolean)
)
SELECT q.*, pg_catalog.format_type(a.atttypid, a.atttypmod) AS actual_type,
       a.attnotnull AS actual_not_null,
       CASE WHEN a.attnum IS NULL THEN 'BLOCK: missing column'
            WHEN (CASE WHEN q.expected_type IN ('user_role', 'account_status')
                       THEN a.atttypid <> pg_catalog.to_regtype('public.' || q.expected_type)
                       ELSE pg_catalog.format_type(a.atttypid, a.atttypmod) <> q.expected_type END)
              OR (q.expected_not_null IS NOT NULL AND a.attnotnull <> q.expected_not_null)
                THEN 'BLOCK: inspect schema drift'
            ELSE 'OK' END AS result
FROM required AS q
LEFT JOIN pg_catalog.pg_namespace AS n ON n.nspname = 'public'
LEFT JOIN pg_catalog.pg_class AS c
       ON c.relnamespace = n.oid AND c.relname = q.table_name
LEFT JOIN pg_catalog.pg_attribute AS a
       ON a.attrelid = c.oid AND a.attname = q.column_name
      AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY q.table_name, q.column_name;

-- Includes Storage metadata columns without reading any Storage object rows.
SELECT table_schema, table_name, column_name, data_type, udt_schema, udt_name,
       is_nullable, column_default
FROM information_schema.columns
WHERE (table_schema = 'public' AND table_name IN (
           'work_assignments', 'work_attendance', 'work_evidence',
           'work_evidence_submissions', 'work_verification_history'))
   OR (table_schema = 'storage' AND table_name = 'objects'
       AND column_name IN ('bucket_id', 'name', 'owner_id', 'metadata'))
ORDER BY table_schema, table_name, ordinal_position;

-- Required enum values must be present; additional values need compatibility
-- review. These type definitions originate outside the checked-in Module 4 SQL.
SELECT n.nspname AS type_schema, t.typname, e.enumlabel
FROM pg_catalog.pg_type AS t
JOIN pg_catalog.pg_namespace AS n ON n.oid = t.typnamespace
JOIN pg_catalog.pg_enum AS e ON e.enumtypid = t.oid
WHERE n.nspname = 'public' AND t.typname IN ('user_role', 'account_status')
ORDER BY t.typname, e.enumsortorder;

-- 4. Core uniqueness guarantees. Expect exists=true, validated=true and exact
-- column definitions. Missing/changed constraints BLOCK deployment.
WITH required(table_name, constraint_name, expected_definition) AS (
    VALUES ('work_assignments', 'work_assignments_pkey', 'PRIMARY KEY (assignment_id)'),
           ('work_attendance', 'work_attendance_assignment_id_key', 'UNIQUE (assignment_id)'),
           ('work_evidence_submissions', 'work_evidence_submissions_pkey', 'PRIMARY KEY (submission_id)'),
           ('work_evidence_submissions', 'work_evidence_submission_round_unique', 'UNIQUE (assignment_id, submission_round)'),
           ('work_evidence', 'work_evidence_storage_path_unique', 'UNIQUE (storage_path)')
)
SELECT q.*, k.oid IS NOT NULL AS exists, k.convalidated AS validated,
       pg_catalog.pg_get_constraintdef(k.oid) AS actual_definition
FROM required AS q
LEFT JOIN pg_catalog.pg_namespace AS n ON n.nspname = 'public'
LEFT JOIN pg_catalog.pg_class AS c
       ON c.relnamespace = n.oid AND c.relname = q.table_name
LEFT JOIN pg_catalog.pg_constraint AS k
       ON k.conrelid = c.oid AND k.conname = q.constraint_name
ORDER BY q.table_name, q.constraint_name;

-- Review ALL checks/FKs and index validity against the original migration.
SELECT c.relname AS table_name, k.conname, k.contype, k.convalidated,
       pg_catalog.pg_get_constraintdef(k.oid) AS definition
FROM pg_catalog.pg_constraint AS k
JOIN pg_catalog.pg_class AS c ON c.oid = k.conrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname IN (
    'work_assignments', 'work_attendance', 'work_evidence',
    'work_evidence_submissions', 'work_verification_history')
ORDER BY c.relname, k.conname;

SELECT c.relname AS table_name, x.relname AS index_name,
       i.indisunique, i.indisvalid, i.indisready,
       pg_catalog.pg_get_indexdef(i.indexrelid) AS definition
FROM pg_catalog.pg_index AS i
JOIN pg_catalog.pg_class AS c ON c.oid = i.indrelid
JOIN pg_catalog.pg_class AS x ON x.oid = i.indexrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname IN (
    'work_assignments', 'work_attendance', 'work_evidence',
    'work_evidence_submissions', 'work_verification_history')
ORDER BY c.relname, x.relname;

-- 5. Required exact function signatures, owners, result types and configuration.
-- All must exist; review returns and named arguments against original source.
-- Legacy submit: integer, definer=true, volatility=v, empty search_path.
WITH required(signature) AS (
    VALUES ('auth.uid()'), ('public.can_manage_company_jobs(uuid)'),
           ('public.can_upload_work_evidence(uuid)'),
           ('public.can_view_work_evidence(uuid)'),
           ('public.can_read_work_evidence_file(text)'),
           ('public.submit_work_evidence(uuid,text,text[])'),
           ('public.list_my_work_assignments()'),
           ('public.list_company_work_assignments(uuid)'),
           ('public.list_work_evidence(uuid)'),
           ('public.request_more_work_evidence(uuid,text)'),
           ('public.verify_work_assignment(uuid)')
)
SELECT q.signature, p.oid IS NOT NULL AS exists,
       pg_catalog.pg_get_userbyid(p.proowner) AS owner,
       p.prosecdef AS security_definer, p.provolatile, p.proconfig,
       pg_catalog.pg_get_function_arguments(p.oid) AS arguments,
       pg_catalog.pg_get_function_result(p.oid) AS result_type,
       pg_catalog.has_function_privilege(current_user, p.oid, 'EXECUTE') AS deployer_can_execute
FROM required AS q
LEFT JOIN pg_catalog.pg_proc AS p ON p.oid = pg_catalog.to_regprocedure(q.signature)
ORDER BY q.signature;

-- Read the existing implementation; compare with original lines 922-1137.
-- Fetching source is not executing it. Inspect external helpers separately if
-- the project has drifted. No table data or function invocation is involved.
SELECT pg_catalog.pg_get_functiondef(
    pg_catalog.to_regprocedure('public.submit_work_evidence(uuid,text,text[])')
) AS legacy_submission_definition;

-- 6. Effective role privileges for the future owner (current_user) and legacy
-- owner. Wrapper needs assignment SELECT + UPDATE (row lock), users SELECT,
-- submissions SELECT + UPDATE, and EXECUTE on legacy submit/auth.uid().
-- With default-deny RLS, missing owner/BYPASS capability needs explicit review;
-- do NOT repair it by granting protected tables to authenticated clients.
WITH actors AS (
    SELECT r.oid, r.rolname, r.rolsuper, r.rolbypassrls
    FROM pg_catalog.pg_roles AS r
    WHERE r.rolname = current_user
       OR r.oid = (SELECT p.proowner FROM pg_catalog.pg_proc AS p
                   WHERE p.oid = pg_catalog.to_regprocedure(
                       'public.submit_work_evidence(uuid,text,text[])'))
)
SELECT r.rolname, c.relname,
       pg_catalog.has_table_privilege(r.oid, c.oid, 'SELECT') AS can_select,
       pg_catalog.has_table_privilege(r.oid, c.oid, 'UPDATE') AS can_update,
       r.rolsuper OR r.rolbypassrls OR
           (pg_catalog.pg_has_role(r.oid, c.relowner, 'USAGE')
            AND NOT c.relforcerowsecurity) AS owner_or_rls_bypass_capability
FROM actors AS r
CROSS JOIN pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname IN (
    'work_assignments', 'users', 'work_evidence_submissions')
ORDER BY r.rolname, c.relname;

-- The definer also needs schema usage; table privileges alone do not suffice.
SELECT r.rolname, n.nspname,
       pg_catalog.has_schema_privilege(r.oid, n.oid, 'USAGE') AS schema_usage
FROM pg_catalog.pg_roles AS r
CROSS JOIN pg_catalog.pg_namespace AS n
WHERE (r.rolname = current_user OR r.oid = (
    SELECT p.proowner FROM pg_catalog.pg_proc AS p WHERE p.oid =
        pg_catalog.to_regprocedure('public.submit_work_evidence(uuid,text,text[])')))
  AND n.nspname IN ('public', 'auth', 'storage')
ORDER BY r.rolname, n.nspname;

-- 7. Client effective table/column privileges: expect ALL false for work_*.
-- Includes inherited/PUBLIC privileges; any true requires investigation.
SELECT r.rolname, c.relname,
       pg_catalog.has_table_privilege(r.oid, c.oid, 'SELECT') AS table_select,
       pg_catalog.has_table_privilege(r.oid, c.oid, 'INSERT') AS table_insert,
       pg_catalog.has_table_privilege(r.oid, c.oid, 'UPDATE') AS table_update,
       pg_catalog.has_table_privilege(r.oid, c.oid, 'DELETE') AS table_delete,
       pg_catalog.has_table_privilege(r.oid, c.oid, 'TRUNCATE') AS table_truncate,
       pg_catalog.has_any_column_privilege(r.oid, c.oid, 'SELECT') AS any_column_select,
       pg_catalog.has_any_column_privilege(r.oid, c.oid, 'INSERT') AS any_column_insert,
       pg_catalog.has_any_column_privilege(r.oid, c.oid, 'UPDATE') AS any_column_update
FROM pg_catalog.pg_roles AS r
CROSS JOIN pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE r.rolname IN ('anon', 'authenticated') AND n.nspname = 'public'
  AND c.relname IN ('work_assignments', 'work_attendance', 'work_evidence',
                   'work_evidence_submissions', 'work_verification_history')
ORDER BY r.rolname, c.relname;

SELECT table_schema, table_name, grantor, grantee, privilege_type, is_grantable
FROM information_schema.table_privileges
WHERE table_schema = 'public' AND table_name IN (
    'work_assignments', 'work_attendance', 'work_evidence',
    'work_evidence_submissions', 'work_verification_history')
ORDER BY table_name, grantee, privilege_type;

-- RPCs: authenticated=true, anon=false for work functions; auth.uid is a helper.
-- Inspect PUBLIC separately because it is not a row in pg_roles.
SELECT n.nspname, p.proname,
       pg_catalog.pg_get_function_identity_arguments(p.oid) AS arguments,
       pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
       pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
       EXISTS (
           SELECT 1 FROM pg_catalog.aclexplode(
               COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) AS acl
           WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
       ) AS public_execute,
       p.proacl AS explicit_acl
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN (
    'submit_work_evidence', 'submit_work_evidence_idempotent',
    'get_my_work_evidence_request', 'list_my_work_assignments',
    'list_work_evidence', 'can_upload_work_evidence', 'can_view_work_evidence',
    'can_read_work_evidence_file', 'request_more_work_evidence', 'verify_work_assignment')
ORDER BY p.proname, arguments;

-- Default function ACLs can add unexpected grantees to newly created functions.
-- No rows means no explicit override, NOT no PUBLIC default. The migration
-- explicitly revokes PUBLIC/anon and grants authenticated in one transaction.
SELECT pg_catalog.pg_get_userbyid(d.defaclrole) AS creator_role,
       n.nspname AS schema_name, d.defaclobjtype, d.defaclacl
FROM pg_catalog.pg_default_acl AS d
LEFT JOIN pg_catalog.pg_namespace AS n ON n.oid = d.defaclnamespace
WHERE d.defaclrole = (SELECT r.oid FROM pg_catalog.pg_roles AS r WHERE r.rolname = current_user)
  AND d.defaclobjtype = 'f' AND (d.defaclnamespace = 0 OR n.nspname = 'public');

-- 8. Already-applied/partial-install detection. Before FIRST application expect
-- ZERO rows from each of these three queries. Any row means STOP: inspect it;
-- do not rerun the draft, drop objects, or assume a complete matching install.
SELECT table_schema, table_name, column_name, data_type, udt_name, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'work_evidence_submissions'
  AND column_name IN ('request_id', 'request_storage_paths')
ORDER BY column_name;

SELECT p.proname, pg_catalog.pg_get_function_identity_arguments(p.oid) AS arguments,
       pg_catalog.pg_get_function_result(p.oid) AS result_type,
       pg_catalog.pg_get_userbyid(p.proowner) AS owner, p.prosecdef, p.proconfig
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('submit_work_evidence_idempotent', 'get_my_work_evidence_request')
ORDER BY p.proname, arguments;

SELECT k.conname, pg_catalog.pg_get_constraintdef(k.oid) AS definition
FROM pg_catalog.pg_constraint AS k
WHERE k.conrelid = pg_catalog.to_regclass('public.work_evidence_submissions')
  AND k.conname IN ('work_evidence_submission_request_unique',
                    'work_evidence_submission_request_consistency');

-- 9. Policies, triggers and dependencies. Review unexplained differences; do not
-- disable them. Internal FK triggers are included. Function dependency catalogs
-- are NOT exhaustive for runtime-resolved PL/pgSQL references; source review is
-- still required. No trigger function body or application data is returned.
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_catalog.pg_policies
WHERE (schemaname = 'public' AND tablename IN (
    'work_assignments', 'work_attendance', 'work_evidence',
    'work_evidence_submissions', 'work_verification_history', 'users'))
   OR (schemaname = 'storage' AND tablename = 'objects')
ORDER BY schemaname, tablename, policyname;

SELECT n.nspname, c.relname, t.tgname, t.tgenabled, t.tgisinternal,
       pg_catalog.pg_get_triggerdef(t.oid) AS definition,
       fn.nspname AS function_schema, p.proname AS trigger_function,
       pg_catalog.pg_get_userbyid(p.proowner) AS function_owner, p.prosecdef
FROM pg_catalog.pg_trigger AS t
JOIN pg_catalog.pg_class AS c ON c.oid = t.tgrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
JOIN pg_catalog.pg_proc AS p ON p.oid = t.tgfoid
JOIN pg_catalog.pg_namespace AS fn ON fn.oid = p.pronamespace
WHERE n.nspname = 'public' AND c.relname IN (
    'work_assignments', 'work_attendance', 'work_evidence',
    'work_evidence_submissions', 'work_verification_history', 'users')
ORDER BY c.relname, t.tgname;

-- DDL event triggers can affect migration execution even without table triggers.
SELECT e.evtname, e.evtevent, e.evtenabled, e.evttags,
       pg_catalog.pg_get_userbyid(e.evtowner) AS event_trigger_owner,
       n.nspname AS function_schema, p.proname AS trigger_function
FROM pg_catalog.pg_event_trigger AS e
JOIN pg_catalog.pg_proc AS p ON p.oid = e.evtfoid
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
ORDER BY e.evtname;

SELECT d.deptype,
       pg_catalog.pg_describe_object(d.classid, d.objid, d.objsubid) AS dependent_object,
       pg_catalog.pg_describe_object(d.refclassid, d.refobjid, d.refobjsubid) AS referenced_object
FROM pg_catalog.pg_depend AS d
WHERE (d.refclassid = 'pg_catalog.pg_class'::regclass
       AND d.refobjid = pg_catalog.to_regclass('public.work_evidence_submissions'))
   OR (d.classid = 'pg_catalog.pg_proc'::regclass
       AND d.objid = pg_catalog.to_regprocedure('public.submit_work_evidence(uuid,text,text[])'))
ORDER BY referenced_object, dependent_object;

-- 10. Lock-risk assessment. The exact count scans submissions but emits no row
-- contents; run ONLY after table existence/access checks pass. Size/count do not
-- predict lock waits. Small tables still require coordination with both devs.
SELECT pg_catalog.count(*) AS submission_row_count
FROM public.work_evidence_submissions;

SELECT c.reltuples AS estimated_rows,
       pg_catalog.pg_relation_size(c.oid) AS heap_bytes,
       pg_catalog.pg_total_relation_size(c.oid) AS total_bytes,
       pg_catalog.pg_size_pretty(pg_catalog.pg_total_relation_size(c.oid)) AS total_size
FROM pg_catalog.pg_class AS c
WHERE c.oid = pg_catalog.to_regclass('public.work_evidence_submissions');

-- Lock inspection exposes no session query text, identities or credentials.
-- Locks are a momentary snapshot. Unexpected activity means coordinate/wait.
SELECT l.pid, l.mode, l.granted, c.relname
FROM pg_catalog.pg_locks AS l
JOIN pg_catalog.pg_class AS c ON c.oid = l.relation
WHERE l.locktype = 'relation'
  AND l.database = (SELECT d.oid FROM pg_catalog.pg_database AS d
                    WHERE d.datname = pg_catalog.current_database())
  AND c.oid IN (pg_catalog.to_regclass('public.work_assignments'),
                pg_catalog.to_regclass('public.work_evidence_submissions'))
ORDER BY c.relname, l.granted, l.pid;

-- 11. KNOWN ASSIGNMENT: confirmed existing Module 4 assignment UUID configured.
-- Do not substitute demo IDs or infer assignment identity from a job title.
-- Expect EXISTS only; this emits no worker/company/name/path/description data.
WITH target AS (
    SELECT '5e103e8a-e51b-41e9-ba8d-6789cb09eea0'::uuid AS assignment_id
)
SELECT CASE WHEN t.assignment_id IS NULL THEN 'BLOCKED: assignment UUID not configured'
            WHEN EXISTS (SELECT 1 FROM public.work_assignments AS a
                         WHERE a.assignment_id = t.assignment_id)
                THEN 'EXISTS: known assignment is present'
            ELSE 'BLOCK: known assignment is missing or not visible' END AS assignment_check
FROM target AS t;

-- Review every result before separately approving deployment. This script does
-- not exercise submission, authentication contexts, rollback or concurrency.
-- Leave Submit Evidence disabled; losing request identity remains unresolved.

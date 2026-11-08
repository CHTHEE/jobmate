# C2 follow-up: membership authorization blockers

Manual inspection only. Every executable block below is a SELECT over PostgreSQL
catalogs. Codex has not executed these queries or inspected the live database.
No application RPCs, application records, authentication records or secrets are
queried. Function/policy bodies are returned as text, never executed.

The owner reports C2 Queries 1–8 are collected, including Storage/logo policy
dependencies. Those actual outputs are not embedded here; this file requests only
remaining definitions and effective privileges needed to assess migration risk.

## Execution and export order

Run blocks **1, 2, 3, 4, 5** separately in the approved project's SQL Editor.
Export each complete result as CSV using the filename indicated. Preserve full
multiline cells, returned/exported row counts, project alias, execution time and
inspection role. Record empty output, permission errors and truncation explicitly.
Do not interpret missing or unreadable metadata as proof an object is safe.

Review literal values in defaults, settings, policy expressions and source before
sharing outside CH/KZ. Redact credentials, signed URLs and personal literals if
found, marking each redaction. Do not execute the DDL text returned in definitions.
No grants or settings should be changed to obtain results without separate approval.

## 1. READ ONLY — named blockers and evaluation authorization

Purpose: retrieve every overload of the required management/onboarding/work RPCs,
plus known evaluation entry points and evaluation-named helpers. Includes a
missing marker for each required name, rather than silently dropping absent RPCs.
Owner, SECURITY DEFINER, search_path/settings and explicit/default execution ACLs
are included. Evaluation helper names beyond the known entry points are discovered,
not assumed to exist. Export: `C2_followup_01_functions.csv`.

```sql
-- READ ONLY: function metadata and source; no function invocation.
WITH required(name) AS (
    VALUES
        ('get_managed_company'),
        ('list_managed_companies'),
        ('submit_company_for_review'),
        ('submit_company_for_review_v2'),
        ('can_review_work_evidence_company'),
        ('create_work_assignment_request'),
        ('verify_work_assignment'),
        ('list_evaluation_candidates'),
        ('list_my_soft_skill_evaluations'),
        ('submit_soft_skill_evaluation')
), names AS (
    SELECT name FROM required
    UNION
    SELECT p.proname::text
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname IN ('public', 'private')
      AND p.prokind IN ('f', 'p')
      AND p.proname ~* '(evaluat|soft_skill)'
), routines AS (
    SELECT p.*, n.nspname
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname IN ('public', 'private')
      AND p.prokind IN ('f', 'p')
)
SELECT
    names.name AS requested_name,
    CASE WHEN p.oid IS NULL THEN 'not_found_in_public_or_private'
         ELSE 'found' END AS inspection_status,
    p.nspname AS schema_name,
    p.prokind AS routine_kind,
    pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    pg_catalog.pg_get_function_arguments(p.oid) AS arguments_with_defaults,
    pg_catalog.pg_get_function_result(p.oid) AS result_type,
    pg_catalog.pg_get_userbyid(p.proowner) AS owner_name,
    p.prosecdef AS security_definer,
    p.proconfig AS settings,
    p.provolatile AS volatility,
    (
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'grantee', CASE WHEN x.grantee = 0 THEN 'PUBLIC'
                ELSE pg_catalog.pg_get_userbyid(x.grantee) END,
            'grantor', pg_catalog.pg_get_userbyid(x.grantor),
            'privilege', x.privilege_type,
            'grantable', x.is_grantable
        ))
        FROM pg_catalog.aclexplode(
            COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))
        ) x
    ) AS execution_acl,
    CASE WHEN p.oid IS NOT NULL
         THEN pg_catalog.pg_get_functiondef(p.oid) END AS definition
FROM names
LEFT JOIN routines p ON p.proname::text = names.name
ORDER BY requested_name, schema_name, identity_arguments;
```

If a body calls an authorization helper not returned here, add its exact name to
the `required` VALUES list and rerun. Follow custom-schema helpers by extending
both schema filters to their actual schema. Retain signatures to disambiguate
overloads. A NULL settings value means no function-local settings are recorded,
not an empty search_path. Known legacy verify RPCs may intentionally have no
client execution privilege; preserve that distinction.

## 2. READ ONLY — complete Storage/logo policies and recorded helpers

Purpose: return all policies on these two relations, including restrictive gates
and indirect helper-based policies. Filtering only expressions containing the
membership table name would miss indirect access and combined-policy effects.
Also reports relation RLS state/owner and recorded policy helper dependencies.
Export: `C2_followup_02_policies.csv`.

```sql
-- READ ONLY: policy definitions and catalog-recorded function dependencies.
SELECT
    n.nspname AS schema_name,
    c.relname AS table_name,
    pg_catalog.pg_get_userbyid(c.relowner) AS table_owner,
    c.relrowsecurity AS rls_enabled,
    c.relforcerowsecurity AS rls_forced,
    p.polname AS policy_name,
    p.polpermissive AS permissive,
    p.polcmd AS command_code,
    ARRAY(
        SELECT CASE WHEN r.role_oid = 0 THEN 'PUBLIC'
                    ELSE pg_catalog.pg_get_userbyid(r.role_oid) END
        FROM pg_catalog.unnest(p.polroles) AS r(role_oid)
    ) AS applies_to_roles,
    pg_catalog.pg_get_expr(p.polqual, p.polrelid) AS using_expression,
    pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid) AS check_expression,
    ARRAY(
        SELECT DISTINCT pg_catalog.pg_describe_object(
            d.refclassid, d.refobjid, d.refobjsubid
        )
        FROM pg_catalog.pg_depend d
        WHERE d.classid = 'pg_catalog.pg_policy'::pg_catalog.regclass
          AND d.objid = p.oid
          AND d.refclassid = 'pg_catalog.pg_proc'::pg_catalog.regclass
    ) AS recorded_function_dependencies
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_catalog.pg_policy p ON p.polrelid = c.oid
WHERE (n.nspname = 'storage' AND c.relname = 'objects')
   OR (n.nspname = 'public' AND c.relname = 'company_logo_change_requests')
ORDER BY schema_name, table_name, policy_name;
```

NULL policy_name means the relation was found without policies. An absent
relation produces no row. Add uncollected custom helper names to Query 1; inspect
their source recursively, including nested Storage helper calls. Do not assume
all memberships should grant private logo-request or Storage access.

## 3. READ ONLY — schema USAGE ACLs and effective access

Purpose: resolve schema access for exposed and private helpers, including PUBLIC
and inherited privileges. Missing schema/role combinations are explicit. Add any
custom schemas discovered above. Export: `C2_followup_03_schema_access.csv`.

```sql
-- READ ONLY: schema ACLs and effective role USAGE privileges.
WITH schemas(name) AS (
    VALUES ('public'), ('private'), ('storage'), ('auth')
), roles(name) AS (
    VALUES ('anon'), ('authenticated'), ('service_role')
)
SELECT
    s.name AS schema_name,
    r.name AS role_name,
    n.oid IS NOT NULL AS schema_exists,
    pr.oid IS NOT NULL AS role_exists,
    pg_catalog.pg_get_userbyid(n.nspowner) AS schema_owner,
    pr.rolinherit AS role_inherits,
    pr.rolsuper AS role_is_superuser,
    pr.rolbypassrls AS role_bypasses_rls,
    CASE WHEN n.oid IS NOT NULL AND pr.oid IS NOT NULL
         THEN pg_catalog.has_schema_privilege(pr.oid, n.oid, 'USAGE')
    END AS effective_usage,
    (
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'grantee', CASE WHEN x.grantee = 0 THEN 'PUBLIC'
                ELSE pg_catalog.pg_get_userbyid(x.grantee) END,
            'grantor', pg_catalog.pg_get_userbyid(x.grantor),
            'privilege', x.privilege_type,
            'grantable', x.is_grantable
        ))
        FROM pg_catalog.aclexplode(
            COALESCE(n.nspacl, pg_catalog.acldefault('n', n.nspowner))
        ) x
    ) AS schema_acl
FROM schemas s
CROSS JOIN roles r
LEFT JOIN pg_catalog.pg_namespace n ON n.nspname = s.name
LEFT JOIN pg_catalog.pg_roles pr ON pr.rolname = r.name
ORDER BY schema_name, role_name;
```

No role authentication fields are selected. Client schema USAGE is not required
merely because an authorized SECURITY DEFINER routine internally calls a private
helper; examine execution identity and the definer's privileges before concluding
a missing client privilege is a defect. Do not broaden grants to make tests pass.

## 4. READ ONLY — effective execution and membership privileges

Purpose: resolve effective EXECUTE (including PUBLIC/inheritance) for named
blockers, evaluation routines and direct membership-querying routines. Inspect
membership table versus column privileges separately because column-only grants
are not equivalent to table-wide grants. Export the two result sets separately as
`C2_followup_04a_execute.csv` and `C2_followup_04b_membership_access.csv`.

```sql
-- READ ONLY: effective execution for migration-sensitive routines.
SELECT
    n.nspname AS schema_name,
    p.proname AS function_name,
    pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    r.rolname AS role_name,
    p.prosecdef AS security_definer,
    pg_catalog.has_schema_privilege(r.oid, n.oid, 'USAGE') AS schema_usage,
    pg_catalog.has_function_privilege(r.oid, p.oid, 'EXECUTE') AS effective_execute
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN pg_catalog.pg_roles r
WHERE p.prokind IN ('f', 'p')
  AND n.nspname IN ('public', 'private')
  AND r.rolname IN ('anon', 'authenticated', 'service_role')
  AND (
      p.proname IN (
          'get_managed_company', 'list_managed_companies',
          'submit_company_for_review', 'submit_company_for_review_v2',
          'can_review_work_evidence_company', 'create_work_assignment_request',
          'verify_work_assignment', 'respond_to_job_application',
          'update_job_application_status', 'can_manage_company_jobs',
          'save_employer_job_posting', 'get_user_account_details'
      )
      OR p.proname ~* '(evaluat|soft_skill)'
      OR p.prosrc ~* 'company_memberships'
  )
ORDER BY schema_name, function_name, identity_arguments, role_name;
```

```sql
-- READ ONLY: effective membership table and per-column privileges.
SELECT
    r.rolname AS role_name,
    a.attname AS column_name,
    pg_catalog.has_table_privilege(r.oid, c.oid, 'SELECT') AS table_select,
    pg_catalog.has_table_privilege(r.oid, c.oid, 'INSERT') AS table_insert,
    pg_catalog.has_table_privilege(r.oid, c.oid, 'UPDATE') AS table_update,
    pg_catalog.has_table_privilege(r.oid, c.oid, 'DELETE') AS table_delete,
    pg_catalog.has_table_privilege(r.oid, c.oid, 'REFERENCES') AS table_references,
    pg_catalog.has_table_privilege(r.oid, c.oid, 'TRIGGER') AS table_trigger,
    pg_catalog.has_table_privilege(r.oid, c.oid, 'TRUNCATE') AS table_truncate,
    pg_catalog.has_column_privilege(r.oid, c.oid, a.attnum, 'SELECT')
        AS column_select,
    pg_catalog.has_column_privilege(r.oid, c.oid, a.attnum, 'INSERT')
        AS column_insert,
    pg_catalog.has_column_privilege(r.oid, c.oid, a.attnum, 'UPDATE')
        AS column_update,
    pg_catalog.has_column_privilege(r.oid, c.oid, a.attnum, 'REFERENCES')
        AS column_references
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid
CROSS JOIN pg_catalog.pg_roles r
WHERE n.nspname = 'public' AND c.relname = 'company_memberships'
  AND a.attnum > 0 AND NOT a.attisdropped
  AND r.rolname IN ('anon', 'authenticated', 'service_role')
ORDER BY role_name, a.attnum;
```

Privilege strings here are arguments to catalog inspection functions, not mutation
statements. These results do not evaluate RLS, application checks, JWT claims or
PostgREST schema exposure. Preserve already-collected raw ACLs; Query 4b is not a
replacement for the complete C1 table/column ACL export if that is still missing.

## 5. READ ONLY — remaining direct membership readers/writers

Purpose: find application routines in any non-system schema that explicitly refer
to memberships. Full bodies expose user-only lookups, scalar SELECT assumptions,
row-multiplying joins, and membership-as-authority checks. No regex can establish
single-membership assumptions conclusively; inspect the source. Export:
`C2_followup_05_membership_functions.csv`.

```sql
-- READ ONLY: direct source references and recorded membership dependencies.
SELECT
    n.nspname AS schema_name,
    p.proname AS function_name,
    pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    pg_catalog.pg_get_userbyid(p.proowner) AS owner_name,
    p.prosecdef AS security_definer,
    p.proconfig AS settings,
    pg_catalog.pg_get_functiondef(p.oid) AS definition
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE p.prokind IN ('f', 'p')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname !~ '^pg_(toast|temp)'
  AND (
      p.prosrc ~* 'company_memberships'
      OR EXISTS (
          SELECT 1
          FROM pg_catalog.pg_depend d
          WHERE d.classid = 'pg_catalog.pg_proc'::pg_catalog.regclass
            AND d.objid = p.oid
            AND d.refclassid = 'pg_catalog.pg_class'::pg_catalog.regclass
            AND d.refobjid = pg_catalog.to_regclass('public.company_memberships')
      )
  )
ORDER BY schema_name, function_name, identity_arguments;
```

This discovery is intentionally narrow. Indirect calls, dynamic SQL assembled
from fragments and view-mediated access can evade it. Use collected C2 Query 8
dependencies and the helper bodies above to close those gaps; retrieve any
uncollected helper with Query 1 before declaring review complete. Add discovered
routine names/schemas to Query 4a when their effective execution remains unknown.

## Review completion criteria

For each returned function/policy, record its signature/name, company selection,
account/membership/Owner/lifecycle checks, authority granted, caller privileges,
and required migration action. Specifically identify ordinary-member escalation,
inactive membership access, Owner onboarding blocked by unrelated memberships,
and multiple-row assumptions. Missing metadata is a blocker, not authorization
to replace a function or change a grant. No production changes are authorized.

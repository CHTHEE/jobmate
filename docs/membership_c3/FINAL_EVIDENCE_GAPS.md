# C3 final evidence gap reduction

**DRAFT / NOT APPROVED FOR DEPLOYMENT. No SQL executed.**

**Resolved update:** the two-table export is integrated in
final_evidence_snapshot.json and combined_evidence_snapshot.json. The original
91-object snapshot is preserved. Do not repeat the query below. See
ISOLATED_TEST_RESULTS.md: runtime testing is now blocked by an incomplete local
PostgreSQL installation, not missing history/notification definitions.

This supersedes earlier broad missing-evidence lists for the next action. The
91-object snapshot, C2 proposal/follow-up guide, C3 integration report, drafts and
KZ checklist were cross-referenced. Do not repeat their completed inspections.

## Evidence already settled

- Full acceptance, management guard, membership schema/keys/indexes/ACLs, Owner
  trigger and 25 selected policies are available in evidence_snapshot.json.
- C2/CH findings establish that submit_company_for_review blocks ordinary members
  of another company, and get_user_account_details assumes one membership. Their
  behavior is NOT an unanswered investigation question. Exact deployed bodies/ACLs
  are still needed only to author compatible KZ patches; summaries are not source.
- Module 4/evaluation lifecycle work is a known compatibility requirement.
- The exact logo/document any-membership ownership error is in supplied policy
  expressions and draft 03 already addresses those predicates.
- Acceptance's existing recipient is job_postings.created_by; its notification
  INSERT is intact. No unknown notification emitter is presumed.
- Historical conflict exclusions must not be changed to active-only merely
  because operational management recipients need lifecycle filtering. This is a
  known semantic split, not a reason to request every notification/conflict RPC.

## Short missing-object list and priority

| Exact missing evidence | Blocks isolated syntax parsing? | Blocks faithful runtime testing of acceptance? | Broader release consequence |
| --- | --- | --- | --- |
| public.application_status_history: columns/defaults/types, constraints, triggers and referenced trigger bodies | No | Yes, original INSERT and rollback/side effects must be exercised against real definitions | Preserve history exactly once |
| public.notifications: same metadata | No | Yes, notification validation/defaults/triggers may fail or create other side effects | Preserve notification event/recipient behavior |
| public.submit_company_for_review and v2; public.get_managed_company/list_managed_companies where actually called | No | Not for a focused acceptance fixture on an already prepared baseline | Exact KZ onboarding patch and regression tests; known failure behavior already established |
| public.get_user_account_details | No | No | Exact versioned KZ Admin projection; known multi-row incompatibility already established |
| public.update_job_application_status and only source-identified alternate Hired writers | No | Not for the target RPC alone | Prevent other authorized writers bypassing enrollment |
| can_review_work_evidence_company, create_work_assignment_request, verify_work_assignment; missing lifecycle-dependent GPS/review helpers and evaluation entry points identified in existing C2 results | No | Not for target acceptance alone | Complete authorization compatibility and cross-module races; retain legacy revoked EXECUTE |

For the last row, evaluation entry points are list_evaluation_candidates,
list_my_soft_skill_evaluations and submit_soft_skill_evaluation. Reuse their
existing follow-up exports. Missing signatures/ACLs are implementation inputs,
not a request to rediscover their behavior. Other helpers are conditional only if
the already-collected bodies show an affected dependency.

Schema privileges/default ACLs, operational recipients and historical conflicts
remain release security review gates where not in supplied results; they do not
prevent static SQL parsing. Existing declared constraints/functions must not be
invented to make an isolated test pass. A matching isolated baseline and PostgreSQL
test environment are also prerequisites for faithful runtime testing, independent
of these two metadata gaps. No such tests have been executed here.

## One targeted READ ONLY export: only the two side-effect tables

Prefer existing results if they cover these objects. Otherwise the authorized
owner may manually run this single catalog SELECT and export its complete JSON
cell as C3_side_effect_tables.json (CSV preserving the cell is also acceptable).
Codex must not execute it. No application/notification rows or authentication
records are read. Inspect returned source/default literals before sharing. Empty
collections/missing markers and errors must be retained; do not execute returned
definition text. This query includes only these tables, associated types and
their triggers, not unrelated company/Admin/dispute functions.

```sql
-- READ ONLY. DRAFT / NOT APPROVED FOR DEPLOYMENT.
WITH RECURSIVE targets AS (
  SELECT c.*,n.nspname FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname IN
    ('application_status_history','notifications')
), used_types(type_oid) AS (
  SELECT DISTINCT a.atttypid FROM pg_catalog.pg_attribute a
  WHERE a.attrelid IN (SELECT oid FROM targets)
    AND a.attnum>0 AND NOT a.attisdropped
  UNION
  SELECT t.typbasetype FROM used_types u
  JOIN pg_catalog.pg_type t ON t.oid=u.type_oid WHERE t.typbasetype<>0
), items AS (
  SELECT 'relation' AS kind,r.relname::text AS identity,
    pg_catalog.jsonb_build_object(
      'owner',pg_catalog.pg_get_userbyid(r.relowner),
      'rls',r.relrowsecurity,'force_rls',r.relforcerowsecurity,
      'acl',COALESCE(r.relacl,pg_catalog.acldefault('r',r.relowner))::text,
      'columns',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'name',a.attname,'type',pg_catalog.format_type(a.atttypid,a.atttypmod),
        'not_null',a.attnotnull,'identity',a.attidentity,'generated',a.attgenerated,
        'acl',a.attacl::text,'default',pg_catalog.pg_get_expr(d.adbin,d.adrelid)
      ) ORDER BY a.attnum)
      FROM pg_catalog.pg_attribute a LEFT JOIN pg_catalog.pg_attrdef d
      ON d.adrelid=a.attrelid AND d.adnum=a.attnum
      WHERE a.attrelid=r.oid AND a.attnum>0 AND NOT a.attisdropped)
    ) AS details FROM targets r
  UNION ALL
  SELECT 'constraint',k.conrelid::pg_catalog.regclass::text||'.'||k.conname,
    pg_catalog.jsonb_build_object('validated',k.convalidated,
      'definition',pg_catalog.pg_get_constraintdef(k.oid,false))
  FROM pg_catalog.pg_constraint k WHERE k.conrelid IN (SELECT oid FROM targets)
  UNION ALL
  SELECT 'index',i.indexrelid::pg_catalog.regclass::text,
    pg_catalog.jsonb_build_object('valid',i.indisvalid,'ready',i.indisready,
      'definition',pg_catalog.pg_get_indexdef(i.indexrelid))
  FROM pg_catalog.pg_index i WHERE i.indrelid IN (SELECT oid FROM targets)
  UNION ALL
  SELECT 'type',n.nspname||'.'||t.typname,
    pg_catalog.jsonb_build_object('kind',t.typtype,'default',t.typdefault,
      'not_null',t.typnotnull,
      'base',CASE WHEN t.typbasetype<>0 THEN
        pg_catalog.format_type(t.typbasetype,t.typtypmod) END,
      'labels',(SELECT pg_catalog.jsonb_agg(e.enumlabel ORDER BY e.enumsortorder)
        FROM pg_catalog.pg_enum e WHERE e.enumtypid=t.oid),
      'constraints',(SELECT pg_catalog.jsonb_agg(
        pg_catalog.pg_get_constraintdef(k.oid,false) ORDER BY k.conname)
        FROM pg_catalog.pg_constraint k WHERE k.contypid=t.oid))
  FROM used_types u JOIN pg_catalog.pg_type t ON t.oid=u.type_oid
  JOIN pg_catalog.pg_namespace n ON n.oid=t.typnamespace WHERE t.typtype IN ('d','e')
  UNION ALL
  SELECT 'trigger',t.tgrelid::pg_catalog.regclass::text||'.'||t.tgname,
    pg_catalog.jsonb_build_object('internal',t.tgisinternal,'enabled',t.tgenabled,
      'definition',pg_catalog.pg_get_triggerdef(t.oid,false),
      'function_schema',n.nspname,'function_name',p.proname,
      'signature',pg_catalog.pg_get_function_identity_arguments(p.oid),
      'owner',pg_catalog.pg_get_userbyid(p.proowner),
      'security_definer',p.prosecdef,'settings',p.proconfig,
      'acl',COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))::text,
      'function_definition',pg_catalog.pg_get_functiondef(p.oid))
  FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE t.tgrelid IN (SELECT oid FROM targets)
  UNION ALL
  SELECT 'policy',p.schemaname||'.'||p.tablename||'.'||p.policyname,
    pg_catalog.jsonb_build_object('permissive',p.permissive,'roles',p.roles,
      'command',p.cmd,'using',p.qual,'check',p.with_check)
  FROM pg_catalog.pg_policies p WHERE p.schemaname='public'
    AND p.tablename IN ('application_status_history','notifications')
)
SELECT pg_catalog.jsonb_build_object(
  'history_found',EXISTS(SELECT 1 FROM targets WHERE relname='application_status_history'),
  'notifications_found',EXISTS(SELECT 1 FROM targets WHERE relname='notifications'),
  'items',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(i)
    ORDER BY i.kind,i.identity) FROM items i)
) AS evidence;
```

Trigger source may expose an exact nested helper not in this bundle. Only that
specific helper then needs its existing export; catalog discovery is not closure.
No blanket request for fresh schema/function discovery follows from this query.

## Next smallest action

Supply the two-table side-effect export, integrate it without changing preserved
INSERT blocks, then prepare faithful isolated acceptance tests. In parallel KZ
can provide/review the already-collected onboarding/Admin originals. No broader
release approval is implied by successful parsing or focused acceptance tests.
All existing SQL draft files remain unchanged, guarded and outside migrations.

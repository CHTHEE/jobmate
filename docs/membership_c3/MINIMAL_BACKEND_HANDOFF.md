# Minimal backend handoff

**DRAFT / NOT APPROVED FOR DEPLOYMENT. No SQL executed.**

## Existing acceptance flow and minimal integration

`lib/features/applications/module2_repository.dart` supplies
`SupabaseMyApplicationsSource` through `myApplications`, unless a source is
injected. `applications_page.dart` passes it to `MyApplicationDetailsPage`.
The confirmation calls `MyApplicationDetailsRepository.respond`, which validates
owned application/status/session, dispatches once and refreshes status/history on
success or failure. `SupabaseMyApplicationsSource.respond` calls
`respond_to_job_application(p_application_id,p_action)` and requires text.

Smallest backend path: revise that SAME deployed RPC while retaining its exact
signature, security settings, ACL, legal actions, text result, history and
notification behavior. Add ordinary enrollment inside its acceptance transaction;
no second client write. The existing client can then benefit without new routing.
The pair-key/member/lifecycle and authorization compatibility drafts remain
prerequisites; just adding an INSERT to the old RPC is insufficient.

For the opt-in source, the future gateway should call the approved same RPC with
the application ID and existing accept_offer action, disabling transport retries.
Inject via `Module2Repository.myApplicationsSource` only after backend release
approval. Do not wire the old RPC into that gateway before approval merely because
its signature matches. No speculative RPC name, capability probe or deployment
flag is needed. Existing production wiring stays unchanged today.

Current update: actual evidence has been supplied and preserved in
`evidence_snapshot.json`. The three files are now partial executable-format,
unexecuted drafts with execution-stop guards. See `EVIDENCE_INTEGRATION.md` for
exact remaining gaps. The export instructions below are historical alternatives,
not a request to collect the supplied objects again.

## One targeted manual export instead of organizing many CSVs

Prefer the existing reviewed export. Otherwise the authorized backend owner may
manually run the single SELECT below and export its complete one JSON cell as
`C3_minimal_backend_evidence.json` or CSV preserving multiline cells. Codex must
not run it. It reads only catalogs, not application/authentication records.
Review literals for secrets before sharing; do not execute returned definitions.

This bundles only the acceptance/management guard, relevant table constraints,
membership indexes/ACLs, interacting triggers and membership-sensitive policies.
It does not replace already-collected helper/dependency evidence. After reading
the actual acceptance body, request only exact missing referenced helpers or
history/notification schema, if needed; no broad rediscovery.

```sql
-- READ ONLY. DRAFT / NOT APPROVED FOR DEPLOYMENT.
WITH tables AS (
    SELECT c.*, n.nspname FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname IN
      ('company_memberships','job_applications','job_postings','users','companies')
), functions AS (
    SELECT p.*, n.nspname FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE p.prokind IN ('f','p') AND (
      (n.nspname='public' AND p.proname IN
        ('respond_to_job_application','can_manage_company_jobs'))
      OR p.oid IN (SELECT t.tgfoid FROM pg_catalog.pg_trigger t
          WHERE t.tgrelid IN (SELECT oid FROM tables) AND NOT t.tgisinternal)
    )
), items AS (
    SELECT 'relation' AS kind, r.relname::text AS identity,
      pg_catalog.jsonb_build_object(
        'owner',pg_catalog.pg_get_userbyid(r.relowner),
        'rls',r.relrowsecurity,'force_rls',r.relforcerowsecurity,
        'acl',COALESCE(r.relacl,pg_catalog.acldefault('r',r.relowner))::text,
        'columns',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'name',a.attname,'type',pg_catalog.format_type(a.atttypid,a.atttypmod),
          'not_null',a.attnotnull,'acl',a.attacl::text,
          'default',pg_catalog.pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum)
          FROM pg_catalog.pg_attribute a LEFT JOIN pg_catalog.pg_attrdef d
          ON d.adrelid=a.attrelid AND d.adnum=a.attnum
          WHERE a.attrelid=r.oid AND a.attnum>0 AND NOT a.attisdropped)
      ) AS details FROM tables r
    UNION ALL
    SELECT 'constraint',k.conrelid::pg_catalog.regclass::text||'.'||k.conname,
      pg_catalog.jsonb_build_object('validated',k.convalidated,
        'definition',pg_catalog.pg_get_constraintdef(k.oid,false))
      FROM pg_catalog.pg_constraint k WHERE k.conrelid IN (SELECT oid FROM tables)
        OR k.confrelid=pg_catalog.to_regclass('public.company_memberships')
    UNION ALL
    SELECT 'index',i.indexrelid::pg_catalog.regclass::text,
      pg_catalog.jsonb_build_object('valid',i.indisvalid,'ready',i.indisready,
        'definition',pg_catalog.pg_get_indexdef(i.indexrelid))
      FROM pg_catalog.pg_index i
      WHERE i.indrelid=pg_catalog.to_regclass('public.company_memberships')
    UNION ALL
    SELECT 'trigger',t.tgrelid::pg_catalog.regclass::text||'.'||t.tgname,
      pg_catalog.jsonb_build_object('enabled',t.tgenabled,
        'definition',pg_catalog.pg_get_triggerdef(t.oid,false))
      FROM pg_catalog.pg_trigger t WHERE t.tgrelid IN (SELECT oid FROM tables)
        AND NOT t.tgisinternal
    UNION ALL
    SELECT 'function',p.nspname||'.'||p.proname||'('||
      pg_catalog.pg_get_function_identity_arguments(p.oid)||')',
      pg_catalog.jsonb_build_object('owner',pg_catalog.pg_get_userbyid(p.proowner),
        'security_definer',p.prosecdef,'settings',p.proconfig,
        'acl',COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))::text,
        'definition',pg_catalog.pg_get_functiondef(p.oid)) FROM functions p
    UNION ALL
    SELECT 'policy',p.schemaname||'.'||p.tablename||'.'||p.policyname,
      pg_catalog.jsonb_build_object('permissive',p.permissive,'roles',p.roles,
        'command',p.cmd,'using',p.qual,'check',p.with_check)
      FROM pg_catalog.pg_policies p WHERE
        (p.schemaname='public' AND p.tablename IN
          ('company_memberships','companies','job_applications',
           'company_logo_change_requests'))
        OR (p.schemaname='storage' AND p.tablename='objects')
)
SELECT pg_catalog.jsonb_build_object(
  'membership_found',EXISTS(SELECT 1 FROM tables WHERE relname='company_memberships'),
  'acceptance_found',EXISTS(SELECT 1 FROM functions
    WHERE nspname='public' AND proname='respond_to_job_application'),
  'items',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(i)
      ORDER BY i.kind,i.identity) FROM items i)
) AS evidence;
```

Verify both found markers, full function endings and exported cell completeness.
Absent sections/errors are not permission to guess. All Storage policies are
included to preserve permissive/restrictive composition; name-only membership
filters can miss an indirect bypass. Domain/enum internals, schema grants and
procedural dependencies can be supplied from existing C2 exports where needed.

## Short approval checklist and next action

- CH/KZ approve exact schema/acceptance/security diffs and preserved ACLs.
- KZ approves owned-company onboarding/Home and Admin compatibility; no ordinary
  private-document, dispute or management-notification access expansion.
- Both approve lifecycle initialization, inactive/revoked denial, historical Hired
  policy, isolated concurrency/security tests and non-destructive recovery.
- Explicit deployment approval/window precedes any separate client activation.

**Next action:** supply the existing original export or the single bundle above.
Complete SQL drafts from originals, then isolated tests and review. No 18-file
organization task, new investigation phase or live execution by Codex is required.

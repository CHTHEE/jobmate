-- READ ONLY. Candidate-specific catalog + pure cutoff predicate verification.
-- This calls only the immutable time predicate, not any attendance/write RPC.
-- NOT authorization/concurrency/evidence workflow runtime proof.
-- Run only after the separately approved Batch 2 migration succeeds. Do not
-- expect old B1 31/31: attendance/evidence/closure definitions intentionally change.
BEGIN READ ONLY;
DO $predicate_guard$
DECLARE p record;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'Run as postgres.'; END IF;
 SELECT f.*,l.lanname INTO p FROM pg_catalog.pg_proc f
 JOIN pg_catalog.pg_language l ON l.oid=f.prolang
 WHERE f.oid=pg_catalog.to_regprocedure('private.attendance_resolution_checkout_allowed(timestamptz,timestamptz)');
 IF NOT FOUND OR p.lanname IS DISTINCT FROM 'sql' OR p.provolatile IS DISTINCT FROM 'i'::"char"
   OR p.prosecdef IS DISTINCT FROM false OR p.prorettype IS DISTINCT FROM 'pg_catalog.bool'::regtype
   OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
   OR pg_catalog.pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'
   OR pg_catalog.md5(replace(replace(p.prosrc,chr(13)||chr(10),chr(10)),chr(13),chr(10)))
      IS DISTINCT FROM '3987d98aab7a35f87250bc684a2fd0b5' THEN
   RAISE EXCEPTION 'Pure cutoff predicate is missing or changed; stop before invocation.';
 END IF;
END;
$predicate_guard$;
WITH functions(signature,required_fragment,expected_definer) AS (VALUES
 ('public.read_work_attendance_resolution(uuid)','can_confirm_absence',true),
 ('public.resolve_work_attendance(uuid,uuid,text,text,text,timestamptz,timestamptz)','reviewed_version',true),
 ('public.list_my_work_assignments_lifecycle()','public.read_work_attendance_resolution',false),
 ('public.list_company_work_assignments_lifecycle(uuid)','public.read_work_attendance_resolution',false),
 ('public.can_upload_work_evidence(uuid)','private.effective_work_attendance',true),
 ('public.prepare_my_work_evidence_submission(uuid,integer,text,text[])','private.effective_work_attendance',true),
 ('public.submit_work_evidence_idempotent(uuid,uuid)','private.effective_work_attendance',true),
 ('public.submit_work_evidence(uuid,text,text[])','private.effective_work_attendance',true),
 ('public.verify_work_assignment(uuid)','private.effective_work_attendance',true),
 ('public.work_evidence_workflow_context(uuid)','private.effective_work_attendance',true),
 ('private.record_job_engagement_closure(uuid,uuid,text)','public.work_attendance_resolutions',true),
 ('public.get_my_job_engagement_closure_status(uuid)','public.work_attendance_resolutions',true)),
checks AS (
 SELECT signature AS object_identity,p.oid IS NOT NULL
  AND pg_catalog.pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef=expected_definer
  AND p.proconfig=ARRAY['search_path=""']::text[] AND strpos(p.prosrc,required_fragment)>0 AS passed,
  pg_catalog.jsonb_build_object('definition_md5',pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)),
    'acl',p.proacl,'definition',pg_catalog.pg_get_functiondef(p.oid)) AS details
 FROM functions f LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(f.signature)
 UNION ALL
 SELECT v.signature||' private ACL',p.oid IS NOT NULL
  AND pg_catalog.pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef=v.definer
  AND p.provolatile::text=v.volatility AND p.proconfig=ARRAY['search_path=""']::text[]
  AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) a WHERE a.grantee<>p.proowner),
  pg_catalog.jsonb_build_object('acl',p.proacl,'definition',pg_catalog.pg_get_functiondef(p.oid))
 FROM (VALUES
  ('private.guard_attendance_resolution_immutable()',true,'v'),
  ('private.guard_attendance_resolution_originals()',true,'v'),
  ('private.guard_attendance_resolution_assignment()',true,'v'),
  ('private.attendance_resolution_version(uuid)',true,'s'),
  ('private.attendance_resolution_checkout_allowed(timestamptz,timestamptz)',false,'i')
 ) v(signature,definer,volatility) LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(v.signature)
 UNION ALL
 SELECT v.signature||' authenticated-only ACL',p.oid IS NOT NULL
  AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
    WHERE a.grantee NOT IN (p.proowner,'authenticated'::regrole) OR (a.grantee<>p.proowner AND a.is_grantable))
  AND pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE'),
  pg_catalog.jsonb_build_object('acl',p.proacl)
 FROM (VALUES('public.read_work_attendance_resolution(uuid)'),
  ('public.resolve_work_attendance(uuid,uuid,text,text,text,timestamptz,timestamptz)')) v(signature)
 LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(v.signature)
 UNION ALL
 SELECT s,pg_catalog.md5(pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure(s)))=h,
  pg_catalog.jsonb_build_object('expected_hash',h)
 FROM (VALUES
  ('public.check_in_work_assignment(uuid,text,numeric,numeric)','da608f2b4ef94bbe4954d2f20d28971a'),
  ('public.list_my_work_assignments()','f9446e58502bc3f39435048c5ff7ef20'),
  ('public.list_company_work_assignments(uuid)','1107b445d7dfdba875b21e551c886ab9'),
  ('public.can_manage_company_jobs(uuid)','7c41597c243580062e49efd25af2f9f0')
 ) v(s,h)
 UNION ALL
 SELECT 'checkout inclusive recovery cutoff',
  strpos(p.prosrc,'private.attendance_resolution_checkout_allowed(v_assignment.scheduled_end,v_check_out_at) IS NOT TRUE')>0,
  pg_catalog.jsonb_build_object('definition',pg_catalog.pg_get_functiondef(p.oid))
 FROM (VALUES(1)) x(n) LEFT JOIN pg_catalog.pg_proc p
  ON p.oid=pg_catalog.to_regprocedure('public.check_out_work_assignment(uuid,text,numeric,numeric)')
 UNION ALL
 SELECT 'cutoff boundary / '||v.name,
   private.attendance_resolution_checkout_allowed('2026-11-05T09:00:00Z'::timestamptz,v.server_time)=v.allowed,
   pg_catalog.jsonb_build_object('allowed',v.allowed)
 FROM (VALUES
  ('one microsecond before','2026-11-06T08:59:59.999999Z'::timestamptz,true),
  ('exactly end plus 24 hours','2026-11-06T09:00:00Z'::timestamptz,true),
  ('one microsecond after','2026-11-06T09:00:00.000001Z'::timestamptz,false)
 ) v(name,server_time,allowed)
 UNION ALL
 SELECT s||' minimum verified work preserved',
  strpos(p.prosrc,'At least one completed and verified Shift is required.')>0
    AND strpos(p.prosrc,'public.work_attendance_resolutions')>0,
  '{}'::jsonb
 FROM (VALUES ('private.record_job_engagement_closure(uuid,uuid,text)'),
  ('public.get_my_job_engagement_closure_status(uuid)')) v(s)
 LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(v.s)
 UNION ALL
 SELECT 'resolution table RLS and no client grants',c.oid IS NOT NULL AND c.relrowsecurity
  AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(coalesce(c.relacl,pg_catalog.acldefault('r',c.relowner))) a WHERE a.grantee<>c.relowner),
  pg_catalog.jsonb_build_object('acl',c.relacl,'rls',c.relrowsecurity)
 FROM (VALUES(1)) x(n) LEFT JOIN pg_catalog.pg_class c ON c.oid=pg_catalog.to_regclass('public.work_attendance_resolutions')
 UNION ALL
 SELECT 'effective attendance view private ACL',c.oid IS NOT NULL AND c.relkind='v'
  AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(coalesce(c.relacl,pg_catalog.acldefault('r',c.relowner))) a WHERE a.grantee<>c.relowner),
  pg_catalog.jsonb_build_object('acl',c.relacl)
 FROM (VALUES(1)) x(n) LEFT JOIN pg_catalog.pg_class c ON c.oid=pg_catalog.to_regclass('private.effective_work_attendance')
 UNION ALL
 SELECT v.table_name||' / '||v.trigger_name,t.oid IS NOT NULL AND t.tgenabled='O' AND NOT t.tgisinternal
  AND t.tgtype=v.type_bits AND t.tgfoid=pg_catalog.to_regprocedure(v.function_name)
  AND t.tgqual IS NULL AND t.tgnargs=0 AND t.tgattr=''::pg_catalog.int2vector
  AND NOT t.tgdeferrable AND NOT t.tginitdeferred,
  pg_catalog.jsonb_build_object('definition',pg_catalog.pg_get_triggerdef(t.oid))
 FROM (VALUES
  ('public.work_attendance_resolutions','attendance_resolution_immutable',27,'private.guard_attendance_resolution_immutable()'),
  ('public.work_attendance','attendance_resolution_preserve_originals',31,'private.guard_attendance_resolution_originals()'),
  ('public.work_assignments','attendance_resolution_assignment_guard',19,'private.guard_attendance_resolution_assignment()')) v(table_name,trigger_name,type_bits,function_name)
 LEFT JOIN pg_catalog.pg_trigger t ON t.tgrelid=pg_catalog.to_regclass(v.table_name) AND t.tgname=v.trigger_name
)
SELECT object_identity,coalesce(passed,false) AS passed,
 bool_and(coalesce(passed,false)) OVER() AS all_checks_passed,details
FROM checks ORDER BY object_identity;
ROLLBACK;

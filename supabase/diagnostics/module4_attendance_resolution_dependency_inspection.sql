-- READ ONLY: Batch 2 live dependency export. One SELECT; no user records,
-- application RPC invocation, settings changes or writes. Run as postgres in
-- the existing project. Return the full result, including definitions and missing
-- markers. Historical migration files cannot establish the current write chain.
WITH required(signature) AS (VALUES
 ('public.can_manage_company_jobs(uuid)'),
 ('public.can_review_work_evidence_company(uuid)'),
 ('public.check_in_work_assignment(uuid,text,numeric,numeric)'),
 ('public.check_out_work_assignment(uuid,text,numeric,numeric)'),
 ('public.list_my_work_assignments()'),
 ('public.list_company_work_assignments(uuid)'),
 ('public.list_my_work_assignments_lifecycle()'),
 ('public.list_company_work_assignments_lifecycle(uuid)'),
 ('public.get_my_job_engagement_closure_status(uuid)'),
 ('private.record_job_engagement_closure(uuid,uuid,text)'),
 ('public.close_job_engagement(uuid,text)'),
 ('public.request_job_engagement_closure(uuid,text)'),
 ('public.respond_job_engagement_closure_request(uuid,text,text)'),
 ('public.cancel_scheduled_work_assignment(uuid,text)'),
 ('public.work_evidence_workflow_context(uuid)'),
 ('public.prepare_my_work_evidence_submission(uuid,integer,text,text[])'),
 ('public.submit_work_evidence_idempotent(uuid,uuid)'),
 ('public.verify_work_assignment(uuid)'),
 ('public.prepare_work_evidence_review(uuid,integer,text,text)'),
 ('public.commit_work_evidence_review(uuid,uuid)')),
relations(name) AS (VALUES
 ('public.work_assignments'), ('public.work_attendance'),
 ('public.job_applications'), ('public.job_postings'),
 ('public.work_assignment_creation_requests'), ('public.work_assignment_shift_claims'),
 ('public.work_assignment_cancellations'), ('public.job_engagement_closures'),
 ('public.job_engagement_closure_requests'), ('public.job_engagement_closure_request_events'),
 ('public.work_evidence_submission_attempts'), ('public.work_evidence_submissions'),
 ('public.work_evidence'), ('public.work_verification_history'),
 ('public.work_evidence_review_requests')),
routine_ids AS (
 SELECT pg_catalog.to_regprocedure(signature)::oid AS oid FROM required
 UNION
 SELECT t.tgfoid FROM pg_catalog.pg_trigger t JOIN relations r
   ON t.tgrelid=pg_catalog.to_regclass(r.name) WHERE NOT t.tgisinternal
 UNION
 -- Include all current overloads/helpers in the relevant workflow, so a guessed
 -- overload above cannot conceal an actual live contract.
 SELECT p.oid FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','private') AND p.prokind='f'
 AND p.proname ~ '(work_evidence|work_verification|engagement_closure|engagement_cancellation|work_attendance)'
), sections AS (
 SELECT '00_context'::text AS section, 'target'::text AS identity,
   pg_catalog.jsonb_build_object('database',pg_catalog.current_database(),
     'role',current_user,'version',pg_catalog.current_setting('server_version'),
     'captured_at',pg_catalog.statement_timestamp()) AS details
 UNION ALL
 SELECT '01_required_presence',r.signature,pg_catalog.jsonb_build_object(
   'found',pg_catalog.to_regprocedure(r.signature) IS NOT NULL) FROM required r
 UNION ALL
 SELECT '02_function',p.oid::regprocedure::text,pg_catalog.jsonb_build_object(
   'owner',pg_catalog.pg_get_userbyid(p.proowner),'acl',p.proacl,
   'config',p.proconfig,'security_definer',p.prosecdef,
   'definition_md5',pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)),
   'definition',pg_catalog.pg_get_functiondef(p.oid))
 FROM routine_ids i JOIN pg_catalog.pg_proc p ON p.oid=i.oid
 UNION ALL
 SELECT '03_relation',r.name,pg_catalog.jsonb_build_object(
   'found',c.oid IS NOT NULL,'owner',pg_catalog.pg_get_userbyid(c.relowner),
   'acl',c.relacl,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
   'columns',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
     'name',a.attname,'type',pg_catalog.format_type(a.atttypid,a.atttypmod),
     'not_null',a.attnotnull,'default',pg_catalog.pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum)
     FROM pg_catalog.pg_attribute a LEFT JOIN pg_catalog.pg_attrdef d
       ON d.adrelid=a.attrelid AND d.adnum=a.attnum
     WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped))
 FROM relations r LEFT JOIN pg_catalog.pg_class c ON c.oid=pg_catalog.to_regclass(r.name)
 UNION ALL
 SELECT '04_constraint',r.name||' / '||x.conname,pg_catalog.jsonb_build_object(
   'definition',pg_catalog.pg_get_constraintdef(x.oid),'validated',x.convalidated)
 FROM relations r JOIN pg_catalog.pg_constraint x ON x.conrelid=pg_catalog.to_regclass(r.name)
 UNION ALL
 SELECT '05_trigger',r.name||' / '||t.tgname,pg_catalog.jsonb_build_object(
   'enabled',t.tgenabled,'definition',pg_catalog.pg_get_triggerdef(t.oid))
 FROM relations r JOIN pg_catalog.pg_trigger t ON t.tgrelid=pg_catalog.to_regclass(r.name)
 WHERE NOT t.tgisinternal
 UNION ALL
 SELECT '06_policy',r.name||' / '||p.polname,pg_catalog.jsonb_build_object(
   'command',p.polcmd,'roles',p.polroles,'permissive',p.polpermissive,
   'using',pg_catalog.pg_get_expr(p.polqual,p.polrelid),
   'check',pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid))
 FROM relations r JOIN pg_catalog.pg_policy p ON p.polrelid=pg_catalog.to_regclass(r.name)
 UNION ALL
 SELECT '07_index',r.name||' / '||i.indexrelid::regclass::text,
   pg_catalog.jsonb_build_object('definition',pg_catalog.pg_get_indexdef(i.indexrelid),
     'valid',i.indisvalid)
 FROM relations r JOIN pg_catalog.pg_index i ON i.indrelid=pg_catalog.to_regclass(r.name)
 UNION ALL
 SELECT '08_ddl_hook',e.evtname,pg_catalog.jsonb_build_object(
   'enabled',e.evtenabled,'event',e.evtevent,'tags',e.evttags,
   'owner',pg_catalog.pg_get_userbyid(e.evtowner),
   'function_owner',pg_catalog.pg_get_userbyid(p.proowner),
   'config',p.proconfig,'security_definer',p.prosecdef,
   'definition_md5',pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)),
   'definition',pg_catalog.pg_get_functiondef(p.oid))
 FROM pg_catalog.pg_event_trigger e JOIN pg_catalog.pg_proc p ON p.oid=e.evtfoid
)
SELECT section,identity,details FROM sections ORDER BY section,identity;

DO $schema_guard$
DECLARE v_table record; v_actual text[]; v_trigger record;
BEGIN
 -- Targeted structural/security checks from the November 14 owner export.
 -- Full relation/constraint/policy definitions remain in the dependency export.
 FOR v_table IN SELECT * FROM (VALUES
  ('public.work_assignments',ARRAY['assignment_id','application_id','job_id','worker_id','company_id','scheduled_start','scheduled_end','workplace_location','status','verification_status','created_by','created_at','updated_at','verified_at']::text[]),
  ('public.work_attendance',ARRAY['attendance_id','assignment_id','check_in_at','check_out_at','check_in_latitude','check_in_longitude','check_out_latitude','check_out_longitude','check_in_location_status','check_out_location_status','created_at','updated_at']::text[]),
  ('public.work_evidence',ARRAY['evidence_id','assignment_id','submitted_by','submission_round','description','storage_path','file_name','mime_type','created_at']::text[]),
  ('public.work_evidence_submissions',ARRAY['submission_id','assignment_id','submission_round','submitted_by','description','file_count','submitted_at']::text[]),
  ('public.work_evidence_submission_attempts',ARRAY['request_id','assignment_id','worker_id','target_round','description','storage_paths','state','submission_id','error_code','created_at','updated_at']::text[])
 ) x(name,columns) LOOP
   SELECT array_agg(a.attname::text ORDER BY a.attnum) INTO v_actual
    FROM pg_catalog.pg_attribute a WHERE a.attrelid=pg_catalog.to_regclass(v_table.name) AND a.attnum>0 AND NOT a.attisdropped;
   IF v_actual IS DISTINCT FROM v_table.columns THEN
     RAISE EXCEPTION 'Column layout drift: %. Stop and review.',v_table.name;
   END IF;
   IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_class c WHERE c.oid=pg_catalog.to_regclass(v_table.name)
     AND c.relkind='r' AND c.relrowsecurity AND NOT c.relforcerowsecurity
     AND pg_catalog.pg_get_userbyid(c.relowner)='postgres') THEN
     RAISE EXCEPTION 'Relation security drift: %.',v_table.name;
   END IF;
   IF EXISTS(SELECT 1 FROM pg_catalog.pg_attribute a
     WHERE a.attrelid=pg_catalog.to_regclass(v_table.name)
      AND a.attname IN ('scheduled_start','scheduled_end','check_in_at','check_out_at','verified_at')
      AND a.atttypid<>'pg_catalog.timestamptz'::regtype) THEN
     RAISE EXCEPTION 'Timestamp type drift: %.',v_table.name;
   END IF;
 END LOOP;
 FOR v_trigger IN SELECT * FROM (VALUES
  ('engagement_cancellation_audit_guard',19,'private.guard_engagement_cancellation_audit()',ARRAY['status']::text[]),
  ('work_assignment_duplicate_shift_guard',23,'public.guard_work_assignment_duplicate_shift()',ARRAY['application_id','scheduled_start','scheduled_end']::text[]),
  ('work_shift_schedule_after_write',21,'private.enforce_work_shift_schedule_after_write()',ARRAY['application_id','scheduled_start','scheduled_end']::text[])
 ) x(name,type_bits,function_name,columns) LOOP
   IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t
     WHERE t.tgrelid='public.work_assignments'::regclass AND t.tgname=v_trigger.name
      AND t.tgenabled='O' AND NOT t.tgisinternal AND t.tgtype=v_trigger.type_bits
      AND t.tgfoid=pg_catalog.to_regprocedure(v_trigger.function_name)
      AND t.tgqual IS NULL AND t.tgnargs=0 AND NOT t.tgdeferrable
      AND ARRAY(SELECT att.attname::text FROM unnest(t.tgattr::smallint[]) WITH ORDINALITY k(num,pos)
        JOIN pg_catalog.pg_attribute att ON att.attrelid=t.tgrelid AND att.attnum=k.num ORDER BY k.pos)=v_trigger.columns) THEN
     RAISE EXCEPTION 'Assignment trigger drift: %.',v_trigger.name;
   END IF;
 END LOOP;
 -- No client policies/direct writes on the protected Module 4 tables.
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_class c
   CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(c.relacl,pg_catalog.acldefault('r',c.relowner))) acl
   WHERE c.oid IN ('public.work_assignments'::regclass,'public.work_attendance'::regclass,
     'public.work_evidence'::regclass,'public.work_evidence_submissions'::regclass,'public.work_evidence_submission_attempts'::regclass)
    AND acl.grantee NOT IN (c.relowner,'service_role'::regrole)) THEN
   RAISE EXCEPTION 'Protected Module 4 table has unexpected direct client grants.';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid IN
   ('public.work_assignments'::regclass,'public.work_attendance'::regclass,
    'public.work_evidence'::regclass,'public.work_evidence_submissions'::regclass,'public.work_evidence_submission_attempts'::regclass)) THEN
   RAISE EXCEPTION 'Protected Module 4 table has unexpected policies.';
 END IF;
 -- Unknown attendance/assignment triggers can change write behavior. Exact
 -- known trigger definitions are independently reviewed in the fresh export.
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t WHERE NOT t.tgisinternal
   AND ((t.tgrelid='public.work_attendance'::regclass AND t.tgname<>'attendance_resolution_preserve_originals')
     OR (t.tgrelid='public.work_assignments'::regclass AND t.tgname NOT IN
       ('engagement_cancellation_audit_guard','work_assignment_duplicate_shift_guard','work_shift_schedule_after_write','attendance_resolution_assignment_guard')))) THEN
   RAISE EXCEPTION 'Unexpected attendance/assignment trigger. Stop and review.';
 END IF;
END;
$schema_guard$;

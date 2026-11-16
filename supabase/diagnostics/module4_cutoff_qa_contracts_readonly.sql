-- READ ONLY: one SELECT, one result. Run separately as postgres.
-- Returns the real deployed definitions, not the local migration candidate.
WITH requested(signature) AS (VALUES
 ('public.check_out_work_assignment(uuid,text,numeric,numeric)'),
 ('public.check_in_work_assignment(uuid,text,numeric,numeric)'),
 ('public.read_work_attendance_resolution(uuid)'),
 ('public.resolve_work_attendance(uuid,uuid,text,text,text,timestamptz,timestamptz)'),
 ('private.attendance_resolution_checkout_allowed(timestamptz,timestamptz)'),
 ('private.validate_work_shift_schedule(timestamptz,timestamptz)'),
 ('private.enforce_work_shift_schedule_after_write()'))
SELECT statement_timestamp() AS captured_at,current_user AS inspected_as,
 r.signature,p.oid IS NOT NULL AS found,
 pg_get_functiondef(p.oid) AS definition,
 md5(pg_get_functiondef(p.oid)) AS definition_md5,
 pg_get_userbyid(p.proowner) AS owner,p.proacl AS acl,
 p.prosecdef AS security_definer,p.proconfig AS config
FROM requested r LEFT JOIN pg_proc p ON p.oid=to_regprocedure(r.signature)
ORDER BY r.signature;

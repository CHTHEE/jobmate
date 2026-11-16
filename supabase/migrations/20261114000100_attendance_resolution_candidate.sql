-- FORWARD-ONLY REVIEW CANDIDATE. NOT EXECUTED. Owner approval + maintenance
-- window required. Based on the owner's 2026-11-14 06:35:58 UTC catalog export.
-- Install as one transaction; stop on any drift. Never bypass assertions.
-- Originals/GPS remain untouched. One immutable final resolution per assignment.
-- Corrections are limited to ended, unverified work BEFORE any evidence attempt.
-- Effective checkout +24h remains an ADVISORY evidence target, even if past.
-- Ordinary checkout cutoff is end+24h INCLUSIVE; historical active shifts retain
-- the employer correction path. All-absent/no-verified engagements remain blocked
-- from normal successful closure; unsuccessful closure requires separate approval.
BEGIN;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET LOCAL lock_timeout='2s';
SET LOCAL statement_timeout='60s';
SET LOCAL search_path='';
SET LOCAL check_function_bodies=on;
LOCK TABLE public.job_applications, public.work_assignments, public.work_attendance,
 public.work_evidence, public.work_evidence_submission_attempts,
 public.work_evidence_submissions, public.job_engagement_closures
 IN SHARE ROW EXCLUSIVE MODE;

DO $baseline$
DECLARE v_dependency record; v_proc pg_catalog.pg_proc; v_hook record; v_expected_acl text;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'Run as postgres.'; END IF;
 IF current_setting('session_replication_role')<>'origin' THEN RAISE EXCEPTION 'Normal origin triggers are required.'; END IF;
 IF current_database()<>'postgres' OR current_setting('server_version_num')::integer/10000<>17 THEN
   RAISE EXCEPTION 'Expected the reviewed postgres database on PostgreSQL 17. Stop and review.';
 END IF;
 -- Fresh owner export: 2026-11-14 08:21:03 UTC. Extension-tagged handlers
 -- cannot fire here: this file creates/drops no extension. The only applicable
 -- handlers are the fingerprinted transactional NOTIFY watchers. Never disable
 -- event triggers. Pause concurrent administrator DDL throughout this run.
 FOR v_hook IN SELECT * FROM (VALUES
  ('issue_graphql_placeholder','sql_drop',ARRAY['DROP EXTENSION']::text[],'set_graphql_placeholder','8da9dff6b2ae47498209d341acaeb60b'),
  ('issue_pg_cron_access','ddl_command_end',ARRAY['CREATE EXTENSION']::text[],'grant_pg_cron_access','53a44336da0ac1dd62d89dbd988e6d1d'),
  ('issue_pg_graphql_access','ddl_command_end',ARRAY['CREATE EXTENSION']::text[],'grant_pg_graphql_access','4e6d7efe4aed1b3b92063b648aa7a0cf'),
  ('issue_pg_net_access','ddl_command_end',ARRAY['CREATE EXTENSION']::text[],'grant_pg_net_access','1d06ef4fb47bb0ab6e6f8818a62013bb'),
  ('pgrst_ddl_watch','ddl_command_end',NULL::text[],'pgrst_ddl_watch','afaad7193dcf8f81e728d2bedb85e43e'),
  ('pgrst_drop_watch','sql_drop',NULL::text[],'pgrst_drop_watch','4357772baf5cfcd5c6d7049585b3a537')
 ) h(name,event_name,tags,function_name,hash) LOOP
   IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_event_trigger et
     JOIN pg_catalog.pg_proc fp ON fp.oid=et.evtfoid
     JOIN pg_catalog.pg_namespace ns ON ns.oid=fp.pronamespace
     JOIN pg_catalog.pg_language lang ON lang.oid=fp.prolang
     WHERE et.evtname=v_hook.name AND et.evtevent=v_hook.event_name AND et.evtenabled='O'
       AND et.evttags IS NOT DISTINCT FROM v_hook.tags AND pg_catalog.pg_get_userbyid(et.evtowner)='supabase_admin'
       AND ns.nspname='extensions' AND fp.proname=v_hook.function_name AND lang.lanname='plpgsql'
       AND fp.prokind='f' AND fp.pronargs=0 AND fp.prorettype='pg_catalog.event_trigger'::regtype
       AND pg_catalog.pg_get_userbyid(fp.proowner)='supabase_admin' AND NOT fp.prosecdef
       AND fp.proconfig=ARRAY['search_path=""']::text[]
       AND pg_catalog.md5(pg_catalog.pg_get_functiondef(fp.oid))=v_hook.hash) THEN
     RAISE EXCEPTION 'DDL hook drift: %. Review; do not bypass.',v_hook.name;
   END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_event_trigger et
   WHERE et.evtenabled IN ('O','A') AND et.evtname NOT IN
     ('issue_graphql_placeholder','issue_pg_cron_access','issue_pg_graphql_access','issue_pg_net_access','pgrst_ddl_watch','pgrst_drop_watch')) THEN
   RAISE EXCEPTION 'An unreviewed DDL hook is enabled. Stop before DDL.';
 END IF;
 IF pg_catalog.to_regclass('public.work_attendance_resolutions') IS NOT NULL
 OR pg_catalog.to_regclass('private.effective_work_attendance') IS NOT NULL
 OR EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
   WHERE (n.nspname='public' AND p.proname IN ('read_work_attendance_resolution','resolve_work_attendance'))
      OR (n.nspname='private' AND p.proname LIKE '%attendance_resolution%')) THEN
   RAISE EXCEPTION 'Resolution objects already exist; stop without replacing.';
 END IF;
 FOR v_dependency IN SELECT * FROM (VALUES
  ('public.check_in_work_assignment(uuid,text,numeric,numeric)','da608f2b4ef94bbe4954d2f20d28971a'),
  ('public.check_out_work_assignment(uuid,text,numeric,numeric)','cd78151fc05490eb8f98a428a85c3c70'),
  ('public.can_manage_company_jobs(uuid)','7c41597c243580062e49efd25af2f9f0'),
  ('public.can_upload_work_evidence(uuid)','d50c05f8d652078576f87a7c647179ef'),
  ('public.prepare_my_work_evidence_submission(uuid,integer,text,text[])','b39f4a971e8fc142c4efcc86ea4d93c7'),
  ('public.submit_work_evidence_idempotent(uuid,uuid)','d98aea4af60e18d9512cfa46b871126b'),
  ('public.submit_work_evidence(uuid,text,text[])','5195aae515ef8e086e7425ec6dda22b2'),
  ('public.verify_work_assignment(uuid)','ec96a7903fc4862b0f5dd8ad278c41a3'),
  ('public.work_evidence_workflow_context(uuid)','ca1660b0f2e5431ca35c4829a5507589'),
  ('public.get_my_job_engagement_closure_status(uuid)','509870d7889729e60d8a02575ff3588e'),
  ('private.record_job_engagement_closure(uuid,uuid,text)','eecdf7e6d167363639b505a7dbc8a6a0'),
  ('public.list_my_work_assignments_lifecycle()','cd76afeeff57cab178752f0df2e7ac6e'),
  ('public.list_company_work_assignments_lifecycle(uuid)','e335fe97b779bacd624d0bb5cea0b590')
 ) v(signature,hash) LOOP
   SELECT * INTO v_proc FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(v_dependency.signature);
   v_expected_acl:=CASE
     WHEN v_dependency.signature LIKE 'private.%' THEN '{postgres=X/postgres}'
     WHEN v_dependency.signature IN ('public.submit_work_evidence(uuid,text,text[])','public.verify_work_assignment(uuid)')
       THEN '{postgres=X/postgres,service_role=X/postgres}'
     WHEN v_dependency.signature IN ('public.get_my_job_engagement_closure_status(uuid)',
       'public.list_my_work_assignments_lifecycle()','public.list_company_work_assignments_lifecycle(uuid)')
       THEN '{postgres=X/postgres,authenticated=X/postgres}'
     ELSE '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' END;
   IF NOT FOUND OR pg_catalog.md5(pg_catalog.pg_get_functiondef(v_proc.oid)) IS DISTINCT FROM v_dependency.hash
      OR pg_catalog.pg_get_userbyid(v_proc.proowner)<>'postgres'
      OR v_proc.proacl::text IS DISTINCT FROM v_expected_acl
      OR v_proc.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[] THEN
     RAISE EXCEPTION 'Live dependency drift: %. Review new definitions.',v_dependency.signature;
   END IF;
 END LOOP;
 -- No existing active shift may lose ordinary checkout without a correction path.
 IF EXISTS(SELECT 1 FROM public.work_assignments a
   LEFT JOIN public.job_applications j ON j.application_id=a.application_id
   LEFT JOIN public.job_postings p ON p.job_id=j.job_id
   WHERE a.status='active' AND (a.verification_status<>'not_submitted' OR a.verified_at IS NOT NULL
    OR j.status IS DISTINCT FROM 'hired' OR j.applicant_id IS DISTINCT FROM a.worker_id
    OR j.job_id IS DISTINCT FROM a.job_id OR p.company_id IS DISTINCT FROM a.company_id
    OR EXISTS(SELECT 1 FROM public.job_engagement_closures c WHERE c.application_id=a.application_id)
    OR EXISTS(SELECT 1 FROM public.work_evidence e WHERE e.assignment_id=a.assignment_id)
    OR EXISTS(SELECT 1 FROM public.work_evidence_submissions s WHERE s.assignment_id=a.assignment_id)
    OR EXISTS(SELECT 1 FROM public.work_evidence_submission_attempts t WHERE t.assignment_id=a.assignment_id)
    OR EXISTS(SELECT 1 FROM public.disputes d WHERE d.status IN ('open','investigating','pending_information')
      AND (d.application_id=a.application_id OR d.assignment_id=a.assignment_id))
    OR NOT EXISTS(SELECT 1 FROM public.users u JOIN public.company_memberships m ON m.user_id=u.user_id
      JOIN public.companies c ON c.company_id=m.company_id WHERE m.company_id=a.company_id
      AND u.role='employer' AND u.status='active' AND m.member_role IN ('owner','employer')
      AND c.verification_status='verified'))) THEN
   RAISE EXCEPTION 'Historical active shifts require a separately reviewed recovery path before cutoff deployment.';
 END IF;
END;
$baseline$;

CREATE TABLE public.work_attendance_resolutions (
 request_id uuid PRIMARY KEY,
 assignment_id uuid NOT NULL UNIQUE REFERENCES public.work_assignments ON DELETE RESTRICT,
 application_id uuid NOT NULL REFERENCES public.job_applications ON DELETE RESTRICT,
 company_id uuid NOT NULL REFERENCES public.companies ON DELETE RESTRICT,
 worker_id uuid NOT NULL REFERENCES public.users ON DELETE RESTRICT,
 decision text NOT NULL CHECK(decision IN ('confirmed_absent','corrected')),
 reason text NOT NULL CHECK(reason=btrim(reason) AND reason ~ '[^[:space:]]' AND char_length(reason)<=2000),
 corrected_check_in_at timestamptz,
 corrected_check_out_at timestamptz,
 original_attendance jsonb NOT NULL,
 original_assignment_status text NOT NULL,
 reviewed_version text NOT NULL,
 resolved_by uuid NOT NULL REFERENCES public.users ON DELETE RESTRICT,
 resolved_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK ((decision='confirmed_absent' AND corrected_check_in_at IS NULL AND corrected_check_out_at IS NULL)
   OR (decision='corrected' AND corrected_check_in_at IS NOT NULL AND corrected_check_out_at IS NOT NULL
       AND isfinite(corrected_check_in_at) AND isfinite(corrected_check_out_at)
       AND corrected_check_out_at>=corrected_check_in_at AND corrected_check_out_at<=resolved_at))
);
ALTER TABLE public.work_attendance_resolutions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.work_attendance_resolutions FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.guard_attendance_resolution_immutable() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
BEGIN RAISE EXCEPTION 'Attendance resolution audit is immutable.' USING ERRCODE='42501'; END;
$f$;
REVOKE ALL ON FUNCTION private.guard_attendance_resolution_immutable() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER attendance_resolution_immutable BEFORE UPDATE OR DELETE ON public.work_attendance_resolutions
 FOR EACH ROW EXECUTE FUNCTION private.guard_attendance_resolution_immutable();

CREATE FUNCTION private.guard_attendance_resolution_originals() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 IF current_setting('transaction_isolation')<>'read committed' THEN
   RAISE EXCEPTION 'Attendance writes require READ COMMITTED.' USING ERRCODE='22023';
 END IF;
 -- Trusted direct writers must not race an assignment-scoped resolution. NOWAIT
 -- avoids an attendance->assignment wait cycle with the normal RPC lock order.
 PERFORM 1 FROM public.work_assignments a
 WHERE a.assignment_id=CASE WHEN TG_OP='INSERT' THEN NEW.assignment_id ELSE OLD.assignment_id END
 FOR UPDATE NOWAIT;
 IF TG_OP='UPDATE' AND NEW.assignment_id IS DISTINCT FROM OLD.assignment_id THEN
   RAISE EXCEPTION 'Attendance identity cannot be changed.' USING ERRCODE='42501';
 END IF;
 IF EXISTS(SELECT 1 FROM public.work_attendance_resolutions r
   WHERE r.assignment_id=CASE WHEN TG_OP='INSERT' THEN NEW.assignment_id ELSE OLD.assignment_id END)
   OR (TG_OP='UPDATE' AND EXISTS(SELECT 1 FROM public.work_attendance_resolutions r WHERE r.assignment_id=NEW.assignment_id)) THEN
   RAISE EXCEPTION 'Original attendance is preserved after employer resolution.' USING ERRCODE='42501';
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END;
$f$;
REVOKE ALL ON FUNCTION private.guard_attendance_resolution_originals() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER attendance_resolution_preserve_originals BEFORE INSERT OR UPDATE OR DELETE ON public.work_attendance
 FOR EACH ROW EXECUTE FUNCTION private.guard_attendance_resolution_originals();

CREATE FUNCTION private.guard_attendance_resolution_assignment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE v_decision text;
BEGIN
 IF current_setting('transaction_isolation')<>'read committed' THEN
   RAISE EXCEPTION 'Assignment lifecycle writes require READ COMMITTED.' USING ERRCODE='22023';
 END IF;
 SELECT r.decision INTO v_decision FROM public.work_attendance_resolutions r WHERE r.assignment_id=OLD.assignment_id;
 IF FOUND THEN
   IF (NEW.application_id,NEW.worker_id,NEW.company_id,NEW.job_id,NEW.scheduled_start,NEW.scheduled_end)
      IS DISTINCT FROM (OLD.application_id,OLD.worker_id,OLD.company_id,OLD.job_id,OLD.scheduled_start,OLD.scheduled_end)
      OR (v_decision='confirmed_absent' AND (NEW.status,NEW.verification_status,NEW.verified_at)
        IS DISTINCT FROM (OLD.status,OLD.verification_status,OLD.verified_at))
      OR (v_decision='corrected' AND NEW.status NOT IN ('awaiting_verification','completed','disputed')) THEN
     RAISE EXCEPTION 'Resolved attendance cannot be relinked, rescheduled or reopened.' USING ERRCODE='42501';
   END IF;
 END IF;
 RETURN NEW;
END;
$f$;
REVOKE ALL ON FUNCTION private.guard_attendance_resolution_assignment() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER attendance_resolution_assignment_guard BEFORE UPDATE ON public.work_assignments
 FOR EACH ROW EXECUTE FUNCTION private.guard_attendance_resolution_assignment();

CREATE VIEW private.effective_work_attendance AS
 SELECT a.assignment_id,
   CASE WHEN r.decision='corrected' THEN r.corrected_check_in_at ELSE att.check_in_at END AS check_in_at,
   CASE WHEN r.decision='corrected' THEN r.corrected_check_out_at ELSE att.check_out_at END AS check_out_at
 FROM public.work_assignments a
 LEFT JOIN public.work_attendance att ON att.assignment_id=a.assignment_id
 LEFT JOIN public.work_attendance_resolutions r ON r.assignment_id=a.assignment_id
 WHERE (att.assignment_id IS NOT NULL OR r.decision='corrected')
   AND r.decision IS DISTINCT FROM 'confirmed_absent';
REVOKE ALL ON private.effective_work_attendance FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.attendance_resolution_version(p_assignment_id uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $f$
 SELECT md5(jsonb_build_array(a.assignment_id,a.application_id,a.worker_id,a.company_id,a.job_id,
   a.status,a.verification_status,a.verified_at,a.scheduled_start,a.scheduled_end,a.updated_at,
   to_jsonb(att),r.request_id,
   EXISTS(SELECT 1 FROM public.job_engagement_closures c WHERE c.application_id=a.application_id))::text)
 FROM public.work_assignments a LEFT JOIN public.work_attendance att ON att.assignment_id=a.assignment_id
 LEFT JOIN public.work_attendance_resolutions r ON r.assignment_id=a.assignment_id
 WHERE a.assignment_id=p_assignment_id;
$f$;
REVOKE ALL ON FUNCTION private.attendance_resolution_version(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.attendance_resolution_checkout_allowed(p_scheduled_end timestamptz,p_server_time timestamptz)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path='' AS $f$
 SELECT p_server_time <= p_scheduled_end + interval '24 hours'
$f$;
REVOKE ALL ON FUNCTION private.attendance_resolution_checkout_allowed(timestamptz,timestamptz) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.read_work_attendance_resolution(p_assignment_id uuid) RETURNS jsonb
-- One statement snapshot keeps authorization, version and audit reads coherent.
-- The VOLATILE write RPC calls this in fresh SPI statements after locking/writes.
-- https://www.postgresql.org/docs/17/xfunc-volatility.html
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $f$
DECLARE a public.work_assignments; r public.work_attendance_resolutions;
 v_employer boolean; v_worker boolean; v_eligible boolean; v_absent boolean; v_now timestamptz:=statement_timestamp();
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.' USING ERRCODE='28000'; END IF;
 SELECT * INTO a FROM public.work_assignments WHERE assignment_id=p_assignment_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Attendance access denied.' USING ERRCODE='42501'; END IF;
 v_employer:=public.can_manage_company_jobs(a.company_id) IS TRUE;
 v_worker:=a.worker_id=auth.uid() AND EXISTS(SELECT 1 FROM public.users u WHERE u.user_id=auth.uid() AND u.role='job_seeker' AND u.status='active');
 IF NOT v_worker AND NOT v_employer THEN RAISE EXCEPTION 'Attendance access denied.' USING ERRCODE='42501'; END IF;
 SELECT * INTO r FROM public.work_attendance_resolutions WHERE assignment_id=p_assignment_id;
 v_eligible:=r.request_id IS NULL AND a.status IN ('scheduled','active','awaiting_verification')
  AND a.verification_status='not_submitted' AND a.verified_at IS NULL AND v_now>a.scheduled_end
  AND EXISTS(SELECT 1 FROM public.job_applications j JOIN public.job_postings p ON p.job_id=j.job_id
    WHERE j.application_id=a.application_id AND j.status='hired' AND j.applicant_id=a.worker_id AND j.job_id=a.job_id AND p.company_id=a.company_id)
  AND NOT EXISTS(SELECT 1 FROM public.job_engagement_closures c WHERE c.application_id=a.application_id)
  AND NOT EXISTS(SELECT 1 FROM public.work_evidence e WHERE e.assignment_id=a.assignment_id)
  AND NOT EXISTS(SELECT 1 FROM public.work_evidence_submissions s WHERE s.assignment_id=a.assignment_id)
  AND NOT EXISTS(SELECT 1 FROM public.work_evidence_submission_attempts t WHERE t.assignment_id=a.assignment_id)
  AND NOT EXISTS(SELECT 1 FROM public.disputes d WHERE d.status IN ('open','investigating','pending_information') AND (d.application_id=a.application_id OR d.assignment_id=a.assignment_id));
 v_absent:=a.status='scheduled' AND NOT EXISTS(SELECT 1 FROM public.work_attendance att
   WHERE att.assignment_id=a.assignment_id AND (att.check_in_at IS NOT NULL OR att.check_out_at IS NOT NULL
     OR att.check_in_location_status IS NOT NULL OR att.check_out_location_status IS NOT NULL
     OR att.check_in_latitude IS NOT NULL OR att.check_in_longitude IS NOT NULL
     OR att.check_out_latitude IS NOT NULL OR att.check_out_longitude IS NOT NULL));
 RETURN jsonb_build_object('contract_version',2,'assignment_id',a.assignment_id,
   'version',private.attendance_resolution_version(a.assignment_id),
   'can_confirm_absence',v_employer AND v_eligible AND v_absent,
   'can_correct',v_employer AND v_eligible,'checkout_recovery_enforced',true,
   'original_location',(SELECT jsonb_build_object('check_in_status',att.check_in_location_status,
      'check_out_status',att.check_out_location_status) FROM public.work_attendance att WHERE att.assignment_id=a.assignment_id),
   'recovery_cutoff',a.scheduled_end+interval '24 hours',
   'resolution',CASE WHEN r.request_id IS NULL THEN NULL ELSE jsonb_build_object(
     'request_id',r.request_id,'decision',r.decision,'reason',r.reason,'resolved_by',r.resolved_by,
     'resolved_at',r.resolved_at,'corrected_check_in_at',r.corrected_check_in_at,
     'corrected_check_out_at',r.corrected_check_out_at) END);
END;
$f$;
REVOKE ALL ON FUNCTION public.read_work_attendance_resolution(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_work_attendance_resolution(uuid) TO authenticated;

CREATE FUNCTION public.resolve_work_attendance(p_assignment_id uuid,p_request_id uuid,p_expected_version text,
 p_decision text,p_reason text,p_check_in_at timestamptz DEFAULT NULL,p_check_out_at timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE a public.work_assignments; r public.work_attendance_resolutions;
 v_app uuid; v_context jsonb; v_now timestamptz; v_original jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.' USING ERRCODE='28000'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN
   RAISE EXCEPTION 'Attendance resolution requires READ COMMITTED.' USING ERRCODE='22023';
 END IF;
 SELECT application_id INTO v_app FROM public.work_assignments
 WHERE assignment_id=p_assignment_id AND public.can_manage_company_jobs(company_id) IS TRUE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Attendance access denied.' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM public.job_applications WHERE application_id=v_app FOR UPDATE;
 SELECT * INTO a FROM public.work_assignments WHERE assignment_id=p_assignment_id FOR UPDATE;
 IF NOT FOUND OR a.application_id IS DISTINCT FROM v_app OR public.can_manage_company_jobs(a.company_id) IS NOT TRUE THEN
   RAISE EXCEPTION 'Attendance access denied.' USING ERRCODE='42501';
 END IF;
 PERFORM 1 FROM public.work_attendance WHERE assignment_id=p_assignment_id FOR UPDATE;
 IF p_request_id IS NULL OR p_expected_version IS NULL OR p_decision IS NULL OR p_decision NOT IN ('confirmed_absent','corrected')
  OR p_reason IS NULL OR p_reason !~ '[^[:space:]]' OR char_length(btrim(p_reason))>2000 THEN
   RAISE EXCEPTION 'Choose a decision and provide a reason of 1 to 2000 characters.' USING ERRCODE='22023';
 END IF;
 SELECT * INTO r FROM public.work_attendance_resolutions WHERE request_id=p_request_id OR assignment_id=p_assignment_id;
 IF FOUND THEN
   IF r.request_id=p_request_id AND r.assignment_id=p_assignment_id AND r.resolved_by=auth.uid()
    AND r.decision=p_decision AND r.reason=btrim(p_reason) AND r.reviewed_version=p_expected_version
    AND r.corrected_check_in_at IS NOT DISTINCT FROM p_check_in_at AND r.corrected_check_out_at IS NOT DISTINCT FROM p_check_out_at THEN
     RETURN public.read_work_attendance_resolution(p_assignment_id);
   END IF;
   RAISE EXCEPTION 'Attendance was already resolved or this request conflicts. Refresh.' USING ERRCODE='22023';
 END IF;
 v_context:=public.read_work_attendance_resolution(p_assignment_id);
 IF v_context->>'version' IS DISTINCT FROM p_expected_version
    OR (p_decision='confirmed_absent' AND (v_context->>'can_confirm_absence')::boolean IS NOT TRUE)
    OR (p_decision='corrected' AND (v_context->>'can_correct')::boolean IS NOT TRUE) THEN
   RAISE EXCEPTION 'Attendance changed or is no longer eligible. Refresh before reviewing.' USING ERRCODE='22023';
 END IF;
 v_now:=clock_timestamp();
 IF p_decision='confirmed_absent' AND (p_check_in_at IS NOT NULL OR p_check_out_at IS NOT NULL) THEN
   RAISE EXCEPTION 'Absence must not include attendance timestamps.' USING ERRCODE='22023';
 ELSIF p_decision='corrected' AND (p_check_in_at IS NULL OR p_check_out_at IS NULL
   OR NOT isfinite(p_check_in_at) OR NOT isfinite(p_check_out_at)
   OR p_check_in_at<a.scheduled_start-interval '60 minutes' OR p_check_in_at>a.scheduled_end
   OR p_check_out_at<p_check_in_at
   OR p_check_in_at>v_now OR p_check_out_at>v_now) THEN
   RAISE EXCEPTION 'Corrected times must be chronological, not future, with check-in inside its allowed window.' USING ERRCODE='22023';
 END IF;
 SELECT to_jsonb(att) INTO v_original FROM public.work_attendance att WHERE att.assignment_id=a.assignment_id;
 INSERT INTO public.work_attendance_resolutions(request_id,assignment_id,application_id,company_id,worker_id,
  decision,reason,corrected_check_in_at,corrected_check_out_at,original_attendance,original_assignment_status,
  reviewed_version,resolved_by,resolved_at)
 VALUES(p_request_id,a.assignment_id,a.application_id,a.company_id,a.worker_id,p_decision,btrim(p_reason),
  p_check_in_at,p_check_out_at,coalesce(v_original,'null'::jsonb),a.status,p_expected_version,auth.uid(),v_now);
 IF p_decision='corrected' THEN
   UPDATE public.work_assignments SET status='awaiting_verification',updated_at=v_now WHERE assignment_id=a.assignment_id;
 END IF;
 RETURN public.read_work_attendance_resolution(p_assignment_id);
END;
$f$;
REVOKE ALL ON FUNCTION public.resolve_work_attendance(uuid,uuid,text,text,text,timestamptz,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.resolve_work_attendance(uuid,uuid,text,text,text,timestamptz,timestamptz) TO authenticated;

-- Deterministic, fingerprint-guarded edits to the ACTUAL inspected definitions.
-- Existing signatures, owners, grants, auth, GPS, storage/audit and idempotency
-- statements are retained. Only attendance reads use the private effective view.
DO $integrate$
DECLARE s text; d text; old_text text; new_text text;
BEGIN
 FOREACH s IN ARRAY ARRAY['public.can_upload_work_evidence(uuid)',
  'public.prepare_my_work_evidence_submission(uuid,integer,text,text[])',
  'public.submit_work_evidence_idempotent(uuid,uuid)','public.submit_work_evidence(uuid,text,text[])',
  'public.verify_work_assignment(uuid)','public.work_evidence_workflow_context(uuid)'] LOOP
  d:=pg_get_functiondef(s::regprocedure);
  IF strpos(d,'public.work_attendance')=0 THEN RAISE EXCEPTION 'Expected attendance read missing: %',s; END IF;
  EXECUTE replace(d,'public.work_attendance','private.effective_work_attendance');
 END LOOP;
 FOREACH s IN ARRAY ARRAY['private.record_job_engagement_closure(uuid,uuid,text)',
   'public.get_my_job_engagement_closure_status(uuid)'] LOOP
   d:=pg_get_functiondef(s::regprocedure);
   old_text:=CASE WHEN s LIKE 'private.%' THEN 'or (a.status=''cancelled'' and exists('
      ELSE 'OR (a.status=''cancelled'' AND EXISTS (' END;
   new_text:='or exists(select 1 from public.work_attendance_resolutions ar where ar.assignment_id=a.assignment_id and ar.decision=''confirmed_absent'') '||old_text;
   IF strpos(d,old_text)=0 OR strpos(substr(d,strpos(d,old_text)+length(old_text)),old_text)>0 THEN
     RAISE EXCEPTION 'Closure predicate differs: %',s;
   END IF;
   d:=replace(d,old_text,new_text);
   d:=replace(d,'Every Shift must be completed and verified, or have an audited cancellation.',
     'Every Shift must be verified, confirmed absent, or have an audited cancellation.');
   EXECUTE d;
 END LOOP;
 d:=replace(pg_get_functiondef('public.check_out_work_assignment(uuid,text,numeric,numeric)'::regprocedure),E'\r\n',E'\n');
 old_text:=E'        a.status\n';
 IF strpos(d,old_text)=0 THEN RAISE EXCEPTION 'Checkout selection differs.'; END IF;
 d:=replace(d,old_text,E'        a.status,\n        a.scheduled_end\n');
 old_text:='    v_check_out_at := clock_timestamp();';
 IF strpos(d,old_text)=0 THEN RAISE EXCEPTION 'Checkout clock differs.'; END IF;
 d:=replace(d,old_text,old_text||E'\n    IF private.attendance_resolution_checkout_allowed(v_assignment.scheduled_end,v_check_out_at) IS NOT TRUE THEN\n        RAISE EXCEPTION ''Checkout recovery window ended. Ask your employer to review attendance.'' USING ERRCODE=''22023'';\n    END IF;');
 EXECUTE d;
 -- Keep additive lifecycle wrapper security modes and original projections.
 FOREACH s IN ARRAY ARRAY['public.list_my_work_assignments_lifecycle()',
    'public.list_company_work_assignments_lifecycle(uuid)'] LOOP
   d:=pg_get_functiondef(s::regprocedure);
   old_text:='''attendance_as_of'', pg_catalog.statement_timestamp())';
   IF strpos(d,old_text)=0 THEN RAISE EXCEPTION 'Lifecycle snapshot differs: %',s; END IF;
   d:=replace(d,old_text,'''attendance_as_of'', pg_catalog.statement_timestamp(), ''attendance_resolution'', public.read_work_attendance_resolution(a.assignment_id))');
   EXECUTE d;
 END LOOP;
END;
$integrate$;

DO $post$
DECLARE s text;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_class WHERE oid='public.work_attendance_resolutions'::regclass AND relrowsecurity) THEN
  RAISE EXCEPTION 'Resolution RLS missing.';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_catalog.aclexplode((SELECT relacl FROM pg_catalog.pg_class WHERE oid='public.work_attendance_resolutions'::regclass)) x
   WHERE x.grantee<>(SELECT relowner FROM pg_catalog.pg_class WHERE oid='public.work_attendance_resolutions'::regclass)) THEN
   RAISE EXCEPTION 'Resolution audit table has unexpected direct grants.';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_catalog.aclexplode((SELECT relacl FROM pg_catalog.pg_class WHERE oid='private.effective_work_attendance'::regclass)) x
   WHERE x.grantee<>(SELECT relowner FROM pg_catalog.pg_class WHERE oid='private.effective_work_attendance'::regclass)) THEN
   RAISE EXCEPTION 'Effective attendance view has unexpected direct grants.';
 END IF;
 FOR s IN SELECT n.nspname||'.'||p.proname FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
   WHERE (n.nspname='public' AND p.proname IN ('read_work_attendance_resolution','resolve_work_attendance'))
      OR (n.nspname='private' AND p.proname LIKE '%attendance_resolution%') LOOP
   IF EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) x
     WHERE n.nspname||'.'||p.proname=s AND (x.grantee NOT IN (p.proowner,CASE WHEN n.nspname='public' THEN 'authenticated'::regrole::oid ELSE p.proowner END)
       OR (x.grantee<>p.proowner AND x.is_grantable))) THEN
     RAISE EXCEPTION 'Unexpected function grants: %',s;
   END IF;
 END LOOP;
 IF pg_catalog.md5(pg_catalog.pg_get_functiondef('public.check_in_work_assignment(uuid,text,numeric,numeric)'::regprocedure))<>'da608f2b4ef94bbe4954d2f20d28971a' THEN
   RAISE EXCEPTION 'Check-in unexpectedly changed.';
 END IF;
END;
$post$;
NOTIFY pgrst,'reload schema';
COMMIT;

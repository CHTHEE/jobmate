-- LOCAL REVIEW ONLY. Requires 20261105000100 and 20261105000300.
-- Do not install the alternative 20261105000200 prototype as a prerequisite.
-- No historical assignments, evidence, attendance or audit rows are rewritten.
BEGIN;

DO $preflight$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'work-evidence' AND public = false) THEN
        RAISE EXCEPTION 'A private work-evidence bucket is required; review existing Storage setup';
    END IF;
END;
$preflight$;

ALTER TABLE public.work_verification_history ADD COLUMN submission_round integer
    CHECK (submission_round IS NULL OR submission_round > 0);

CREATE FUNCTION public.record_work_verification_round()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
BEGIN
    NEW.created_at := clock_timestamp();
    SELECT max(s.submission_round) INTO NEW.submission_round
    FROM public.work_evidence_submissions s WHERE s.assignment_id = NEW.assignment_id;
    IF NEW.action IN ('evidence_submitted', 'evidence_resubmitted', 'more_evidence_requested', 'verified')
       AND NEW.submission_round IS NULL THEN
        RAISE EXCEPTION 'Submission round required for evidence history';
    END IF;
    RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION public.record_work_verification_round() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER work_verification_record_round BEFORE INSERT ON public.work_verification_history
FOR EACH ROW EXECUTE FUNCTION public.record_work_verification_round();

CREATE TABLE public.work_evidence_review_requests (
    request_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id uuid NOT NULL REFERENCES public.work_assignments(assignment_id),
    submission_round integer NOT NULL CHECK (submission_round > 0),
    actor_id uuid NOT NULL REFERENCES public.users(user_id),
    decision text NOT NULL CHECK (decision IN ('verified', 'more_evidence_requested')),
    reason text,
    state text NOT NULL DEFAULT 'prepared' CHECK (state IN ('prepared', 'committed')),
    history_id uuid UNIQUE REFERENCES public.work_verification_history(verification_id),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE(assignment_id, submission_round),
    CHECK ((state = 'committed') = (history_id IS NOT NULL)),
    CHECK ((decision = 'verified' AND reason IS NULL) OR
        (decision = 'more_evidence_requested' AND reason IS NOT NULL AND reason = btrim(reason) AND length(reason) BETWEEN 1 AND 1000))
);
ALTER TABLE public.work_evidence_review_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.work_evidence_review_requests FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.guard_work_evidence_review_request()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $function$
BEGIN
    IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Review request deletion is not supported'; END IF;
    IF ROW(NEW.request_id, NEW.assignment_id, NEW.submission_round, NEW.actor_id,
        NEW.decision, NEW.reason, NEW.created_at) IS DISTINCT FROM
       ROW(OLD.request_id, OLD.assignment_id, OLD.submission_round, OLD.actor_id,
        OLD.decision, OLD.reason, OLD.created_at)
       OR OLD.state <> 'prepared' OR NEW.state <> 'committed' THEN
        RAISE EXCEPTION 'Review request identity is immutable';
    END IF;
    RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION public.guard_work_evidence_review_request() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER work_evidence_review_immutable BEFORE UPDATE OR DELETE ON public.work_evidence_review_requests
FOR EACH ROW EXECUTE FUNCTION public.guard_work_evidence_review_request();

CREATE FUNCTION public.can_review_work_evidence_company(p_company_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
    SELECT auth.uid() IS NOT NULL
    AND public.can_manage_company_jobs(p_company_id) IS TRUE
    AND EXISTS (SELECT 1 FROM public.users u
        JOIN public.company_memberships m ON m.user_id = u.user_id
        JOIN public.companies c ON c.company_id = m.company_id
        WHERE u.user_id = auth.uid() AND u.role = 'employer' AND u.status = 'active'
        AND m.company_id = p_company_id AND m.member_role IN ('owner', 'employer')
        AND c.verification_status = 'verified');
$function$;
REVOKE ALL ON FUNCTION public.can_review_work_evidence_company(uuid) FROM PUBLIC, anon, authenticated;

-- Keep existing metadata/signing APIs, with current active-account checks.
CREATE OR REPLACE FUNCTION public.can_view_work_evidence(p_assignment_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
    SELECT auth.uid() IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.work_assignments a WHERE a.assignment_id = p_assignment_id AND (
            (a.worker_id = auth.uid() AND EXISTS (SELECT 1 FROM public.users u
                WHERE u.user_id = auth.uid() AND u.role = 'job_seeker' AND u.status = 'active'))
            OR (public.can_review_work_evidence_company(a.company_id) IS TRUE AND EXISTS (
                SELECT 1 FROM public.work_evidence_submissions s WHERE s.assignment_id = a.assignment_id))
        )
    );
$function$;

CREATE OR REPLACE FUNCTION public.can_read_work_evidence_file(p_storage_path text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE a public.work_assignments;
BEGIN
    IF auth.uid() IS NULL OR p_storage_path IS NULL OR p_storage_path !~
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[A-Za-z0-9][A-Za-z0-9._-]{0,199}\.(jpg|jpeg|png|webp|pdf)$'
    THEN RETURN false; END IF;
    SELECT * INTO a FROM public.work_assignments WHERE assignment_id = split_part(p_storage_path, '/', 1)::uuid;
    IF NOT FOUND THEN RETURN false; END IF;
    IF a.worker_id = auth.uid() AND EXISTS (SELECT 1 FROM public.users u
        WHERE u.user_id = auth.uid() AND u.role = 'job_seeker' AND u.status = 'active') THEN RETURN true; END IF;
    RETURN public.can_review_work_evidence_company(a.company_id) IS TRUE AND EXISTS (
        SELECT 1 FROM public.work_evidence e WHERE e.assignment_id = a.assignment_id AND e.storage_path = p_storage_path
        AND EXISTS (SELECT 1 FROM public.work_evidence_submissions s
            WHERE s.assignment_id = e.assignment_id AND s.submission_round = e.submission_round)
    );
END;
$function$;
REVOKE ALL ON FUNCTION public.can_view_work_evidence(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_read_work_evidence_file(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_view_work_evidence(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_read_work_evidence_file(text) TO authenticated;

CREATE FUNCTION public.work_evidence_workflow_context(p_assignment_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $function$
DECLARE a public.work_assignments; v_worker boolean; v_round integer; v_attempts jsonb := '[]';
    v_history jsonb; v_review jsonb;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000'; END IF;
    SELECT * INTO a FROM public.work_assignments WHERE assignment_id = p_assignment_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Evidence access denied' USING ERRCODE = '42501'; END IF;
    v_worker := a.worker_id = auth.uid() AND EXISTS (SELECT 1 FROM public.users u
        WHERE u.user_id = auth.uid() AND u.role = 'job_seeker' AND u.status = 'active');
    IF NOT v_worker AND public.can_review_work_evidence_company(a.company_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Evidence access denied' USING ERRCODE = '42501';
    END IF;
    SELECT coalesce(max(s.submission_round), 0) INTO v_round
    FROM public.work_evidence_submissions s WHERE s.assignment_id = p_assignment_id;
    IF v_worker THEN
        -- Deliberately require the server-reservation draft, not the prototype.
        v_attempts := public.get_my_work_evidence_attempt(p_assignment_id)->'attempts';
    ELSE
        SELECT to_jsonb(r) INTO v_review FROM public.work_evidence_review_requests r
        WHERE r.assignment_id = p_assignment_id AND r.submission_round = v_round;
    END IF;
    SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY h.created_at, h.verification_id), '[]'::jsonb)
    INTO v_history FROM public.work_verification_history h WHERE h.assignment_id = p_assignment_id;
    RETURN jsonb_build_object('contract_version', 1, 'assignment_id', p_assignment_id,
        'viewer_role', CASE WHEN v_worker THEN 'worker' ELSE 'employer' END,
        'latest_round', v_round, 'assignment_status', a.status,
        'verification_status', a.verification_status,
        'attendance_complete', EXISTS (SELECT 1 FROM public.work_attendance att
            WHERE att.assignment_id = p_assignment_id AND att.check_in_at IS NOT NULL
            AND att.check_out_at IS NOT NULL AND att.check_out_at >= att.check_in_at),
        'attempts', v_attempts, 'review', v_review, 'history', v_history);
END;
$function$;

CREATE FUNCTION public.prepare_work_evidence_review(p_assignment_id uuid, p_expected_round integer,
    p_decision text, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE a public.work_assignments; r public.work_evidence_review_requests; v_round integer;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000'; END IF;
    SELECT * INTO a FROM public.work_assignments WHERE assignment_id = p_assignment_id FOR UPDATE;
    IF NOT FOUND OR public.can_review_work_evidence_company(a.company_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Review access denied' USING ERRCODE = '42501';
    END IF;
    IF p_expected_round IS NULL OR p_expected_round < 1 OR p_decision IS NULL
       OR p_decision NOT IN ('verified', 'more_evidence_requested')
       OR (p_decision = 'verified' AND p_reason IS NOT NULL)
       OR (p_decision = 'more_evidence_requested' AND (p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 1 AND 1000)) THEN
        RAISE EXCEPTION 'Invalid review payload' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO r FROM public.work_evidence_review_requests
    WHERE assignment_id = p_assignment_id AND submission_round = p_expected_round FOR UPDATE;
    IF FOUND THEN
        IF r.actor_id <> auth.uid() OR r.decision IS DISTINCT FROM p_decision OR r.reason IS DISTINCT FROM btrim(p_reason) THEN
            RAISE EXCEPTION 'Review round already reserved with another payload' USING ERRCODE = '22023';
        END IF;
        RETURN to_jsonb(r);
    END IF;
    SELECT max(s.submission_round) INTO v_round FROM public.work_evidence_submissions s WHERE s.assignment_id = p_assignment_id;
    IF v_round IS DISTINCT FROM p_expected_round OR a.status <> 'awaiting_verification' OR a.verification_status <> 'pending_review' THEN
        RAISE EXCEPTION 'Review round or eligibility changed' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.work_evidence_review_requests(assignment_id, submission_round, actor_id, decision, reason)
    VALUES(p_assignment_id, v_round, auth.uid(), p_decision, btrim(p_reason)) RETURNING * INTO r;
    RETURN to_jsonb(r);
END;
$function$;

CREATE FUNCTION public.commit_work_evidence_review(p_assignment_id uuid, p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE a public.work_assignments; r public.work_evidence_review_requests; v_round integer; v_history uuid;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000'; END IF;
    SELECT * INTO a FROM public.work_assignments WHERE assignment_id = p_assignment_id FOR UPDATE;
    IF NOT FOUND OR public.can_review_work_evidence_company(a.company_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Review access denied' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO r FROM public.work_evidence_review_requests
    WHERE request_id = p_request_id AND assignment_id = p_assignment_id AND actor_id = auth.uid() FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Review access denied' USING ERRCODE = '42501'; END IF;
    IF r.state = 'committed' THEN RETURN to_jsonb(r); END IF;
    SELECT max(s.submission_round) INTO v_round FROM public.work_evidence_submissions s WHERE s.assignment_id = p_assignment_id;
    IF v_round IS DISTINCT FROM r.submission_round OR a.status <> 'awaiting_verification' OR a.verification_status <> 'pending_review' THEN
        RAISE EXCEPTION 'Review round or eligibility changed' USING ERRCODE = '22023';
    END IF;
    IF r.decision = 'verified' THEN
        PERFORM public.verify_work_assignment(p_assignment_id);
    ELSE
        PERFORM public.request_more_work_evidence(p_assignment_id, r.reason);
    END IF;
    -- The nested legacy transaction must have written exactly this round's
    -- decision. Any missing/duplicate association rolls the entire call back.
    SELECT h.verification_id INTO STRICT v_history FROM public.work_verification_history h
    WHERE h.assignment_id = p_assignment_id AND h.submission_round = r.submission_round
        AND h.action = r.decision AND h.performed_by = r.actor_id;
    UPDATE public.work_evidence_review_requests SET state = 'committed', history_id = v_history
    WHERE request_id = p_request_id RETURNING * INTO r;
    RETURN to_jsonb(r);
END;
$function$;

REVOKE ALL ON FUNCTION public.work_evidence_workflow_context(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.prepare_work_evidence_review(uuid, integer, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.commit_work_evidence_review(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.work_evidence_workflow_context(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_work_evidence_review(uuid, integer, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.commit_work_evidence_review(uuid, uuid) TO authenticated;

-- Coordinated cutover: prevent legacy clients from bypassing durable identities
-- or applying an old review action to a later resubmission round. Definer owners
-- retain implicit EXECUTE for the nested calls above and in draft 0003.
REVOKE ALL ON FUNCTION public.submit_work_evidence(uuid, text, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.verify_work_assignment(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.request_more_work_evidence(uuid, text) FROM PUBLIC, anon, authenticated;
DO $cutover$
BEGIN
    IF to_regprocedure('public.submit_work_evidence_idempotent(uuid,uuid,text,text[])') IS NOT NULL THEN
        EXECUTE 'REVOKE ALL ON FUNCTION public.submit_work_evidence_idempotent(uuid,uuid,text,text[]) FROM PUBLIC, anon, authenticated';
    END IF;
END;
$cutover$;

-- Preserve private append-only evidence even if an unrelated permissive policy
-- exists on storage.objects. No bucket or historical object is modified.
CREATE POLICY work_evidence_no_authenticated_deletes ON storage.objects
AS RESTRICTIVE FOR DELETE TO authenticated USING (bucket_id <> 'work-evidence');
CREATE POLICY work_evidence_scoped_private_reads ON storage.objects
AS RESTRICTIVE FOR SELECT TO authenticated
USING (bucket_id <> 'work-evidence' OR public.can_read_work_evidence_file(name));
CREATE POLICY work_evidence_scoped_private_inserts ON storage.objects
AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK (bucket_id <> 'work-evidence' OR (
    name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[A-Za-z0-9][A-Za-z0-9._-]{0,199}\.(jpg|jpeg|png|webp|pdf)$'
    AND CASE WHEN split_part(name, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        THEN public.can_upload_work_evidence(split_part(name, '/', 1)::uuid) ELSE false END
));
NOTIFY pgrst, 'reload schema';
COMMIT;

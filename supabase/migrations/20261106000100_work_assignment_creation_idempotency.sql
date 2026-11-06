-- REVIEW ONLY: do not apply without separate deployment approval.
BEGIN;
-- No assignment/evidence/history rows are rewritten. Keep the existing GiST
-- worker-overlap exclusion constraint, including its cancelled-shift predicate.
CREATE TABLE public.work_assignment_creation_requests (
 request_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 actor_id uuid NOT NULL REFERENCES public.users(user_id),
 application_id uuid NOT NULL REFERENCES public.job_applications(application_id),
 company_id uuid NOT NULL REFERENCES public.companies(company_id),
 scheduled_start timestamptz NOT NULL,
 scheduled_end timestamptz NOT NULL CHECK (scheduled_end > scheduled_start),
 workplace_location text NOT NULL CHECK (length(workplace_location) BETWEEN 1 AND 500),
 assignment_id uuid UNIQUE REFERENCES public.work_assignments(assignment_id),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(actor_id, application_id, scheduled_start, scheduled_end)
);
ALTER TABLE public.work_assignment_creation_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.work_assignment_creation_requests FROM PUBLIC, anon, authenticated;

-- Durable unique claims arbitrate concurrent duplicate inserts even if snapshots
-- differ. No backfill: the trigger also checks untouched historical assignments.
CREATE TABLE public.work_assignment_shift_claims (
 application_id uuid NOT NULL REFERENCES public.job_applications(application_id),
 scheduled_start timestamptz NOT NULL,
 scheduled_end timestamptz NOT NULL,
 assignment_id uuid NOT NULL,
 PRIMARY KEY(application_id, scheduled_start, scheduled_end)
);
ALTER TABLE public.work_assignment_shift_claims ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.work_assignment_shift_claims FROM PUBLIC, anon, authenticated;

-- Covers the legacy RPC too. Application-row locking serializes identical shift
-- inserts without building a unique index that could invalidate historical rows.
CREATE FUNCTION public.guard_work_assignment_duplicate_shift()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_claim uuid;
BEGIN
 PERFORM 1 FROM public.job_applications WHERE application_id = NEW.application_id FOR UPDATE;
 IF EXISTS (SELECT 1 FROM public.work_assignments a
   WHERE a.application_id = NEW.application_id
     AND a.scheduled_start = NEW.scheduled_start AND a.scheduled_end = NEW.scheduled_end
     AND a.assignment_id <> NEW.assignment_id) THEN
   RAISE EXCEPTION 'This application shift already exists.' USING ERRCODE = '23505';
 END IF;
 INSERT INTO public.work_assignment_shift_claims(application_id, scheduled_start, scheduled_end, assignment_id)
 VALUES(NEW.application_id, NEW.scheduled_start, NEW.scheduled_end, NEW.assignment_id)
 ON CONFLICT DO NOTHING;
 SELECT assignment_id INTO v_claim FROM public.work_assignment_shift_claims
 WHERE application_id = NEW.application_id AND scheduled_start = NEW.scheduled_start AND scheduled_end = NEW.scheduled_end;
 IF v_claim IS DISTINCT FROM NEW.assignment_id THEN
  RAISE EXCEPTION 'This application shift is already claimed.' USING ERRCODE = '23505';
 END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_work_assignment_duplicate_shift() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER work_assignment_duplicate_shift_guard
 BEFORE INSERT OR UPDATE OF application_id, scheduled_start, scheduled_end ON public.work_assignments
 FOR EACH ROW EXECUTE FUNCTION public.guard_work_assignment_duplicate_shift();

CREATE FUNCTION public.reserve_work_assignment_request(
 p_application_id uuid, p_scheduled_start timestamptz,
 p_scheduled_end timestamptz, p_workplace_location text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_app record; v_request public.work_assignment_creation_requests;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '28000'; END IF;
 SELECT a.status, j.company_id INTO v_app FROM public.job_applications a
 JOIN public.job_postings j ON j.job_id = a.job_id
 WHERE a.application_id = p_application_id FOR UPDATE OF a, j;
 IF NOT FOUND THEN RAISE EXCEPTION 'Application unavailable.'; END IF;
 IF v_app.status <> 'hired' OR public.can_manage_company_jobs(v_app.company_id) IS NOT TRUE THEN
  RAISE EXCEPTION 'Employer access or hired eligibility denied.' USING ERRCODE = '42501';
 END IF;
 IF p_scheduled_start IS NULL OR p_scheduled_end IS NULL OR p_scheduled_end <= p_scheduled_start
 OR NOT isfinite(p_scheduled_start) OR NOT isfinite(p_scheduled_end)
 OR p_workplace_location IS NULL OR length(trim(p_workplace_location)) NOT BETWEEN 1 AND 500 THEN
  RAISE EXCEPTION 'Invalid shift payload.' USING ERRCODE = '22023';
 END IF;
 SELECT * INTO v_request FROM public.work_assignment_creation_requests
 WHERE actor_id = auth.uid() AND application_id = p_application_id
 AND scheduled_start = p_scheduled_start AND scheduled_end = p_scheduled_end;
 IF FOUND THEN
  IF v_request.workplace_location <> trim(p_workplace_location) THEN
   RAISE EXCEPTION 'Request payload cannot change.' USING ERRCODE = '22023';
  END IF;
  RETURN v_request.request_id;
 END IF;
 INSERT INTO public.work_assignment_creation_requests(actor_id, application_id, company_id,
 scheduled_start, scheduled_end, workplace_location)
 VALUES(auth.uid(), p_application_id, v_app.company_id, p_scheduled_start, p_scheduled_end, trim(p_workplace_location))
 RETURNING * INTO v_request;
 RETURN v_request.request_id;
END;
$$;

CREATE FUNCTION public.create_work_assignment_request(
 p_request_id uuid, p_application_id uuid, p_scheduled_start timestamptz,
 p_scheduled_end timestamptz, p_workplace_location text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_request public.work_assignment_creation_requests; v_app record; v_assignment uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '28000'; END IF;
 -- Same lock order as reservation and the legacy insert trigger.
 SELECT a.status, j.company_id INTO v_app FROM public.job_applications a
 JOIN public.job_postings j ON j.job_id = a.job_id
 WHERE a.application_id = p_application_id FOR UPDATE OF a, j;
 IF NOT FOUND THEN RAISE EXCEPTION 'Application unavailable.'; END IF;
 IF public.can_manage_company_jobs(v_app.company_id) IS NOT TRUE THEN
  RAISE EXCEPTION 'Employer access denied.' USING ERRCODE = '42501';
 END IF;
 SELECT * INTO v_request FROM public.work_assignment_creation_requests WHERE request_id = p_request_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Request unavailable.' USING ERRCODE = '22023'; END IF;
 IF v_request.actor_id <> auth.uid() OR v_request.company_id <> v_app.company_id THEN
  RAISE EXCEPTION 'Request access denied.' USING ERRCODE = '42501';
 END IF;
 IF v_request.application_id IS DISTINCT FROM p_application_id
 OR v_request.scheduled_start IS DISTINCT FROM p_scheduled_start
 OR v_request.scheduled_end IS DISTINCT FROM p_scheduled_end
 OR v_request.workplace_location IS DISTINCT FROM trim(p_workplace_location) THEN
  RAISE EXCEPTION 'Request payload cannot change.' USING ERRCODE = '22023';
 END IF;
 IF v_request.assignment_id IS NOT NULL THEN RETURN v_request.assignment_id; END IF;
 IF v_app.status <> 'hired' THEN RAISE EXCEPTION 'Application no longer hired.'; END IF;
 v_assignment := public.create_work_assignment(p_application_id, p_scheduled_start, p_scheduled_end, p_workplace_location);
 UPDATE public.work_assignment_creation_requests SET assignment_id = v_assignment WHERE request_id = p_request_id;
 RETURN v_assignment;
END;
$$;

CREATE FUNCTION public.lookup_work_assignment_request(p_request_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_request public.work_assignment_creation_requests;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '28000'; END IF;
 SELECT * INTO v_request FROM public.work_assignment_creation_requests WHERE request_id = p_request_id;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF v_request.actor_id <> auth.uid() OR public.can_manage_company_jobs(v_request.company_id) IS NOT TRUE THEN
  RAISE EXCEPTION 'Request access denied.' USING ERRCODE = '42501';
 END IF;
 RETURN v_request.assignment_id;
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_work_assignment_request(uuid,timestamptz,timestamptz,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_work_assignment_request(uuid,uuid,timestamptz,timestamptz,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.lookup_work_assignment_request(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reserve_work_assignment_request(uuid,timestamptz,timestamptz,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_work_assignment_request(uuid,uuid,timestamptz,timestamptz,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.lookup_work_assignment_request(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;

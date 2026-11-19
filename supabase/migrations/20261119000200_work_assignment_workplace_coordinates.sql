-- Review only. Based on the complete 2026-11-19 production catalog exports.
-- An edited definition, unexpected trigger, or owner drift requires re-review.
BEGIN;

SET LOCAL search_path = pg_catalog, public;
SET LOCAL lock_timeout = '5s';

DO $guard$
DECLARE expected record; actual text;
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Run the reviewed migration as the existing postgres function owner.';
  END IF;
  FOR expected IN SELECT * FROM (VALUES
      ('public.can_manage_company_jobs(uuid)', '58682d9659bcf3557ad5d52f1ccccb40', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.cancel_scheduled_work_assignment(uuid,text)', '917b76a3e5884c62313fa603ca909301', '{postgres=X/postgres,authenticated=X/postgres}'),
      ('public.cancel_work_assignment_request(uuid,text)', '28141eb761a30be827979b3797f696a4', '{postgres=X/postgres,authenticated=X/postgres}'),
      ('public.create_work_assignment_request(uuid,uuid,timestamp with time zone,timestamp with time zone,text)', '8792b53b5cc8a28857db4f4dcbc21fdf', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.create_work_assignment(uuid,timestamp with time zone,timestamp with time zone,text)', '5ff95097f5328c565236516944a8d391', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.list_company_work_assignments_lifecycle(uuid)', '7af203f71f2c94271ccc5b0e4def28c0', '{postgres=X/postgres,authenticated=X/postgres}'),
      ('public.list_company_work_assignments(uuid)', 'b2d61c62157ef280cfe3e7219f6729ff', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.list_my_work_assignments_lifecycle()', 'e84677e9911861a4ec4081a8d76ff7f3', '{postgres=X/postgres,authenticated=X/postgres}'),
      ('public.list_my_work_assignments()', '8c010de82ace1e42227bc5d7f5d629ce', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.lookup_work_assignment_request(uuid)', '72ef43195bd8772c00f10fdcf8ae1e63', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('private.validate_work_shift_schedule(timestamp with time zone,timestamp with time zone)', '2eb7484d485f351c042e38c98a550cdf', '{postgres=X/postgres}'),
      ('public.reserve_work_assignment_request(uuid,timestamp with time zone,timestamp with time zone,text)', '7f491105997af7d8349aeb2b5600f090', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}')
    ) AS v(identity, fingerprint, acl)
  LOOP
    SELECT pg_catalog.md5(pg_catalog.rtrim(pg_catalog.replace(
             pg_catalog.pg_get_functiondef(p.oid), pg_catalog.chr(13), ''), pg_catalog.chr(10)))
      INTO actual
    FROM pg_catalog.pg_proc p
    WHERE p.oid = pg_catalog.to_regprocedure(expected.identity)
      AND pg_catalog.pg_get_userbyid(p.proowner) = 'postgres'
      AND p.proacl::text = expected.acl;
    IF actual IS DISTINCT FROM expected.fingerprint THEN
      RAISE EXCEPTION 'Work assignment RPC baseline mismatch: %', expected.identity;
    END IF;
  END LOOP;

  FOR expected IN SELECT * FROM (VALUES
      ('public.job_engagement_closures', 'job_engagement_closure_immutable', '0a8344172c54e15926e6fe4aae11ebd6', 'df0d866926c166b3baed59156cf12272'),
      ('public.work_assignment_creation_requests', 'engagement_request_insert_guard', '04e719cc470b81068da0c8dc19f89049', 'ecc9455c4136dbb0f899907802627e9e'),
      ('public.work_assignment_creation_requests', 'protect_assignment_request_terminal_state', '78e86f6d19b3caf11b9b4bc0f20f756d', '9381ba5b3be920eac8c0eb78cc371a95'),
      ('public.work_assignment_creation_requests', 'work_shift_reservation_schedule_after_insert', '918dc975ab4b06a1b90bd8c9a86ca719', '3bc93356f8f58f02d22c13738a86847c'),
      ('public.work_assignments', 'attendance_resolution_assignment_guard', '5b0457cf3e2f077fbbb97c17b2e8a409', '04215d105f5305cef4fd15f6cfccd624'),
      ('public.work_assignments', 'engagement_cancellation_audit_guard', '163824375ed5ef48016e9a8e3f9bb013', '0c2021e154956018f59eaa0d9350e4c8'),
      ('public.work_assignments', 'work_assignment_duplicate_shift_guard', '2a4f66dc8c0fd2c54bcdcff8f34c104f', 'a8e29530a3b6ab0aeeb2ee6c34441186'),
      ('public.work_assignments', 'work_shift_schedule_after_write', 'cd377806606fbf10834318b4df3e43f0', '3bc93356f8f58f02d22c13738a86847c')
    ) AS v(relation, trigger_name, trigger_hash, function_hash)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_trigger t
      WHERE t.tgrelid = pg_catalog.to_regclass(expected.relation)
        AND t.tgname = expected.trigger_name
        AND NOT t.tgisinternal AND t.tgenabled = 'O'
        AND pg_catalog.md5(pg_catalog.pg_get_triggerdef(t.oid, true)) = expected.trigger_hash
        AND pg_catalog.md5(pg_catalog.rtrim(pg_catalog.replace(
              pg_catalog.pg_get_functiondef(t.tgfoid), pg_catalog.chr(13), ''), pg_catalog.chr(10)))
            = expected.function_hash
    ) THEN
      RAISE EXCEPTION 'Work assignment trigger baseline mismatch: %', expected.trigger_name;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_catalog.pg_trigger t
      WHERE NOT t.tgisinternal AND t.tgrelid IN (
        'public.work_assignments'::regclass, 'public.work_assignment_creation_requests'::regclass,
        'public.work_assignment_shift_claims'::regclass, 'public.job_engagement_closures'::regclass
      )) <> 8 THEN
    RAISE EXCEPTION 'Unexpected triggers in the work assignment baseline.';
  END IF;
END;
$guard$;

ALTER TABLE public.work_assignments
  ADD COLUMN workplace_latitude numeric(9,6),
  ADD COLUMN workplace_longitude numeric(9,6),
  ADD CONSTRAINT work_assignments_workplace_coordinates_valid CHECK (
    (workplace_latitude IS NULL AND workplace_longitude IS NULL)
    OR (workplace_latitude IS NOT NULL AND workplace_longitude IS NOT NULL
        AND workplace_latitude BETWEEN -90 AND 90
        AND workplace_longitude BETWEEN -180 AND 180)
  );

ALTER TABLE public.work_assignment_creation_requests
  ADD COLUMN workplace_latitude numeric(9,6),
  ADD COLUMN workplace_longitude numeric(9,6),
  ADD CONSTRAINT work_assignment_creation_requests_workplace_coordinates_valid CHECK (
    (workplace_latitude IS NULL AND workplace_longitude IS NULL)
    OR (workplace_latitude IS NOT NULL AND workplace_longitude IS NOT NULL
        AND workplace_latitude BETWEEN -90 AND 90
        AND workplace_longitude BETWEEN -180 AND 180)
  );

-- Existing contracts retain their exported bodies apart from the mixed-version guards.
CREATE OR REPLACE FUNCTION public.reserve_work_assignment_request(p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_app record; v_request public.work_assignment_creation_requests;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '28000'; END IF;
 PERFORM 1 FROM public.job_applications a WHERE a.application_id = p_application_id FOR UPDATE;
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
  IF v_request.workplace_latitude IS NOT NULL OR v_request.workplace_longitude IS NOT NULL THEN
   RAISE EXCEPTION 'Pinned workplace request requires the coordinate-aware API.' USING ERRCODE = '22023';
  END IF;
  IF v_request.workplace_location <> trim(p_workplace_location) THEN
   RAISE EXCEPTION 'Request payload cannot change.' USING ERRCODE = '22023';
  END IF;
  RETURN v_request.request_id;
 END IF;
 PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);
 INSERT INTO public.work_assignment_creation_requests(actor_id, application_id, company_id,
 scheduled_start, scheduled_end, workplace_location)
 VALUES(auth.uid(), p_application_id, v_app.company_id, p_scheduled_start, p_scheduled_end, trim(p_workplace_location))
 RETURNING * INTO v_request;
 PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);
 RETURN v_request.request_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_work_assignment_request(p_request_id uuid, p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_request public.work_assignment_creation_requests; v_app record; v_assignment uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '28000'; END IF;
 -- Same lock order as reservation and the legacy insert trigger.
 PERFORM 1 FROM public.job_applications a WHERE a.application_id = p_application_id FOR UPDATE;
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
 IF v_request.workplace_latitude IS NOT NULL OR v_request.workplace_longitude IS NOT NULL THEN
  RAISE EXCEPTION 'Pinned workplace request requires the coordinate-aware API.' USING ERRCODE = '22023';
 END IF;
 IF v_request.assignment_id IS NOT NULL THEN RETURN v_request.assignment_id; END IF;
 IF v_app.status <> 'hired' THEN RAISE EXCEPTION 'Application no longer hired.'; END IF;
 PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);
 v_assignment := public.create_work_assignment(p_application_id, p_scheduled_start, p_scheduled_end, p_workplace_location);
 UPDATE public.work_assignment_creation_requests SET assignment_id = v_assignment WHERE request_id = p_request_id;
 PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);
 RETURN v_assignment;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_work_assignment(p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_application record;
    v_company_id uuid;
    v_assignment_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'You must be signed in.';
    END IF;

    PERFORM 1 FROM public.job_applications a WHERE a.application_id = p_application_id FOR UPDATE;
    SELECT
        a.application_id,
        a.job_id,
        a.applicant_id,
        a.status,
        j.company_id
    INTO v_application
    FROM public.job_applications a
    JOIN public.job_postings j
      ON j.job_id = a.job_id
    WHERE a.application_id = p_application_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job application not found.';
    END IF;

    IF v_application.status <> 'hired' THEN
        RAISE EXCEPTION
            'Work assignments can only be created for Hired applications.';
    END IF;

    v_company_id := v_application.company_id;

    IF NOT public.can_manage_company_jobs(v_company_id) THEN
        RAISE EXCEPTION
            'You are not authorized to create assignments for this company.';
    END IF;

    IF p_scheduled_start IS NULL
       OR p_scheduled_end IS NULL
       OR p_scheduled_end <= p_scheduled_start THEN
        RAISE EXCEPTION 'Invalid shift schedule.';
    END IF;

    IF p_workplace_location IS NULL
       OR length(trim(p_workplace_location)) = 0
       OR length(p_workplace_location) > 500 THEN
        RAISE EXCEPTION
            'Enter a workplace location of up to 500 characters.';
    END IF;

    PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);
    IF EXISTS (
        SELECT 1 FROM public.work_assignment_creation_requests r
        WHERE r.actor_id = auth.uid() AND r.application_id = p_application_id
          AND r.scheduled_start = p_scheduled_start AND r.scheduled_end = p_scheduled_end
          AND r.cancelled_at IS NULL
          AND (r.workplace_latitude IS NOT NULL OR r.workplace_longitude IS NOT NULL)
    ) THEN
        RAISE EXCEPTION 'Pinned workplace request requires the coordinate-aware API.' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.work_assignments (
        application_id,
        job_id,
        worker_id,
        company_id,
        scheduled_start,
        scheduled_end,
        workplace_location,
        created_by
    )
    VALUES (
        v_application.application_id,
        v_application.job_id,
        v_application.applicant_id,
        v_company_id,
        p_scheduled_start,
        p_scheduled_end,
        trim(p_workplace_location),
        auth.uid()
    )
    RETURNING assignment_id INTO v_assignment_id;

    PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);
    RETURN v_assignment_id;
END;
$function$;

CREATE FUNCTION private.insert_work_assignment_with_workplace(p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text, p_workplace_latitude numeric, p_workplace_longitude numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_application record;
    v_company_id uuid;
    v_assignment_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'You must be signed in.';
    END IF;

    PERFORM 1 FROM public.job_applications a WHERE a.application_id = p_application_id FOR UPDATE;
    SELECT
        a.application_id,
        a.job_id,
        a.applicant_id,
        a.status,
        j.company_id
    INTO v_application
    FROM public.job_applications a
    JOIN public.job_postings j
      ON j.job_id = a.job_id
    WHERE a.application_id = p_application_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job application not found.';
    END IF;

    IF v_application.status <> 'hired' THEN
        RAISE EXCEPTION
            'Work assignments can only be created for Hired applications.';
    END IF;

    v_company_id := v_application.company_id;

    IF NOT public.can_manage_company_jobs(v_company_id) THEN
        RAISE EXCEPTION
            'You are not authorized to create assignments for this company.';
    END IF;

    IF p_scheduled_start IS NULL
       OR p_scheduled_end IS NULL
       OR p_scheduled_end <= p_scheduled_start THEN
        RAISE EXCEPTION 'Invalid shift schedule.';
    END IF;

    IF p_workplace_location IS NULL
       OR length(trim(p_workplace_location)) = 0
       OR length(p_workplace_location) > 500 THEN
        RAISE EXCEPTION
            'Enter a workplace location of up to 500 characters.';
    END IF;

    PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);
    INSERT INTO public.work_assignments (
        application_id,
        job_id,
        worker_id,
        company_id,
        scheduled_start,
        scheduled_end,
        workplace_location,
        workplace_latitude,
        workplace_longitude,
        created_by
    )
    VALUES (
        v_application.application_id,
        v_application.job_id,
        v_application.applicant_id,
        v_company_id,
        p_scheduled_start,
        p_scheduled_end,
        trim(p_workplace_location),
        p_workplace_latitude,
        p_workplace_longitude,
        auth.uid()
    )
    RETURNING assignment_id INTO v_assignment_id;

    PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);
    RETURN v_assignment_id;
END;
$function$;

REVOKE ALL ON FUNCTION private.insert_work_assignment_with_workplace(uuid, timestamptz, timestamptz, text, numeric, numeric) FROM PUBLIC, anon, authenticated, service_role;


CREATE FUNCTION public.reserve_work_assignment_request_v2(p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text, p_workplace_latitude numeric, p_workplace_longitude numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_app record; v_request public.work_assignment_creation_requests;
 v_latitude numeric;
 v_longitude numeric;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '28000'; END IF;
 PERFORM 1 FROM public.job_applications a WHERE a.application_id = p_application_id FOR UPDATE;
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

 IF (p_workplace_latitude IS NULL) <> (p_workplace_longitude IS NULL)
 OR (p_workplace_latitude IS NOT NULL AND (
   p_workplace_latitude NOT BETWEEN -90 AND 90
   OR p_workplace_longitude NOT BETWEEN -180 AND 180
 )) THEN
  RAISE EXCEPTION 'Invalid workplace coordinate pair.' USING ERRCODE = '22023';
 END IF;
 v_latitude := pg_catalog.round(p_workplace_latitude, 6);
 v_longitude := pg_catalog.round(p_workplace_longitude, 6);
 SELECT * INTO v_request FROM public.work_assignment_creation_requests
 WHERE actor_id = auth.uid() AND application_id = p_application_id
 AND scheduled_start = p_scheduled_start AND scheduled_end = p_scheduled_end;
 IF FOUND THEN
  IF v_request.cancelled_at IS NOT NULL THEN
   RAISE EXCEPTION 'This Assignment Request was cancelled.' USING ERRCODE = '22023';
  END IF;
  IF v_request.workplace_location IS DISTINCT FROM trim(p_workplace_location)
     OR v_request.workplace_latitude IS DISTINCT FROM v_latitude
     OR v_request.workplace_longitude IS DISTINCT FROM v_longitude THEN
   RAISE EXCEPTION 'Request payload cannot change.' USING ERRCODE = '22023';
  END IF;
  RETURN v_request.request_id;
 END IF;
 PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);
 INSERT INTO public.work_assignment_creation_requests(actor_id, application_id, company_id,
 scheduled_start, scheduled_end, workplace_location, workplace_latitude, workplace_longitude)
 VALUES(auth.uid(), p_application_id, v_app.company_id, p_scheduled_start, p_scheduled_end, trim(p_workplace_location), v_latitude, v_longitude)
 RETURNING * INTO v_request;
 PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);
 RETURN v_request.request_id;
END;
$function$;

CREATE FUNCTION public.create_work_assignment_request_v2(p_request_id uuid, p_application_id uuid, p_scheduled_start timestamp with time zone, p_scheduled_end timestamp with time zone, p_workplace_location text, p_workplace_latitude numeric, p_workplace_longitude numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_request public.work_assignment_creation_requests; v_app record; v_assignment uuid;
 v_latitude numeric;
 v_longitude numeric;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '28000'; END IF;
 -- Same lock order as reservation and the legacy insert trigger.
 PERFORM 1 FROM public.job_applications a WHERE a.application_id = p_application_id FOR UPDATE;
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

 IF (p_workplace_latitude IS NULL) <> (p_workplace_longitude IS NULL)
 OR (p_workplace_latitude IS NOT NULL AND (
   p_workplace_latitude NOT BETWEEN -90 AND 90
   OR p_workplace_longitude NOT BETWEEN -180 AND 180
 )) THEN
  RAISE EXCEPTION 'Invalid workplace coordinate pair.' USING ERRCODE = '22023';
 END IF;
 v_latitude := pg_catalog.round(p_workplace_latitude, 6);
 v_longitude := pg_catalog.round(p_workplace_longitude, 6);
 IF v_request.cancelled_at IS NOT NULL THEN
  RAISE EXCEPTION 'This Assignment Request was cancelled.' USING ERRCODE = '22023';
 END IF;
 IF v_request.application_id IS DISTINCT FROM p_application_id
 OR v_request.scheduled_start IS DISTINCT FROM p_scheduled_start
 OR v_request.scheduled_end IS DISTINCT FROM p_scheduled_end
 OR v_request.workplace_location IS DISTINCT FROM trim(p_workplace_location)
 OR v_request.workplace_latitude IS DISTINCT FROM v_latitude
 OR v_request.workplace_longitude IS DISTINCT FROM v_longitude THEN
  RAISE EXCEPTION 'Request payload cannot change.' USING ERRCODE = '22023';
 END IF;
 IF v_request.assignment_id IS NOT NULL THEN RETURN v_request.assignment_id; END IF;
 IF v_app.status <> 'hired' THEN RAISE EXCEPTION 'Application no longer hired.'; END IF;
 PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);
 v_assignment := private.insert_work_assignment_with_workplace(p_application_id, p_scheduled_start, p_scheduled_end, p_workplace_location, v_request.workplace_latitude, v_request.workplace_longitude);
 UPDATE public.work_assignment_creation_requests SET assignment_id = v_assignment WHERE request_id = p_request_id;
 PERFORM private.validate_work_shift_schedule(p_scheduled_start, p_scheduled_end);
 RETURN v_assignment;
END;
$function$;

-- One transaction via the same request protocol. A direct v2 call cannot
-- leave a competing reservation unlinked or bypass pinned-payload comparison.
CREATE FUNCTION public.create_work_assignment_v2(
 p_application_id uuid, p_scheduled_start timestamptz, p_scheduled_end timestamptz,
 p_workplace_location text, p_workplace_latitude numeric, p_workplace_longitude numeric
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_request_id uuid;
BEGIN
    v_request_id := public.reserve_work_assignment_request_v2(
        p_application_id, p_scheduled_start, p_scheduled_end,
        p_workplace_location, p_workplace_latitude, p_workplace_longitude
    );
    RETURN public.create_work_assignment_request_v2(
        v_request_id, p_application_id, p_scheduled_start, p_scheduled_end,
        p_workplace_location, p_workplace_latitude, p_workplace_longitude
    );
END;
$function$;

-- Only augment IDs returned by the existing caller-authorized lifecycle read.
CREATE FUNCTION public.list_my_work_assignments_lifecycle_v2()
RETURNS SETOF jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
    SELECT r.payload || pg_catalog.jsonb_build_object(
        'workplace_latitude', a.workplace_latitude,
        'workplace_longitude', a.workplace_longitude
    )
    FROM public.list_my_work_assignments_lifecycle() WITH ORDINALITY AS r(payload, ordinal)
    JOIN public.work_assignments a
      ON a.assignment_id = (r.payload ->> 'assignment_id')::uuid
    ORDER BY r.ordinal
$function$;

-- Only augment IDs returned by the existing caller-authorized lifecycle read.
CREATE FUNCTION public.list_company_work_assignments_lifecycle_v2(p_company_id uuid)
RETURNS SETOF jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
    SELECT r.payload || pg_catalog.jsonb_build_object(
        'workplace_latitude', a.workplace_latitude,
        'workplace_longitude', a.workplace_longitude
    )
    FROM public.list_company_work_assignments_lifecycle(p_company_id) WITH ORDINALITY AS r(payload, ordinal)
    JOIN public.work_assignments a
      ON a.assignment_id = (r.payload ->> 'assignment_id')::uuid
    ORDER BY r.ordinal
$function$;

REVOKE ALL ON FUNCTION public.reserve_work_assignment_request_v2(uuid, timestamptz, timestamptz, text, numeric, numeric) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_work_assignment_request_v2(uuid, timestamptz, timestamptz, text, numeric, numeric) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_work_assignment_request_v2(uuid, uuid, timestamptz, timestamptz, text, numeric, numeric) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_work_assignment_request_v2(uuid, uuid, timestamptz, timestamptz, text, numeric, numeric) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_work_assignment_v2(uuid, timestamptz, timestamptz, text, numeric, numeric) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_work_assignment_v2(uuid, timestamptz, timestamptz, text, numeric, numeric) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.list_my_work_assignments_lifecycle_v2() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_my_work_assignments_lifecycle_v2() TO authenticated;
REVOKE ALL ON FUNCTION public.list_company_work_assignments_lifecycle_v2(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_company_work_assignments_lifecycle_v2(uuid) TO authenticated;

-- Explicit revokes above may not cover custom default grants from this owner.
DO $acl$
DECLARE
  expected record;
  function_oid oid;
  function_owner oid;
  function_acl aclitem[];
BEGIN
  FOR expected IN SELECT * FROM (VALUES
      ('private.insert_work_assignment_with_workplace(uuid,timestamptz,timestamptz,text,numeric,numeric)', ARRAY['postgres']::text[]),
      ('public.reserve_work_assignment_request_v2(uuid,timestamptz,timestamptz,text,numeric,numeric)', ARRAY['postgres','authenticated','service_role']),
      ('public.create_work_assignment_request_v2(uuid,uuid,timestamptz,timestamptz,text,numeric,numeric)', ARRAY['postgres','authenticated','service_role']),
      ('public.create_work_assignment_v2(uuid,timestamptz,timestamptz,text,numeric,numeric)', ARRAY['postgres','authenticated','service_role']),
      ('public.list_my_work_assignments_lifecycle_v2()', ARRAY['postgres','authenticated']),
      ('public.list_company_work_assignments_lifecycle_v2(uuid)', ARRAY['postgres','authenticated'])
    ) AS v(identity, allowed_roles)
  LOOP
    SELECT p.oid, p.proowner, COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))
      INTO STRICT function_oid, function_owner, function_acl
    FROM pg_catalog.pg_proc p
    WHERE p.oid = pg_catalog.to_regprocedure(expected.identity);

    IF EXISTS (
      SELECT 1
      FROM pg_catalog.aclexplode(function_acl) a
      LEFT JOIN pg_catalog.pg_roles r ON r.oid = a.grantee
      WHERE a.grantee = 0
         OR (r.rolname::text = ANY (expected.allowed_roles)) IS NOT TRUE
         OR (a.is_grantable AND a.grantee <> function_owner)
    ) THEN
      RAISE EXCEPTION 'Unexpected Work Assignment v2 or private helper EXECUTE grant: %', expected.identity;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_catalog.unnest(expected.allowed_roles) AS intended(role_name)
      WHERE NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles r
        JOIN pg_catalog.aclexplode(function_acl) a ON a.grantee = r.oid
        WHERE r.rolname::text = intended.role_name
          AND a.privilege_type = 'EXECUTE'
      )
    ) THEN
      RAISE EXCEPTION 'Missing Work Assignment EXECUTE grant: %', expected.identity;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_catalog.pg_roles r
      WHERE r.rolname IN ('anon', 'authenticated', 'service_role')
        AND (
          pg_catalog.has_function_privilege(r.oid, function_oid, 'EXECUTE')
            IS DISTINCT FROM (r.rolname::text = ANY (expected.allowed_roles))
          OR pg_catalog.has_function_privilege(r.oid, function_oid, 'EXECUTE WITH GRANT OPTION')
        )
    ) THEN
      RAISE EXCEPTION 'Unexpected effective Work Assignment EXECUTE privilege: %', expected.identity;
    END IF;
  END LOOP;
END;
$acl$;

NOTIFY pgrst, 'reload schema';
COMMIT;

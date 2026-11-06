-- DRAFT ONLY. NOT EXECUTED OR DEPLOYED. Requires the deployed 20261105000100.
-- Independent of, and does NOT replace/apply, the undeployed 20261105000200.
-- See docs/work_evidence_attempt_reservations_test_plan.md BEFORE deployment.
-- Legacy EXECUTE grants deliberately remain unchanged: cutover is a blocker.
BEGIN;

CREATE TABLE public.work_evidence_submission_attempts (
    request_id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
    assignment_id uuid NOT NULL REFERENCES public.work_assignments(assignment_id),
    worker_id uuid NOT NULL REFERENCES public.users(user_id),
    target_round integer NOT NULL CHECK (target_round >= 1),
    description text NOT NULL CHECK (
        description = pg_catalog.btrim(description)
        AND pg_catalog.char_length(description) BETWEEN 1 AND 2000
    ),
    storage_paths text[] NOT NULL CHECK (
        pg_catalog.array_ndims(storage_paths) = 1
        AND pg_catalog.array_lower(storage_paths, 1) = 1
        AND pg_catalog.cardinality(storage_paths) BETWEEN 1 AND 5
        AND pg_catalog.array_position(storage_paths, NULL::text) IS NULL
    ),
    state text NOT NULL DEFAULT 'prepared'
        CHECK (state IN ('prepared', 'committed', 'blocked')),
    submission_id uuid UNIQUE REFERENCES public.work_evidence_submissions(submission_id),
    error_code text CHECK (error_code IN (
        'round_changed', 'assignment_changed', 'attendance_incomplete',
        'payload_invalid', 'storage_invalid', 'path_already_submitted'
    )),
    created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
    CONSTRAINT work_evidence_attempt_round_unique UNIQUE (assignment_id, target_round),
    CONSTRAINT work_evidence_attempt_commit_consistency
        CHECK ((state = 'committed') = (submission_id IS NOT NULL)),
    CONSTRAINT work_evidence_attempt_error_consistency
        CHECK ((state = 'blocked') = (error_code IS NOT NULL))
);

ALTER TABLE public.work_evidence_submission_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.work_evidence_submission_attempts
FROM PUBLIC, anon, authenticated;
-- No direct client policies. The migration role must be a trusted owner with
-- protected-table access, including Storage metadata and legacy RPC EXECUTE.

CREATE FUNCTION public.guard_work_evidence_attempt()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Attempt deletion is not supported';
    END IF;
    IF ROW(NEW.request_id, NEW.assignment_id, NEW.worker_id, NEW.target_round,
           NEW.description, NEW.storage_paths, NEW.created_at)
       IS DISTINCT FROM
       ROW(OLD.request_id, OLD.assignment_id, OLD.worker_id, OLD.target_round,
           OLD.description, OLD.storage_paths, OLD.created_at)
       OR OLD.state <> 'prepared'
       OR NEW.state NOT IN ('committed', 'blocked') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Attempt identity and payload are immutable';
    END IF;
    NEW.updated_at := pg_catalog.clock_timestamp();
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_work_evidence_attempt()
FROM PUBLIC, anon, authenticated;

CREATE TRIGGER work_evidence_attempt_immutable
BEFORE UPDATE OR DELETE ON public.work_evidence_submission_attempts
FOR EACH ROW EXECUTE FUNCTION public.guard_work_evidence_attempt();

-- Internal, read-only validation. Invoker rights: called only inside trusted
-- definers. Private SQLSTATEs distinguish these deliberate business failures
-- from arbitrary P0001 errors raised by legacy functions or unrelated triggers.
CREATE FUNCTION public.assert_work_evidence_attempt_payload(
    p_assignment_id uuid, p_worker_id uuid, p_description text, p_storage_paths text[]
)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $function$
DECLARE
    v_path text;
    v_count integer;
BEGIN
    IF p_description IS NULL
       OR pg_catalog.char_length(pg_catalog.btrim(p_description)) NOT BETWEEN 1 AND 2000
       OR p_storage_paths IS NULL
       OR pg_catalog.array_ndims(p_storage_paths) IS DISTINCT FROM 1
       OR pg_catalog.array_lower(p_storage_paths, 1) IS DISTINCT FROM 1
       OR pg_catalog.cardinality(p_storage_paths) NOT BETWEEN 1 AND 5 THEN
        RAISE EXCEPTION USING ERRCODE = 'JM001', MESSAGE = 'payload_invalid';
    END IF;
    IF pg_catalog.array_position(p_storage_paths, NULL::text) IS NOT NULL THEN
        RAISE EXCEPTION USING ERRCODE = 'JM001', MESSAGE = 'payload_invalid';
    END IF;
    SELECT pg_catalog.count(DISTINCT path) INTO v_count
    FROM pg_catalog.unnest(p_storage_paths) AS paths(path);
    IF v_count <> pg_catalog.cardinality(p_storage_paths) THEN
        RAISE EXCEPTION USING ERRCODE = 'JM001', MESSAGE = 'payload_invalid';
    END IF;
    FOREACH v_path IN ARRAY p_storage_paths LOOP
        IF v_path !~ ('^' || p_assignment_id::text ||
            '/[A-Za-z0-9][A-Za-z0-9._-]{0,199}\.(jpg|jpeg|png|webp|pdf)$') THEN
            RAISE EXCEPTION USING ERRCODE = 'JM001', MESSAGE = 'payload_invalid';
        END IF;
        SELECT pg_catalog.count(*) INTO v_count
        FROM storage.objects AS o
        WHERE o.bucket_id = 'work-evidence'
          AND o.name = v_path AND o.owner_id = p_worker_id::text
          AND o.metadata ->> 'mimetype' IN ('image/jpeg', 'image/png', 'image/webp', 'application/pdf')
          AND CASE WHEN (o.metadata ->> 'size') ~ '^[0-9]+$'
              THEN (o.metadata ->> 'size')::numeric BETWEEN 1 AND 10485760
              ELSE false END;
        IF v_count <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'JM002', MESSAGE = 'storage_invalid';
        END IF;
        IF EXISTS (SELECT 1 FROM public.work_evidence AS e WHERE e.storage_path = v_path) THEN
            RAISE EXCEPTION USING ERRCODE = 'JM003', MESSAGE = 'path_already_submitted';
        END IF;
    END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION public.assert_work_evidence_attempt_payload(uuid, uuid, text, text[])
FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.prepare_my_work_evidence_submission(
    p_assignment_id uuid,
    p_expected_previous_round integer,
    p_description text,
    p_storage_paths text[]
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_assignment public.work_assignments%ROWTYPE;
    v_attempt public.work_evidence_submission_attempts%ROWTYPE;
    v_previous integer;
    v_description text := pg_catalog.btrim(p_description);
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '28000', MESSAGE = 'Authentication required';
    END IF;
    SELECT a.* INTO v_assignment FROM public.work_assignments AS a
    WHERE a.assignment_id = p_assignment_id AND a.worker_id = v_actor FOR UPDATE OF a;
    IF NOT FOUND OR NOT EXISTS (
        SELECT 1 FROM public.users AS u WHERE u.user_id = v_actor
        AND u.role = 'job_seeker'::public.user_role AND u.status = 'active'::public.account_status
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Work assignment access denied';
    END IF;
    IF p_expected_previous_round IS NULL OR p_expected_previous_round < 0
       OR p_expected_previous_round >= 2147483647 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'A valid previous round is required';
    END IF;
    -- Replay uses the ORIGINAL baseline, not whatever round is eligible now.
    -- The assignment lock is always acquired before the attempt lock.
    SELECT t.* INTO v_attempt FROM public.work_evidence_submission_attempts AS t
    WHERE t.assignment_id = p_assignment_id
      AND t.target_round = p_expected_previous_round + 1 FOR UPDATE OF t;
    IF FOUND THEN
        IF v_attempt.worker_id <> v_actor THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Attempt access denied';
        END IF;
        IF v_attempt.description IS DISTINCT FROM v_description
           OR v_attempt.storage_paths IS DISTINCT FROM p_storage_paths THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Attempt payload conflicts with the reserved round';
        END IF;
        RETURN pg_catalog.to_jsonb(v_attempt);
    END IF;
    SELECT coalesce(pg_catalog.max(s.submission_round), 0) INTO v_previous
    FROM public.work_evidence_submissions AS s WHERE s.assignment_id = p_assignment_id;
    IF v_previous <> p_expected_previous_round THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Submission round changed; recover the existing attempt';
    END IF;
    IF v_assignment.status <> 'awaiting_verification'
       OR NOT ((v_previous = 0 AND v_assignment.verification_status = 'not_submitted')
           OR (v_previous > 0 AND v_assignment.verification_status = 'more_evidence_required')) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Evidence preparation is not currently allowed';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.work_attendance AS att
        WHERE att.assignment_id = p_assignment_id AND att.check_in_at IS NOT NULL
        AND att.check_out_at IS NOT NULL AND att.check_out_at >= att.check_in_at) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Completed attendance is required';
    END IF;
    BEGIN
        PERFORM public.assert_work_evidence_attempt_payload(p_assignment_id, v_actor, v_description, p_storage_paths);
    EXCEPTION WHEN SQLSTATE 'JM001' OR SQLSTATE 'JM002' OR SQLSTATE 'JM003' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Evidence payload or uploaded files are not valid';
    END;
    INSERT INTO public.work_evidence_submission_attempts
        (assignment_id, worker_id, target_round, description, storage_paths)
    VALUES (p_assignment_id, v_actor, v_previous + 1, v_description, p_storage_paths)
    RETURNING * INTO v_attempt;
    RETURN pg_catalog.to_jsonb(v_attempt);
END;
$function$;

REVOKE ALL ON FUNCTION public.prepare_my_work_evidence_submission(uuid, integer, text, text[])
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_my_work_evidence_submission(uuid, integer, text, text[])
TO authenticated;

CREATE FUNCTION public.get_my_work_evidence_attempt(p_assignment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_assignment public.work_assignments%ROWTYPE;
    v_previous integer;
    v_attempts jsonb;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '28000', MESSAGE = 'Authentication required';
    END IF;
    SELECT a.* INTO v_assignment FROM public.work_assignments AS a
    JOIN public.users AS u ON u.user_id = a.worker_id
    WHERE a.assignment_id = p_assignment_id AND a.worker_id = v_actor
      AND u.role = 'job_seeker'::public.user_role AND u.status = 'active'::public.account_status;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Work assignment access denied';
    END IF;
    SELECT coalesce(pg_catalog.max(s.submission_round), 0) INTO v_previous
    FROM public.work_evidence_submissions AS s WHERE s.assignment_id = p_assignment_id;
    SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) ORDER BY t.target_round DESC), '[]'::jsonb)
    INTO v_attempts FROM public.work_evidence_submission_attempts AS t
    WHERE t.assignment_id = p_assignment_id AND t.worker_id = v_actor;
    RETURN pg_catalog.jsonb_build_object(
        'assignment_id', p_assignment_id, 'latest_submission_round', v_previous,
        'assignment_status', v_assignment.status, 'verification_status', v_assignment.verification_status,
        'attempts', v_attempts);
    -- Empty attempts is NOT proof that an earlier preparation/request failed.
    -- This read never creates a replacement, expires a reservation or unlocks it.
END;
$function$;

REVOKE ALL ON FUNCTION public.get_my_work_evidence_attempt(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_work_evidence_attempt(uuid) TO authenticated;

-- New TWO-argument overload: payload comes exclusively from the immutable
-- reservation. Intentionally distinct from the older undeployed four-argument
-- prototype (integer return); do not blindly apply every draft in this folder.
CREATE FUNCTION public.submit_work_evidence_idempotent(p_assignment_id uuid, p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_assignment public.work_assignments%ROWTYPE;
    v_attempt public.work_evidence_submission_attempts%ROWTYPE;
    v_submission public.work_evidence_submissions%ROWTYPE;
    v_previous integer;
    v_round integer;
    v_updated integer;
    v_error text;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '28000', MESSAGE = 'Authentication required';
    END IF;
    SELECT a.* INTO v_assignment FROM public.work_assignments AS a
    WHERE a.assignment_id = p_assignment_id AND a.worker_id = v_actor FOR UPDATE OF a;
    IF NOT FOUND OR NOT EXISTS (
        SELECT 1 FROM public.users AS u WHERE u.user_id = v_actor
        AND u.role = 'job_seeker'::public.user_role AND u.status = 'active'::public.account_status
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Work assignment access denied';
    END IF;
    SELECT t.* INTO v_attempt FROM public.work_evidence_submission_attempts AS t
    WHERE t.request_id = p_request_id AND t.assignment_id = p_assignment_id
      AND t.worker_id = v_actor FOR UPDATE OF t;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Attempt access denied';
    END IF;
    -- Current authentication/ownership precede replay; new eligibility follows.
    IF v_attempt.state IN ('committed', 'blocked') THEN
        RETURN pg_catalog.to_jsonb(v_attempt);
    END IF;
    SELECT coalesce(pg_catalog.max(s.submission_round), 0) INTO v_previous
    FROM public.work_evidence_submissions AS s WHERE s.assignment_id = p_assignment_id;
    IF v_previous <> v_attempt.target_round - 1 THEN
        v_error := 'round_changed';
    ELSIF v_assignment.status <> 'awaiting_verification'
       OR NOT ((v_previous = 0 AND v_assignment.verification_status = 'not_submitted')
           OR (v_previous > 0 AND v_assignment.verification_status = 'more_evidence_required')) THEN
        v_error := 'assignment_changed';
    ELSIF NOT EXISTS (SELECT 1 FROM public.work_attendance AS att
        WHERE att.assignment_id = p_assignment_id AND att.check_in_at IS NOT NULL
        AND att.check_out_at IS NOT NULL AND att.check_out_at >= att.check_in_at) THEN
        v_error := 'attendance_incomplete';
    ELSE
        BEGIN
            PERFORM public.assert_work_evidence_attempt_payload(
                p_assignment_id, v_actor, v_attempt.description, v_attempt.storage_paths);
        EXCEPTION
            WHEN SQLSTATE 'JM001' THEN v_error := 'payload_invalid';
            WHEN SQLSTATE 'JM002' THEN v_error := 'storage_invalid';
            WHEN SQLSTATE 'JM003' THEN v_error := 'path_already_submitted';
        END;
    END IF;
    IF v_error IS NOT NULL THEN
        UPDATE public.work_evidence_submission_attempts AS t
        SET state = 'blocked', error_code = v_error
        WHERE t.request_id = v_attempt.request_id AND t.state = 'prepared'
        RETURNING t.* INTO v_attempt;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Unable to record attempt outcome';
        END IF;
        -- Structured result, NOT RAISE: the terminal marker must commit.
        -- No expiry/reset/replacement API exists in this draft.
        RETURN pg_catalog.to_jsonb(v_attempt);
    END IF;
    -- auth.uid() reads JWT settings, not current_user. Nested SECURITY DEFINER
    -- does not replace those settings. The trusted owner needs legacy EXECUTE.
    -- Reacquiring the same assignment lock is compatible within this transaction.
    v_round := public.submit_work_evidence(p_assignment_id, v_attempt.description, v_attempt.storage_paths);
    IF v_round IS DISTINCT FROM v_attempt.target_round THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Submission round could not be confirmed';
    END IF;
    SELECT s.* INTO v_submission FROM public.work_evidence_submissions AS s
    WHERE s.assignment_id = p_assignment_id AND s.submitted_by = v_actor
      AND s.submission_round = v_round AND s.description = v_attempt.description
      AND s.file_count = pg_catalog.cardinality(v_attempt.storage_paths);
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Submission identity could not be confirmed';
    END IF;
    UPDATE public.work_evidence_submission_attempts AS t
    SET state = 'committed', submission_id = v_submission.submission_id
    WHERE t.request_id = v_attempt.request_id AND t.state = 'prepared'
    RETURNING t.* INTO v_attempt;
    GET DIAGNOSTICS v_updated = ROW_COUNT;
    IF v_updated <> 1 THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Attempt commitment could not be confirmed';
    END IF;
    RETURN pg_catalog.to_jsonb(v_attempt);
    -- No catch-all: timeouts, serialization/deadlock failures, unknown P0001,
    -- triggers, constraints and association failures roll back ALL this call's
    -- writes. The separately committed reservation remains prepared.
END;
$function$;

REVOKE ALL ON FUNCTION public.submit_work_evidence_idempotent(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_work_evidence_idempotent(uuid, uuid) TO authenticated;

-- NO legacy grant changes. Public submit_work_evidence(uuid,text,text[]) and,
-- if separately installed, the old four-argument prototype remain bypasses.
-- Coordinated, separately approved cutover/restriction is REQUIRED before
-- claiming reservation enforcement or enabling production submission.
COMMIT;

BEGIN;
-- Module 4: Attendance & Work Verification
-- One work assignment represents one scheduled shift.
-- Every shift requires evidence before employer verification.

CREATE TABLE public.work_assignments (
    assignment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    application_id uuid NOT NULL
        REFERENCES public.job_applications(application_id),

    job_id uuid NOT NULL
        REFERENCES public.job_postings(job_id),

    worker_id uuid NOT NULL
        REFERENCES public.users(user_id),

    company_id uuid NOT NULL
        REFERENCES public.companies(company_id),

    scheduled_start timestamptz NOT NULL,
    scheduled_end timestamptz NOT NULL,

    workplace_location text NOT NULL,

    status text NOT NULL DEFAULT 'scheduled'
        CHECK (
            status IN (
                'scheduled',
                'active',
                'awaiting_verification',
                'completed',
                'cancelled',
                'disputed'
            )
        ),

    verification_status text NOT NULL DEFAULT 'not_submitted'
        CHECK (
            verification_status IN (
                'not_submitted',
                'pending_review',
                'more_evidence_required',
                'verified',
                'disputed'
            )
        ),

    created_by uuid NOT NULL
        REFERENCES public.users(user_id),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    verified_at timestamptz,

    CONSTRAINT valid_assignment_schedule
        CHECK (scheduled_end > scheduled_start),

    CONSTRAINT verified_assignment_consistency
        CHECK (
            verification_status <> 'verified'
            OR (status = 'completed' AND verified_at IS NOT NULL)
        )
);

CREATE INDEX idx_work_assignments_application
    ON public.work_assignments(application_id);

CREATE INDEX idx_work_assignments_worker
    ON public.work_assignments(worker_id);

CREATE INDEX idx_work_assignments_company
    ON public.work_assignments(company_id);

-- Prevent a worker from having overlapping scheduled shifts.
-- Cancelled assignments do not block new schedules.
-- The exclusion constraint also protects against concurrent inserts.

CREATE SCHEMA IF NOT EXISTS extensions;

CREATE EXTENSION IF NOT EXISTS btree_gist
WITH SCHEMA extensions;

SET LOCAL search_path = public, extensions;

ALTER TABLE public.work_assignments
ADD CONSTRAINT work_assignments_no_worker_overlap
EXCLUDE USING gist (
    worker_id WITH =,
    tstzrange(
        scheduled_start,
        scheduled_end,
        '[)'
    ) WITH &&
)
WHERE (status <> 'cancelled');

ALTER TABLE public.work_assignments
    ENABLE ROW LEVEL SECURITY;


-- One attendance record per scheduled shift.
-- Check-in and check-out timestamps must be assigned by
-- secure backend functions, not trusted from the device.

CREATE TABLE public.work_attendance (
    attendance_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    assignment_id uuid NOT NULL UNIQUE
        REFERENCES public.work_assignments(assignment_id),

    check_in_at timestamptz,
    check_out_at timestamptz,

    check_in_latitude numeric(10, 7),
    check_in_longitude numeric(10, 7),

    check_out_latitude numeric(10, 7),
    check_out_longitude numeric(10, 7),

    check_in_location_status text
        CHECK (
            check_in_location_status IN (
                'granted',
                'denied',
                'unavailable'
            )
        ),

    check_out_location_status text
        CHECK (
            check_out_location_status IN (
                'granted',
                'denied',
                'unavailable'
            )
        ),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT valid_attendance_order
        CHECK (
            check_out_at IS NULL
            OR (
                check_in_at IS NOT NULL
                AND check_out_at >= check_in_at
            )
        ),

    CONSTRAINT valid_check_in_coordinates
        CHECK (
            (check_in_latitude IS NULL AND check_in_longitude IS NULL)
            OR (
                check_in_latitude BETWEEN -90 AND 90
                AND check_in_longitude BETWEEN -180 AND 180
            )
        ),

    CONSTRAINT valid_check_out_coordinates
        CHECK (
            (check_out_latitude IS NULL AND check_out_longitude IS NULL)
            OR (
                check_out_latitude BETWEEN -90 AND 90
                AND check_out_longitude BETWEEN -180 AND 180
            )
        ),

    CONSTRAINT check_in_location_consistency
        CHECK (
            check_in_location_status IS NULL
            OR (
                check_in_at IS NOT NULL
                AND (
                    check_in_location_status = 'granted'
                    OR (
                        check_in_latitude IS NULL
                        AND check_in_longitude IS NULL
                    )
                )
            )
        ),

    CONSTRAINT check_out_location_consistency
        CHECK (
            check_out_location_status IS NULL
            OR (
                check_out_at IS NOT NULL
                AND (
                    check_out_location_status = 'granted'
                    OR (
                        check_out_latitude IS NULL
                        AND check_out_longitude IS NULL
                    )
                )
            )
        )
);

CREATE INDEX idx_work_attendance_assignment
    ON public.work_attendance(assignment_id);

ALTER TABLE public.work_attendance
    ENABLE ROW LEVEL SECURITY;

-- Module 4: Daily work evidence
-- Evidence belongs to one scheduled shift.
-- Files will be stored in a private Supabase Storage bucket.

CREATE TABLE public.work_evidence (
    evidence_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    assignment_id uuid NOT NULL
        REFERENCES public.work_assignments(assignment_id),

    submitted_by uuid NOT NULL
        REFERENCES public.users(user_id),

    submission_round integer NOT NULL DEFAULT 1
        CHECK (submission_round >= 1),

    description text NOT NULL
        CHECK (
            length(trim(description)) BETWEEN 1 AND 2000
        ),

    storage_path text NOT NULL
        CHECK (length(trim(storage_path)) > 0),

    file_name text NOT NULL
        CHECK (length(trim(file_name)) > 0),

    mime_type text NOT NULL,

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_work_evidence_assignment
    ON public.work_evidence(
        assignment_id,
        submission_round
    );

ALTER TABLE public.work_evidence
    ENABLE ROW LEVEL SECURITY;

-- Module 4: Employer verification audit history
-- Records every verification decision for a work assignment.

CREATE TABLE public.work_verification_history (
    verification_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    assignment_id uuid NOT NULL
        REFERENCES public.work_assignments(assignment_id),

    action text NOT NULL
        CHECK (
            action IN (
                'evidence_submitted',
                'more_evidence_requested',
                'evidence_resubmitted',
                'verified',
                'disputed'
            )
        ),

    previous_status text,
    new_status text NOT NULL,

    performed_by uuid NOT NULL
        REFERENCES public.users(user_id),

    note text,

    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT verification_note_length
        CHECK (
            note IS NULL
            OR length(note) <= 1000
        ),

    CONSTRAINT evidence_request_requires_reason
        CHECK (
            action <> 'more_evidence_requested'
            OR (
                note IS NOT NULL
                AND length(trim(note)) > 0
            )
        )
);

CREATE INDEX idx_work_verification_history_assignment
    ON public.work_verification_history(
        assignment_id,
        created_at
    );

ALTER TABLE public.work_verification_history
    ENABLE ROW LEVEL SECURITY;

-- Module 4: Restrict direct access to sensitive tables.
-- Secure RPCs will perform authorized operations.

REVOKE ALL ON TABLE public.work_assignments
    FROM PUBLIC, anon, authenticated;

REVOKE ALL ON TABLE public.work_attendance
    FROM PUBLIC, anon, authenticated;

REVOKE ALL ON TABLE public.work_evidence
    FROM PUBLIC, anon, authenticated;

REVOKE ALL ON TABLE public.work_verification_history
    FROM PUBLIC, anon, authenticated;

-- Module 4: Create one work assignment per scheduled shift.
-- Only an authorized employer may create assignments for Hired workers.

CREATE OR REPLACE FUNCTION public.create_work_assignment(
    p_application_id uuid,
    p_scheduled_start timestamptz,
    p_scheduled_end timestamptz,
    p_workplace_location text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_application record;
    v_company_id uuid;
    v_assignment_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'You must be signed in.';
    END IF;

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

    RETURN v_assignment_id;
END;
$function$;

-- Restrict who may invoke the function.
REVOKE ALL ON FUNCTION public.create_work_assignment(
    uuid, timestamptz, timestamptz, text
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_work_assignment(
    uuid, timestamptz, timestamptz, text
) TO authenticated;

-- Module 4: Worker check-in
-- Server time is authoritative. GPS is device-reported, not proof of presence.

CREATE OR REPLACE FUNCTION public.check_in_work_assignment(
    p_assignment_id uuid,
    p_location_status text,
    p_latitude numeric DEFAULT NULL,
    p_longitude numeric DEFAULT NULL
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_assignment record;
    v_check_in_at timestamptz;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'You must be signed in.';
    END IF;

    SELECT
        a.assignment_id,
        a.worker_id,
        a.status,
        a.scheduled_start,
        a.scheduled_end
    INTO v_assignment
    FROM public.work_assignments a
    WHERE a.assignment_id = p_assignment_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Work assignment not found.';
    END IF;

    IF v_assignment.worker_id <> auth.uid()
       OR NOT EXISTS (
           SELECT 1
           FROM public.users u
           WHERE u.user_id = auth.uid()
             AND u.role = 'job_seeker'::public.user_role
             AND u.status = 'active'::public.account_status
       ) THEN
        RAISE EXCEPTION 'You cannot check in to this assignment.';
    END IF;

    IF v_assignment.status <> 'scheduled' THEN
        RAISE EXCEPTION 'This assignment is not available for check-in.';
    END IF;

    IF p_location_status IS NULL
       OR p_location_status NOT IN ('granted', 'denied', 'unavailable') THEN
        RAISE EXCEPTION 'Invalid location permission status.';
    END IF;

    IF p_location_status = 'granted' THEN
        IF p_latitude IS NULL
           OR p_longitude IS NULL
           OR p_latitude NOT BETWEEN -90 AND 90
           OR p_longitude NOT BETWEEN -180 AND 180 THEN
            RAISE EXCEPTION 'Valid coordinates are required when GPS is granted.';
        END IF;
    ELSIF p_latitude IS NOT NULL OR p_longitude IS NOT NULL THEN
        RAISE EXCEPTION 'Coordinates must be omitted when GPS is unavailable.';
    END IF;

    -- Allow check-in from 60 minutes before scheduled start
    -- until the scheduled shift ends.
    IF clock_timestamp() < v_assignment.scheduled_start - interval '60 minutes'
       OR clock_timestamp() > v_assignment.scheduled_end THEN
        RAISE EXCEPTION 'Check-in is outside the allowed shift window.';
    END IF;

    v_check_in_at := clock_timestamp();

    INSERT INTO public.work_attendance (
        assignment_id,
        check_in_at,
        check_in_latitude,
        check_in_longitude,
        check_in_location_status
    )
    VALUES (
        p_assignment_id,
        v_check_in_at,
        p_latitude,
        p_longitude,
        p_location_status
    );

    UPDATE public.work_assignments
    SET status = 'active',
        updated_at = v_check_in_at
    WHERE assignment_id = p_assignment_id;

    RETURN v_check_in_at;
END;
$function$;

REVOKE ALL ON FUNCTION public.check_in_work_assignment(
    uuid, text, numeric, numeric
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.check_in_work_assignment(
    uuid, text, numeric, numeric
) TO authenticated;

-- Module 4: Worker check-out
-- Uses server time and prevents duplicate check-outs.

CREATE OR REPLACE FUNCTION public.check_out_work_assignment(
    p_assignment_id uuid,
    p_location_status text,
    p_latitude numeric DEFAULT NULL,
    p_longitude numeric DEFAULT NULL
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_assignment record;
    v_attendance record;
    v_check_out_at timestamptz;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'You must be signed in.';
    END IF;

    SELECT
        a.assignment_id,
        a.worker_id,
        a.status
    INTO v_assignment
    FROM public.work_assignments a
    WHERE a.assignment_id = p_assignment_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Work assignment not found.';
    END IF;

    IF v_assignment.worker_id <> auth.uid()
       OR NOT EXISTS (
           SELECT 1
           FROM public.users u
           WHERE u.user_id = auth.uid()
             AND u.role = 'job_seeker'::public.user_role
             AND u.status = 'active'::public.account_status
       ) THEN
        RAISE EXCEPTION 'You cannot check out of this assignment.';
    END IF;

    IF v_assignment.status <> 'active' THEN
        RAISE EXCEPTION 'This assignment is not active.';
    END IF;

    SELECT check_in_at, check_out_at
    INTO v_attendance
    FROM public.work_attendance
    WHERE assignment_id = p_assignment_id
    FOR UPDATE;

    IF NOT FOUND OR v_attendance.check_in_at IS NULL THEN
        RAISE EXCEPTION 'You must check in before checking out.';
    END IF;

    IF v_attendance.check_out_at IS NOT NULL THEN
        RAISE EXCEPTION 'You have already checked out.';
    END IF;

    IF p_location_status IS NULL
       OR p_location_status NOT IN ('granted', 'denied', 'unavailable') THEN
        RAISE EXCEPTION 'Invalid location permission status.';
    END IF;

    IF p_location_status = 'granted' THEN
        IF p_latitude IS NULL
           OR p_longitude IS NULL
           OR p_latitude NOT BETWEEN -90 AND 90
           OR p_longitude NOT BETWEEN -180 AND 180 THEN
            RAISE EXCEPTION 'Valid GPS coordinates are required.';
        END IF;
    ELSIF p_latitude IS NOT NULL OR p_longitude IS NOT NULL THEN
        RAISE EXCEPTION 'Coordinates must be omitted when GPS is unavailable.';
    END IF;

    v_check_out_at := clock_timestamp();

    IF v_check_out_at < v_attendance.check_in_at THEN
        RAISE EXCEPTION 'Check-out cannot precede check-in.';
    END IF;

    UPDATE public.work_attendance
    SET check_out_at = v_check_out_at,
        check_out_latitude = p_latitude,
        check_out_longitude = p_longitude,
        check_out_location_status = p_location_status,
        updated_at = v_check_out_at
    WHERE assignment_id = p_assignment_id;

    UPDATE public.work_assignments
    SET status = 'awaiting_verification',
        updated_at = v_check_out_at
    WHERE assignment_id = p_assignment_id;

    RETURN v_check_out_at;
END;
$function$;

REVOKE ALL ON FUNCTION public.check_out_work_assignment(
    uuid, text, numeric, numeric
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.check_out_work_assignment(
    uuid, text, numeric, numeric
) TO authenticated;

-- Module 4: Private work evidence Storage bucket.
-- Photos and PDFs only, maximum 10 MB per file.

INSERT INTO storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
VALUES (
    'work-evidence',
    'work-evidence',
    false,
    10485760,
    ARRAY[
        'image/jpeg',
        'image/png',
        'image/webp',
        'application/pdf'
    ]::text[]
)
ON CONFLICT (id) DO NOTHING;

-- Module 4: Worker evidence upload policy.
-- Workers may upload files only to their own checked-out assignments.
-- File paths must be: assignment_id/unique_filename.ext

-- Module 4: Secure authorization for evidence uploads.
-- This helper can read protected tables without exposing them to Flutter.

CREATE OR REPLACE FUNCTION public.can_upload_work_evidence(
    p_assignment_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT auth.uid() IS NOT NULL
   AND EXISTS (
       SELECT 1
       FROM public.users u
       WHERE u.user_id = auth.uid()
         AND u.role = 'job_seeker'::public.user_role
         AND u.status = 'active'::public.account_status
   )
       AND EXISTS (
           SELECT 1
           FROM public.work_assignments a
           JOIN public.work_attendance att
             ON att.assignment_id = a.assignment_id
           WHERE a.assignment_id = p_assignment_id
             AND a.worker_id = auth.uid()
             AND a.status = 'awaiting_verification'
             AND att.check_out_at IS NOT NULL
             AND a.verification_status IN (
                 'not_submitted',
                 'more_evidence_required'
             )
       );
$function$;

REVOKE ALL ON FUNCTION public.can_upload_work_evidence(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.can_upload_work_evidence(uuid)
TO authenticated;

-- Workers may upload only to an eligible assignment folder.
-- Storage object paths use: assignment_id/unique_filename.ext

-- Evidence storage is append-only for authenticated clients.
--
-- Only INSERT is permitted through the worker upload policy.
-- Do not create UPDATE or DELETE policies for this bucket.
--
-- Flutter must upload evidence with upsert: false.
-- Existing evidence objects must never be overwritten.
--
-- Any future evidence removal or correction must use a
-- separately audited, server-controlled workflow.

-- Explicitly deny authenticated updates to work evidence.
-- This restrictive policy also applies if another UPDATE
-- policy exists on storage.objects.

CREATE POLICY "work_evidence_no_authenticated_updates"
ON storage.objects
AS RESTRICTIVE
FOR UPDATE
TO authenticated
USING (bucket_id <> 'work-evidence')
WITH CHECK (bucket_id <> 'work-evidence');

CREATE POLICY "work_evidence_worker_upload"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'work-evidence'
    AND storage.filename(name) ~
        '^[A-Za-z0-9][A-Za-z0-9._-]{0,199}\.(jpg|jpeg|png|webp|pdf)$'
    AND array_length(storage.foldername(name), 1) = 1
    AND (storage.foldername(name))[1] ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    AND public.can_upload_work_evidence(
        ((storage.foldername(name))[1])::uuid
    )
);

-- Module 4: Track each evidence submission round.
-- Individual files remain in public.work_evidence.

CREATE TABLE public.work_evidence_submissions (
    submission_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    assignment_id uuid NOT NULL
        REFERENCES public.work_assignments(assignment_id),

    submission_round integer NOT NULL
        CHECK (submission_round >= 1),

    submitted_by uuid NOT NULL
        REFERENCES public.users(user_id),

    description text NOT NULL
        CHECK (
            char_length(btrim(description)) BETWEEN 1 AND 2000
        ),

    file_count integer NOT NULL
        CHECK (file_count BETWEEN 1 AND 5),

    submitted_at timestamptz NOT NULL
        DEFAULT clock_timestamp(),

    CONSTRAINT work_evidence_submission_round_unique
        UNIQUE (assignment_id, submission_round)
);

CREATE INDEX work_evidence_submissions_assignment_idx
ON public.work_evidence_submissions (assignment_id);

ALTER TABLE public.work_evidence_submissions
ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.work_evidence_submissions
FROM PUBLIC, anon, authenticated;
-- Access will be through secure RPCs only.


-- Module 4: Secure authorization for viewing work evidence.
-- The assigned worker or an authorized employer may view
-- files belonging to the assignment.

CREATE OR REPLACE FUNCTION public.can_view_work_evidence(
    p_assignment_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT auth.uid() IS NOT NULL
       AND EXISTS (
           SELECT 1
           FROM public.work_assignments a
           WHERE a.assignment_id = p_assignment_id
             AND (
                 -- Assigned worker
                 a.worker_id = auth.uid()

                 OR

                -- Authorized employer may view only assignments
                -- that have at least one formal evidence submission.
                (
                    public.can_manage_company_jobs(a.company_id)
                    AND EXISTS (
                        SELECT 1
                        FROM public.work_evidence_submissions s
                        WHERE s.assignment_id = a.assignment_id
                    )
                )
             )
       );
$function$;

REVOKE ALL ON FUNCTION public.can_view_work_evidence(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.can_view_work_evidence(uuid)
TO authenticated;

-- Module 4 security hardening:
-- Check access to an individual work evidence file.
--
-- Workers can view files in their own assignment folder.
-- Employers can view only formally submitted evidence files.

CREATE OR REPLACE FUNCTION public.can_read_work_evidence_file(
    p_storage_path text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_assignment_id uuid;
    v_company_id uuid;
    v_worker_id uuid;
BEGIN
    IF auth.uid() IS NULL OR p_storage_path IS NULL THEN
        RETURN false;
    END IF;

    -- Expected path: assignment_uuid/filename.ext
    IF p_storage_path !~
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]+$'
    THEN
        RETURN false;
    END IF;

    v_assignment_id := split_part(p_storage_path, '/', 1)::uuid;

    SELECT a.company_id, a.worker_id
    INTO v_company_id, v_worker_id
    FROM public.work_assignments a
    WHERE a.assignment_id = v_assignment_id;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    -- The assigned worker may view their own uploaded files.
    IF v_worker_id = auth.uid() THEN
        RETURN true;
    END IF;

    -- Employers must be authorized AND the specific file
    -- must have been formally registered as evidence.
    RETURN public.can_manage_company_jobs(v_company_id)
       AND EXISTS (
           SELECT 1
           FROM public.work_evidence e
           WHERE e.assignment_id = v_assignment_id
             AND e.storage_path = p_storage_path
       );
END;
$function$;

REVOKE ALL ON FUNCTION public.can_read_work_evidence_file(text)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.can_read_work_evidence_file(text)
TO authenticated;

-- Allow authorized users to read private evidence files.
-- Paths must follow: assignment_id/filename.ext

CREATE POLICY "work_evidence_authorized_read"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'work-evidence'

    AND array_length(storage.foldername(name), 1) = 1

    AND (storage.foldername(name))[1] ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

    AND public.can_read_work_evidence_file(name)
);



-- Module 4: Submit evidence for a completed shift.
-- p_storage_paths contains 1–5 previously uploaded private files.

CREATE OR REPLACE FUNCTION public.submit_work_evidence(
    p_assignment_id uuid,
    p_description text,
    p_storage_paths text[]
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_assignment public.work_assignments%ROWTYPE;
    v_round integer;
    v_path text;
    v_file_count integer;
    v_existing_count integer;
    v_object_count integer;
    v_mime_type text;
    v_file_name text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF p_description IS NULL
       OR char_length(btrim(p_description)) NOT BETWEEN 1 AND 2000
    THEN
        RAISE EXCEPTION 'Description must contain 1–2000 characters';
    END IF;

    v_file_count := coalesce(array_length(p_storage_paths, 1), 0);

    IF v_file_count NOT BETWEEN 1 AND 5 THEN
        RAISE EXCEPTION 'Submit between 1 and 5 evidence files';
    END IF;

    SELECT *
    INTO v_assignment
    FROM public.work_assignments
    WHERE assignment_id = p_assignment_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Assignment not found';
    END IF;

    IF v_assignment.worker_id <> auth.uid() THEN
        RAISE EXCEPTION 'Not authorized for this assignment';
    END IF;
    IF NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.user_id = auth.uid()
      AND u.role = 'job_seeker'::public.user_role
      AND u.status = 'active'::public.account_status
) THEN
    RAISE EXCEPTION
        'Only active job seekers may submit work evidence';
END IF;

    IF v_assignment.status <> 'awaiting_verification'
       OR v_assignment.verification_status NOT IN (
           'not_submitted',
           'more_evidence_required'
       )
    THEN
        RAISE EXCEPTION 'Evidence submission is not currently allowed';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.work_attendance
        WHERE assignment_id = p_assignment_id
          AND check_in_at IS NOT NULL
          AND check_out_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'Check-in and check-out are required';
    END IF;

    -- Do not allow the same path twice within one submission.
    SELECT count(DISTINCT path)
    INTO v_existing_count
    FROM unnest(p_storage_paths) AS paths(path);

    IF v_existing_count <> v_file_count THEN
        RAISE EXCEPTION 'Duplicate or invalid evidence paths';
    END IF;

    SELECT coalesce(max(submission_round), 0) + 1
    INTO v_round
    FROM public.work_evidence_submissions
    WHERE assignment_id = p_assignment_id;

    IF v_assignment.verification_status = 'not_submitted'
       AND v_round <> 1 THEN
        RAISE EXCEPTION 'Invalid first submission';
    END IF;

    IF v_assignment.verification_status = 'more_evidence_required'
       AND v_round = 1 THEN
        RAISE EXCEPTION 'No previous submission to supplement';
    END IF;

    -- Validate each file against the private Storage bucket.
    FOREACH v_path IN ARRAY p_storage_paths LOOP

    IF v_path IS NULL
    OR v_path !~ (
        '^'
        || p_assignment_id::text
        || '/[A-Za-z0-9][A-Za-z0-9._-]{0,199}\.(jpg|jpeg|png|webp|pdf)$'
    )
    THEN
        RAISE EXCEPTION
            'Invalid evidence file path or unsupported filename';
    END IF;

        -- Confirm the object exists, belongs to this worker,
        -- and is within the 10 MB file-size limit.

        SELECT count(*), max(o.metadata ->> 'mimetype')
        INTO v_object_count, v_mime_type
        FROM storage.objects o
        WHERE o.bucket_id = 'work-evidence'
            AND o.name = v_path
            AND o.owner_id = auth.uid()::text
            AND (o.metadata ->> 'size') ~ '^[0-9]+$'
            AND (o.metadata ->> 'size')::bigint
                BETWEEN 1 AND 10485760;

        IF v_object_count <> 1 THEN
            RAISE EXCEPTION 'Evidence file not found in private storage';
        END IF;

        IF v_mime_type NOT IN (
            'image/jpeg',
            'image/png',
            'image/webp',
            'application/pdf'
        ) THEN
            RAISE EXCEPTION 'Unsupported evidence file type';
        END IF;

        IF EXISTS (
            SELECT 1
            FROM public.work_evidence e
            WHERE e.storage_path = v_path
        ) THEN
            RAISE EXCEPTION 'Evidence file has already been submitted';
        END IF;

        v_file_name := split_part(v_path, '/', 2);

        INSERT INTO public.work_evidence (
            assignment_id,
            submitted_by,
            submission_round,
            description,
            storage_path,
            file_name,
            mime_type
        )
        VALUES (
            p_assignment_id,
            auth.uid(),
            v_round,
            btrim(p_description),
            v_path,
            v_file_name,
            v_mime_type
        );
    END LOOP;

    INSERT INTO public.work_evidence_submissions (
        assignment_id,
        submission_round,
        submitted_by,
        description,
        file_count
    )
    VALUES (
        p_assignment_id,
        v_round,
        auth.uid(),
        btrim(p_description),
        v_file_count
    );

    INSERT INTO public.work_verification_history (
        assignment_id,
        action,
        previous_status,
        new_status,
        performed_by,
        note
    )
    VALUES (
        p_assignment_id,
        CASE
            WHEN v_round = 1 THEN 'evidence_submitted'
            ELSE 'evidence_resubmitted'
        END,
        v_assignment.verification_status,
        'pending_review',
        auth.uid(),
        NULL
    );

    UPDATE public.work_assignments
    SET verification_status = 'pending_review',
        updated_at = clock_timestamp()
    WHERE assignment_id = p_assignment_id;

    RETURN v_round;
END;
$function$;

REVOKE ALL ON FUNCTION public.submit_work_evidence(
    uuid, text, text[]
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.submit_work_evidence(
    uuid, text, text[]
) TO authenticated;

-- Module 4: Employer requests additional evidence.
-- The request must include a reason and is recorded in audit history.

CREATE OR REPLACE FUNCTION public.request_more_work_evidence(
    p_assignment_id uuid,
    p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_assignment public.work_assignments%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF p_reason IS NULL
       OR char_length(btrim(p_reason)) NOT BETWEEN 1 AND 1000
    THEN
        RAISE EXCEPTION 'Reason must contain 1–1000 characters';
    END IF;

    SELECT *
    INTO v_assignment
    FROM public.work_assignments
    WHERE assignment_id = p_assignment_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Assignment not found';
    END IF;

    IF NOT public.can_manage_company_jobs(v_assignment.company_id) THEN
        RAISE EXCEPTION 'Not authorized to review this assignment';
    END IF;

    IF v_assignment.status <> 'awaiting_verification'
       OR v_assignment.verification_status <> 'pending_review'
    THEN
        RAISE EXCEPTION 'Assignment is not pending evidence review';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.work_evidence_submissions
        WHERE assignment_id = p_assignment_id
    ) THEN
        RAISE EXCEPTION 'No evidence submission exists';
    END IF;

    UPDATE public.work_assignments
    SET verification_status = 'more_evidence_required',
        updated_at = clock_timestamp()
    WHERE assignment_id = p_assignment_id;

    INSERT INTO public.work_verification_history (
        assignment_id,
        action,
        previous_status,
        new_status,
        performed_by,
        note
    )
    VALUES (
        p_assignment_id,
        'more_evidence_requested',
        'pending_review',
        'more_evidence_required',
        auth.uid(),
        btrim(p_reason)
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.request_more_work_evidence(
    uuid, text
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.request_more_work_evidence(
    uuid, text
) TO authenticated;

-- Module 4: Employer verifies completed work.
-- Verification requires attendance and submitted evidence.

CREATE OR REPLACE FUNCTION public.verify_work_assignment(
    p_assignment_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_assignment public.work_assignments%ROWTYPE;
    v_latest_round integer;
    v_expected_files integer;
    v_recorded_files bigint;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT *
    INTO v_assignment
    FROM public.work_assignments
    WHERE assignment_id = p_assignment_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Assignment not found';
    END IF;

    IF NOT public.can_manage_company_jobs(v_assignment.company_id) THEN
        RAISE EXCEPTION 'Not authorized to verify this assignment';
    END IF;

    IF v_assignment.status <> 'awaiting_verification'
       OR v_assignment.verification_status <> 'pending_review'
    THEN
        RAISE EXCEPTION 'Assignment is not pending verification';
    END IF;

    -- Both attendance timestamps must exist.
    IF NOT EXISTS (
        SELECT 1
        FROM public.work_attendance
        WHERE assignment_id = p_assignment_id
          AND check_in_at IS NOT NULL
          AND check_out_at IS NOT NULL
          AND check_out_at >= check_in_at
    ) THEN
        RAISE EXCEPTION 'Completed attendance is required';
    END IF;

    -- Identify the most recent evidence submission.
    SELECT submission_round, file_count
    INTO v_latest_round, v_expected_files
    FROM public.work_evidence_submissions
    WHERE assignment_id = p_assignment_id
    ORDER BY submission_round DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Work evidence has not been submitted';
    END IF;

    -- Confirm that the latest submission has 1–5 recorded files.
    SELECT count(*)
    INTO v_recorded_files
    FROM public.work_evidence
    WHERE assignment_id = p_assignment_id
      AND submission_round = v_latest_round;

    IF v_recorded_files <> v_expected_files
       OR v_recorded_files NOT BETWEEN 1 AND 5
    THEN
        RAISE EXCEPTION 'Evidence file records are incomplete';
    END IF;

    -- Confirm that every recorded file in the latest submission
    -- still exists in the private Storage bucket.
    IF EXISTS (
        SELECT 1
        FROM public.work_evidence e
        WHERE e.assignment_id = p_assignment_id
        AND e.submission_round = v_latest_round
        AND NOT EXISTS (
            SELECT 1
            FROM storage.objects o
            WHERE o.bucket_id = 'work-evidence'
                AND o.name = e.storage_path
                AND o.owner_id = e.submitted_by::text
        )
    ) THEN
        RAISE EXCEPTION
            'One or more evidence files are missing from private storage';
    END IF;
    -- Mark the shift as completed and verified.
    UPDATE public.work_assignments
    SET status = 'completed',
        verification_status = 'verified',
        verified_at = clock_timestamp(),
        updated_at = clock_timestamp()
    WHERE assignment_id = p_assignment_id;

    -- Preserve the employer's verification decision.
    INSERT INTO public.work_verification_history (
        assignment_id,
        action,
        previous_status,
        new_status,
        performed_by,
        note
    )
    VALUES (
        p_assignment_id,
        'verified',
        'pending_review',
        'verified',
        auth.uid(),
        'Work verified by employer'
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.verify_work_assignment(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.verify_work_assignment(uuid)
TO authenticated;

-- Module 4: List assignments for the signed-in worker.
-- Uses a security-definer RPC because direct table access is revoked.

CREATE OR REPLACE FUNCTION public.list_my_work_assignments()
RETURNS TABLE (
    assignment_id uuid,
    application_id uuid,
    job_id uuid,
    job_title text,
    company_id uuid,
    company_name text,
    scheduled_start timestamptz,
    scheduled_end timestamptz,
    workplace_location text,
    assignment_status text,
    verification_status text,
    check_in_at timestamptz,
    check_out_at timestamptz,
    verified_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    RETURN QUERY
    SELECT
        a.assignment_id,
        a.application_id,
        a.job_id,
        j.title::text,
        a.company_id,
        c.company_name::text,
        a.scheduled_start,
        a.scheduled_end,
        a.workplace_location,
        a.status::text,
        a.verification_status::text,
        att.check_in_at,
        att.check_out_at,
        a.verified_at
    FROM public.work_assignments a
    JOIN public.job_postings j
      ON j.job_id = a.job_id
    JOIN public.companies c
      ON c.company_id = a.company_id
    LEFT JOIN public.work_attendance att
      ON att.assignment_id = a.assignment_id
    WHERE a.worker_id = auth.uid()
      AND EXISTS (
          SELECT 1
          FROM public.users u
          WHERE u.user_id = auth.uid()
            AND u.role = 'job_seeker'
            AND u.status = 'active'
      )
    ORDER BY a.scheduled_start DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.list_my_work_assignments()
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.list_my_work_assignments()
TO authenticated;

-- Module 4: List work assignments for an authorized employer.
-- Direct table access remains revoked.

CREATE OR REPLACE FUNCTION public.list_company_work_assignments(
    p_company_id uuid
)
RETURNS TABLE (
    assignment_id uuid,
    application_id uuid,
    job_id uuid,
    job_title text,
    worker_id uuid,
    scheduled_start timestamptz,
    scheduled_end timestamptz,
    workplace_location text,
    assignment_status text,
    verification_status text,
    check_in_at timestamptz,
    check_out_at timestamptz,
    verified_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF p_company_id IS NULL
       OR NOT public.can_manage_company_jobs(p_company_id)
    THEN
        RAISE EXCEPTION 'Not authorized to view company assignments';
    END IF;

    RETURN QUERY
    SELECT
        a.assignment_id,
        a.application_id,
        a.job_id,
        j.title::text,
        a.worker_id,
        a.scheduled_start,
        a.scheduled_end,
        a.workplace_location,
        a.status::text,
        a.verification_status::text,
        att.check_in_at,
        att.check_out_at,
        a.verified_at
    FROM public.work_assignments a
    JOIN public.job_postings j
      ON j.job_id = a.job_id
    LEFT JOIN public.work_attendance att
      ON att.assignment_id = a.assignment_id
    WHERE a.company_id = p_company_id
    ORDER BY a.scheduled_start DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.list_company_work_assignments(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.list_company_work_assignments(uuid)
TO authenticated;

-- Module 4: List evidence files for one work assignment.
-- Accessible only to the assigned worker or authorized employer.

CREATE OR REPLACE FUNCTION public.list_work_evidence(
    p_assignment_id uuid
)
RETURNS TABLE (
    evidence_id uuid,
    submission_round integer,
    description text,
    storage_path text,
    file_name text,
    mime_type text,
    submitted_by uuid,
    submitted_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF p_assignment_id IS NULL
       OR NOT public.can_view_work_evidence(p_assignment_id)
    THEN
        RAISE EXCEPTION 'Not authorized to view this evidence';
    END IF;

    RETURN QUERY
    SELECT
        e.evidence_id,
        e.submission_round,
        e.description,
        e.storage_path,
        e.file_name,
        e.mime_type,
        e.submitted_by,
        e.created_at
    FROM public.work_evidence e
    WHERE e.assignment_id = p_assignment_id
    ORDER BY e.submission_round DESC, e.created_at ASC;
END;
$function$;

REVOKE ALL ON FUNCTION public.list_work_evidence(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.list_work_evidence(uuid)
TO authenticated;

-- Module 4 security hardening:
-- A Storage object can be registered as evidence only once.

ALTER TABLE public.work_evidence
ADD CONSTRAINT work_evidence_storage_path_unique
UNIQUE (storage_path);

COMMIT;
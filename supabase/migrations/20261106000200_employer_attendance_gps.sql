-- Review and apply separately; no attendance records are changed.
BEGIN;

CREATE FUNCTION public.read_employer_work_attendance_gps(
    p_company_id uuid,
    p_assignment_id uuid
)
RETURNS TABLE (
    assignment_id uuid,
    company_id uuid,
    check_in_at timestamptz,
    check_in_location_status text,
    check_in_latitude numeric,
    check_in_longitude numeric,
    check_out_at timestamptz,
    check_out_location_status text,
    check_out_latitude numeric,
    check_out_longitude numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
    END IF;
    IF p_company_id IS NULL OR p_assignment_id IS NULL
       OR public.can_manage_company_jobs(p_company_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Not authorized to view attendance GPS' USING ERRCODE = '42501';
    END IF;
    -- Retain the existing helper and the same explicit eligibility used by
    -- JobPostingsRepository.loadAccess. GPS is for active company employers.
    IF NOT EXISTS (
        SELECT 1
        FROM public.users u
        JOIN public.company_memberships m ON m.user_id = u.user_id
        JOIN public.companies c ON c.company_id = m.company_id
        WHERE u.user_id = auth.uid()
          AND u.role = 'employer' AND u.status = 'active'
          AND m.company_id = p_company_id
          AND m.member_role IN ('owner', 'employer')
          AND c.verification_status = 'verified'
    ) THEN
        RAISE EXCEPTION 'Not authorized to view attendance GPS' USING ERRCODE = '42501';
    END IF;
    -- Scope the assignment as well as the caller. A supplied company UUID
    -- never authorizes an assignment belonging to another company.
    IF NOT EXISTS (
        SELECT 1 FROM public.work_assignments a
        WHERE a.assignment_id = p_assignment_id AND a.company_id = p_company_id
    ) THEN
        RAISE EXCEPTION 'Not authorized to view attendance GPS' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT a.assignment_id, a.company_id,
        att.check_in_at, att.check_in_location_status,
        att.check_in_latitude, att.check_in_longitude,
        att.check_out_at, att.check_out_location_status,
        att.check_out_latitude, att.check_out_longitude
    FROM public.work_assignments a
    LEFT JOIN public.work_attendance att ON att.assignment_id = a.assignment_id
    WHERE a.assignment_id = p_assignment_id AND a.company_id = p_company_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.read_employer_work_attendance_gps(uuid, uuid)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.read_employer_work_attendance_gps(uuid, uuid)
    TO authenticated;
-- Direct table access and existing attendance-write functions remain unchanged.
NOTIFY pgrst, 'reload schema';
COMMIT;

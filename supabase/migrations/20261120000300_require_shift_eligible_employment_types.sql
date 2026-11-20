BEGIN;

SET LOCAL lock_timeout = '5s';

-- Apply after the workplace coordinates and Temporary posting migrations.
-- Both assignment creation paths insert here. Linked-request replays and
-- existing assignment updates do not insert and remain outside this guard.
CREATE FUNCTION private.guard_new_work_assignment_employment_type()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    posting_employment_type text;
BEGIN
    SELECT j.employment_type::text
      INTO posting_employment_type
      FROM public.job_postings AS j
     WHERE j.job_id = NEW.job_id
       AND j.company_id = NEW.company_id
       FOR SHARE OF j;

    -- The row lock serializes this check with edits to the posting.
    IF posting_employment_type IS NULL
       OR posting_employment_type NOT IN ('part_time', 'temporary') THEN
        RAISE EXCEPTION 'New shifts require a Part-Time or Temporary job.'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.guard_new_work_assignment_employment_type()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER work_assignment_employment_type_insert_guard
    BEFORE INSERT ON public.work_assignments
    FOR EACH ROW EXECUTE FUNCTION private.guard_new_work_assignment_employment_type();

COMMIT;

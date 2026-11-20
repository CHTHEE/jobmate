BEGIN;

SET LOCAL lock_timeout = '5s';

CREATE SCHEMA applicant_notifications_private;
REVOKE ALL ON SCHEMA applicant_notifications_private
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE applicant_notifications_private.activation (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  activated_at timestamptz
);
INSERT INTO applicant_notifications_private.activation (singleton) VALUES (true);

CREATE FUNCTION applicant_notifications_private.guard_activation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  IF TG_OP <> 'UPDATE' THEN
    RAISE EXCEPTION 'The applicant notification activation row cannot be removed.'
      USING ERRCODE = '55000';
  END IF;
  IF OLD.activated_at IS NOT NULL THEN
    RAISE EXCEPTION 'The applicant notification activation timestamp is write-once.'
      USING ERRCODE = '55000';
  END IF;
  IF NEW.activated_at IS NULL THEN
    RAISE EXCEPTION 'The activation update must request a timestamp.'
      USING ERRCODE = '55000';
  END IF;
  NEW.activated_at := pg_catalog.clock_timestamp();
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION applicant_notifications_private.guard_activation()
  FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER guard_applicant_notification_activation
  BEFORE UPDATE OR DELETE ON applicant_notifications_private.activation
  FOR EACH ROW EXECUTE FUNCTION applicant_notifications_private.guard_activation();
CREATE TRIGGER guard_applicant_notification_activation_truncate
  BEFORE TRUNCATE ON applicant_notifications_private.activation
  FOR EACH STATEMENT EXECUTE FUNCTION applicant_notifications_private.guard_activation();

CREATE TABLE applicant_notifications_private.receipts (
  employer_user_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE CASCADE,
  application_id uuid NOT NULL REFERENCES public.job_applications (application_id) ON DELETE CASCADE,
  seen_at timestamptz NOT NULL DEFAULT pg_catalog.statement_timestamp(),
  PRIMARY KEY (employer_user_id, application_id)
);
CREATE INDEX ON applicant_notifications_private.receipts (application_id);

ALTER TABLE applicant_notifications_private.activation ENABLE ROW LEVEL SECURITY;
ALTER TABLE applicant_notifications_private.receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE applicant_notifications_private.activation,
  applicant_notifications_private.receipts
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.list_unseen_applicant_counts()
RETURNS TABLE (job_id uuid, unseen_count bigint)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  employer_id uuid := auth.uid();
  cutoff timestamptz;
BEGIN
  IF employer_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.users AS u
    WHERE u.user_id = employer_id AND u.role = 'employer' AND u.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Active Employer access required.' USING ERRCODE = '42501';
  END IF;

  SELECT activation.activated_at INTO cutoff
  FROM applicant_notifications_private.activation
  WHERE activation.singleton;
  IF cutoff IS NULL THEN RETURN; END IF;

  RETURN QUERY
  WITH managed_companies AS MATERIALIZED (
    SELECT DISTINCT m.company_id
    FROM public.company_memberships AS m
    WHERE m.user_id = employer_id
      AND public.can_manage_company_jobs(m.company_id) IS TRUE
  )
  SELECT j.job_id, pg_catalog.count(*)
  FROM managed_companies AS company
  JOIN public.job_postings AS j ON j.company_id = company.company_id
  JOIN public.job_applications AS a ON a.job_id = j.job_id
  JOIN public.users AS applicant ON applicant.user_id = a.applicant_id
  WHERE a.applied_at > cutoff
    AND NOT EXISTS (
      SELECT 1 FROM applicant_notifications_private.receipts AS receipt
      WHERE receipt.employer_user_id = employer_id
        AND receipt.application_id = a.application_id
    )
  GROUP BY j.job_id;
END;
$function$;

CREATE FUNCTION public.acknowledge_applicants_seen(p_job_id uuid, p_application_ids uuid[])
RETURNS integer
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  employer_id uuid := auth.uid();
  authorized boolean;
  all_visible boolean;
  inserted_count integer;
BEGIN
  IF p_job_id IS NULL OR p_application_ids IS NULL
    OR pg_catalog.cardinality(p_application_ids) NOT BETWEEN 1 AND 100
    OR pg_catalog.array_ndims(p_application_ids) <> 1 THEN
    RAISE EXCEPTION 'Provide a job and a batch of 1 to 100 application IDs.' USING ERRCODE = '22023';
  END IF;
  IF pg_catalog.array_position(p_application_ids, NULL::uuid) IS NOT NULL THEN
    RAISE EXCEPTION 'Application IDs cannot be null.' USING ERRCODE = '22023';
  END IF;

  -- Validate and insert against one statement snapshot. Never acknowledge IDs
  -- outside this batch, including submissions that appear after a list read.
  WITH authorized_job AS MATERIALIZED (
    SELECT j.job_id
    FROM public.job_postings AS j
    WHERE j.job_id = p_job_id
      AND employer_id IS NOT NULL
      AND public.can_manage_company_jobs(j.company_id) IS TRUE
  ),
  requested AS MATERIALIZED (
    SELECT DISTINCT input.application_id
    FROM pg_catalog.unnest(p_application_ids) AS input(application_id)
  ),
  visible AS MATERIALIZED (
    SELECT a.application_id, a.applied_at
    FROM requested
    JOIN public.job_applications AS a USING (application_id)
    JOIN authorized_job AS j ON j.job_id = a.job_id
    JOIN public.users AS applicant ON applicant.user_id = a.applicant_id
  ),
  validation AS (
    SELECT EXISTS (SELECT 1 FROM authorized_job) AS job_allowed,
      (SELECT pg_catalog.count(*) FROM requested) =
        (SELECT pg_catalog.count(*) FROM visible) AS batch_allowed
  ),
  inserted AS (
    INSERT INTO applicant_notifications_private.receipts (employer_user_id, application_id)
    SELECT employer_id, visible.application_id
    FROM visible
    CROSS JOIN validation
    CROSS JOIN applicant_notifications_private.activation AS activation
    WHERE validation.job_allowed AND validation.batch_allowed
      AND activation.singleton AND visible.applied_at > activation.activated_at
    ORDER BY visible.application_id
    ON CONFLICT (employer_user_id, application_id) DO NOTHING
    RETURNING 1
  )
  SELECT validation.job_allowed, validation.batch_allowed,
    (SELECT pg_catalog.count(*)::integer FROM inserted)
  INTO authorized, all_visible, inserted_count
  FROM validation;

  IF NOT authorized THEN
    RAISE EXCEPTION 'Employer job access denied.' USING ERRCODE = '42501';
  END IF;
  IF NOT all_visible THEN
    RAISE EXCEPTION 'One or more applications are unavailable for this job.' USING ERRCODE = '22023';
  END IF;
  RETURN inserted_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.list_unseen_applicant_counts(),
  public.acknowledge_applicants_seen(uuid, uuid[])
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_unseen_applicant_counts(),
  public.acknowledge_applicants_seen(uuid, uuid[]) TO authenticated;

-- PostgreSQL 17 supports EXECUTE WITH GRANT OPTION in privilege inquiries.
-- Check effective object privileges, including grants inherited from other roles.
DO $acl$
DECLARE
  client_role text;
BEGIN
  FOREACH client_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF pg_catalog.has_schema_privilege(client_role, 'applicant_notifications_private', 'USAGE, CREATE')
       OR pg_catalog.has_table_privilege(client_role, 'applicant_notifications_private.activation',
          'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       OR pg_catalog.has_table_privilege(client_role, 'applicant_notifications_private.receipts',
          'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       OR pg_catalog.has_function_privilege(client_role, 'applicant_notifications_private.guard_activation()', 'EXECUTE')
       OR pg_catalog.has_function_privilege(client_role, 'public.list_unseen_applicant_counts()', 'EXECUTE')
          IS DISTINCT FROM (client_role = 'authenticated')
       OR pg_catalog.has_function_privilege(client_role, 'public.acknowledge_applicants_seen(uuid,uuid[])', 'EXECUTE')
          IS DISTINCT FROM (client_role = 'authenticated')
       OR pg_catalog.has_function_privilege(client_role, 'public.list_unseen_applicant_counts()', 'EXECUTE WITH GRANT OPTION')
       OR pg_catalog.has_function_privilege(client_role, 'public.acknowledge_applicants_seen(uuid,uuid[])', 'EXECUTE WITH GRANT OPTION')
    THEN
      RAISE EXCEPTION 'Unexpected effective applicant notification privileges for %', client_role;
    END IF;
  END LOOP;
END;
$acl$;

COMMIT;

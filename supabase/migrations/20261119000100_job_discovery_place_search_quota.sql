BEGIN;

-- Requires the existing workplace quota migration. Keep the lock and project
-- counters identical to the Employer RPC. The legacy employer_id column stores
-- the verified account UUID for both entry points.
CREATE FUNCTION public.reserve_job_discovery_place_search(p_job_seeker_id uuid)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_now timestamptz;
BEGIN
  -- Each statement after acquiring the lock must see the preceding commit.
  IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'Place search requires read committed isolation';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.users
     WHERE user_id = p_job_seeker_id AND role = 'job_seeker' AND status = 'active'
  ) THEN
    RETURN 'forbidden';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('jobmate.workplace_place_search.quota.v1', 0)
  );
  v_now := pg_catalog.clock_timestamp();

  DELETE FROM workplace_search_private.reservations
    WHERE reserved_at <= v_now - interval '24 hours';

  IF (SELECT count(*) FROM workplace_search_private.reservations) >= 2000
     OR (SELECT count(*) FROM workplace_search_private.reservations
          WHERE reserved_at > v_now - interval '1 second') >= 2
     OR (SELECT count(*) FROM workplace_search_private.reservations
          WHERE employer_id = p_job_seeker_id) >= 20
     OR EXISTS (SELECT 1 FROM workplace_search_private.reservations
                 WHERE employer_id = p_job_seeker_id
                   AND reserved_at > v_now - interval '3 seconds') THEN
    RETURN 'rate_limited';
  END IF;

  INSERT INTO workplace_search_private.reservations (employer_id, reserved_at)
    VALUES (p_job_seeker_id, v_now);
  RETURN 'reserved';
END;
$function$;

REVOKE ALL ON FUNCTION public.reserve_job_discovery_place_search(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_job_discovery_place_search(uuid)
  TO service_role;

COMMIT;

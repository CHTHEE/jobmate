BEGIN;

CREATE SCHEMA workplace_search_private;
REVOKE ALL ON SCHEMA workplace_search_private
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE workplace_search_private.reservations (
  employer_id uuid NOT NULL,
  reserved_at timestamptz NOT NULL
);
ALTER TABLE workplace_search_private.reservations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE workplace_search_private.reservations
  FROM PUBLIC, anon, authenticated, service_role;
CREATE INDEX ON workplace_search_private.reservations (reserved_at);
CREATE INDEX ON workplace_search_private.reservations (employer_id, reserved_at);

CREATE FUNCTION public.reserve_workplace_place_search(p_employer_id uuid)
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
    RAISE EXCEPTION 'Workplace search requires read committed isolation';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.users
     WHERE user_id = p_employer_id AND role = 'employer' AND status = 'active'
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
          WHERE employer_id = p_employer_id) >= 20
     OR EXISTS (SELECT 1 FROM workplace_search_private.reservations
                 WHERE employer_id = p_employer_id
                   AND reserved_at > v_now - interval '3 seconds') THEN
    RETURN 'rate_limited';
  END IF;

  INSERT INTO workplace_search_private.reservations (employer_id, reserved_at)
    VALUES (p_employer_id, v_now);
  RETURN 'reserved';
END;
$function$;

REVOKE ALL ON FUNCTION public.reserve_workplace_place_search(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_workplace_place_search(uuid)
  TO service_role;

COMMIT;

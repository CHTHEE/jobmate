-- UNEXECUTED / NOT APPROVED. Separate rollback-only validation candidate.
-- Derivation/equality checks: chat_phase2_static_check.ps1 and implementation doc.
-- Never run a selection skipping guards/ROLLBACK. No accounts, fixtures, RPC calls.
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL lock_timeout = '1s';
SET LOCAL statement_timeout = '15s';
SET LOCAL idle_in_transaction_session_timeout = '60s';
SET LOCAL transaction_timeout = '90s';
SET LOCAL check_function_bodies = on;
DO $chat_validation_approval_guard$
BEGIN
  RAISE EXCEPTION 'CHAT ROLLBACK VALIDATION NOT APPROVED: CH/KZ must review DDL hooks, baseline and execution session before authorizing this separate candidate';
END;
$chat_validation_approval_guard$;
DO $chat_validation_safety$
DECLARE v_hook_drift text;
BEGIN
  IF current_user <> 'postgres' OR pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'Validation requires reviewed postgres ownership and READ COMMITTED.';
  END IF;
  IF pg_catalog.to_regnamespace('jobmate_chat_private') IS NOT NULL
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname IN
        ('chat_conversations','chat_messages','chat_read_states','chat_conversations_activity_idx'))
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname IN ('get_or_create_chat_conversation',
        'list_my_chat_conversations','list_chat_messages','send_chat_message','mark_chat_conversation_read')) THEN
    RAISE EXCEPTION 'Unexpected existing Chat object: stop, do not replace or clean it.';
  END IF;
  -- User-supplied reviewed PostgreSQL 17.11 six-hook baseline. Pin the complete
  -- set (including disabled/unexpected entries), not merely applicable hooks.
  -- ACL normalization compares effective explicit grant sets without ACL order
  -- or grantor provenance (grantors were not part of the supplied baseline).
  IF pg_catalog.current_database() <> 'postgres'
    OR pg_catalog.current_setting('server_version_num')::integer <> 170011
    OR pg_catalog.current_setting('session_replication_role') <> 'origin' THEN
    RAISE EXCEPTION 'Reviewed database/version/origin baseline differs; stop before DDL.';
  END IF;
  IF (SELECT pg_catalog.count(*) FROM pg_catalog.pg_event_trigger) <> 6 THEN
    RAISE EXCEPTION 'Reviewed event-trigger set must contain exactly six entries, including disabled entries.';
  END IF;
  WITH expected(hook,event_name,enabled,tags,handler,definition_md5,acl) AS (VALUES
    ('issue_graphql_placeholder','sql_drop','O',ARRAY['DROP EXTENSION'],
      'extensions.set_graphql_placeholder()','8da9dff6b2ae47498209d341acaeb60b',
      '[["PUBLIC","EXECUTE",false],["postgres","EXECUTE",true],["supabase_admin","EXECUTE",false]]'::jsonb),
    ('issue_pg_cron_access','ddl_command_end','O',ARRAY['CREATE EXTENSION'],
      'extensions.grant_pg_cron_access()','53a44336da0ac1dd62d89dbd988e6d1d',
      '[["PUBLIC","EXECUTE",false],["dashboard_user","EXECUTE",false],["supabase_admin","EXECUTE",true]]'::jsonb),
    ('issue_pg_graphql_access','ddl_command_end','O',ARRAY['CREATE EXTENSION'],
      'extensions.grant_pg_graphql_access()','4e6d7efe4aed1b3b92063b648aa7a0cf',
      '[["PUBLIC","EXECUTE",false],["postgres","EXECUTE",true],["supabase_admin","EXECUTE",false]]'::jsonb),
    ('issue_pg_net_access','ddl_command_end','O',ARRAY['CREATE EXTENSION'],
      'extensions.grant_pg_net_access()','1d06ef4fb47bb0ab6e6f8818a62013bb',
      '[["PUBLIC","EXECUTE",false],["dashboard_user","EXECUTE",false],["supabase_admin","EXECUTE",true]]'::jsonb),
    ('pgrst_ddl_watch','ddl_command_end','O',NULL::text[],
      'extensions.pgrst_ddl_watch()','afaad7193dcf8f81e728d2bedb85e43e',
      '[["PUBLIC","EXECUTE",false],["postgres","EXECUTE",true],["supabase_admin","EXECUTE",false]]'::jsonb),
    ('pgrst_drop_watch','sql_drop','O',NULL::text[],
      'extensions.pgrst_drop_watch()','4357772baf5cfcd5c6d7049585b3a537',
      '[["PUBLIC","EXECUTE",false],["postgres","EXECUTE",true],["supabase_admin","EXECUTE",false]]'::jsonb)
  ), actual AS (
    SELECT e.evtname::text AS hook,e.evtevent AS event_name,e.evtenabled::text AS enabled,e.evttags AS tags,
      pg_catalog.pg_get_userbyid(e.evtowner)::text AS trigger_owner,
      pg_catalog.format('%I.%I(%s)',n.nspname,p.proname,
        pg_catalog.pg_get_function_identity_arguments(p.oid)) AS handler,
      pg_catalog.pg_get_userbyid(p.proowner)::text AS handler_owner,
      l.lanname,p.prosecdef,p.proconfig,p.prokind,p.pronargs,p.prorettype,p.proretset,
      pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) AS definition_md5,
      (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_array(g.grantee,g.privilege,g.grantable)
          ORDER BY g.grantee COLLATE "C",g.privilege COLLATE "C")
       FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(a.grantee)::text END AS grantee,
           a.privilege_type AS privilege,pg_catalog.bool_or(a.is_grantable) AS grantable
         FROM pg_catalog.aclexplode(
           CASE WHEN pg_catalog.cardinality(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) > 0
             THEN COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner)) ELSE NULL::aclitem[] END
         ) a
         GROUP BY a.grantee,a.privilege_type) g) AS acl
    FROM pg_catalog.pg_event_trigger e JOIN pg_catalog.pg_proc p ON p.oid = e.evtfoid
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_catalog.pg_language l ON l.oid = p.prolang
  )
  SELECT pg_catalog.string_agg(COALESCE(x.hook,a.hook),', ' ORDER BY COALESCE(x.hook,a.hook))
    INTO v_hook_drift FROM expected x FULL JOIN actual a ON a.hook = x.hook
  WHERE x.hook IS NULL OR a.hook IS NULL OR a.event_name IS DISTINCT FROM x.event_name
    OR a.enabled IS DISTINCT FROM x.enabled OR a.tags IS DISTINCT FROM x.tags
    OR a.trigger_owner IS DISTINCT FROM 'supabase_admin' OR a.handler_owner IS DISTINCT FROM 'supabase_admin'
    OR a.handler IS DISTINCT FROM x.handler OR a.lanname IS DISTINCT FROM 'plpgsql'
    OR a.prosecdef IS DISTINCT FROM false OR a.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
    OR a.prokind IS DISTINCT FROM 'f'::"char" OR a.pronargs IS DISTINCT FROM 0::smallint
    OR a.prorettype IS DISTINCT FROM 'pg_catalog.event_trigger'::regtype OR a.proretset IS DISTINCT FROM false
    OR a.definition_md5 IS DISTINCT FROM x.definition_md5 OR a.acl IS DISTINCT FROM x.acl;
  IF v_hook_drift IS NOT NULL THEN
    RAISE EXCEPTION 'Reviewed six-trigger baseline differs: %. Stop; never disable/alter hooks to pass.',v_hook_drift;
  END IF;
END;
$chat_validation_safety$;
-- BEGIN EXACT MIGRATION BODY
DO $chat_preflight$
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Chat candidate requires reviewed postgres ownership.';
  END IF;
  IF pg_catalog.to_regnamespace('jobmate_chat_private') IS NOT NULL
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname IN (
        'get_or_create_chat_conversation','list_my_chat_conversations',
        'list_chat_messages','send_chat_message','mark_chat_conversation_read')) THEN
    RAISE EXCEPTION 'Chat namespace/routine collision: inspect, never replace.';
  END IF;
  IF pg_catalog.to_regprocedure('public.can_manage_company_jobs(uuid)') IS NULL
    OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_publication
      WHERE pubname = 'supabase_realtime' AND NOT puballtables AND pubinsert AND pubupdate) THEN
    RAISE EXCEPTION 'Chat authorization/publication baseline differs.';
  END IF;
END;
$chat_preflight$;

-- CREATE (not OR REPLACE / IF NOT EXISTS) deliberately rejects collisions.
-- No pre-existing function, policy, table or grant is replaced.
CREATE SCHEMA jobmate_chat_private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA jobmate_chat_private FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA jobmate_chat_private TO authenticated;

CREATE FUNCTION jobmate_chat_private.valid_body(p_body text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = ''
AS $body$
  SELECT p_body IS NOT NULL AND pg_catalog.char_length(p_body) BETWEEN 1 AND 4000
    AND pg_catalog.char_length(pg_catalog.btrim(p_body,
      U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000')) > 0;
$body$;

CREATE TABLE public.chat_conversations (
  conversation_id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  application_id uuid NOT NULL UNIQUE
    REFERENCES public.job_applications(application_id) ON DELETE NO ACTION,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  last_sequence bigint NOT NULL DEFAULT 0 CHECK (last_sequence >= 0),
  last_message_at timestamptz,
  CHECK ((last_sequence = 0 AND last_message_at IS NULL)
      OR (last_sequence > 0 AND last_message_at IS NOT NULL))
);
CREATE TABLE public.chat_messages (
  message_id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  conversation_id uuid NOT NULL
    REFERENCES public.chat_conversations(conversation_id) ON DELETE NO ACTION,
  sender_id uuid NOT NULL REFERENCES public.users(user_id) ON DELETE NO ACTION,
  body text NOT NULL CHECK (jobmate_chat_private.valid_body(body)),
  client_request_id uuid NOT NULL,
  sequence bigint NOT NULL CHECK (sequence > 0),
  sent_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (conversation_id, sequence),
  UNIQUE (conversation_id, sender_id, client_request_id)
);
CREATE TABLE public.chat_read_states (
  conversation_id uuid NOT NULL
    REFERENCES public.chat_conversations(conversation_id) ON DELETE NO ACTION,
  user_id uuid NOT NULL REFERENCES public.users(user_id) ON DELETE NO ACTION,
  last_read_sequence bigint NOT NULL CHECK (last_read_sequence > 0),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  PRIMARY KEY (conversation_id, user_id),
  FOREIGN KEY (conversation_id, last_read_sequence)
    REFERENCES public.chat_messages(conversation_id, sequence) ON DELETE NO ACTION
);
CREATE INDEX chat_conversations_activity_idx ON public.chat_conversations
  ((COALESCE(last_message_at, created_at)) DESC, conversation_id DESC);
-- Message uniqueness indexes also cover history, unread range scans and retries.

ALTER TABLE public.chat_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_read_states ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.chat_conversations, public.chat_messages, public.chat_read_states
  FROM PUBLIC, anon, authenticated, service_role;

-- Returns no row for unauthorized actors. Invoked only by trusted chat functions.
-- No cached employer participant; the existing helper reads current membership.
CREATE FUNCTION jobmate_chat_private.application_access(p_application_id uuid)
RETURNS TABLE (
  application_id uuid, job_id uuid, company_id uuid, applicant_id uuid,
  application_status text, can_send boolean, read_only_reason text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $access$
  SELECT a.application_id, j.job_id, j.company_id, a.applicant_id, a.status,
    reason.code IS NULL, reason.code
  FROM public.job_applications a
  JOIN public.job_postings j ON j.job_id = a.job_id
  JOIN public.companies co ON co.company_id = j.company_id
  JOIN public.users actor ON actor.user_id = auth.uid()
  LEFT JOIN public.company_restrictions cr ON cr.company_id = j.company_id
  CROSS JOIN LATERAL (
    SELECT CASE
      WHEN cr.company_id IS NULL THEN 'company_restriction_missing'
      WHEN cr.restriction_status NOT IN ('active', 'restricted')
        OR cr.restriction_status IS NULL THEN 'company_restriction_invalid'
      WHEN co.verification_status IS DISTINCT FROM 'verified'::public.verification_status
        THEN 'company_unverified'
      WHEN a.status IN ('rejected','declined','withdrawn') THEN 'application_terminal'
      WHEN a.status NOT IN ('submitted','shortlisted','interview','offered','hired')
        OR a.status IS NULL THEN 'application_status_unknown'
      WHEN a.status <> 'hired' AND (cr.restriction_status = 'restricted'
        OR EXISTS (SELECT 1 FROM public.job_moderation_state ms
          WHERE ms.job_id = j.job_id AND ms.moderation_status = 'restricted'))
        THEN 'recruitment_restricted'
      ELSE NULL::text END AS code
  ) reason
  WHERE a.application_id = p_application_id
    AND actor.status = 'active'::public.account_status
    AND ((actor.role = 'job_seeker'::public.user_role AND actor.user_id = a.applicant_id)
      OR (actor.role = 'employer'::public.user_role
        AND public.can_manage_company_jobs(j.company_id)));
$access$;

-- Boolean RLS entry point. Does not reveal any unauthorized relation identity.
-- Definer bypass prevents RLS recursion through chat_conversations.
CREATE FUNCTION jobmate_chat_private.can_read_conversation(p_conversation_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $read$
  SELECT EXISTS (
    SELECT 1 FROM public.chat_conversations c
    CROSS JOIN LATERAL jobmate_chat_private.application_access(c.application_id) ac
    WHERE c.conversation_id = p_conversation_id
  );
$read$;

CREATE POLICY chat_conversations_select ON public.chat_conversations
  FOR SELECT TO authenticated
  USING (jobmate_chat_private.can_read_conversation(conversation_id));
CREATE POLICY chat_messages_select ON public.chat_messages
  FOR SELECT TO authenticated
  USING (jobmate_chat_private.can_read_conversation(conversation_id));
-- Read cursors are RPC-only: no direct SELECT policy/grant and no publication.
-- Full message SELECT is retained for Realtime compatibility; request UUIDs are
-- non-secret dedup selectors, not participant/sender authorization credentials.
GRANT SELECT ON public.chat_conversations, public.chat_messages
  TO authenticated;

-- Shared actor/relationship locks protect read authorization without locking
-- recipients, restriction/moderation state, or the conversation activity row.
CREATE FUNCTION jobmate_chat_private.lock_participant(p_application_id uuid)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $participant_lock$
DECLARE
  v_job_id uuid; v_company_id uuid; v_worker_id uuid; v_actor_role public.user_role;
BEGIN
  IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'Locked chat operations require READ COMMITTED isolation.' USING ERRCODE = '25001';
  END IF;
  SELECT ac.job_id, ac.company_id, ac.applicant_id
    INTO v_job_id, v_company_id, v_worker_id
  FROM jobmate_chat_private.application_access(p_application_id) ac;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Chat unavailable.' USING ERRCODE = '42501';
  END IF;
  SELECT u.role INTO v_actor_role FROM public.users u
    WHERE u.user_id = auth.uid() FOR SHARE NOWAIT;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Chat unavailable.' USING ERRCODE = '42501';
  END IF;
  IF v_actor_role = 'employer'::public.user_role THEN
    PERFORM cm.user_id FROM public.company_memberships cm
      WHERE cm.user_id = auth.uid() AND cm.company_id = v_company_id FOR SHARE NOWAIT;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Chat unavailable.' USING ERRCODE = '42501';
    END IF;
    PERFORM c.company_id FROM public.companies c
      WHERE c.company_id = v_company_id FOR SHARE NOWAIT;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Chat unavailable.' USING ERRCODE = '42501';
    END IF;
  END IF;
  PERFORM j.job_id FROM public.job_postings j
    WHERE j.job_id = v_job_id FOR SHARE NOWAIT;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Chat relationship changed. Retry.' USING ERRCODE = '40001';
  END IF;
  PERFORM a.application_id FROM public.job_applications a
    WHERE a.application_id = p_application_id FOR SHARE NOWAIT;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Chat relationship changed. Retry.' USING ERRCODE = '40001';
  END IF;
  -- Fresh statement/snapshot after locks; never rely on preliminary access result.
  IF NOT EXISTS (SELECT 1 FROM jobmate_chat_private.application_access(p_application_id)) THEN
    RAISE EXCEPTION 'Chat unavailable.' USING ERRCODE = '42501';
  END IF;
  -- Identity columns are expected immutable in the deployed module. Reject drift
  -- rather than authorize/lock a newly related company through stale identifiers.
  IF NOT EXISTS (SELECT 1 FROM public.job_applications a
      JOIN public.job_postings j ON j.job_id = a.job_id
      WHERE a.application_id = p_application_id AND a.job_id = v_job_id
        AND a.applicant_id = v_worker_id AND j.company_id = v_company_id) THEN
    RAISE EXCEPTION 'Chat relationship changed. Retry.' USING ERRCODE = '40001';
  END IF;
END;
$participant_lock$;

-- Fresh creation/sending reuses lock_participant's existing job SHARE lock.
-- CH verified update_job_moderation locks that job FOR UPDATE before either
-- moderation UPDATE or initial INSERT. No moderation-row/table lock is needed.
-- Privileged external/dynamic writers are outside this supported protocol and
-- must coordinate on the same job before being treated as safe concurrent writers.
CREATE FUNCTION jobmate_chat_private.lock_application(
  p_application_id uuid, p_creation boolean DEFAULT false
)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $lock$
DECLARE v_company_id uuid;
BEGIN
  -- Shared participant locking enforces READ COMMITTED for creation, sending,
  -- identical replay and mark-read; do not repeat the isolation check here.
  IF p_creation THEN
    PERFORM jobmate_chat_private.lock_participant(p_application_id);
    -- Serializes first initiation only. NOWAIT makes shared-lock upgrades retryable.
    PERFORM a.application_id FROM public.job_applications a
      WHERE a.application_id = p_application_id FOR NO KEY UPDATE NOWAIT;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Chat relationship changed. Retry.' USING ERRCODE = '40001';
    END IF;
  END IF;
  -- For a send (p_creation=false), the private caller already holds participant
  -- and job locks from its replay/authorization stage. Do not acquire them twice.
  SELECT ac.company_id INTO v_company_id
    FROM jobmate_chat_private.application_access(p_application_id) ac;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Chat unavailable.' USING ERRCODE = '42501';
  END IF;
  -- Worker writes also require stable verified company/restriction eligibility.
  PERFORM c.company_id FROM public.companies c
    WHERE c.company_id = v_company_id FOR SHARE NOWAIT;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Chat relationship changed. Retry.' USING ERRCODE = '40001';
  END IF;
  PERFORM cr.company_id FROM public.company_restrictions cr
    WHERE cr.company_id = v_company_id FOR SHARE NOWAIT;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Chat is read-only: company_restriction_missing.' USING ERRCODE = '55000';
  END IF;
  -- Callers make their final eligibility decision in a separate SQL statement
  -- after this returns, with a fresh READ COMMITTED snapshot and locks still held.
END;
$lock$;

CREATE FUNCTION public.get_or_create_chat_conversation(p_application_id uuid)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $create$
DECLARE v_id uuid; v_reason text;
BEGIN
  -- A single read-only statement supplies current snapshot authorization. It
  -- takes no mutation/recipient locks and works in all history-readable states.
  SELECT c.conversation_id INTO v_id FROM public.chat_conversations c
    CROSS JOIN LATERAL jobmate_chat_private.application_access(c.application_id) ac
    WHERE c.application_id = p_application_id;
  IF FOUND THEN RETURN v_id; END IF;
  PERFORM jobmate_chat_private.lock_application(p_application_id, true);
  SELECT c.conversation_id INTO v_id FROM public.chat_conversations c
    WHERE c.application_id = p_application_id;
  IF FOUND THEN RETURN v_id; END IF;
  SELECT ac.read_only_reason INTO v_reason
    FROM jobmate_chat_private.application_access(p_application_id) ac;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Chat unavailable.' USING ERRCODE = '42501';
  END IF;
  IF v_reason IS NOT NULL THEN
    RAISE EXCEPTION 'Chat is read-only: %.', v_reason USING ERRCODE = '55000';
  END IF;
  -- Application lock serializes both parties; UNIQUE remains the final invariant.
  INSERT INTO public.chat_conversations(application_id) VALUES (p_application_id)
    RETURNING conversation_id INTO v_id;
  RETURN v_id;
END;
$create$;

CREATE FUNCTION public.list_my_chat_conversations(
  p_limit integer DEFAULT 50,
  p_before_activity_at timestamptz DEFAULT NULL,
  p_before_conversation_id uuid DEFAULT NULL,
  p_conversation_id uuid DEFAULT NULL
)
RETURNS TABLE (
  conversation_id uuid, application_id uuid, job_id uuid, job_title text,
  company_name text, worker_name text, application_status text,
  created_at timestamptz, activity_at timestamptz,
  last_message_preview text, last_message_at timestamptz, last_sequence bigint,
  unread_count bigint, can_send boolean, read_only_reason text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $list$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.users u WHERE u.user_id = auth.uid()
    AND u.status = 'active'::public.account_status
    AND u.role IN ('job_seeker'::public.user_role,'employer'::public.user_role)) THEN
    RAISE EXCEPTION 'Chat unavailable.' USING ERRCODE = '42501';
  END IF;
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
    OR ((p_before_activity_at IS NULL) <> (p_before_conversation_id IS NULL)) THEN
    RAISE EXCEPTION 'Invalid chat page.' USING ERRCODE = '22023';
  END IF;
  RETURN QUERY
  SELECT c.conversation_id, c.application_id, ac.job_id, j.title::text,
    co.company_name::text, worker.name::text, ac.application_status,
    c.created_at, COALESCE(c.last_message_at,c.created_at),
    pg_catalog.left(last_msg.body,160), c.last_message_at, c.last_sequence,
    (SELECT pg_catalog.count(*) FROM public.chat_messages unread
      WHERE unread.conversation_id = c.conversation_id
        AND unread.sender_id <> auth.uid()
        AND unread.sequence > COALESCE(rs.last_read_sequence,0)),
    ac.can_send, ac.read_only_reason
  FROM public.chat_conversations c
  CROSS JOIN LATERAL jobmate_chat_private.application_access(c.application_id) ac
  JOIN public.job_postings j ON j.job_id = ac.job_id
  JOIN public.companies co ON co.company_id = ac.company_id
  JOIN public.users worker ON worker.user_id = ac.applicant_id
  LEFT JOIN public.chat_read_states rs
    ON rs.conversation_id = c.conversation_id AND rs.user_id = auth.uid()
  LEFT JOIN public.chat_messages last_msg
    ON last_msg.conversation_id = c.conversation_id AND last_msg.sequence = c.last_sequence
  WHERE (p_conversation_id IS NULL OR c.conversation_id = p_conversation_id)
    AND (p_before_activity_at IS NULL
      OR (COALESCE(c.last_message_at,c.created_at), c.conversation_id)
        < (p_before_activity_at,p_before_conversation_id))
  ORDER BY COALESCE(c.last_message_at,c.created_at) DESC, c.conversation_id DESC
  LIMIT p_limit;
END;
$list$;

CREATE FUNCTION public.list_chat_messages(
  p_conversation_id uuid, p_limit integer DEFAULT 50, p_before_sequence bigint DEFAULT NULL
)
RETURNS TABLE (
  message_id uuid, conversation_id uuid, sender_id uuid, sender_name text,
  body text, sent_at timestamptz, sequence bigint
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $history$
BEGIN
  IF NOT jobmate_chat_private.can_read_conversation(p_conversation_id) THEN
    RAISE EXCEPTION 'Chat unavailable.' USING ERRCODE = '42501';
  END IF;
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
    OR (p_before_sequence IS NOT NULL AND p_before_sequence < 1) THEN
    RAISE EXCEPTION 'Invalid chat page.' USING ERRCODE = '22023';
  END IF;
  RETURN QUERY
  SELECT m.message_id, m.conversation_id, m.sender_id, sender.name::text,
    m.body, m.sent_at, m.sequence
  FROM public.chat_messages m JOIN public.users sender ON sender.user_id = m.sender_id
  WHERE m.conversation_id = p_conversation_id
    AND (p_before_sequence IS NULL OR m.sequence < p_before_sequence)
  ORDER BY m.sequence DESC LIMIT p_limit;
END;
$history$;

CREATE FUNCTION public.send_chat_message(
  p_conversation_id uuid, p_client_request_id uuid, p_body text
)
RETURNS TABLE (message_id uuid, conversation_id uuid, sender_id uuid,
  body text, sent_at timestamptz, sequence bigint)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $send$
DECLARE
  v_application_id uuid; v_context record; v_message public.chat_messages%ROWTYPE;
  v_sequence bigint; v_sent_at timestamptz; v_recipient_ids uuid[];
BEGIN
  IF NOT jobmate_chat_private.can_read_conversation(p_conversation_id) THEN
    RAISE EXCEPTION 'Chat unavailable.' USING ERRCODE = '42501';
  END IF;
  IF p_client_request_id IS NULL OR NOT jobmate_chat_private.valid_body(p_body) THEN
    RAISE EXCEPTION 'A request UUID and nonblank message of 1 to 4000 characters are required.'
      USING ERRCODE = '22023';
  END IF;
  SELECT c.application_id INTO v_application_id FROM public.chat_conversations c
    WHERE c.conversation_id = p_conversation_id;
  PERFORM jobmate_chat_private.lock_participant(v_application_id);
  PERFORM c.conversation_id FROM public.chat_conversations c
    WHERE c.conversation_id = p_conversation_id FOR NO KEY UPDATE NOWAIT;
  -- Current read authorization required even for a replay. Eligibility to write
  -- may have ended since the original commit; identical replay is reconciliation.
  SELECT m.* INTO v_message FROM public.chat_messages m
    WHERE m.conversation_id = p_conversation_id AND m.sender_id = auth.uid()
      AND m.client_request_id = p_client_request_id;
  IF FOUND THEN
    IF v_message.body IS DISTINCT FROM p_body THEN
      RAISE EXCEPTION 'Chat request UUID was used for different content.' USING ERRCODE = '22023';
    END IF;
  ELSE
    PERFORM jobmate_chat_private.lock_application(v_application_id);
    SELECT ac.* INTO v_context FROM jobmate_chat_private.application_access(v_application_id) ac;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Chat unavailable.' USING ERRCODE = '42501';
    END IF;
    IF v_context.can_send IS DISTINCT FROM TRUE THEN
      RAISE EXCEPTION 'Chat is read-only: %.', v_context.read_only_reason USING ERRCODE = '55000';
    END IF;
    -- One recipient-selection statement fixes the candidate set at its snapshot.
    -- Lock only selected account/member rows and retain the resulting IDs. Later
    -- membership additions are not reselected by the notification INSERT.
    IF auth.uid() = v_context.applicant_id THEN
      SELECT COALESCE(pg_catalog.array_agg(locked.user_id), ARRAY[]::uuid[])
        INTO v_recipient_ids
      FROM (
        SELECT recipient.user_id FROM public.users recipient
        JOIN public.company_memberships cm ON cm.user_id = recipient.user_id
        WHERE cm.company_id = v_context.company_id AND cm.member_role IN ('owner','employer')
          AND recipient.role = 'employer'::public.user_role
          AND recipient.status = 'active'::public.account_status
          AND recipient.user_id <> auth.uid()
        ORDER BY recipient.user_id FOR SHARE OF recipient, cm NOWAIT
      ) locked;
    ELSE
      SELECT COALESCE(pg_catalog.array_agg(locked.user_id), ARRAY[]::uuid[])
        INTO v_recipient_ids
      FROM (
        SELECT recipient.user_id FROM public.users recipient
        WHERE recipient.user_id = v_context.applicant_id
          AND recipient.role = 'job_seeker'::public.user_role
          AND recipient.status = 'active'::public.account_status
          AND recipient.user_id <> auth.uid()
        FOR SHARE NOWAIT
      ) locked;
    END IF;
    -- clock_timestamp is server-owned; keep activity order monotonic if clock moves.
    SELECT c.last_sequence + 1,
      GREATEST(pg_catalog.clock_timestamp(), COALESCE(c.last_message_at,c.created_at))
      INTO v_sequence, v_sent_at FROM public.chat_conversations c
      WHERE c.conversation_id = p_conversation_id;
    INSERT INTO public.chat_messages AS inserted
      (conversation_id,sender_id,body,client_request_id,sequence,sent_at)
      VALUES (p_conversation_id,auth.uid(),p_body,p_client_request_id,v_sequence,v_sent_at)
      RETURNING inserted.* INTO v_message;
    UPDATE public.chat_conversations c SET last_sequence = v_sequence, last_message_at = v_sent_at
      WHERE c.conversation_id = p_conversation_id;

    -- Same transaction, only on the first insert. No private content/deep link.
    -- The locked snapshot fixes recipients; a committed retry never re-emits.
    INSERT INTO public.notifications(user_id,notification_type,title,message,created_at)
    SELECT recipient.user_id, 'chat_message', 'New message',
      CASE WHEN recipient.user_id = v_context.applicant_id
        THEN 'You have a new message about your job application.'
        ELSE 'You have a new message from a job applicant.' END,
      pg_catalog.clock_timestamp()
    FROM pg_catalog.unnest(v_recipient_ids) AS recipient(user_id);
  END IF;
  RETURN QUERY SELECT v_message.message_id, v_message.conversation_id, v_message.sender_id,
    v_message.body, v_message.sent_at, v_message.sequence;
END;
$send$;

CREATE FUNCTION public.mark_chat_conversation_read(p_conversation_id uuid, p_message_id uuid)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $mark$
DECLARE v_application_id uuid; v_sequence bigint; v_cursor bigint;
BEGIN
  IF NOT jobmate_chat_private.can_read_conversation(p_conversation_id) THEN
    RAISE EXCEPTION 'Chat unavailable.' USING ERRCODE = '42501';
  END IF;
  SELECT c.application_id INTO v_application_id FROM public.chat_conversations c
    WHERE c.conversation_id = p_conversation_id;
  PERFORM jobmate_chat_private.lock_participant(v_application_id);
  -- No conversation activity lock: only this user's upsert serializes cursors.
  -- Its FK KEY SHARE checks coexist with send's NO KEY UPDATE activity lock.
  SELECT m.sequence INTO v_sequence FROM public.chat_messages m
    WHERE m.conversation_id = p_conversation_id AND m.message_id = p_message_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid chat read cursor.' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.chat_read_states AS rs (conversation_id,user_id,last_read_sequence)
    VALUES (p_conversation_id,auth.uid(),v_sequence)
    ON CONFLICT (conversation_id,user_id) DO UPDATE
      SET last_read_sequence = GREATEST(rs.last_read_sequence,EXCLUDED.last_read_sequence),
          updated_at = pg_catalog.clock_timestamp()
    RETURNING rs.last_read_sequence INTO v_cursor;
  RETURN v_cursor;
END;
$mark$;

-- Remove default/inherited installation grants on every new routine explicitly.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA jobmate_chat_private
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION jobmate_chat_private.can_read_conversation(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.get_or_create_chat_conversation(uuid),
  public.list_my_chat_conversations(integer,timestamptz,uuid,uuid),
  public.list_chat_messages(uuid,integer,bigint),
  public.send_chat_message(uuid,uuid,text), public.mark_chat_conversation_read(uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_or_create_chat_conversation(uuid),
  public.list_my_chat_conversations(integer,timestamptz,uuid,uuid),
  public.list_chat_messages(uuid,integer,bigint),
  public.send_chat_message(uuid,uuid,text), public.mark_chat_conversation_read(uuid,uuid)
  TO authenticated;

-- Existing publication only; no settings changes, no read-state/notification feed.
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_conversations, public.chat_messages;
-- END EXACT MIGRATION BODY
-- Catalogue-only assertions: the same summary CTE as the main diagnostics.
DO $chat_validation_assertions$
DECLARE v_failures text;
BEGIN
  SELECT pg_catalog.string_agg(report.check_name, ', ' ORDER BY report.check_name)
    INTO v_failures FROM (
-- BEGIN EXACT CATALOG SUMMARY
WITH
tables(name) AS (VALUES ('chat_conversations'),('chat_messages'),('chat_read_states')),
rels AS (SELECT t.name,c.oid,c.relkind,c.relrowsecurity,c.relowner
  FROM tables t LEFT JOIN pg_catalog.pg_class c
    ON c.oid = pg_catalog.to_regclass('public.' || t.name)),
columns_expected(tbl,col,typ,nullable) AS (VALUES
 ('chat_conversations','conversation_id','uuid',false),
 ('chat_conversations','application_id','uuid',false),
 ('chat_conversations','created_at','timestamp with time zone',false),
 ('chat_conversations','last_sequence','bigint',false),
 ('chat_conversations','last_message_at','timestamp with time zone',true),
 ('chat_messages','message_id','uuid',false),('chat_messages','conversation_id','uuid',false),
 ('chat_messages','sender_id','uuid',false),('chat_messages','body','text',false),
 ('chat_messages','client_request_id','uuid',false),('chat_messages','sequence','bigint',false),
 ('chat_messages','sent_at','timestamp with time zone',false),
 ('chat_read_states','conversation_id','uuid',false),('chat_read_states','user_id','uuid',false),
 ('chat_read_states','last_read_sequence','bigint',false),
 ('chat_read_states','updated_at','timestamp with time zone',false)),
keys_expected(tbl,kind,cols) AS (VALUES
 ('chat_conversations','p',ARRAY['conversation_id']),
 ('chat_conversations','u',ARRAY['application_id']),
 ('chat_messages','p',ARRAY['message_id']),
 ('chat_messages','u',ARRAY['conversation_id','sequence']),
 ('chat_messages','u',ARRAY['conversation_id','sender_id','client_request_id']),
 ('chat_read_states','p',ARRAY['conversation_id','user_id'])),
fks_expected(tbl,cols,target,target_cols) AS (VALUES
 ('chat_conversations',ARRAY['application_id'],'job_applications',ARRAY['application_id']),
 ('chat_messages',ARRAY['conversation_id'],'chat_conversations',ARRAY['conversation_id']),
 ('chat_messages',ARRAY['sender_id'],'users',ARRAY['user_id']),
 ('chat_read_states',ARRAY['conversation_id'],'chat_conversations',ARRAY['conversation_id']),
 ('chat_read_states',ARRAY['user_id'],'users',ARRAY['user_id']),
 ('chat_read_states',ARRAY['conversation_id','last_read_sequence'],'chat_messages',ARRAY['conversation_id','sequence'])),
constraints_actual AS (
 SELECT k.*,r.name AS tbl,
   ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(k.conkey) WITH ORDINALITY x(num,ord)
     JOIN pg_catalog.pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = x.num
     ORDER BY x.ord) AS cols,
   ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(k.confkey) WITH ORDINALITY x(num,ord)
     JOIN pg_catalog.pg_attribute a ON a.attrelid = k.confrelid AND a.attnum = x.num
     ORDER BY x.ord) AS target_cols
 FROM pg_catalog.pg_constraint k JOIN rels r ON r.oid = k.conrelid),
routines(signature,is_definer,volatility,result_type,client_execute) AS (VALUES
 ('public.get_or_create_chat_conversation(uuid)',true,'v','uuid',true),
 ('public.list_my_chat_conversations(integer,timestamp with time zone,uuid,uuid)',true,'s','record',true),
 ('public.list_chat_messages(uuid,integer,bigint)',true,'s','record',true),
 ('public.send_chat_message(uuid,uuid,text)',true,'v','record',true),
 ('public.mark_chat_conversation_read(uuid,uuid)',true,'v','bigint',true),
 ('jobmate_chat_private.valid_body(text)',false,'i','boolean',false),
 ('jobmate_chat_private.application_access(uuid)',true,'s','record',false),
 ('jobmate_chat_private.can_read_conversation(uuid)',true,'s','boolean',true),
 ('jobmate_chat_private.lock_participant(uuid)',true,'v','void',false),
 ('jobmate_chat_private.lock_application(uuid,boolean)',true,'v','void',false)),
funcs AS (SELECT e.*,p.oid,p.prosecdef,p.provolatile,p.proconfig,p.proowner,p.prorettype
  FROM routines e LEFT JOIN pg_catalog.pg_proc p
    ON p.oid = pg_catalog.to_regprocedure(e.signature)),
phase AS (SELECT NOT EXISTS (SELECT 1 FROM rels WHERE oid IS NOT NULL)
  AND pg_catalog.to_regnamespace('jobmate_chat_private') IS NULL
  AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN ('get_or_create_chat_conversation',
      'list_my_chat_conversations','list_chat_messages','send_chat_message','mark_chat_conversation_read')) AS absent),
checks(check_name,ok) AS (
 SELECT 'tables_columns',
   (SELECT pg_catalog.count(*) = 3 FROM rels WHERE oid IS NOT NULL AND relkind = 'r')
   AND NOT EXISTS (SELECT 1 FROM columns_expected e JOIN rels r ON r.name = e.tbl
     LEFT JOIN pg_catalog.pg_attribute a ON a.attrelid = r.oid AND a.attname = e.col AND NOT a.attisdropped
     WHERE a.attnum IS NULL OR pg_catalog.format_type(a.atttypid,a.atttypmod) <> e.typ
       OR a.attnotnull = e.nullable)
   AND (SELECT pg_catalog.count(*) = 16 FROM pg_catalog.pg_attribute a JOIN rels r ON r.oid = a.attrelid
     WHERE a.attnum > 0 AND NOT a.attisdropped)
 UNION ALL SELECT 'rls_owners', NOT EXISTS (SELECT 1 FROM rels
   WHERE oid IS NULL OR NOT relrowsecurity OR pg_catalog.pg_get_userbyid(relowner) <> 'postgres')
 UNION ALL SELECT 'keys_foreign_keys',
   (SELECT pg_catalog.count(*) = 6 FROM constraints_actual WHERE contype IN ('p','u'))
   AND (SELECT pg_catalog.count(*) = 6 FROM constraints_actual WHERE contype = 'f')
   AND
   NOT EXISTS (SELECT 1 FROM keys_expected e WHERE NOT EXISTS (
     SELECT 1 FROM constraints_actual k WHERE k.tbl = e.tbl AND k.contype::text = e.kind
       AND k.cols = e.cols AND k.convalidated AND NOT k.condeferrable))
   AND NOT EXISTS (SELECT 1 FROM fks_expected e WHERE NOT EXISTS (
     SELECT 1 FROM constraints_actual k WHERE k.tbl = e.tbl AND k.contype = 'f'
       AND k.cols = e.cols AND k.confrelid = pg_catalog.to_regclass('public.' || e.target)
       AND k.target_cols = e.target_cols AND k.confdeltype = 'a' AND k.confupdtype = 'a'
       AND k.convalidated AND NOT k.condeferrable))
 UNION ALL SELECT 'required_indexes',
   NOT EXISTS (SELECT 1 FROM constraints_actual k LEFT JOIN pg_catalog.pg_index i ON i.indexrelid = k.conindid
     WHERE k.contype IN ('p','u') AND (i.indexrelid IS NULL OR NOT i.indisvalid OR NOT i.indisready))
   AND EXISTS (SELECT 1 FROM pg_catalog.pg_index i
     WHERE i.indexrelid = pg_catalog.to_regclass('public.chat_conversations_activity_idx')
       AND i.indrelid = pg_catalog.to_regclass('public.chat_conversations')
       AND i.indisvalid AND i.indisready AND i.indnkeyatts = 2
       AND pg_catalog.regexp_replace(pg_catalog.pg_get_indexdef(i.indexrelid),'[[:space:]]','','g')
         LIKE '%COALESCE(last_message_at,created_at)%DESC,conversation_idDESC%')
 UNION ALL SELECT 'rpc_signatures',
   NOT EXISTS (SELECT 1 FROM funcs WHERE oid IS NULL)
   AND (SELECT pg_catalog.count(*) = 5 FROM pg_catalog.pg_proc p
     JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname IN ('get_or_create_chat_conversation',
       'list_my_chat_conversations','list_chat_messages','send_chat_message','mark_chat_conversation_read'))
   AND (SELECT pg_catalog.count(*) = 5 FROM pg_catalog.pg_proc p
     JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'jobmate_chat_private')
 UNION ALL SELECT 'routine_security', NOT EXISTS (SELECT 1 FROM funcs
   WHERE oid IS NULL OR prosecdef IS DISTINCT FROM is_definer OR provolatile::text <> volatility
     OR proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
     OR pg_catalog.pg_get_userbyid(proowner) <> 'postgres'
     OR prorettype <> pg_catalog.to_regtype(result_type))
 UNION ALL SELECT 'effective_table_privileges', NOT EXISTS (
   SELECT 1 FROM rels r CROSS JOIN (VALUES ('anon'),('authenticated'),('service_role')) role(name)
   CROSS JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER'),('MAINTAIN')) priv(name)
   WHERE r.oid IS NULL OR pg_catalog.has_table_privilege(role.name::name,r.oid,priv.name)
     IS DISTINCT FROM (role.name = 'authenticated' AND priv.name = 'SELECT' AND r.name <> 'chat_read_states'))
   AND NOT EXISTS (SELECT 1 FROM rels r
     CROSS JOIN (VALUES ('anon'),('authenticated'),('service_role')) role(name)
     CROSS JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('REFERENCES')) priv(name)
     WHERE r.oid IS NULL OR pg_catalog.has_any_column_privilege(role.name::name,r.oid,priv.name)
       IS DISTINCT FROM (role.name = 'authenticated' AND priv.name = 'SELECT' AND r.name <> 'chat_read_states'))
 UNION ALL SELECT 'effective_execute_privileges', NOT EXISTS (
   SELECT 1 FROM funcs f CROSS JOIN (VALUES ('anon'),('authenticated'),('service_role')) role(name)
   WHERE f.oid IS NULL OR pg_catalog.has_function_privilege(role.name::name,f.oid,'EXECUTE')
     IS DISTINCT FROM (role.name = 'authenticated' AND f.client_execute))
   AND EXISTS (SELECT 1 FROM pg_catalog.pg_namespace n WHERE n.nspname = 'jobmate_chat_private'
     AND pg_catalog.pg_get_userbyid(n.nspowner) = 'postgres'
     AND pg_catalog.has_schema_privilege('authenticated',n.oid,'USAGE')
     AND NOT pg_catalog.has_schema_privilege('anon',n.oid,'USAGE')
     AND NOT pg_catalog.has_schema_privilege('service_role',n.oid,'USAGE')
     AND NOT pg_catalog.has_schema_privilege('authenticated',n.oid,'CREATE')
     AND NOT pg_catalog.has_schema_privilege('anon',n.oid,'CREATE')
     AND NOT pg_catalog.has_schema_privilege('service_role',n.oid,'CREATE'))
 UNION ALL SELECT 'exact_select_policies',
   (SELECT pg_catalog.count(*) = 2 FROM pg_catalog.pg_policy p JOIN rels r ON r.oid = p.polrelid)
   AND NOT EXISTS (SELECT 1 FROM rels r WHERE r.name <> 'chat_read_states' AND NOT EXISTS (
     SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid = r.oid
       AND p.polname = r.name || '_select' AND p.polcmd = 'r' AND p.polpermissive
       AND p.polroles = ARRAY['authenticated'::regrole::oid] AND p.polwithcheck IS NULL
       AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),
         '[[:space:]()]','','g') = 'jobmate_chat_private.can_read_conversationconversation_id'))
 -- Source-shape check only, not execution/concurrency proof. CH's verified live
 -- update_job_moderation job-first protocol is a separate supported-writer input.
 UNION ALL SELECT 'chat_targeted_locking_source',
   EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid =
     pg_catalog.to_regprocedure('jobmate_chat_private.lock_participant(uuid)')
     AND p.prosrc ~* 'FROM public\.job_postings j[[:space:]]+WHERE j\.job_id = v_job_id FOR SHARE NOWAIT'
     AND pg_catalog.strpos(p.prosrc,'transaction_isolation') > 0
     AND pg_catalog.strpos(p.prosrc,'read committed') > 0)
   AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
     JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'jobmate_chat_private'
       AND p.prosrc ~* '(^|[;\n])[[:space:]]*LOCK[[:space:]]')
 UNION ALL SELECT 'publication_settings',
   EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime'
     AND NOT puballtables AND pubinsert AND pubupdate AND pubdelete AND pubtruncate)
 UNION ALL SELECT 'publication_membership',
   EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime'
     AND NOT puballtables AND pubinsert AND pubupdate AND pubdelete AND pubtruncate)
   AND (SELECT pg_catalog.count(*) = 2 FROM pg_catalog.pg_publication_tables
     WHERE schemaname = 'public' AND tablename IN ('chat_conversations','chat_messages','chat_read_states'))
   AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_publication_tables
     WHERE schemaname = 'public' AND tablename IN ('chat_conversations','chat_messages','chat_read_states')
       AND (pubname <> 'supabase_realtime' OR tablename = 'chat_read_states'))
)
SELECT CASE WHEN phase.absent THEN 'pre_deployment' ELSE 'post_deployment_or_partial' END AS phase,
  check_name, CASE WHEN phase.absent AND check_name <> 'publication_settings' THEN 'PASS_EXPECTED_ABSENT'
    WHEN COALESCE(ok,false) THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks CROSS JOIN phase ORDER BY check_name
-- END EXACT CATALOG SUMMARY
  ) report WHERE report.status <> 'PASS';
  IF v_failures IS NOT NULL THEN
    RAISE EXCEPTION 'Chat catalogue assertions failed: %', v_failures;
  END IF;
  RAISE NOTICE 'Chat DDL/catalogue checks reached; runtime RPC/RLS/concurrency/Realtime NOT tested. ROLLBACK follows.';
END;
$chat_validation_assertions$;
SELECT 'CHAT_DDL_CATALOG_ASSERTIONS_PASSED_ROLLBACK_PENDING'::text AS validation_marker,
  pg_catalog.pg_backend_pid() AS validation_backend_pid,
  pg_catalog.current_setting('transaction_isolation') AS isolation;
ROLLBACK;

-- BASIC UNIVERSITY DEMO ONLY. Content/type validation is NOT antivirus.
-- GUARDED ADDITIVE MIGRATION CANDIDATE. NOT APPROVED OR DATABASE-TESTED.
-- See docs/chat_basic_attachments.md. Original Chat SQL is untouched.
-- Kept outside migrations so db push cannot accidentally schedule this draft.
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL lock_timeout = '1s';
SET LOCAL statement_timeout = '15s';
SET LOCAL idle_in_transaction_session_timeout = '60s';
SET LOCAL transaction_timeout = '90s';
SET LOCAL check_function_bodies = on;
DO $attachment_approval_guard$
BEGIN
  RAISE EXCEPTION 'CHAT ATTACHMENTS BLOCKED: trusted content validator, NO ANTIVIRUS: isolated basic validation/security tests and separate CH/KZ demo deployment approval required';
END;
$attachment_approval_guard$;

-- BEGIN PINNED ATTACHMENT PREFLIGHT
DO $attachment_preflight$
DECLARE v_hook_drift text; v_backend_md5 text; v_count bigint;
BEGIN
 IF current_user<>'postgres' OR pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
   RAISE EXCEPTION 'Reviewed postgres/READ COMMITTED required.'; END IF;
 IF pg_catalog.to_regclass('public.chat_basic_attachments') IS NOT NULL OR EXISTS (
   SELECT 1 FROM storage.buckets WHERE id='jobmate-chat-basic-files') OR EXISTS (
   SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('get_chat_attachment_basic_v1','reserve_chat_attachment_basic_v1',
     'prepare_chat_attachment_upload_basic_v1','prepare_chat_attachment_validation_basic_v1','finish_chat_attachment_validation_basic_v1',
     'send_chat_attachment_basic_v1','list_chat_messages_basic_v1','list_pending_chat_attachments_basic_v1',
     'claim_expired_chat_attachments_basic_v1','complete_chat_attachment_cleanup_basic_v1')) THEN
   RAISE EXCEPTION 'Attachment object collision; never replace unknown objects.'; END IF;
 IF pg_catalog.to_regprocedure('public.send_chat_message(uuid,uuid,text)') IS NULL
   OR pg_catalog.to_regprocedure('jobmate_chat_private.lock_application(uuid,boolean)') IS NULL THEN
   RAISE EXCEPTION 'Deployed Chat baseline unavailable.'; END IF;
 WITH routines AS (
 SELECT p.*,n.nspname FROM pg_catalog.pg_proc p
 JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE (n.nspname='public' AND p.proname IN ('get_or_create_chat_conversation',
   'list_my_chat_conversations','list_chat_messages','send_chat_message','mark_chat_conversation_read'))
 OR (n.nspname='jobmate_chat_private' AND p.proname IN ('valid_body','application_access',
   'can_read_conversation','lock_participant','lock_application'))
), normalized AS (
 SELECT p.oid::regprocedure::text signature,pg_catalog.jsonb_build_object(
   'signature',p.oid::regprocedure::text,'definition',pg_catalog.pg_get_functiondef(p.oid),
   'owner',pg_catalog.pg_get_userbyid(p.proowner),'definer',p.prosecdef,'config',p.proconfig,
   'acl',COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_array(
     pg_catalog.pg_get_userbyid(a.grantor),CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(a.grantee) END,
     a.privilege_type,a.is_grantable) ORDER BY a.grantor,a.grantee,a.privilege_type COLLATE "C",a.is_grantable)
     FROM pg_catalog.aclexplode(CASE WHEN pg_catalog.cardinality(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner)))>0
       THEN COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner)) ELSE NULL::aclitem[] END) a),'[]'::jsonb)) value
 FROM routines p
)
 SELECT pg_catalog.count(*),pg_catalog.md5(pg_catalog.jsonb_agg(value ORDER BY signature COLLATE "C")::text)
 INTO v_count,v_backend_md5 FROM normalized;
 IF v_count<>10 OR pg_catalog.current_setting('jobmate.chat_reviewed_backend_md5',true) IS DISTINCT FROM v_backend_md5 THEN
   RAISE EXCEPTION 'Reviewed Chat routine fingerprint missing/different; preserve and review fresh read-only baseline first.'; END IF;
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
$attachment_preflight$;
-- END PINNED ATTACHMENT PREFLIGHT

-- CREATE and bucket PK deliberately reject collisions. Never replace text SQL.
-- Backend activation is owner-only and defaults off independently of Flutter
-- and Edge flags. A controlled trial can restrict all writes to one conversation
-- and the two jointly validated participants; ordinary eligibility still applies.
CREATE TABLE jobmate_chat_private.basic_attachment_release (
 singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
 enabled boolean NOT NULL DEFAULT false,
 trial_conversation uuid REFERENCES public.chat_conversations(conversation_id),
 participant_ids uuid[] NOT NULL DEFAULT ARRAY[]::uuid[],
 CHECK ((trial_conversation IS NULL AND pg_catalog.cardinality(participant_ids)=0)
   OR (trial_conversation IS NOT NULL AND pg_catalog.cardinality(participant_ids)=2))
);
REVOKE ALL ON jobmate_chat_private.basic_attachment_release FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO jobmate_chat_private.basic_attachment_release(singleton) VALUES(true);
CREATE FUNCTION jobmate_chat_private.basic_attachment_writes_enabled(p_conversation uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
 SELECT EXISTS(SELECT 1 FROM jobmate_chat_private.basic_attachment_release s WHERE s.singleton AND s.enabled
   AND (s.trial_conversation IS NULL OR (s.trial_conversation=p_conversation AND auth.uid()=ANY(s.participant_ids))));
$$;
REVOKE ALL ON FUNCTION jobmate_chat_private.basic_attachment_writes_enabled(uuid) FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE public.chat_messages ADD CONSTRAINT chat_messages_basic_attachment_binding_key
  UNIQUE (message_id, conversation_id, sender_id, client_request_id);
CREATE TABLE public.chat_basic_attachments (
  attachment_id uuid PRIMARY KEY,
  conversation_id uuid NOT NULL REFERENCES public.chat_conversations(conversation_id),
  sender_id uuid NOT NULL REFERENCES public.users(user_id),
  client_request_id uuid NOT NULL,
  message_id uuid UNIQUE,
  caption text CHECK (caption IS NULL OR jobmate_chat_private.valid_body(caption)),
  original_name text NOT NULL CHECK (
    pg_catalog.char_length(original_name) BETWEEN 1 AND 255
    AND pg_catalog.btrim(original_name) <> ''
    AND original_name !~ '[[:cntrl:]/\\]'),
  mime_type text NOT NULL CHECK (mime_type IN (
    'image/jpeg','image/png','application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')),
  size_bytes bigint NOT NULL CHECK (size_bytes BETWEEN 1 AND 5242880),
  sha256 text CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  expected_sha256 text NOT NULL CHECK (expected_sha256 ~ '^[0-9a-f]{64}$'),
  storage_path text NOT NULL UNIQUE CHECK (
    storage_path = conversation_id::text || '/' || sender_id::text || '/' || attachment_id::text || '/file'),
  state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','validating','validated','rejected','committed','expired')),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  expires_at timestamptz NOT NULL,
  validated_at timestamptz,
  validator_version text,
  validation_scope text NOT NULL DEFAULT 'basic-type-validation-no-antivirus-v1' CHECK (validation_scope='basic-type-validation-no-antivirus-v1'),
  validation_token uuid,
  validation_lease_until timestamptz,
  upload_lease_until timestamptz,
  cleanup_done boolean NOT NULL DEFAULT false,
  upload_attempts integer NOT NULL DEFAULT 0 CHECK (upload_attempts BETWEEN 0 AND 160),
  validation_attempts integer NOT NULL DEFAULT 0 CHECK (validation_attempts BETWEEN 0 AND 4),
  CHECK (expires_at > created_at),
  CHECK ((state = 'committed') = (message_id IS NOT NULL)),
  CHECK (state NOT IN ('validated','committed') OR (validated_at IS NOT NULL AND validator_version IS NOT NULL AND sha256 IS NOT NULL)),
  UNIQUE (conversation_id, sender_id, client_request_id),
  -- Composite key prevents linking another conversation's/actor's message.
  FOREIGN KEY (message_id, conversation_id, sender_id, client_request_id)
    REFERENCES public.chat_messages(message_id, conversation_id, sender_id, client_request_id)
);
ALTER TABLE public.chat_basic_attachments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.chat_basic_attachments FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.chat_basic_attachments TO authenticated;
CREATE POLICY chat_attachment_metadata_read ON public.chat_basic_attachments
  FOR SELECT TO authenticated USING (state = 'committed'
    AND jobmate_chat_private.can_read_conversation(conversation_id));

INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES ('jobmate-chat-basic-files','jobmate-chat-basic-files',false,5242880,ARRAY[
  'application/octet-stream', -- opaque immutable quarantine chunks, never client-readable
  'image/jpeg','image/png','application/pdf',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']);

-- Restrictive checks protect against unrelated broad permissive Storage rules.
-- No direct client upload/overwrite/delete. Trusted service-role bypass is an
-- explicit server trust boundary; do not give its key to Flutter.
CREATE POLICY chat_basic_files_client_insert_deny ON storage.objects AS RESTRICTIVE
  FOR INSERT TO anon, authenticated WITH CHECK (bucket_id <> 'jobmate-chat-basic-files');
CREATE POLICY chat_basic_files_client_update_deny ON storage.objects AS RESTRICTIVE
  FOR UPDATE TO anon, authenticated USING (bucket_id <> 'jobmate-chat-basic-files')
  WITH CHECK (bucket_id <> 'jobmate-chat-basic-files');
CREATE POLICY chat_basic_files_client_delete_deny ON storage.objects AS RESTRICTIVE
  FOR DELETE TO anon, authenticated USING (bucket_id <> 'jobmate-chat-basic-files');
-- Even clean/validationned bytes are unreadable until atomically linked to a message.
CREATE POLICY chat_basic_files_read_boundary ON storage.objects AS RESTRICTIVE
  FOR SELECT TO authenticated USING (bucket_id <> 'jobmate-chat-basic-files' OR EXISTS (
    SELECT 1 FROM public.chat_basic_attachments a WHERE a.storage_path = objects.name
      AND a.state = 'committed'
      AND jobmate_chat_private.can_read_conversation(a.conversation_id)));
CREATE POLICY chat_basic_files_anon_read_deny ON storage.objects AS RESTRICTIVE
  FOR SELECT TO anon USING (bucket_id <> 'jobmate-chat-basic-files');
CREATE POLICY chat_basic_files_participant_read ON storage.objects
  FOR SELECT TO authenticated USING (bucket_id = 'jobmate-chat-basic-files' AND EXISTS (
    SELECT 1 FROM public.chat_basic_attachments a WHERE a.storage_path = objects.name
      AND a.state = 'committed'
      AND jobmate_chat_private.can_read_conversation(a.conversation_id)));

CREATE INDEX chat_basic_attachments_owner_pending_idx ON public.chat_basic_attachments(sender_id, created_at);

CREATE FUNCTION jobmate_chat_private.basic_attachment_json(a public.chat_basic_attachments)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
 SELECT pg_catalog.jsonb_build_object('attachment_id',a.attachment_id,
 'conversation_id',a.conversation_id,'sender_id',a.sender_id,
 'client_request_id',a.client_request_id,'message_id',a.message_id,
 'validation_scope',a.validation_scope,'caption',a.caption,'original_name',a.original_name,'mime_type',a.mime_type,
 'size_bytes',a.size_bytes,'state',a.state,'sha256',a.sha256,'expected_sha256',a.expected_sha256,
 'storage_path',CASE WHEN a.state='committed' THEN a.storage_path ELSE NULL END);
$$;
REVOKE ALL ON FUNCTION jobmate_chat_private.basic_attachment_json(public.chat_basic_attachments)
 FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.get_chat_attachment_basic_v1(p_attachment_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE a public.chat_basic_attachments; v_application uuid; v_send boolean;
BEGIN
 SELECT x.* INTO a FROM public.chat_basic_attachments x WHERE x.attachment_id=p_attachment_id;
 IF NOT FOUND OR a.sender_id IS DISTINCT FROM auth.uid()
   OR NOT jobmate_chat_private.can_read_conversation(a.conversation_id) THEN
   RAISE EXCEPTION 'Attachment unavailable.' USING ERRCODE='42501';
 END IF;
 SELECT c.application_id INTO v_application FROM public.chat_conversations c WHERE c.conversation_id=a.conversation_id;
 SELECT ac.can_send INTO v_send FROM jobmate_chat_private.application_access(v_application) ac;
 RETURN jobmate_chat_private.basic_attachment_json(a) || pg_catalog.jsonb_build_object('can_upload',
   v_send IS TRUE AND jobmate_chat_private.basic_attachment_writes_enabled(a.conversation_id));
END; $$;

CREATE FUNCTION public.reserve_chat_attachment_basic_v1(p_conversation_id uuid,p_client_request_id uuid,
 p_attachment_id uuid,p_original_name text,p_mime_type text,p_size_bytes bigint,p_sha256 text,p_caption text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE a public.chat_basic_attachments; v_application uuid; v_caption text := NULLIF(p_caption,'');
BEGIN
 IF NOT jobmate_chat_private.can_read_conversation(p_conversation_id) THEN
   RAISE EXCEPTION 'Attachment unavailable.' USING ERRCODE='42501'; END IF;
 SELECT c.application_id INTO v_application FROM public.chat_conversations c WHERE c.conversation_id=p_conversation_id;
 PERFORM jobmate_chat_private.lock_participant(v_application);
 PERFORM u.user_id FROM public.users u WHERE u.user_id=auth.uid() FOR NO KEY UPDATE NOWAIT;
 SELECT x.* INTO a FROM public.chat_basic_attachments x WHERE x.conversation_id=p_conversation_id
   AND x.sender_id=auth.uid() AND x.client_request_id=p_client_request_id FOR UPDATE NOWAIT;
 IF FOUND THEN
   IF (a.attachment_id,a.original_name,a.mime_type,a.size_bytes,a.expected_sha256,a.caption) IS DISTINCT FROM
      (p_attachment_id,p_original_name,p_mime_type,p_size_bytes,p_sha256,v_caption) THEN
     RAISE EXCEPTION 'Request conflict.' USING ERRCODE='22023'; END IF;
   RETURN public.get_chat_attachment_basic_v1(a.attachment_id);
 END IF;
 IF NOT jobmate_chat_private.basic_attachment_writes_enabled(p_conversation_id) THEN
   RAISE EXCEPTION 'Attachment release is disabled for this context.' USING ERRCODE='55000'; END IF;
 PERFORM jobmate_chat_private.lock_application(v_application);
 IF NOT EXISTS(SELECT 1 FROM jobmate_chat_private.application_access(v_application) ac WHERE ac.can_send) THEN
   RAISE EXCEPTION 'Chat is read-only.' USING ERRCODE='55000'; END IF;
 IF p_client_request_id IS NULL OR p_attachment_id IS NULL OR
   EXISTS(SELECT 1 FROM public.chat_messages m WHERE m.conversation_id=p_conversation_id
     AND m.sender_id=auth.uid() AND m.client_request_id=p_client_request_id) THEN
   RAISE EXCEPTION 'Request conflict.' USING ERRCODE='22023'; END IF;
 IF (SELECT pg_catalog.count(*) FROM public.chat_basic_attachments x WHERE x.sender_id=auth.uid()
     AND x.state IN ('pending','validating','validated')) >= 8 OR
    (SELECT pg_catalog.count(*) FROM public.chat_basic_attachments x WHERE x.sender_id=auth.uid()
     AND x.created_at>pg_catalog.clock_timestamp()-INTERVAL '1 day') >= 100 THEN
   RAISE EXCEPTION 'Attachment quota reached.' USING ERRCODE='54000'; END IF;
 INSERT INTO public.chat_basic_attachments(attachment_id,conversation_id,sender_id,client_request_id,
   original_name,mime_type,size_bytes,expected_sha256,caption,storage_path,expires_at)
 VALUES(p_attachment_id,p_conversation_id,auth.uid(),p_client_request_id,p_original_name,p_mime_type,
   p_size_bytes,p_sha256,v_caption,p_conversation_id::text||'/'||auth.uid()::text||'/'||p_attachment_id::text||'/file',
   pg_catalog.clock_timestamp()+INTERVAL '1 hour') RETURNING * INTO a;
 RETURN public.get_chat_attachment_basic_v1(a.attachment_id);
END; $$;

CREATE FUNCTION public.prepare_chat_attachment_validation_basic_v1(p_attachment_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE a public.chat_basic_attachments; v_application uuid;
BEGIN
 PERFORM public.get_chat_attachment_basic_v1(p_attachment_id);
 SELECT c.application_id INTO v_application FROM public.chat_basic_attachments x
 JOIN public.chat_conversations c USING(conversation_id) WHERE x.attachment_id=p_attachment_id;
 IF NOT jobmate_chat_private.basic_attachment_writes_enabled((SELECT x.conversation_id FROM public.chat_basic_attachments x WHERE x.attachment_id=p_attachment_id)) THEN
   RAISE EXCEPTION 'Attachment release is disabled for this context.' USING ERRCODE='55000'; END IF;
 PERFORM jobmate_chat_private.lock_participant(v_application);
 PERFORM jobmate_chat_private.lock_application(v_application);
 IF NOT EXISTS(SELECT 1 FROM jobmate_chat_private.application_access(v_application) ac WHERE ac.can_send) THEN
   RAISE EXCEPTION 'Chat is read-only.' USING ERRCODE='55000'; END IF;
 SELECT x.* INTO a FROM public.chat_basic_attachments x WHERE x.attachment_id=p_attachment_id FOR UPDATE NOWAIT;
 IF a.state IN ('validated','committed') THEN RETURN jobmate_chat_private.basic_attachment_json(a); END IF;
 IF a.state NOT IN ('pending','validating') OR a.expires_at<=pg_catalog.clock_timestamp() THEN
   RAISE EXCEPTION 'Attachment expired or rejected.' USING ERRCODE='55000'; END IF;
 IF a.validation_lease_until>pg_catalog.clock_timestamp() THEN
   RAISE EXCEPTION 'Validation in progress.' USING ERRCODE='55P03'; END IF;
 IF a.validation_attempts>=4 THEN RAISE EXCEPTION 'Validation attempt limit reached.' USING ERRCODE='54000'; END IF;
 UPDATE public.chat_basic_attachments SET state='validating',validation_token=pg_catalog.gen_random_uuid(),
   validation_lease_until=pg_catalog.clock_timestamp()+INTERVAL '2 minutes',validation_attempts=validation_attempts+1
 WHERE attachment_id=p_attachment_id RETURNING * INTO a;
 RETURN jobmate_chat_private.basic_attachment_json(a)||pg_catalog.jsonb_build_object('validation_token',a.validation_token);
END; $$;

CREATE FUNCTION public.prepare_chat_attachment_upload_basic_v1(p_attachment_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE a public.chat_basic_attachments; v_application uuid;
BEGIN
 PERFORM public.get_chat_attachment_basic_v1(p_attachment_id);
 SELECT c.application_id INTO v_application FROM public.chat_basic_attachments x
 JOIN public.chat_conversations c USING(conversation_id) WHERE x.attachment_id=p_attachment_id;
 IF NOT jobmate_chat_private.basic_attachment_writes_enabled((SELECT x.conversation_id FROM public.chat_basic_attachments x WHERE x.attachment_id=p_attachment_id)) THEN
   RAISE EXCEPTION 'Attachment release is disabled for this context.' USING ERRCODE='55000'; END IF;
 PERFORM jobmate_chat_private.lock_participant(v_application);
 PERFORM jobmate_chat_private.lock_application(v_application);
 IF NOT EXISTS(SELECT 1 FROM jobmate_chat_private.application_access(v_application) ac WHERE ac.can_send) THEN
   RAISE EXCEPTION 'Chat is read-only.' USING ERRCODE='55000'; END IF;
 SELECT x.* INTO a FROM public.chat_basic_attachments x WHERE x.attachment_id=p_attachment_id FOR UPDATE NOWAIT;
 IF a.state<>'pending' OR a.expires_at<=pg_catalog.clock_timestamp() THEN
   RAISE EXCEPTION 'Upload unavailable.' USING ERRCODE='55000'; END IF;
 IF a.upload_attempts>=160 THEN RAISE EXCEPTION 'Upload attempt limit reached.' USING ERRCODE='54000'; END IF;
 -- Longer than the hosted Edge worker maximum lifetime. GC must not race any
 -- in-flight bounded Storage write; final send still needs a fresh eligibility check.
 UPDATE public.chat_basic_attachments SET upload_lease_until=pg_catalog.clock_timestamp()+INTERVAL '10 minutes',
   upload_attempts=upload_attempts+1
 WHERE attachment_id=p_attachment_id;
 RETURN public.get_chat_attachment_basic_v1(p_attachment_id);
END; $$;

-- Trusted content-validator service only; NOT malware scanning; token, state and lease bind a verdict to one immutable upload.
CREATE FUNCTION public.finish_chat_attachment_validation_basic_v1(p_attachment_id uuid,p_validation_token uuid,
 p_verdict text,p_sha256 text,p_mime_type text,p_size_bytes bigint,p_validator_version text)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE a public.chat_basic_attachments;
BEGIN
 SELECT x.* INTO a FROM public.chat_basic_attachments x WHERE x.attachment_id=p_attachment_id FOR UPDATE NOWAIT;
 IF NOT FOUND OR a.state<>'validating' OR a.validation_token IS DISTINCT FROM p_validation_token
   OR a.validation_lease_until<=pg_catalog.clock_timestamp() OR a.expires_at<=pg_catalog.clock_timestamp() THEN
   RAISE EXCEPTION 'Stale validation.' USING ERRCODE='55000'; END IF;
 IF p_verdict NOT IN ('validated','rejected') OR p_verdict IS NULL OR p_sha256 IS NULL
   OR p_sha256!~'^[0-9a-f]{64}$' OR p_validator_version IS NULL
   OR pg_catalog.char_length(p_validator_version) NOT BETWEEN 1 AND 200
   OR p_mime_type IS DISTINCT FROM a.mime_type OR p_size_bytes IS DISTINCT FROM a.size_bytes
   OR (p_verdict='validated' AND (p_sha256 IS DISTINCT FROM a.expected_sha256 OR p_validator_version IS DISTINCT FROM 'basic-type-validation-no-antivirus-v1'))
   OR (a.sha256 IS NOT NULL AND a.sha256 IS DISTINCT FROM p_sha256) THEN
   RAISE EXCEPTION 'Invalid validation receipt.' USING ERRCODE='22023'; END IF;
 UPDATE public.chat_basic_attachments SET state=p_verdict,sha256=p_sha256,
   validated_at=pg_catalog.clock_timestamp(),validator_version=p_validator_version,
   validation_token=NULL,validation_lease_until=NULL WHERE attachment_id=p_attachment_id;
END; $$;

CREATE FUNCTION public.send_chat_attachment_basic_v1(p_attachment_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE a public.chat_basic_attachments; m record; v_application uuid;
BEGIN
 PERFORM public.get_chat_attachment_basic_v1(p_attachment_id);
 SELECT c.application_id INTO v_application FROM public.chat_basic_attachments x
 JOIN public.chat_conversations c USING(conversation_id) WHERE x.attachment_id=p_attachment_id;
 PERFORM jobmate_chat_private.lock_participant(v_application);
 -- Same order as the original text sender; never take the attachment first.
 PERFORM c.conversation_id FROM public.chat_conversations c JOIN public.chat_basic_attachments x USING(conversation_id)
   WHERE x.attachment_id=p_attachment_id FOR NO KEY UPDATE OF c NOWAIT;
 SELECT x.* INTO a FROM public.chat_basic_attachments x WHERE x.attachment_id=p_attachment_id FOR UPDATE NOWAIT;
 IF a.state='committed' THEN
   SELECT x.* INTO m FROM public.chat_messages x WHERE x.message_id=a.message_id;
 ELSE
   IF NOT jobmate_chat_private.basic_attachment_writes_enabled(a.conversation_id) THEN
     RAISE EXCEPTION 'Attachment release is disabled for this context.' USING ERRCODE='55000'; END IF;
   IF a.state<>'validated' OR a.expires_at<=pg_catalog.clock_timestamp() THEN
     RAISE EXCEPTION 'Attachment not validated.' USING ERRCODE='55000'; END IF;
   IF EXISTS(SELECT 1 FROM public.chat_messages x WHERE x.conversation_id=a.conversation_id
     AND x.sender_id=a.sender_id AND x.client_request_id=a.client_request_id) THEN
     RAISE EXCEPTION 'Request conflict.' USING ERRCODE='22023'; END IF;
   -- Compatibility text is an explicit attachment description for v1 clients.
   -- basic-v1 returns the real nullable caption, never mistakes this label for a caption.
   SELECT * INTO m FROM public.send_chat_message(a.conversation_id,a.client_request_id,
     COALESCE(a.caption,'Attachment: '||a.original_name));
   UPDATE public.chat_basic_attachments SET state='committed',message_id=m.message_id
     WHERE attachment_id=a.attachment_id RETURNING * INTO a;
 END IF;
 RETURN pg_catalog.jsonb_build_object('message_id',m.message_id,'conversation_id',m.conversation_id,
   'sender_id',m.sender_id,'body',m.body,'sent_at',m.sent_at,'sequence',m.sequence,
   'caption',a.caption,'attachment',jobmate_chat_private.basic_attachment_json(a));
END; $$;

CREATE FUNCTION public.list_chat_messages_basic_v1(p_conversation_id uuid,p_limit integer DEFAULT 50,p_before_sequence bigint DEFAULT NULL)
RETURNS TABLE(message_id uuid,conversation_id uuid,sender_id uuid,sender_name text,body text,
 sent_at timestamptz,sequence bigint,caption text,attachment jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
 SELECT m.*,CASE WHEN a.attachment_id IS NULL THEN m.body ELSE a.caption END,
   CASE WHEN a.attachment_id IS NULL THEN NULL ELSE jobmate_chat_private.basic_attachment_json(a) END
 FROM public.list_chat_messages(p_conversation_id,p_limit,p_before_sequence) m
 LEFT JOIN public.chat_basic_attachments a ON a.message_id=m.message_id AND a.state='committed';
$$;

CREATE FUNCTION public.list_pending_chat_attachments_basic_v1(p_conversation_id uuid)
RETURNS SETOF jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT jobmate_chat_private.can_read_conversation(p_conversation_id) THEN
   RAISE EXCEPTION 'Attachment unavailable.' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT jobmate_chat_private.basic_attachment_json(a) FROM public.chat_basic_attachments a
 WHERE a.conversation_id=p_conversation_id AND a.sender_id=auth.uid()
   AND a.state IN ('pending','validating','validated','rejected') ORDER BY a.created_at DESC LIMIT 8;
END; $$;

CREATE FUNCTION public.claim_expired_chat_attachments_basic_v1()
RETURNS SETOF jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 RETURN QUERY WITH candidates AS (SELECT a.attachment_id FROM public.chat_basic_attachments a
   WHERE NOT a.cleanup_done AND a.expires_at<pg_catalog.clock_timestamp()
     AND COALESCE(a.validation_lease_until,'-infinity'::timestamptz)<pg_catalog.clock_timestamp()
     AND COALESCE(a.upload_lease_until,'-infinity'::timestamptz)<pg_catalog.clock_timestamp()
   ORDER BY a.expires_at LIMIT 50 FOR UPDATE SKIP LOCKED), expired AS (
   UPDATE public.chat_basic_attachments a SET state=CASE WHEN a.state='committed' THEN 'committed' ELSE 'expired' END,
     validation_token=NULL,validation_lease_until=NULL
   FROM candidates c WHERE a.attachment_id=c.attachment_id RETURNING a.*)
 SELECT pg_catalog.jsonb_build_object('attachment_id',e.attachment_id,'storage_path',e.storage_path,
   'size_bytes',e.size_bytes,'chunks_only',e.state='committed') FROM expired e;
END; $$;
CREATE FUNCTION public.complete_chat_attachment_cleanup_basic_v1(p_attachment_id uuid)
RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
 UPDATE public.chat_basic_attachments SET cleanup_done=true WHERE attachment_id=p_attachment_id AND state IN ('expired','committed');
$$;

REVOKE ALL ON FUNCTION public.get_chat_attachment_basic_v1(uuid),
 public.reserve_chat_attachment_basic_v1(uuid,uuid,uuid,text,text,bigint,text,text),
 public.prepare_chat_attachment_validation_basic_v1(uuid),public.send_chat_attachment_basic_v1(uuid),
 public.prepare_chat_attachment_upload_basic_v1(uuid),
 public.list_chat_messages_basic_v1(uuid,integer,bigint),public.list_pending_chat_attachments_basic_v1(uuid),
 public.finish_chat_attachment_validation_basic_v1(uuid,uuid,text,text,text,bigint,text),
 public.claim_expired_chat_attachments_basic_v1(),public.complete_chat_attachment_cleanup_basic_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_chat_attachment_basic_v1(uuid),
 public.reserve_chat_attachment_basic_v1(uuid,uuid,uuid,text,text,bigint,text,text),
 public.prepare_chat_attachment_validation_basic_v1(uuid),public.send_chat_attachment_basic_v1(uuid),
 public.prepare_chat_attachment_upload_basic_v1(uuid),
 public.list_chat_messages_basic_v1(uuid,integer,bigint),public.list_pending_chat_attachments_basic_v1(uuid)
 TO authenticated;
GRANT EXECUTE ON FUNCTION public.finish_chat_attachment_validation_basic_v1(uuid,uuid,text,text,text,bigint,text),
 public.claim_expired_chat_attachments_basic_v1(),public.complete_chat_attachment_cleanup_basic_v1(uuid) TO service_role;

-- New metadata is reconciled through basic-v1 history on the existing chat_messages
-- INSERT/conversation UPDATE events. No publication expansion or new notification trigger.
COMMIT;

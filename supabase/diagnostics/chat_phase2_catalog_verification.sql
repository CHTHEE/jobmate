-- READ ONLY; not executed by the agent. No business rows or mutation RPC calls.
-- Export before and after an independently approved deployment. The candidate
-- intentionally cannot deploy until its release guard is reviewed and removed.
-- Missing objects return missing rows/status, not an instruction to repair live.

-- 0. Compact summary. PASS_EXPECTED_ABSENT means no chat installation exists yet;
-- it does NOT mean post-deployment requirements have passed. Any partial chat
-- installation switches to post/partial mode and must meet all requirements.
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
FROM checks CROSS JOIN phase ORDER BY check_name;

-- 1. Expected relation presence, owner, RLS, replica identity and effective ACLs.
WITH expected(name) AS (VALUES ('chat_conversations'),('chat_messages'),('chat_read_states'))
SELECT e.name, c.oid IS NOT NULL AS present, c.relkind, c.relrowsecurity,
  c.relforcerowsecurity, c.relreplident, c.relacl,
  pg_catalog.pg_get_userbyid(c.relowner) AS owner
FROM expected e LEFT JOIN pg_catalog.pg_namespace n ON n.nspname = 'public'
LEFT JOIN pg_catalog.pg_class c ON c.relnamespace = n.oid AND c.relname = e.name
ORDER BY e.name;
SELECT table_name, column_name, ordinal_position, udt_schema, udt_name,
  is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('chat_conversations','chat_messages','chat_read_states')
ORDER BY table_name, ordinal_position;
SELECT c.relname, k.conname, k.contype, pg_catalog.pg_get_constraintdef(k.oid,true) AS definition
FROM pg_catalog.pg_constraint k JOIN pg_catalog.pg_class c ON c.oid = k.conrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname IN ('chat_conversations','chat_messages','chat_read_states')
ORDER BY c.relname,k.conname;
SELECT tablename,indexname,indexdef FROM pg_catalog.pg_indexes
WHERE schemaname = 'public' AND tablename IN ('chat_conversations','chat_messages','chat_read_states')
ORDER BY tablename,indexname;

-- 2. Exactly two participant-only SELECT policies; read states are RPC-only.
SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check
FROM pg_catalog.pg_policies WHERE schemaname = 'public'
AND tablename IN ('chat_conversations','chat_messages','chat_read_states')
ORDER BY tablename,policyname;
SELECT r.rolname, c.oid::regclass::text AS relation, priv.name AS privilege,
  pg_catalog.has_table_privilege(r.oid,c.oid,priv.name) AS effective_allowed
FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN pg_catalog.pg_roles r
CROSS JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER'),('MAINTAIN')) priv(name)
WHERE n.nspname = 'public' AND c.relname IN ('chat_conversations','chat_messages','chat_read_states')
  AND r.rolname IN ('anon','authenticated','service_role')
ORDER BY r.rolname,relation,priv.name;
-- Column grants can bypass absence of whole-table write grants.
SELECT table_name,column_name,grantee,privilege_type,is_grantable
FROM information_schema.column_privileges WHERE table_schema = 'public'
AND table_name IN ('chat_conversations','chat_messages','chat_read_states')
ORDER BY table_name,column_name,grantee,privilege_type;

-- 3. Five exact public signatures, no extra overloads; safe owner/config/ACL/body.
WITH expected(signature) AS (VALUES
 ('public.get_or_create_chat_conversation(uuid)'),
 ('public.list_my_chat_conversations(integer,timestamp with time zone,uuid,uuid)'),
 ('public.list_chat_messages(uuid,integer,bigint)'),
 ('public.send_chat_message(uuid,uuid,text)'),
 ('public.mark_chat_conversation_read(uuid,uuid)'))
SELECT signature,pg_catalog.to_regprocedure(signature) IS NOT NULL AS present
FROM expected ORDER BY signature;
SELECT p.oid::regprocedure::text AS signature,
  pg_catalog.pg_get_function_arguments(p.oid) AS arguments,
  pg_catalog.pg_get_function_result(p.oid) AS result,
  pg_catalog.pg_get_userbyid(p.proowner) AS owner,p.prosecdef,p.provolatile,p.proconfig,p.proacl,
  pg_catalog.pg_get_functiondef(p.oid) AS definition
FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'jobmate_chat_private'
  OR (n.nspname = 'public' AND p.proname IN ('get_or_create_chat_conversation',
    'list_my_chat_conversations','list_chat_messages','send_chat_message','mark_chat_conversation_read'))
ORDER BY signature;
SELECT r.rolname,p.oid::regprocedure::text AS signature,
  pg_catalog.has_function_privilege(r.oid,p.oid,'EXECUTE') AS effective_execute,
  pg_catalog.has_schema_privilege(r.oid,n.oid,'USAGE') AS schema_usage
FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN pg_catalog.pg_roles r
WHERE r.rolname IN ('anon','authenticated','service_role')
AND (n.nspname = 'jobmate_chat_private'
  OR (n.nspname = 'public' AND p.proname IN ('get_or_create_chat_conversation',
    'list_my_chat_conversations','list_chat_messages','send_chat_message','mark_chat_conversation_read')))
ORDER BY signature,r.rolname;

-- 4. Publication: existing settings unchanged; add ONLY conversations/messages.
SELECT pubname,pg_catalog.pg_get_userbyid(pubowner) AS owner,
  puballtables,pubinsert,pubupdate,pubdelete,pubtruncate,pubviaroot
FROM pg_catalog.pg_publication ORDER BY pubname;
SELECT pubname,schemaname,tablename,attnames,rowfilter FROM pg_catalog.pg_publication_tables
ORDER BY pubname,schemaname,tablename;

-- 5. Consolidated baseline: shared verbatim with post-rollback verification.
WITH relations AS (
 SELECT c.*,n.nspname FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p','v','m')
 AND NOT (n.nspname = 'public' AND c.relname IN ('chat_conversations','chat_messages','chat_read_states'))
), functions AS (
 SELECT p.*,n.nspname FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE p.prokind IN ('f','p') AND (n.nspname IN ('public','private')
 OR EXISTS (SELECT 1 FROM pg_catalog.pg_event_trigger e WHERE e.evtfoid = p.oid))
), raw_acls(kind,obj,sub,acl) AS (
 SELECT 'routine',p.oid,0,COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner)) FROM functions p
 UNION ALL SELECT 'relation',c.oid,0,COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner)) FROM relations c
 UNION ALL SELECT 'column',a.attrelid,a.attnum::integer,COALESCE(a.attacl,'{}'::aclitem[])
 FROM pg_catalog.pg_attribute a JOIN relations c ON c.oid = a.attrelid WHERE a.attnum > 0 AND NOT a.attisdropped
 UNION ALL SELECT 'default',d.oid,0,d.defaclacl FROM pg_catalog.pg_default_acl d
), normalized_acls AS (
 SELECT r.kind,r.obj,r.sub,pg_catalog.jsonb_agg(pg_catalog.jsonb_build_array(
 pg_catalog.pg_get_userbyid(a.grantor)::text,
 CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(a.grantee)::text END,
 a.privilege_type,a.is_grantable)
 ORDER BY pg_catalog.pg_get_userbyid(a.grantor)::text COLLATE "C",
 (CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(a.grantee)::text END) COLLATE "C",
 a.privilege_type COLLATE "C",a.is_grantable) AS value
 FROM raw_acls r
 CROSS JOIN LATERAL pg_catalog.aclexplode(
   CASE WHEN pg_catalog.cardinality(r.acl) > 0 THEN r.acl ELSE NULL::aclitem[] END
 ) a GROUP BY r.kind,r.obj,r.sub
), absence(check_name,ok) AS (
 SELECT 'no_chat_relations',NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
 JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public'
 AND c.relname IN ('chat_conversations','chat_messages','chat_read_states','chat_conversations_activity_idx'))
 UNION ALL SELECT 'no_chat_private_schema',pg_catalog.to_regnamespace('jobmate_chat_private') IS NULL
 UNION ALL SELECT 'no_public_chat_rpcs',NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
 JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public'
 AND p.proname IN ('get_or_create_chat_conversation','list_my_chat_conversations','list_chat_messages',
 'send_chat_message','mark_chat_conversation_read'))
 UNION ALL SELECT 'no_chat_publication_members',NOT EXISTS (SELECT 1 FROM pg_catalog.pg_publication_tables
 WHERE schemaname = 'public' AND tablename IN ('chat_conversations','chat_messages','chat_read_states'))
), baseline_rows(category,object_identity,fingerprint_or_value) AS (
 SELECT 'absence',check_name,CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END FROM absence
 UNION ALL SELECT 'routine',pg_catalog.format('%I.%I(%s)',p.nspname,p.proname,
 pg_catalog.pg_get_function_identity_arguments(p.oid)),
 pg_catalog.md5(pg_catalog.jsonb_build_array(pg_catalog.pg_get_functiondef(p.oid),
 pg_catalog.pg_get_userbyid(p.proowner),COALESCE(a.value,'[]'::jsonb))::text)
 FROM functions p LEFT JOIN normalized_acls a ON a.kind = 'routine' AND a.obj = p.oid AND a.sub = 0
 WHERE p.nspname IN ('public','private') AND NOT (p.nspname = 'public' AND p.proname IN (
 'get_or_create_chat_conversation','list_my_chat_conversations','list_chat_messages',
 'send_chat_message','mark_chat_conversation_read'))
 UNION ALL SELECT 'relation',pg_catalog.format('%I.%I',c.nspname,c.relname),
 pg_catalog.md5(pg_catalog.jsonb_build_array(c.relkind,pg_catalog.pg_get_userbyid(c.relowner),
 c.relrowsecurity,c.relforcerowsecurity,c.relreplident,c.reloptions,COALESCE(a.value,'[]'::jsonb))::text)
 FROM relations c LEFT JOIN normalized_acls a ON a.kind = 'relation' AND a.obj = c.oid AND a.sub = 0
 UNION ALL SELECT 'policy',pg_catalog.format('%I.%I/%I',p.schemaname,p.tablename,p.policyname),
 pg_catalog.md5(pg_catalog.jsonb_build_array(p.permissive,
 ARRAY(SELECT x::text FROM pg_catalog.unnest(p.roles) x ORDER BY x::text COLLATE "C"),
 p.cmd,p.qual,p.with_check)::text)
 FROM pg_catalog.pg_policies p WHERE p.schemaname IN ('public','private','storage','realtime')
 AND NOT (p.schemaname = 'public' AND p.tablename IN ('chat_conversations','chat_messages','chat_read_states'))
 UNION ALL SELECT 'constraint',pg_catalog.format('%I.%I/%I',c.nspname,c.relname,k.conname),
 pg_catalog.md5(pg_catalog.jsonb_build_array(pg_catalog.pg_get_constraintdef(k.oid,false),
 k.convalidated,k.condeferrable,k.condeferred)::text)
 FROM pg_catalog.pg_constraint k JOIN relations c ON c.oid = k.conrelid
 UNION ALL SELECT CASE WHEN t.tgisinternal THEN 'internal_trigger' ELSE 'trigger' END,
 pg_catalog.format('%I.%I/%I',c.nspname,c.relname,t.tgname),
 pg_catalog.md5(pg_catalog.jsonb_build_array(t.tgisinternal,t.tgenabled,t.tgdeferrable,t.tginitdeferred,
 pg_catalog.pg_get_triggerdef(t.oid,false),pg_catalog.pg_get_functiondef(t.tgfoid))::text)
 FROM pg_catalog.pg_trigger t JOIN relations c ON c.oid = t.tgrelid
 -- Include internal RI triggers temporarily added to existing users/applications.
 UNION ALL SELECT 'column',pg_catalog.format('%I.%I/%I',c.nspname,c.relname,a.attname),
 pg_catalog.md5(pg_catalog.jsonb_build_array(a.attnum,pg_catalog.format_type(a.atttypid,a.atttypmod),
 a.attnotnull,a.attidentity,a.attgenerated,
 CASE WHEN coll.oid IS NULL THEN NULL ELSE pg_catalog.format('%I.%I',cn.nspname,coll.collname) END,
 pg_catalog.pg_get_expr(d.adbin,d.adrelid),COALESCE(acl.value,'[]'::jsonb))::text)
 FROM pg_catalog.pg_attribute a JOIN relations c ON c.oid = a.attrelid
 LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
 LEFT JOIN pg_catalog.pg_collation coll ON coll.oid = a.attcollation
 LEFT JOIN pg_catalog.pg_namespace cn ON cn.oid = coll.collnamespace
 LEFT JOIN normalized_acls acl ON acl.kind = 'column' AND acl.obj = a.attrelid AND acl.sub = a.attnum
 WHERE a.attnum > 0 AND NOT a.attisdropped
 UNION ALL SELECT 'column_grant',pg_catalog.format('%I.%I/%I',p.table_schema,p.table_name,p.column_name)
 || '/' || pg_catalog.jsonb_build_array(p.grantor,p.grantee,p.privilege_type)::text,
 p.is_grantable::text FROM information_schema.column_privileges p
 WHERE p.table_schema IN ('public','private')
 AND NOT (p.table_schema = 'public' AND p.table_name IN ('chat_conversations','chat_messages','chat_read_states'))
 UNION ALL SELECT 'index',pg_catalog.format('%I.%I',i.schemaname,i.indexname),pg_catalog.md5(i.indexdef)
 FROM pg_catalog.pg_indexes i WHERE i.schemaname IN ('public','private')
 AND NOT (i.schemaname = 'public' AND i.tablename IN ('chat_conversations','chat_messages','chat_read_states'))
 UNION ALL SELECT 'view',pg_catalog.format('%I.%I',c.nspname,c.relname),
 pg_catalog.md5(pg_catalog.pg_get_viewdef(c.oid,false)) FROM relations c WHERE c.relkind IN ('v','m')
 UNION ALL SELECT 'default_privilege',pg_catalog.jsonb_build_array(pg_catalog.pg_get_userbyid(d.defaclrole),
 COALESCE(n.nspname::text,'*'),d.defaclobjtype)::text,COALESCE(a.value,'[]'::jsonb)::text
 FROM pg_catalog.pg_default_acl d LEFT JOIN pg_catalog.pg_namespace n ON n.oid = d.defaclnamespace
 LEFT JOIN normalized_acls a ON a.kind = 'default' AND a.obj = d.oid AND a.sub = 0
 UNION ALL SELECT 'publication',p.pubname::text,pg_catalog.jsonb_build_object(
 'owner',pg_catalog.pg_get_userbyid(p.pubowner),'puballtables',p.puballtables,
 'pubinsert',p.pubinsert,'pubupdate',p.pubupdate,'pubdelete',p.pubdelete,
 'pubtruncate',p.pubtruncate,'pubviaroot',p.pubviaroot)::text FROM pg_catalog.pg_publication p
 UNION ALL SELECT 'publication_table',pg_catalog.jsonb_build_array(p.pubname,
 pg_catalog.format('%I.%I',p.schemaname,p.tablename))::text,
 pg_catalog.jsonb_build_object('attnames',p.attnames,'rowfilter',p.rowfilter)::text
 FROM pg_catalog.pg_publication_tables p
 UNION ALL SELECT 'event_hook',e.evtname::text,pg_catalog.jsonb_build_object(
 'event',e.evtevent,'enabled',e.evtenabled,'tags',e.evttags,
 'trigger_owner',pg_catalog.pg_get_userbyid(e.evtowner),
 'handler',pg_catalog.format('%I.%I(%s)',p.nspname,p.proname,pg_catalog.pg_get_function_identity_arguments(p.oid)),
 'handler_owner',pg_catalog.pg_get_userbyid(p.proowner),'language',l.lanname,
 'security_definer',p.prosecdef,'config',p.proconfig,'kind',p.prokind,
 'input_count',p.pronargs,'returns_set',p.proretset,'result',pg_catalog.pg_get_function_result(p.oid),
 'acl_with_grantors',COALESCE(a.value,'[]'::jsonb),
 'definition_md5',pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)),
 'definition',pg_catalog.pg_get_functiondef(p.oid))::text
 FROM pg_catalog.pg_event_trigger e JOIN functions p ON p.oid = e.evtfoid
 JOIN pg_catalog.pg_language l ON l.oid = p.prolang
 LEFT JOIN normalized_acls a ON a.kind = 'routine' AND a.obj = p.oid AND a.sub = 0
 UNION ALL SELECT 'context','inspection',pg_catalog.jsonb_build_object('role',current_user,
 'database',pg_catalog.current_database(),'version',pg_catalog.current_setting('server_version'),
 'search_path',pg_catalog.current_setting('search_path'),
 'replication_role',pg_catalog.current_setting('session_replication_role'))::text
)
SELECT pg_catalog.count(*) AS record_count,
 pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('category',category,
 'object_identity',object_identity,'fingerprint_or_value',fingerprint_or_value)
 ORDER BY category COLLATE "C",object_identity COLLATE "C") AS baseline
FROM baseline_rows;

-- 6. WRITER BASELINE / DRIFT REVIEW: CH ran this manually for Phase 2B and
-- supplied verified job-first update_job_moderation INSERT/UPDATE evidence,
-- moderation RLS/postgres-only explicit ACL/no policies/no non-internal triggers,
-- plus membership ACLs, enabled owner protection and user-first onboarding.
-- The agent has not executed it. Retain for later source/security drift review;
-- no repeat live inspection is required merely to remove the now-resolved blocker.
-- Supported moderation writes use update_job_moderation and take job FOR UPDATE
-- before touching moderation state, including initial INSERT. No supported
-- DELETE/upsert path was established. A future path must obey that protocol.
-- Membership references cover onboarding/reassignment/protection/account paths.
-- Text matching and pg_depend are discovery only: PL/pgSQL/dynamic/external
-- callers may have no catalogue dependency. Follow returned helper calls manually.
WITH RECURSIVE routine_source AS (
 SELECT p.oid,p.proname,p.prosrc FROM pg_catalog.pg_proc p
 JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','private') AND p.prokind IN ('f','p')
), seeds AS (
 SELECT oid FROM routine_source WHERE prosrc ~* '(job_moderation_state|company_memberships)'
   OR proname IN ('update_job_moderation','set_user_account_status','set_company_restriction',
     'update_job_application_status','respond_to_job_application','submit_company_for_review_v2')
 UNION SELECT t.tgfoid FROM pg_catalog.pg_trigger t
 WHERE t.tgrelid IN (pg_catalog.to_regclass('public.job_moderation_state'),
   pg_catalog.to_regclass('public.company_memberships'),pg_catalog.to_regclass('public.users'))
   AND NOT t.tgisinternal
), related(oid,path,depth) AS (
 SELECT oid,ARRAY[oid],0 FROM seeds
 UNION ALL
 SELECT s.oid,r.path || s.oid,r.depth + 1 FROM related r
 JOIN pg_catalog.pg_depend d ON d.classid = 'pg_catalog.pg_proc'::regclass
   AND d.refclassid = 'pg_catalog.pg_proc'::regclass
   AND (d.objid = r.oid OR d.refobjid = r.oid)
 JOIN routine_source s ON s.oid = CASE WHEN d.objid = r.oid THEN d.refobjid ELSE d.objid END
 WHERE r.depth < 3 AND NOT s.oid = ANY(r.path)
)
SELECT
 (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
   'signature',p.oid::regprocedure::text,'definition',pg_catalog.pg_get_functiondef(p.oid),
   'owner',pg_catalog.pg_get_userbyid(p.proowner),'security_definer',p.prosecdef,
   'config',p.proconfig,'acl',p.proacl) ORDER BY p.oid)
  FROM pg_catalog.pg_proc p WHERE p.oid IN (SELECT oid FROM related)) AS routines,
 (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('table',t.tgrelid::regclass::text,
   'enabled',t.tgenabled,'trigger',pg_catalog.pg_get_triggerdef(t.oid,true),
   'function',t.tgfoid::regprocedure::text) ORDER BY t.oid)
  FROM pg_catalog.pg_trigger t WHERE NOT t.tgisinternal
    AND (t.tgfoid IN (SELECT oid FROM related) OR t.tgrelid IN (
      pg_catalog.to_regclass('public.job_moderation_state'),pg_catalog.to_regclass('public.company_memberships')))) AS triggers,
 (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('table',c.oid::regclass::text,
   'acl',c.relacl,'rls',c.relrowsecurity)) FROM pg_catalog.pg_class c
  WHERE c.oid IN (pg_catalog.to_regclass('public.job_moderation_state'),
    pg_catalog.to_regclass('public.company_memberships'))) AS direct_writer_acls,
 (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p)) FROM pg_catalog.pg_policies p
  WHERE p.schemaname = 'public' AND p.tablename IN ('job_moderation_state','company_memberships')) AS policies;

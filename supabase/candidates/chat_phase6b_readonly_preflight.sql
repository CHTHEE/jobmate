-- READ ONLY. CH runs manually in a fresh SQL Editor session before any approval.
-- No rows, user credentials or file data. Preserve the complete result.
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
SELECT current_user,current_database(),pg_catalog.current_setting('server_version') server_version,
 pg_catalog.current_setting('session_replication_role') replication_role,
 (SELECT pg_catalog.count(*) FROM normalized) routine_count,
 (SELECT pg_catalog.md5(pg_catalog.jsonb_agg(value ORDER BY signature COLLATE "C")::text) FROM normalized) reviewed_backend_md5,
 (SELECT pg_catalog.jsonb_agg(value ORDER BY signature COLLATE "C") FROM normalized) reviewed_backend,
 (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY schemaname,tablename,policyname)
    FROM pg_catalog.pg_policies p WHERE schemaname IN ('public','storage')) policies,
 (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(b) ORDER BY id)
    FROM (SELECT id,name,public,file_size_limit,allowed_mime_types FROM storage.buckets) b) buckets;

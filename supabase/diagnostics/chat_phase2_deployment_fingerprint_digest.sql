-- READ ONLY / UNEXECUTED CANDIDATE. No database rows or configuration are changed.
-- Prospective deployment comparison only; cannot prove earlier exports matched.
-- Save the full small result BEFORE and AFTER under the same schema freeze/role.
-- Require matching compared counts/global/category digests, zero duplicate keys,
-- and review separately the six new parent FK RI triggers + two publication rows.
-- Main catalogue assertions remain required; this does not validate Chat runtime.
-- Uses PostgreSQL 17 built-in SHA256; no extension install is required.
-- BEGIN EXACT SHARED BASELINE CTE
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
-- END EXACT SHARED BASELINE CTE
, planned_additions(category,object_identity,details) AS (
 SELECT 'internal_trigger',pg_catalog.format('%I.%I/%I',parent_ns.nspname,parent.relname,t.tgname),
   pg_catalog.jsonb_build_object('kind','new_chat_parent_fk_trigger',
     'child',pg_catalog.format('%I.%I',child_ns.nspname,child.relname),'constraint',k.conname,
     'parent',pg_catalog.format('%I.%I',parent_ns.nspname,parent.relname),
     'columns',keys.child_cols,'referenced_columns',keys.parent_cols,
     'enabled',t.tgenabled,'definition',pg_catalog.pg_get_triggerdef(t.oid,false))
 FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_constraint k ON k.oid = t.tgconstraint
 JOIN pg_catalog.pg_class child ON child.oid = k.conrelid
 JOIN pg_catalog.pg_namespace child_ns ON child_ns.oid = child.relnamespace
 JOIN pg_catalog.pg_class parent ON parent.oid = k.confrelid
 JOIN pg_catalog.pg_namespace parent_ns ON parent_ns.oid = parent.relnamespace
 CROSS JOIN LATERAL (
   SELECT ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(k.conkey) WITH ORDINALITY x(num,ord)
     JOIN pg_catalog.pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = x.num ORDER BY x.ord) AS child_cols,
     ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(k.confkey) WITH ORDINALITY x(num,ord)
     JOIN pg_catalog.pg_attribute a ON a.attrelid = k.confrelid AND a.attnum = x.num ORDER BY x.ord) AS parent_cols
 ) keys
 WHERE t.tgisinternal AND t.tgrelid = k.confrelid AND k.contype = 'f'
   AND child_ns.nspname = 'public' AND parent_ns.nspname = 'public'
   AND k.confdeltype = 'a' AND k.confupdtype = 'a'
   AND ((child.relname = 'chat_conversations' AND parent.relname = 'job_applications'
       AND keys.child_cols = ARRAY['application_id'] AND keys.parent_cols = ARRAY['application_id'])
     OR (child.relname = 'chat_messages' AND parent.relname = 'users'
       AND keys.child_cols = ARRAY['sender_id'] AND keys.parent_cols = ARRAY['user_id'])
     OR (child.relname = 'chat_read_states' AND parent.relname = 'users'
       AND keys.child_cols = ARRAY['user_id'] AND keys.parent_cols = ARRAY['user_id']))
 UNION ALL SELECT 'publication_table',pg_catalog.jsonb_build_array(p.pubname,
     pg_catalog.format('%I.%I',p.schemaname,p.tablename))::text,
   pg_catalog.jsonb_build_object('kind','new_chat_publication_member',
     'publication',p.pubname,'table',pg_catalog.format('%I.%I',p.schemaname,p.tablename),
     'attnames',p.attnames,'rowfilter',p.rowfilter)
 FROM pg_catalog.pg_publication_tables p WHERE p.pubname = 'supabase_realtime'
   AND p.schemaname = 'public' AND p.tablename IN ('chat_conversations','chat_messages')
), compared AS (
 SELECT b.* FROM baseline_rows b WHERE b.category <> 'absence'
 AND NOT EXISTS (SELECT 1 FROM planned_additions p
   WHERE p.category = b.category AND p.object_identity = b.object_identity)
), category_digests AS (
 SELECT category,pg_catalog.count(*) AS record_count,
   pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(
     pg_catalog.jsonb_agg(pg_catalog.jsonb_build_array(object_identity,fingerprint_or_value)
       ORDER BY object_identity COLLATE "C")::text,'UTF8')),'hex') AS sha256
 FROM compared GROUP BY category
), global_digest AS (
 SELECT pg_catalog.count(*) AS record_count,
   pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(COALESCE(
     pg_catalog.jsonb_agg(pg_catalog.jsonb_build_array(category,object_identity,fingerprint_or_value)
       ORDER BY category COLLATE "C",object_identity COLLATE "C"),'[]'::jsonb)::text,'UTF8')),'hex') AS sha256
 FROM compared
)
SELECT 'jobmate-chat-deployment-digest-v1'::text AS digest_format,
 (SELECT pg_catalog.count(*) FROM baseline_rows) AS source_record_count,
 g.record_count AS compared_record_count,g.sha256 AS unchanged_catalog_sha256,
 (SELECT pg_catalog.count(*) FROM (SELECT category,object_identity FROM baseline_rows
   GROUP BY category,object_identity HAVING pg_catalog.count(*) > 1) duplicates) AS duplicate_key_count,
 (SELECT pg_catalog.jsonb_object_agg(check_name,CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END) FROM absence) AS absence_checks,
 (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('category',category,
   'record_count',record_count,'sha256',sha256) ORDER BY category COLLATE "C") FROM category_digests) AS category_digests,
 (SELECT pg_catalog.count(*) FROM planned_additions WHERE category = 'internal_trigger') AS planned_parent_fk_trigger_count,
 (SELECT pg_catalog.count(*) FROM planned_additions WHERE category = 'publication_table') AS planned_publication_member_count,
 (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('category',p.category,
   'object_identity',p.object_identity,'details',p.details,'fingerprint_or_value',b.fingerprint_or_value)
   ORDER BY p.category COLLATE "C",p.object_identity COLLATE "C"),'[]'::jsonb)
   FROM planned_additions p JOIN baseline_rows b USING (category,object_identity)) AS planned_additions_for_review
FROM global_digest g;

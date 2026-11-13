-- READ ONLY. Run unchanged BEFORE and AFTER the approved rollback-only trial.
-- Catalogue/configuration only: no application/message/token/storage.objects rows.
-- Existing text Chat is INCLUDED. Compare full key/value sets, not counts alone.
WITH schemas AS (
 SELECT * FROM pg_catalog.pg_namespace WHERE nspname IN
 ('public','private','jobmate_chat_private','storage','realtime','extensions')
), relations AS (
 SELECT c.*,n.nspname FROM pg_catalog.pg_class c JOIN schemas n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p','v','m','f','S')
), routines AS (
 SELECT p.*,n.nspname FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE p.prokind IN ('f','p') AND (n.oid IN (SELECT oid FROM schemas)
 OR EXISTS(SELECT 1 FROM pg_catalog.pg_event_trigger e WHERE e.evtfoid=p.oid))
), raw_acls(kind,obj,sub,acl) AS (
 SELECT 'routine',p.oid,0,COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner)) FROM routines p
 UNION ALL SELECT 'relation',c.oid,0,COALESCE(c.relacl,
   pg_catalog.acldefault(CASE WHEN c.relkind='S' THEN 'S'::"char" ELSE 'r'::"char" END,c.relowner)) FROM relations c
 UNION ALL SELECT 'column',a.attrelid,a.attnum::integer,a.attacl FROM pg_catalog.pg_attribute a
   JOIN relations c ON c.oid=a.attrelid WHERE a.attnum>0 AND NOT a.attisdropped
 UNION ALL SELECT 'schema',n.oid,0,COALESCE(n.nspacl,pg_catalog.acldefault('n',n.nspowner)) FROM schemas n
 UNION ALL SELECT 'default',d.oid,0,d.defaclacl FROM pg_catalog.pg_default_acl d
), acls AS (
 SELECT r.kind,r.obj,r.sub,pg_catalog.jsonb_agg(pg_catalog.jsonb_build_array(
   pg_catalog.pg_get_userbyid(a.grantor)::text,
   CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(a.grantee)::text END,
   a.privilege_type,a.is_grantable)
   ORDER BY pg_catalog.pg_get_userbyid(a.grantor)::text COLLATE "C",
   (CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(a.grantee)::text END) COLLATE "C",
   a.privilege_type COLLATE "C",a.is_grantable) value
 FROM raw_acls r CROSS JOIN LATERAL pg_catalog.aclexplode(
   CASE WHEN pg_catalog.cardinality(r.acl)>0 THEN r.acl ELSE NULL::aclitem[] END) a
 GROUP BY r.kind,r.obj,r.sub
), absence(name,ok) AS (
 SELECT 'no_basic_relations',NOT EXISTS(SELECT 1 FROM relations c WHERE
   (c.nspname='public' AND c.relname LIKE 'chat_basic_%') OR
   (c.nspname='jobmate_chat_private' AND c.relname='basic_attachment_release'))
 UNION ALL SELECT 'no_basic_routines',NOT EXISTS(SELECT 1 FROM routines p WHERE
   (p.nspname='public' AND p.proname LIKE '%chat%basic_v1') OR
   (p.nspname='jobmate_chat_private' AND p.proname IN ('basic_attachment_json','basic_attachment_writes_enabled')))
 UNION ALL SELECT 'no_basic_policies',NOT EXISTS(SELECT 1 FROM pg_catalog.pg_policies p
   WHERE p.policyname LIKE 'chat_basic_files_%' OR (p.schemaname='public' AND p.tablename='chat_basic_attachments'))
 UNION ALL SELECT 'no_basic_bucket',NOT EXISTS(SELECT 1 FROM storage.buckets WHERE id='jobmate-chat-basic-files')
 UNION ALL SELECT 'no_basic_binding_key',NOT EXISTS(SELECT 1 FROM pg_catalog.pg_constraint k
   WHERE k.conrelid=pg_catalog.to_regclass('public.chat_messages') AND k.conname='chat_messages_basic_attachment_binding_key')
), records(category,object_identity,fingerprint_or_value) AS (
 SELECT 'absence',name,CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END FROM absence
 UNION ALL SELECT 'schema',n.nspname::text,pg_catalog.md5(pg_catalog.jsonb_build_array(
   pg_catalog.pg_get_userbyid(n.nspowner),COALESCE(a.value,'[]'::jsonb))::text)
   FROM schemas n LEFT JOIN acls a ON a.kind='schema' AND a.obj=n.oid
 UNION ALL SELECT 'routine',p.oid::regprocedure::text,pg_catalog.md5(pg_catalog.jsonb_build_array(
   pg_catalog.pg_get_functiondef(p.oid),pg_catalog.pg_get_userbyid(p.proowner),COALESCE(a.value,'[]'::jsonb))::text)
   FROM routines p LEFT JOIN acls a ON a.kind='routine' AND a.obj=p.oid
 UNION ALL SELECT 'relation',pg_catalog.format('%I.%I',c.nspname,c.relname),pg_catalog.md5(pg_catalog.jsonb_build_array(
   c.relkind,pg_catalog.pg_get_userbyid(c.relowner),c.relrowsecurity,c.relforcerowsecurity,c.relreplident,c.reloptions,
   CASE WHEN c.relispartition THEN pg_catalog.pg_get_expr(c.relpartbound,c.oid) ELSE NULL END,
   COALESCE(a.value,'[]'::jsonb))::text) FROM relations c LEFT JOIN acls a ON a.kind='relation' AND a.obj=c.oid
 UNION ALL SELECT 'column',pg_catalog.jsonb_build_array(c.nspname,c.relname,a.attname)::text,
   pg_catalog.md5(pg_catalog.jsonb_build_array(a.attnum,pg_catalog.format_type(a.atttypid,a.atttypmod),a.attnotnull,
     a.attidentity,a.attgenerated,CASE WHEN a.attcollation=0 THEN NULL ELSE a.attcollation::regcollation::text END,
     pg_catalog.pg_get_expr(d.adbin,d.adrelid),
     COALESCE(acl.value,'[]'::jsonb))::text)
   FROM pg_catalog.pg_attribute a JOIN relations c ON c.oid=a.attrelid
   LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
   LEFT JOIN acls acl ON acl.kind='column' AND acl.obj=a.attrelid AND acl.sub=a.attnum
   WHERE a.attnum>0 AND NOT a.attisdropped
 UNION ALL SELECT 'constraint',pg_catalog.jsonb_build_array(c.nspname,c.relname,k.conname)::text,
   pg_catalog.md5(pg_catalog.jsonb_build_array(pg_catalog.pg_get_constraintdef(k.oid,false),k.convalidated,k.condeferrable,k.condeferred)::text)
   FROM pg_catalog.pg_constraint k JOIN relations c ON c.oid=k.conrelid
 UNION ALL SELECT CASE WHEN t.tgisinternal THEN 'internal_trigger' ELSE 'trigger' END,
   pg_catalog.jsonb_build_array(c.nspname,c.relname,t.tgname)::text,
   pg_catalog.md5(pg_catalog.jsonb_build_array(t.tgenabled,pg_catalog.pg_get_triggerdef(t.oid,false),
     pg_catalog.pg_get_functiondef(t.tgfoid))::text)
   FROM pg_catalog.pg_trigger t JOIN relations c ON c.oid=t.tgrelid
 UNION ALL SELECT 'policy',pg_catalog.jsonb_build_array(p.schemaname,p.tablename,p.policyname)::text,
   pg_catalog.md5(pg_catalog.jsonb_build_array(p.permissive,
     ARRAY(SELECT x::text FROM pg_catalog.unnest(p.roles) x ORDER BY x::text COLLATE "C"),p.cmd,p.qual,p.with_check)::text)
   FROM pg_catalog.pg_policies p WHERE p.schemaname IN (SELECT nspname FROM schemas)
 UNION ALL SELECT 'index',pg_catalog.format('%I.%I',i.schemaname,i.indexname),pg_catalog.md5(i.indexdef)
   FROM pg_catalog.pg_indexes i WHERE i.schemaname IN (SELECT nspname FROM schemas)
 UNION ALL SELECT 'view',pg_catalog.format('%I.%I',c.nspname,c.relname),pg_catalog.md5(pg_catalog.pg_get_viewdef(c.oid,false))
   FROM relations c WHERE c.relkind IN ('v','m')
 UNION ALL SELECT 'default_privilege',pg_catalog.jsonb_build_array(pg_catalog.pg_get_userbyid(d.defaclrole),
   COALESCE(n.nspname::text,'*'),d.defaclobjtype)::text,COALESCE(a.value,'[]'::jsonb)::text
   FROM pg_catalog.pg_default_acl d LEFT JOIN pg_catalog.pg_namespace n ON n.oid=d.defaclnamespace
   LEFT JOIN acls a ON a.kind='default' AND a.obj=d.oid
 UNION ALL SELECT 'enum',pg_catalog.format('%I.%I',n.nspname,t.typname),
   pg_catalog.jsonb_agg(e.enumlabel ORDER BY e.enumsortorder)::text
   FROM pg_catalog.pg_type t JOIN schemas n ON n.oid=t.typnamespace
   JOIN pg_catalog.pg_enum e ON e.enumtypid=t.oid GROUP BY n.nspname,t.typname
 UNION ALL SELECT 'publication',p.pubname::text,pg_catalog.jsonb_build_array(pg_catalog.pg_get_userbyid(p.pubowner),
   p.puballtables,p.pubinsert,p.pubupdate,p.pubdelete,p.pubtruncate,p.pubviaroot)::text FROM pg_catalog.pg_publication p
 UNION ALL SELECT 'publication_table',pg_catalog.jsonb_build_array(p.pubname,p.schemaname,p.tablename)::text,
   pg_catalog.jsonb_build_array(p.attnames,p.rowfilter)::text FROM pg_catalog.pg_publication_tables p
 UNION ALL SELECT 'event_hook',e.evtname::text,pg_catalog.jsonb_build_object('event',e.evtevent,'enabled',e.evtenabled,
   'tags',e.evttags,'owner',pg_catalog.pg_get_userbyid(e.evtowner),'handler',p.oid::regprocedure::text,
   'handler_owner',pg_catalog.pg_get_userbyid(p.proowner),'language',l.lanname,'security_definer',p.prosecdef,
   'config',p.proconfig,'kind',p.prokind,'inputs',p.pronargs,'returns_set',p.proretset,
   'returns',pg_catalog.pg_get_function_result(p.oid),'acl',COALESCE(a.value,'[]'::jsonb),
   'definition_md5',pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)))::text
   FROM pg_catalog.pg_event_trigger e JOIN routines p ON p.oid=e.evtfoid
   JOIN pg_catalog.pg_language l ON l.oid=p.prolang LEFT JOIN acls a ON a.kind='routine' AND a.obj=p.oid
 UNION ALL SELECT 'bucket',b.id,pg_catalog.jsonb_build_array(b.name,b.public,b.file_size_limit,b.allowed_mime_types)::text FROM storage.buckets b
 UNION ALL SELECT 'context','inspection',pg_catalog.jsonb_build_object('role',current_user,'database',pg_catalog.current_database(),
   'version',pg_catalog.current_setting('server_version'),'search_path',pg_catalog.current_setting('search_path'),
   'replication_role',pg_catalog.current_setting('session_replication_role'))::text
), assembled AS (
 SELECT pg_catalog.count(*) record_count,pg_catalog.count(DISTINCT(category,object_identity)) unique_key_count,
   pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('category',category,'object_identity',object_identity,
     'fingerprint_or_value',fingerprint_or_value) ORDER BY category COLLATE "C",object_identity COLLATE "C") baseline
 FROM records
)
SELECT record_count,unique_key_count,pg_catalog.md5(baseline::text) baseline_md5,
 (SELECT pg_catalog.jsonb_object_agg(name,CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END) FROM absence) absence_checks,
 (SELECT pg_catalog.jsonb_object_agg(category,n) FROM (SELECT category,pg_catalog.count(*) n FROM records GROUP BY category) counts) category_counts,
 baseline FROM assembled;

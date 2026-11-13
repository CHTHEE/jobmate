-- READ ONLY. Verify installed disabled r1 deployment only; not a post-rollback query.
BEGIN READ ONLY;
DO $attachment_catalog_assertions$
DECLARE f record; owner_oid oid; v_metadata oid; v_release oid;
BEGIN
 SELECT p.oid INTO owner_oid FROM pg_catalog.pg_roles p WHERE p.rolname='postgres';
 -- Resolve these objects only when this DO executes, after the CREATE statements.
 v_metadata := pg_catalog.to_regclass('public.chat_basic_attachments');
 v_release := pg_catalog.to_regclass('jobmate_chat_private.basic_attachment_release');
 IF v_metadata IS NULL OR v_release IS NULL THEN
   RAISE EXCEPTION 'Basic attachment DDL is not visible at post-DDL assertions; stop, never create missing objects manually.' USING ERRCODE='55000';
 END IF;
 IF (SELECT pg_catalog.count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('get_chat_attachment_basic_v1','reserve_chat_attachment_basic_v1',
     'prepare_chat_attachment_upload_basic_v1','prepare_chat_attachment_validation_basic_v1','finish_chat_attachment_validation_basic_v1',
     'send_chat_attachment_basic_v1','list_chat_messages_basic_v1','list_pending_chat_attachments_basic_v1',
     'claim_expired_chat_attachments_basic_v1','complete_chat_attachment_cleanup_basic_v1'))<>10
 THEN RAISE EXCEPTION 'Exact basic-v1 RPC inventory mismatch'; END IF;
 IF (SELECT pg_catalog.count(*) FROM jobmate_chat_private.basic_attachment_release WHERE singleton AND NOT enabled
   AND trial_conversation IS NULL AND pg_catalog.cardinality(participant_ids)=0)<>1
   OR pg_catalog.has_table_privilege('authenticated',v_release,'SELECT,INSERT,UPDATE,DELETE,MAINTAIN')
   OR pg_catalog.has_table_privilege('service_role',v_release,'SELECT,INSERT,UPDATE,DELETE,MAINTAIN')
 THEN RAISE EXCEPTION 'Backend release gate must be owner-only and disabled'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_class c WHERE c.oid=v_metadata
   AND c.relrowsecurity AND c.relowner=owner_oid) THEN RAISE EXCEPTION 'Metadata RLS/owner mismatch'; END IF;
 IF NOT EXISTS(SELECT 1 FROM storage.buckets WHERE id='jobmate-chat-basic-files' AND NOT public
   AND file_size_limit=5242880) THEN RAISE EXCEPTION 'Private bucket mismatch'; END IF;
 IF pg_catalog.has_table_privilege('authenticated',v_metadata,'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
   OR pg_catalog.has_table_privilege('anon',v_metadata,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
   OR pg_catalog.has_table_privilege('service_role',v_metadata,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
 THEN RAISE EXCEPTION 'Unexpected direct metadata privileges'; END IF;
 FOR f IN SELECT p.* FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('get_chat_attachment_basic_v1','reserve_chat_attachment_basic_v1',
     'prepare_chat_attachment_upload_basic_v1','prepare_chat_attachment_validation_basic_v1','finish_chat_attachment_validation_basic_v1',
     'send_chat_attachment_basic_v1','list_chat_messages_basic_v1','list_pending_chat_attachments_basic_v1',
     'claim_expired_chat_attachments_basic_v1','complete_chat_attachment_cleanup_basic_v1') LOOP
   IF f.proowner<>owner_oid OR NOT f.prosecdef OR f.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
     OR EXISTS(SELECT 1 FROM pg_catalog.aclexplode(CASE WHEN pg_catalog.cardinality(f.proacl)>0 THEN f.proacl ELSE NULL::aclitem[] END) a
       WHERE a.grantee=0 OR a.is_grantable) THEN RAISE EXCEPTION 'Routine security mismatch %',f.proname; END IF;
   IF pg_catalog.has_function_privilege('anon',f.oid,'EXECUTE') THEN RAISE EXCEPTION 'Anonymous RPC access'; END IF;
   IF f.proname IN ('finish_chat_attachment_validation_basic_v1','claim_expired_chat_attachments_basic_v1','complete_chat_attachment_cleanup_basic_v1') THEN
     IF pg_catalog.has_function_privilege('authenticated',f.oid,'EXECUTE') OR NOT pg_catalog.has_function_privilege('service_role',f.oid,'EXECUTE')
       THEN RAISE EXCEPTION 'Trusted validationner/cleanup ACL mismatch'; END IF;
   ELSIF NOT pg_catalog.has_function_privilege('authenticated',f.oid,'EXECUTE') OR pg_catalog.has_function_privilege('service_role',f.oid,'EXECUTE')
     THEN RAISE EXCEPTION 'Participant RPC ACL mismatch'; END IF;
 END LOOP;
 IF (SELECT pg_catalog.count(*) FROM pg_catalog.pg_policies WHERE schemaname='storage'
   AND policyname IN ('chat_basic_files_client_insert_deny','chat_basic_files_client_update_deny','chat_basic_files_client_delete_deny',
     'chat_basic_files_read_boundary','chat_basic_files_anon_read_deny') AND permissive='RESTRICTIVE')<>5
 THEN RAISE EXCEPTION 'Restrictive Storage boundary missing'; END IF;
END;
$attachment_catalog_assertions$;
SELECT 'CHAT_ATTACHMENTS_DISABLED_DEPLOYMENT_CATALOG_VERIFIED' AS validation_result,
 pg_catalog.pg_backend_pid() AS validation_pid,
 pg_catalog.clock_timestamp() AS observed_at,
 pg_catalog.current_setting('transaction_isolation') AS isolation,
 pg_catalog.jsonb_build_object(
 'bucket',(SELECT pg_catalog.jsonb_build_object('id',id,'public',public,'max_bytes',file_size_limit,'mime_types',allowed_mime_types)
   FROM storage.buckets WHERE id='jobmate-chat-basic-files'),
 'columns',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY ordinal_position)
   FROM information_schema.columns c WHERE table_schema='public' AND table_name='chat_basic_attachments'),
 'constraints',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('table',conrelid::regclass::text,
   'name',conname,'definition',pg_catalog.pg_get_constraintdef(oid,false)) ORDER BY conname)
   FROM pg_catalog.pg_constraint WHERE conrelid IN (pg_catalog.to_regclass('public.chat_basic_attachments'),
     pg_catalog.to_regclass('jobmate_chat_private.basic_attachment_release')) OR
     (conrelid=pg_catalog.to_regclass('public.chat_messages') AND conname='chat_messages_basic_attachment_binding_key')),
 'policies',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY schemaname,tablename,policyname)
   FROM pg_catalog.pg_policies p WHERE (schemaname='public' AND tablename='chat_basic_attachments') OR
     (schemaname='storage' AND policyname LIKE 'chat_basic_files_%'))
 ) AS attachment_trial_catalogue;
ROLLBACK;

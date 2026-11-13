// Local source generation only. Never connects to a database.
import { readFileSync, writeFileSync } from 'node:fs';
const root = new URL('../../', import.meta.url);
const original = readFileSync(new URL('supabase/diagnostics/chat_phase2_rollback_validation_candidate.sql',root),'utf8').replaceAll('\r\n','\n');
const hooks = original.slice(original.indexOf('  -- User-supplied reviewed PostgreSQL'),original.indexOf('\nEND;\n$chat_validation_safety$;'));
const diagnostic = readFileSync(new URL('supabase/candidates/chat_phase6b_readonly_preflight.sql',root),'utf8').replaceAll('\r\n','\n');
const routineCte = diagnostic.slice(diagnostic.indexOf('WITH routines AS ('),diagnostic.indexOf('\nSELECT current_user'));
const file = new URL('supabase/candidates/chat_phase6b_attachment_foundation.sql',root);
let sql = readFileSync(file,'utf8').replaceAll('\r\n','\n');
const begin = '-- BEGIN PINNED ATTACHMENT PREFLIGHT\n', end = '-- END PINNED ATTACHMENT PREFLIGHT\n';
if(sql.includes(begin)) sql = sql.slice(0,sql.indexOf(begin))+sql.slice(sql.indexOf(end)+end.length);
sql = sql.replace(/\n+(?=-- CREATE and bucket PK deliberately reject collisions\. Never replace text SQL\.)/,'\n\n');
const preflight = `${begin}DO $attachment_preflight$\nDECLARE v_hook_drift text; v_backend_md5 text; v_count bigint;\nBEGIN
 IF current_user<>'postgres' OR pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
   RAISE EXCEPTION 'Reviewed postgres/READ COMMITTED required.'; END IF;
 IF pg_catalog.to_regclass('public.chat_attachments') IS NOT NULL OR EXISTS (
   SELECT 1 FROM storage.buckets WHERE id='jobmate-chat-files') OR EXISTS (
   SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('get_chat_attachment_v2','reserve_chat_attachment_v2',
     'prepare_chat_attachment_upload_v2','prepare_chat_attachment_scan_v2','finish_chat_attachment_scan_v2',
     'send_chat_attachment_v2','list_chat_messages_v2','list_pending_chat_attachments_v2',
     'claim_expired_chat_attachments_v2','complete_chat_attachment_cleanup_v2')) THEN
   RAISE EXCEPTION 'Attachment object collision; never replace unknown objects.'; END IF;
 IF pg_catalog.to_regprocedure('public.send_chat_message(uuid,uuid,text)') IS NULL
   OR pg_catalog.to_regprocedure('jobmate_chat_private.lock_application(uuid,boolean)') IS NULL THEN
   RAISE EXCEPTION 'Deployed Chat baseline unavailable.'; END IF;
 ${routineCte}
 SELECT pg_catalog.count(*),pg_catalog.md5(pg_catalog.jsonb_agg(value ORDER BY signature COLLATE "C")::text)
 INTO v_count,v_backend_md5 FROM normalized;
 IF v_count<>10 OR pg_catalog.current_setting('jobmate.chat_reviewed_backend_md5',true) IS DISTINCT FROM v_backend_md5 THEN
   RAISE EXCEPTION 'Reviewed Chat routine fingerprint missing/different; preserve and review fresh read-only baseline first.'; END IF;
${hooks}\nEND;\n$attachment_preflight$;\n${end}\n`;
sql=sql.replace('-- CREATE and bucket PK deliberately reject collisions. Never replace text SQL.',preflight+'-- CREATE and bucket PK deliberately reject collisions. Never replace text SQL.');
writeFileSync(file,sql);
const assertions = `
DO $attachment_catalog_assertions$
DECLARE f record; owner_oid oid;
BEGIN
 SELECT p.oid INTO owner_oid FROM pg_catalog.pg_roles p WHERE p.rolname='postgres';
 IF (SELECT pg_catalog.count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('get_chat_attachment_v2','reserve_chat_attachment_v2',
     'prepare_chat_attachment_upload_v2','prepare_chat_attachment_scan_v2','finish_chat_attachment_scan_v2',
     'send_chat_attachment_v2','list_chat_messages_v2','list_pending_chat_attachments_v2',
     'claim_expired_chat_attachments_v2','complete_chat_attachment_cleanup_v2'))<>10
 THEN RAISE EXCEPTION 'Exact v2 RPC inventory mismatch'; END IF;
 IF (SELECT pg_catalog.count(*) FROM jobmate_chat_private.attachment_release WHERE singleton AND NOT enabled
   AND trial_conversation IS NULL AND pg_catalog.cardinality(participant_ids)=0)<>1
   OR pg_catalog.has_table_privilege('authenticated','jobmate_chat_private.attachment_release','SELECT,INSERT,UPDATE,DELETE,MAINTAIN')
   OR pg_catalog.has_table_privilege('service_role','jobmate_chat_private.attachment_release','SELECT,INSERT,UPDATE,DELETE,MAINTAIN')
 THEN RAISE EXCEPTION 'Backend release gate must be owner-only and disabled'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_class c WHERE c.oid='public.chat_attachments'::regclass
   AND c.relrowsecurity AND c.relowner=owner_oid) THEN RAISE EXCEPTION 'Metadata RLS/owner mismatch'; END IF;
 IF NOT EXISTS(SELECT 1 FROM storage.buckets WHERE id='jobmate-chat-files' AND NOT public
   AND file_size_limit=10485760) THEN RAISE EXCEPTION 'Private bucket mismatch'; END IF;
 IF pg_catalog.has_table_privilege('authenticated','public.chat_attachments','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
   OR pg_catalog.has_table_privilege('anon','public.chat_attachments','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
   OR pg_catalog.has_table_privilege('service_role','public.chat_attachments','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
 THEN RAISE EXCEPTION 'Unexpected direct metadata privileges'; END IF;
 FOR f IN SELECT p.* FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('get_chat_attachment_v2','reserve_chat_attachment_v2',
     'prepare_chat_attachment_upload_v2','prepare_chat_attachment_scan_v2','finish_chat_attachment_scan_v2',
     'send_chat_attachment_v2','list_chat_messages_v2','list_pending_chat_attachments_v2',
     'claim_expired_chat_attachments_v2','complete_chat_attachment_cleanup_v2') LOOP
   IF f.proowner<>owner_oid OR NOT f.prosecdef OR f.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
     OR EXISTS(SELECT 1 FROM pg_catalog.aclexplode(CASE WHEN pg_catalog.cardinality(f.proacl)>0 THEN f.proacl ELSE NULL::aclitem[] END) a
       WHERE a.grantee=0 OR a.is_grantable) THEN RAISE EXCEPTION 'Routine security mismatch %',f.proname; END IF;
   IF pg_catalog.has_function_privilege('anon',f.oid,'EXECUTE') THEN RAISE EXCEPTION 'Anonymous RPC access'; END IF;
   IF f.proname IN ('finish_chat_attachment_scan_v2','claim_expired_chat_attachments_v2','complete_chat_attachment_cleanup_v2') THEN
     IF pg_catalog.has_function_privilege('authenticated',f.oid,'EXECUTE') OR NOT pg_catalog.has_function_privilege('service_role',f.oid,'EXECUTE')
       THEN RAISE EXCEPTION 'Trusted scanner/cleanup ACL mismatch'; END IF;
   ELSIF NOT pg_catalog.has_function_privilege('authenticated',f.oid,'EXECUTE') OR pg_catalog.has_function_privilege('service_role',f.oid,'EXECUTE')
     THEN RAISE EXCEPTION 'Participant RPC ACL mismatch'; END IF;
 END LOOP;
 IF (SELECT pg_catalog.count(*) FROM pg_catalog.pg_policies WHERE schemaname='storage'
   AND policyname IN ('chat_files_client_insert_deny','chat_files_client_update_deny','chat_files_client_delete_deny',
     'chat_files_read_boundary','chat_files_anon_read_deny') AND permissive='RESTRICTIVE')<>5
 THEN RAISE EXCEPTION 'Restrictive Storage boundary missing'; END IF;
END;
$attachment_catalog_assertions$;
SELECT 'CHAT_ATTACHMENTS_CATALOG_ASSERTIONS_PASSED_ROLLBACK_PENDING' AS validation_result;
ROLLBACK;
`;
writeFileSync(new URL('supabase/candidates/chat_phase6b_rollback_validation_candidate.sql',root),
  '-- GENERATED by tools/chat_scanner/prepare_sql.mjs; same migration body and approval guard.\n'+sql.replace(/COMMIT;\s*$/,assertions));
writeFileSync(new URL('supabase/candidates/chat_phase6b_catalog_verification.sql',root),
  '-- READ ONLY. Post-deployment verification before enabling any attachment flags.\nBEGIN READ ONLY;\n'+
    assertions.replace('CHAT_ATTACHMENTS_CATALOG_ASSERTIONS_PASSED_ROLLBACK_PENDING','CHAT_ATTACHMENTS_DISABLED_DEPLOYMENT_CATALOG_VERIFIED'));

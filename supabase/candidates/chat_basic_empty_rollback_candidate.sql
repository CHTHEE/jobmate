-- BASIC UNIVERSITY DEMO ONLY. Content/type validation is NOT antivirus.
-- Guarded recovery for an EMPTY attachment deployment only. Never deletes files.
-- Populated deployments require forward repair / retention decision, not this SQL.
BEGIN;
DO $attachment_rollback_approval$ BEGIN
 RAISE EXCEPTION 'BLOCKED: separate CH/KZ rollback approval and current catalogue review required';
END; $attachment_rollback_approval$;
DO $empty_only$ BEGIN
 IF current_user<>'postgres' OR EXISTS(SELECT 1 FROM public.chat_basic_attachments)
   OR EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='jobmate-chat-basic-files') THEN
   RAISE EXCEPTION 'Rollback requires reviewed owner and no metadata or object bytes'; END IF;
END; $empty_only$;
DROP POLICY chat_basic_files_client_insert_deny ON storage.objects;
DROP POLICY chat_basic_files_client_update_deny ON storage.objects;
DROP POLICY chat_basic_files_client_delete_deny ON storage.objects;
DROP POLICY chat_basic_files_read_boundary ON storage.objects;
DROP POLICY chat_basic_files_anon_read_deny ON storage.objects;
DROP POLICY chat_basic_files_participant_read ON storage.objects;
DROP FUNCTION public.list_chat_messages_basic_v1(uuid,integer,bigint);
DROP FUNCTION public.list_pending_chat_attachments_basic_v1(uuid);
DROP FUNCTION public.send_chat_attachment_basic_v1(uuid);
DROP FUNCTION public.prepare_chat_attachment_upload_basic_v1(uuid);
DROP FUNCTION public.prepare_chat_attachment_validation_basic_v1(uuid);
DROP FUNCTION public.reserve_chat_attachment_basic_v1(uuid,uuid,uuid,text,text,bigint,text,text);
DROP FUNCTION public.get_chat_attachment_basic_v1(uuid);
DROP FUNCTION public.finish_chat_attachment_validation_basic_v1(uuid,uuid,text,text,text,bigint,text);
DROP FUNCTION public.claim_expired_chat_attachments_basic_v1();
DROP FUNCTION public.complete_chat_attachment_cleanup_basic_v1(uuid);
DROP FUNCTION jobmate_chat_private.basic_attachment_json(public.chat_basic_attachments);
DROP TABLE public.chat_basic_attachments;
DROP FUNCTION jobmate_chat_private.basic_attachment_writes_enabled(uuid);
DROP TABLE jobmate_chat_private.basic_attachment_release;
ALTER TABLE public.chat_messages DROP CONSTRAINT chat_messages_basic_attachment_binding_key;
DELETE FROM storage.buckets WHERE id='jobmate-chat-basic-files';
COMMIT;

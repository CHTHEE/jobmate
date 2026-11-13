-- READ ONLY: CH runs as postgres in the existing project SQL Editor.
-- Scoped to the reported QA participant/conversation. No mutation RPCs,
-- file bytes, filenames, hashes, storage paths, credentials or lease tokens.
WITH candidates AS (
  SELECT a.*
  FROM public.chat_basic_attachments a
  WHERE a.sender_id = 'fb66cc74-1a4f-44e0-ae4f-6831c7a39b8f'::uuid
    AND a.conversation_id = 'e08aee68-59d5-40eb-aaf8-bc5676d19f7f'::uuid
    AND a.created_at >= '2026-11-13 14:24:21+00'::timestamptz
    AND a.created_at <= '2026-11-13 15:25:21+00'::timestamptz
  ORDER BY a.created_at DESC
  LIMIT 8
), routines AS (
  SELECT p.*
  FROM pg_catalog.pg_proc p
  WHERE p.oid IN (
    pg_catalog.to_regprocedure('public.prepare_chat_attachment_validation_basic_v1(uuid)'),
    pg_catalog.to_regprocedure('public.finish_chat_attachment_validation_basic_v1(uuid,uuid,text,text,text,bigint,text)')
  )
)
SELECT pg_catalog.jsonb_build_object(
  'observed_at',pg_catalog.clock_timestamp(),
  'reservations',COALESCE((SELECT pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'attachment_id',a.attachment_id,'client_request_id',a.client_request_id,
      'state',a.state,'size_bytes',a.size_bytes,'mime_type',a.mime_type,
      'created_at',a.created_at,'expired',a.expires_at<=pg_catalog.clock_timestamp(),
      'upload_attempts',a.upload_attempts,'validation_attempts',a.validation_attempts,
      'validation_lease_active',a.validation_lease_until>pg_catalog.clock_timestamp(),
      'validated_at',a.validated_at,'validator_version',a.validator_version,
      'message_linked',a.message_id IS NOT NULL,'cleanup_done',a.cleanup_done,
      'first_chunk_catalogued',EXISTS(SELECT 1 FROM storage.objects o
        WHERE o.bucket_id='jobmate-chat-basic-files'
          AND o.name=pg_catalog.left(a.storage_path,pg_catalog.length(a.storage_path)-4)||'part.0'),
      'final_file_catalogued',EXISTS(SELECT 1 FROM storage.objects o
        WHERE o.bucket_id='jobmate-chat-basic-files' AND o.name=a.storage_path)
    ) ORDER BY a.created_at DESC) FROM candidates a),'[]'::jsonb),
  'validation_rpc_metadata',COALESCE((SELECT pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'signature',p.oid::regprocedure::text,
      'return_type',pg_catalog.format_type(p.prorettype,NULL),
      'definition_md5',pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)),
      'service_execute',pg_catalog.has_function_privilege('service_role',p.oid,'EXECUTE'),
      'authenticated_execute',pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
    ) ORDER BY p.proname) FROM routines p),'[]'::jsonb)
) AS validation_failure_inspection;

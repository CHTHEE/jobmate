-- ISOLATED DATABASE ONLY. Requires the candidate installed in that isolated DB
-- and existing authorized fixture actors/application; creates no accounts.
-- No real scanner is represented by the trusted SQL verdict used below.
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='15s';
DO $isolated_test_guard$ BEGIN
 RAISE EXCEPTION 'BLOCKED: isolated fixture review and explicit test approval required; never run on the shared production project';
END; $isolated_test_guard$;
-- Reviewer supplies transaction-local jobmate.test.conversation and .seeker
-- from an isolated fixture, not production UUIDs. No defaults are provided.
UPDATE jobmate_chat_private.attachment_release SET enabled=true,
 trial_conversation=pg_catalog.current_setting('jobmate.test.conversation')::uuid,
 participant_ids=ARRAY[pg_catalog.current_setting('jobmate.test.seeker')::uuid,
   pg_catalog.current_setting('jobmate.test.employer')::uuid] WHERE singleton;
SELECT pg_catalog.set_config('request.jwt.claim.sub',pg_catalog.current_setting('jobmate.test.seeker'),true);
SELECT pg_catalog.set_config('jobmate.test.attachment',pg_catalog.gen_random_uuid()::text,true);
SELECT pg_catalog.set_config('jobmate.test.request',pg_catalog.gen_random_uuid()::text,true);
SET LOCAL ROLE authenticated;
DO $participant_tests$
DECLARE c uuid:=pg_catalog.current_setting('jobmate.test.conversation')::uuid;
 a uuid:=pg_catalog.current_setting('jobmate.test.attachment')::uuid;
 r uuid:=pg_catalog.current_setting('jobmate.test.request')::uuid; first jsonb; replay jsonb;
BEGIN
 first:=public.reserve_chat_attachment_v2(c,r,a,'test.pdf','application/pdf',100,pg_catalog.repeat('a',64),NULL);
 replay:=public.reserve_chat_attachment_v2(c,r,a,'test.pdf','application/pdf',100,pg_catalog.repeat('a',64),NULL);
 IF first IS DISTINCT FROM replay OR first->>'state'<>'pending' THEN RAISE EXCEPTION 'Reservation/replay mismatch'; END IF;
 BEGIN
  PERFORM public.reserve_chat_attachment_v2(c,r,a,'test.pdf','application/pdf',100,pg_catalog.repeat('b',64),NULL);
  RAISE EXCEPTION 'Changed request accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.send_chat_attachment_v2(a); RAISE EXCEPTION 'Pending send accepted';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
 BEGIN
  PERFORM public.finish_chat_attachment_scan_v2(a,pg_catalog.gen_random_uuid(),'approved',pg_catalog.repeat('a',64),'application/pdf',100,'MOCK');
  RAISE EXCEPTION 'Participant approved own scan';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 IF EXISTS(SELECT 1 FROM public.chat_attachments WHERE attachment_id=a) THEN RAISE EXCEPTION 'Pending metadata exposed by direct SELECT'; END IF;
 IF EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='jobmate-chat-files') THEN RAISE EXCEPTION 'Quarantine exposed'; END IF;
 PERFORM public.prepare_chat_attachment_scan_v2(a);
END; $participant_tests$;
RESET ROLE;
-- Trusted test-only verdict, no Storage bytes / malware scan implied. Exercise
-- SQL state/idempotency/notifications independently of the real worker tests.
DO $trusted_fixture$
DECLARE a uuid:=pg_catalog.current_setting('jobmate.test.attachment')::uuid; token uuid;
BEGIN
 SELECT scan_token INTO token FROM public.chat_attachments WHERE attachment_id=a;
 PERFORM public.finish_chat_attachment_scan_v2(a,token,'approved',pg_catalog.repeat('a',64),'application/pdf',100,'ISOLATED_SQL_MOCK_NOT_AV');
END; $trusted_fixture$;
SET LOCAL ROLE authenticated;
DO $committed_tests$
DECLARE a uuid:=pg_catalog.current_setting('jobmate.test.attachment')::uuid; first jsonb; replay jsonb;
BEGIN
 first:=public.send_chat_attachment_v2(a); replay:=public.send_chat_attachment_v2(a);
 IF first IS DISTINCT FROM replay OR first->'attachment'->>'caption' IS NOT NULL
   OR first->'attachment'->>'state'<>'committed' THEN RAISE EXCEPTION 'Attachment-only replay mismatch'; END IF;
 IF (SELECT pg_catalog.count(*) FROM public.chat_messages WHERE message_id=(first->>'message_id')::uuid)<>1
 THEN RAISE EXCEPTION 'Duplicate message'; END IF;
END; $committed_tests$;
RESET ROLE;
-- Mandatory extension cases before deployment (not claimed by this script):
-- repeat with Employer, foreign seeker/employer/Admin/suspended/revoked actor;
-- signed URL pending/rejected/expired and committed access through Storage HTTP;
-- restriction changes, caption conflicts, text UUID collision and partial upload;
-- concurrent reserve/send/scan/cleanup; exact notification count for both replay
-- directions; actual worker clean/malware/timeout fixtures in the isolated project.
SELECT 'CHAT_ATTACHMENT_ISOLATED_SQL_TESTS_PASSED_ROLLBACK_PENDING' AS result;
ROLLBACK;

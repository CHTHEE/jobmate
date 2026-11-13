// Preserve every originally reviewed artifact. Generate GUARDED r1 sources only.
// No execution copy, database access, fixture, installation or network.
import { readFileSync,writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
const root=new URL('../../',import.meta.url),read=p=>readFileSync(new URL(p,root));
const sha=b=>createHash('sha256').update(b).digest('hex');
const original=JSON.parse(read('docs/chat_basic_attachment_hashes.json'));
for(const [path,hash] of Object.entries(original.files)) assert.equal(sha(read(path)),hash,path);
const migration=read('supabase/candidates/chat_basic_attachment_migration.sql');
const trial=read('supabase/candidates/chat_basic_rollback_validation_candidate.sql').toString('utf8');
const nl=trial.includes('\r\n')?'\r\n':'\n';
const normalize=s=>s.replace(/\r?\n/g,nl);
const beforeAssertions=trial.slice(0,trial.indexOf('DO $attachment_catalog_assertions$'));
const oldAssertions=trial.slice(trial.indexOf('DO $attachment_catalog_assertions$'),trial.indexOf("SELECT 'CHAT_ATTACHMENTS_CATALOG_ASSERTIONS_PASSED_ROLLBACK_PENDING'"));
assert.ok(oldAssertions.endsWith('$attachment_catalog_assertions$;'+nl));
let assertions=oldAssertions.replace('DECLARE f record; owner_oid oid;',
 'DECLARE f record; owner_oid oid; v_metadata oid; v_release oid;');
const owner=" SELECT p.oid INTO owner_oid FROM pg_catalog.pg_roles p WHERE p.rolname='postgres';";
assert.equal(assertions.split(owner).length,2);
assertions=assertions.replace(owner,owner+normalize(`
 -- Resolve these objects only when this DO executes, after the CREATE statements.
 v_metadata := pg_catalog.to_regclass('public.chat_basic_attachments');
 v_release := pg_catalog.to_regclass('jobmate_chat_private.basic_attachment_release');
 IF v_metadata IS NULL OR v_release IS NULL THEN
   RAISE EXCEPTION 'Basic attachment DDL is not visible at post-DDL assertions; stop, never create missing objects manually.' USING ERRCODE='55000';
 END IF;`));
assertions=assertions.replaceAll("'public.chat_basic_attachments'::regclass",'v_metadata');
assertions=assertions.replaceAll("pg_catalog.has_table_privilege('authenticated','public.chat_basic_attachments',", "pg_catalog.has_table_privilege('authenticated',v_metadata,")
 .replaceAll("pg_catalog.has_table_privilege('anon','public.chat_basic_attachments',", "pg_catalog.has_table_privilege('anon',v_metadata,")
 .replaceAll("pg_catalog.has_table_privilege('service_role','public.chat_basic_attachments',", "pg_catalog.has_table_privilege('service_role',v_metadata,")
 .replaceAll("pg_catalog.has_table_privilege('authenticated','jobmate_chat_private.basic_attachment_release',", "pg_catalog.has_table_privilege('authenticated',v_release,")
 .replaceAll("pg_catalog.has_table_privilege('service_role','jobmate_chat_private.basic_attachment_release',", "pg_catalog.has_table_privilege('service_role',v_release,");
// Snapshot is deliberately at runtime and returned WITH the last marker row:
// pg-meta commonly exposes only the last nonempty result of a multi-command batch.
const result=normalize(`SELECT 'CHAT_ATTACHMENTS_CATALOG_ASSERTIONS_PASSED_ROLLBACK_PENDING' AS validation_result,
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
`);
// Exact same permanent migration bytes: its DDL ordering is already correct and
// it has no added top-level regclass snapshot. No business/schema changes.
writeFileSync(new URL('supabase/candidates/chat_basic_attachment_migration_r1.sql',root),migration);
writeFileSync(new URL('supabase/candidates/chat_basic_rollback_validation_r1_candidate.sql',root),beforeAssertions+assertions+result);
writeFileSync(new URL('supabase/candidates/chat_basic_catalog_verification_r1.sql',root),
 normalize('-- READ ONLY. Verify installed disabled r1 deployment only; not a post-rollback query.\nBEGIN READ ONLY;\n')+assertions+
 result.replace('CHAT_ATTACHMENTS_CATALOG_ASSERTIONS_PASSED_ROLLBACK_PENDING','CHAT_ATTACHMENTS_DISABLED_DEPLOYMENT_CATALOG_VERIFIED'));
const files=[
 'supabase/candidates/chat_basic_attachment_migration_r1.sql','supabase/candidates/chat_basic_rollback_validation_r1_candidate.sql',
 'supabase/candidates/chat_basic_catalog_verification_r1.sql',
 'supabase/candidates/chat_basic_security_tests.sql','supabase/candidates/chat_basic_empty_rollback_candidate.sql',
 'supabase/functions/chat-basic-attachments/index.ts','supabase/functions/_shared/chat_basic/protocol.mjs','supabase/functions/_shared/chat_basic/validate.mjs',
].sort();
const hashes=Object.fromEntries(files.map(path=>[path,sha(read(path))]));
writeFileSync(new URL('docs/chat_basic_attachment_r1_hashes.json',root),JSON.stringify({
 backend_bundle_sha256:sha(JSON.stringify(hashes)),supersedes_failed_bundle:original.backend_bundle_sha256,files:hashes,
},null,2)+'\n');
for(const [path,hash] of Object.entries(original.files)) assert.equal(sha(read(path)),hash,path);
console.log('Prepared guarded r1 candidates only. Original reviewed artifacts unchanged; no unguarded copy or SQL execution.');

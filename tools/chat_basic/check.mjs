import { readFileSync,writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
const root=new URL('../../',import.meta.url),read=p=>readFileSync(new URL(p,root),'utf8').replaceAll('\r\n','\n');
const sha=p=>createHash('sha256').update(readFileSync(new URL(p,root))).digest('hex');
const future=JSON.parse(read('docs/chat_phase6b_artifact_hashes.json'));
for(const [path,hash] of Object.entries(future.files)) assert.equal(sha(path),hash,`Future scanner artifact changed: ${path}`);
const sql=read('supabase/candidates/chat_basic_attachment_migration.sql');
const rollback=read('supabase/candidates/chat_basic_rollback_validation_candidate.sql');
assert.ok(rollback.includes(sql.slice(sql.indexOf('BEGIN ISOLATION LEVEL')).replace(/COMMIT;\s*$/,'')),'exact guarded basic migration body equality');
assert.ok(rollback.trimEnd().endsWith('ROLLBACK;'));
assert.ok(sql.includes("RAISE EXCEPTION 'CHAT ATTACHMENTS BLOCKED:"));
assert.ok(sql.includes('enabled boolean NOT NULL DEFAULT false'));
assert.ok(sql.includes('auth.uid()=ANY(s.participant_ids)'));
assert.equal((sql.match(/CREATE FUNCTION public\./g)??[]).length,10);
assert.equal((sql.match(/SECURITY DEFINER SET search_path = ''/g)??[]).length,11);
assert.equal((sql.match(/RESTRICTIVE/g)??[]).length,5);
assert.ok(!/\bapproved\b|\bscanning\b|\bscan_token\b|10485760|application\/msword|application\/vnd.ms-excel|_v2/.test(sql.replace(/--[^\n]*/g,'')));
assert.ok(sql.includes('basic-type-validation-no-antivirus-v1'));
assert.ok(sql.includes('size_bytes BETWEEN 1 AND 5242880'));
assert.ok(sql.includes('public.send_chat_message(a.conversation_id,a.client_request_id,'));
assert.ok(sql.includes('FOR UPDATE SKIP LOCKED'));
const dart=read('lib/features/chat/chat_attachments.dart');
for(const match of dart.matchAll(/_rpc\('([^']+)'/g)) assert.ok(sql.includes(`CREATE FUNCTION public.${match[1]}(`),`RPC mismatch ${match[1]}`);
const protocol=read('supabase/functions/_shared/chat_basic/protocol.mjs');
for(const match of protocol.matchAll(/(?:userRpc\(request, |serviceRpc\()'([^']+)'/g)) assert.ok(sql.includes(`CREATE FUNCTION public.${match[1]}(`),`Edge RPC mismatch ${match[1]}`);
const entry=read('supabase/functions/chat-basic-attachments/index.ts');
assert.ok(!/CHAT_SCANNER|fetch\(scanner|clamScanner|MOCK/.test(entry));
assert.ok(entry.includes('validateFile(bytes, row.original_name, row.mime_type)'));
const original=read('supabase/diagnostics/chat_phase2_rollback_validation_candidate.sql');
const hooks=original.slice(original.indexOf('  -- User-supplied reviewed PostgreSQL'),original.indexOf('\nEND;\n$chat_validation_safety$;'));
assert.ok(sql.includes(hooks),'exact six-hook baseline unchanged');
const baseline=read('supabase/candidates/chat_phase6b_readonly_preflight.sql');
assert.ok(sql.includes(baseline.slice(baseline.indexOf('WITH routines AS ('),baseline.indexOf('\nSELECT current_user'))),'shared original routine fingerprint query');
const files=[
 'supabase/candidates/chat_basic_attachment_migration.sql','supabase/candidates/chat_basic_rollback_validation_candidate.sql',
 'supabase/candidates/chat_basic_security_tests.sql','supabase/candidates/chat_basic_empty_rollback_candidate.sql','supabase/candidates/chat_basic_catalog_verification.sql',
 'supabase/functions/chat-basic-attachments/index.ts','supabase/functions/_shared/chat_basic/protocol.mjs','supabase/functions/_shared/chat_basic/validate.mjs',
].sort();
const hashes=Object.fromEntries(files.map(p=>[p,sha(p)]));
writeFileSync(new URL('docs/chat_basic_attachment_hashes.json',root),JSON.stringify({backend_bundle_sha256:createHash('sha256').update(JSON.stringify(hashes)).digest('hex'),files:hashes},null,2)+'\n');
console.log('PASS: separate basic namespace, 5 MiB/types, honest validation scope, default-off gates, 10 secured RPCs, exact DDL/guard/hooks/fingerprint equality, Dart/Edge RPC contracts and unchanged scanner artifacts. SQL runtime UNVERIFIED.');

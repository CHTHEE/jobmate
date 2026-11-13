import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const root=new URL('../../',import.meta.url),bytes=p=>readFileSync(new URL(p,root));
const read=p=>bytes(p).toString('utf8').replaceAll('\r\n','\n');
const sha=b=>createHash('sha256').update(b).digest('hex');
const r1=read('supabase/candidates/chat_basic_rollback_validation_r1_candidate.sql');
const old=read('supabase/candidates/chat_basic_rollback_validation_candidate.sql');
const manifest=JSON.parse(read('docs/chat_basic_attachment_r1_hashes.json'));
const corsManifest=JSON.parse(read('docs/chat_basic_attachment_cors_hashes.json'));
const rpcManifest=JSON.parse(read('docs/chat_basic_attachment_rpc_fix_hashes.json'));
const protocolPath='supabase/functions/_shared/chat_basic/protocol.mjs';
const entryPath='supabase/functions/chat-basic-attachments/index.ts';
function verifyReviewed(path,hash){
 if(path===protocolPath){
  assert.equal(hash,'43027b80fb9e40aff0c6d7334d32f5339c8624be69dd67f85b3396a949ca5782');
  assert.equal(sha(bytes(path)),corsManifest.files[path],path);
 }else if(path===entryPath){
  assert.equal(hash,'c7abf9adca9ec15ed1b77ae9f614b1e132f839f113b2c2520a1e966199e0b606');
  assert.equal(sha(bytes(path)),rpcManifest.files[path],path);
 }else assert.equal(sha(bytes(path)),hash,path);
}
test('CORS revision changes only protocol; historical r1 manifest is retained',()=>{
 assert.equal(corsManifest.supersedes_bundle_sha256,manifest.backend_bundle_sha256);
 assert.equal(sha(JSON.stringify(corsManifest.files)),corsManifest.backend_bundle_sha256);
 assert.deepEqual(Object.keys(corsManifest.files),Object.keys(manifest.files));
 assert.deepEqual(Object.keys(manifest.files).filter(path=>manifest.files[path]!==corsManifest.files[path]),[protocolPath]);
 for(const [path,hash] of Object.entries(corsManifest.files))assert.equal(sha(bytes(path)),path===entryPath?rpcManifest.files[path]:hash,path);
});
test('void RPC response revision changes only entry point; previous manifests retained',()=>{
 assert.equal(rpcManifest.supersedes_bundle_sha256,corsManifest.backend_bundle_sha256);
 assert.equal(sha(JSON.stringify(rpcManifest.files)),rpcManifest.backend_bundle_sha256);
 assert.deepEqual(Object.keys(rpcManifest.files),Object.keys(corsManifest.files));
 assert.deepEqual(Object.keys(corsManifest.files).filter(path=>corsManifest.files[path]!==rpcManifest.files[path]),[entryPath]);
 for(const [path,hash] of Object.entries(rpcManifest.files))assert.equal(sha(bytes(path)),hash,path);
});
test('original sources except authorized CORS/RPC revisions, guards and failed copy are preserved',()=>{
 for(const file of ['docs/chat_basic_attachment_hashes.json','docs/chat_phase6b_artifact_hashes.json']){
  const original=JSON.parse(read(file));for(const [path,hash] of Object.entries(original.files))verifyReviewed(path,hash);
 }
 assert.equal(sha(bytes('tmp/chat_basic_rollback_validation_APPROVED_20261113.sql')),'c0728eb0d85bcce6a9a14468022eb00e70c456a3b8553e4ae1d2bacc027ce767');
 assert.equal(sha(bytes('supabase/migrations/20261112000100_chat_backend_foundation_candidate.sql')),'8704715e62de895324a651c41bfd55cc2a756d2c739fded85b624fb4ab5fa0e7');
 assert.equal(sha(bytes('supabase/diagnostics/chat_phase2_rollback_validation_candidate.sql')),'84ddf9ab9f30b2fc1930c3f68cfe7371b730c0ae1adfeceba859d070368ec099');
});
test('r1 sources match except recorded CORS/RPC revisions and permanent migration is byte-identical',()=>{
 for(const [path,hash] of Object.entries(manifest.files))verifyReviewed(path,hash);
 assert.equal(sha(JSON.stringify(manifest.files)),manifest.backend_bundle_sha256);
 assert.deepEqual(bytes('supabase/candidates/chat_basic_attachment_migration_r1.sql'),bytes('supabase/candidates/chat_basic_attachment_migration.sql'));
});
test('all DDL, preflight, approval guard and timeouts are unchanged',()=>{
 const boundary='DO $attachment_catalog_assertions$';
 assert.equal(r1.slice(0,r1.indexOf(boundary)),old.slice(0,old.indexOf(boundary)));
 assert.match(r1,/DO \$attachment_approval_guard\$\s+BEGIN\s+RAISE EXCEPTION/);
 assert.ok(r1.trimEnd().endsWith('ROLLBACK;'));
 const outside=r1.replace(/--[^\n]*/g,'').replace(/(\$[a-zA-Z_0-9]*\$)[\s\S]*?\1/g,'$BODY$');
 assert.ok(!/\bCOMMIT\b/i.test(outside));
 assert.ok(!/\b(?:SELECT|PERFORM)\s+(?:public\.)?(?:send_chat|reserve_chat|get_or_create_chat|mark_chat)\w*\s*\(/i.test(outside));
});
test('post-DDL existence check must fail closed before any table query',()=>{
 const block=r1.slice(r1.indexOf('DO $attachment_catalog_assertions$'));
 const check=block.indexOf('IF v_metadata IS NULL OR v_release IS NULL THEN');
 assert.ok(check>0);assert.ok(check<block.indexOf('FROM jobmate_chat_private.basic_attachment_release'));
 assert.ok(r1.indexOf('CREATE TABLE jobmate_chat_private.basic_attachment_release')<r1.indexOf('DO $attachment_catalog_assertions$'));
 assert.match(block,/ERRCODE='55000'/);
 assert.ok(!/'(?:public\.chat_basic_attachments|jobmate_chat_private\.basic_attachment_release)'::regclass/.test(block));
});
test('all old assertions are preserved with equivalent runtime OID arguments',()=>{
 const start='DO $attachment_catalog_assertions$',end='$attachment_catalog_assertions$;';
 const block=text=>text.slice(text.indexOf(start),text.indexOf(end,text.indexOf(start))+end.length);
 let actual=block(r1).replace('DECLARE f record; owner_oid oid; v_metadata oid; v_release oid;','DECLARE f record; owner_oid oid;');
 actual=actual.replace(/\n -- Resolve these objects[\s\S]*?\n END IF;/,'');
 actual=actual.replaceAll("pg_catalog.has_table_privilege('authenticated',v_metadata,","pg_catalog.has_table_privilege('authenticated','public.chat_basic_attachments',")
  .replaceAll("pg_catalog.has_table_privilege('anon',v_metadata,","pg_catalog.has_table_privilege('anon','public.chat_basic_attachments',")
  .replaceAll("pg_catalog.has_table_privilege('service_role',v_metadata,","pg_catalog.has_table_privilege('service_role','public.chat_basic_attachments',")
  .replaceAll("pg_catalog.has_table_privilege('authenticated',v_release,","pg_catalog.has_table_privilege('authenticated','jobmate_chat_private.basic_attachment_release',")
  .replaceAll("pg_catalog.has_table_privilege('service_role',v_release,","pg_catalog.has_table_privilege('service_role','jobmate_chat_private.basic_attachment_release',")
  .replaceAll('c.oid=v_metadata',"c.oid='public.chat_basic_attachments'::regclass");
 assert.equal(actual,block(old));
});
test('last success result includes PID and safe runtime catalogue snapshot',()=>{
 const select=r1.slice(r1.indexOf("SELECT 'CHAT_ATTACHMENTS_CATALOG_ASSERTIONS_PASSED_ROLLBACK_PENDING'"));
 assert.ok(select.includes('pg_catalog.pg_backend_pid() AS validation_pid'));
 assert.ok(select.includes('AS attachment_trial_catalogue;'));
 assert.ok(select.includes("pg_catalog.to_regclass('jobmate_chat_private.basic_attachment_release')"));
 assert.ok(!/'[^']+'::regclass/.test(select));
 assert.match(select,/AS attachment_trial_catalogue;\s*ROLLBACK;\s*$/);
});

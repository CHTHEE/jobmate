// CH/KZ-approved local preparation only. Never submits SQL or connects to Supabase.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const root=new URL('../../',import.meta.url), read=p=>readFileSync(new URL(p,root));
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const manifest=JSON.parse(read('docs/chat_basic_attachment_hashes.json'));
assert.equal(manifest.backend_bundle_sha256,'15beba70d5fcedc33a9f48a0f28ad843c6fca744a8300d26dacd81bf2d1d1a1e');
assert.equal(sha(JSON.stringify(manifest.files)),manifest.backend_bundle_sha256);
for(const [path,hash] of Object.entries(manifest.files)) assert.equal(sha(read(path)),hash,path);
const protectedFiles={
 'supabase/migrations/20261112000100_chat_backend_foundation_candidate.sql':'8704715e62de895324a651c41bfd55cc2a756d2c739fded85b624fb4ab5fa0e7',
 'supabase/diagnostics/chat_phase2_rollback_validation_candidate.sql':'84ddf9ab9f30b2fc1930c3f68cfe7371b730c0ae1adfeceba859d070368ec099',
};
for(const [path,hash] of Object.entries(protectedFiles)) assert.equal(sha(read(path)),hash,path);
const sourceBytes=read('supabase/candidates/chat_basic_rollback_validation_candidate.sql');
assert.equal(sha(sourceBytes),'05b7ea04ef94caaf7086e012d0641f628e332a8114c7e933249fe3f1a3481957');
const source=sourceBytes.toString('utf8'), nl=source.includes('\r\n')?'\r\n':'\n';
const runbook=read('docs/chat_basic_rollback_validation_preparation.md').toString('utf8');
const blocks=[...runbook.matchAll(/```sql\r?\n([\s\S]*?)\r?\n```/g)].map(m=>m[1]);
const snapshots=blocks.filter(b=>b.endsWith('AS attachment_trial_catalogue;'));
const contexts=blocks.filter(b=>b.includes('AS validation_pid,'));
assert.equal(snapshots.length,1);assert.equal(contexts.length,1);
const normalize=s=>s.replace(/\r?\n/g,nl);
const snapshot=normalize(snapshots[0])+nl;
const setting=`SET LOCAL jobmate.chat_reviewed_backend_md5 = 'a5d682393de3f9ffc66f01c5264ec7c1';${nl}`;
const context=normalize(contexts[0])+nl;
for(const statement of [snapshot,context]) assert.match(statement,/^SELECT /);
const guards=[...source.matchAll(/^DO \$attachment_approval_guard\$\r?\nBEGIN\r?\n  RAISE EXCEPTION '[^']*';\r?\nEND;\r?\n\$attachment_approval_guard\$;\r?\n/gm)];
assert.equal(guards.length,1);
const withoutGuard=source.replace(guards[0][0],'');
const anchor=`SET LOCAL check_function_bodies = on;${nl}`;
assert.equal(withoutGuard.split(anchor).length,2);
const marker="SELECT 'CHAT_ATTACHMENTS_CATALOG_ASSERTIONS_PASSED_ROLLBACK_PENDING' AS validation_result;";
assert.equal(withoutGuard.split(marker).length,2);
const prepared=withoutGuard.replace(anchor,anchor+setting+context).replace(marker,snapshot+marker);
// Exact reverse transformation proves every other byte/DDL/check is unchanged.
assert.equal(prepared.replace(setting+context,'').replace(snapshot,''),withoutGuard);
assert.ok(!prepared.includes('DO $attachment_approval_guard$'));
assert.ok(prepared.trimEnd().endsWith('ROLLBACK;'));
const outside=prepared.replace(/--[^\r\n]*/g,'').replace(/(\$[a-zA-Z_0-9]*\$)[\s\S]*?\1/g,'$BODY$');
assert.ok(!/\bCOMMIT\b/i.test(outside));
assert.ok(!/\b(?:SELECT|PERFORM)\s+(?:public\.)?(?:send_chat|reserve_chat|get_or_create_chat|mark_chat)\w*\s*\(/i.test(outside));
assert.match(outside,/^\s*[\s\S]*BEGIN ISOLATION LEVEL READ COMMITTED;/);
for(const expected of ["lock_timeout = '1s'","statement_timeout = '15s'","idle_in_transaction_session_timeout = '60s'","transaction_timeout = '90s'",'SET LOCAL check_function_bodies = on;']) assert.ok(outside.includes(expected));
const inserts=[...outside.matchAll(/\bINSERT INTO\s+([\w.]+)/gi)].map(m=>m[1]);
assert.deepEqual(inserts,['jobmate_chat_private.basic_attachment_release','storage.buckets']);
assert.ok(!/\b(?:UPDATE|DELETE|TRUNCATE)\s+(?:public\.|storage\.|jobmate_chat_private\.)/i.test(outside));
const target=resolve(join(tmpdir(),'chat_basic_rollback_validation_APPROVED_20261113.sql'));
const repo=resolve(fileURLToPath(root));
assert.ok(!target.toLowerCase().startsWith(repo.toLowerCase()+'\\'),'Execution copy must be outside repository');
if(existsSync(target)) assert.equal(readFileSync(target).toString('utf8'),prepared,'Existing temporary copy differs; do not overwrite');
else writeFileSync(target,prepared,{flag:'wx',encoding:'utf8'});
assert.equal(readFileSync(target).toString('utf8'),prepared);
for(const [path,hash] of Object.entries(manifest.files)) assert.equal(sha(read(path)),hash,path);
for(const [path,hash] of Object.entries(protectedFiles)) assert.equal(sha(read(path)),hash,path);
const report={
 preparation:'PASS',path:target,sha256:sha(readFileSync(target)),source_sha256:sha(sourceBytes),
 approved_bundle_sha256:manifest.backend_bundle_sha256,
 reported_pre_trial_baseline:{record_count:2652,unique_key_count:2652,baseline_md5:'9117d06648f2fe2c85ac5d3131faee1f',five_absences:'PASS',
   evidence_status:'CH reported complete export preserved; not independently inspected by Codex'},
 pinned_backend_md5:'a5d682393de3f9ffc66f01c5264ec7c1',
 changes_only:['Remove new attachment approval guard from temporary copy','Insert approved SET LOCAL backend MD5','Insert exact read-only PID/context and catalogue SELECTs from runbook'],
 preserved:'Every other source byte including DDL, preflight, timeouts, assertions, marker and final ROLLBACK',
 original_artifacts:'all eight hash matches; both original SQL guards/source hashes unchanged',
 executable_COMMIT:false,business_RPC_invocation:false,live_SQL_executed:false,
};
const audit=new URL('docs/chat_basic_approved_rollback_preparation.json',root);
if(existsSync(audit)) assert.equal(readFileSync(audit).toString('utf8'),JSON.stringify(report,null,2)+'\n','Existing audit differs');
else writeFileSync(audit,JSON.stringify(report,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify(report,null,2));

// CH/KZ approval supplied 13 Nov 2026. LOCAL PREPARATION ONLY, no SQL execution.
import { readFileSync,writeFileSync,existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const root=new URL('../../',import.meta.url),read=p=>readFileSync(new URL(p,root));
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const manifest=JSON.parse(read('docs/chat_basic_attachment_r1_hashes.json'));
assert.equal(manifest.backend_bundle_sha256,'52e68790f64b6f566bac30a871899b6130c6c6b1ad65606b23100a6e6e9fa317');
assert.equal(sha(JSON.stringify(manifest.files)),manifest.backend_bundle_sha256);
for(const [path,hash] of Object.entries(manifest.files))assert.equal(sha(read(path)),hash,path);
for(const name of ['docs/chat_basic_attachment_hashes.json','docs/chat_phase6b_artifact_hashes.json']){
 const original=JSON.parse(read(name));for(const [path,hash] of Object.entries(original.files))assert.equal(sha(read(path)),hash,path);
}
const protectedFiles={
 'supabase/migrations/20261112000100_chat_backend_foundation_candidate.sql':'8704715e62de895324a651c41bfd55cc2a756d2c739fded85b624fb4ab5fa0e7',
 'supabase/diagnostics/chat_phase2_rollback_validation_candidate.sql':'84ddf9ab9f30b2fc1930c3f68cfe7371b730c0ae1adfeceba859d070368ec099',
 'tmp/chat_basic_rollback_validation_APPROVED_20261113.sql':'c0728eb0d85bcce6a9a14468022eb00e70c456a3b8553e4ae1d2bacc027ce767',
};
for(const [path,hash] of Object.entries(protectedFiles))assert.equal(sha(read(path)),hash,path);
const sourceBytes=read('supabase/candidates/chat_basic_rollback_validation_r1_candidate.sql');
assert.equal(sha(sourceBytes),'4fb01897ba657df5118046b31d6f41994bfbfa0093f980976bbe4824d47ac010');
const source=sourceBytes.toString('utf8'),nl=source.includes('\r\n')?'\r\n':'\n';
const guardPattern=/^DO \$attachment_approval_guard\$\r?\nBEGIN\r?\n  RAISE EXCEPTION '[^']*';\r?\nEND;\r?\n\$attachment_approval_guard\$;\r?\n/gm;
const guards=[...source.matchAll(guardPattern)];assert.equal(guards.length,1);
const withoutGuard=source.replace(guards[0][0],'');
const anchor='SET LOCAL check_function_bodies = on;'+nl;
assert.equal(withoutGuard.split(anchor).length,2);
const setting="SET LOCAL jobmate.chat_reviewed_backend_md5 = 'a5d682393de3f9ffc66f01c5264ec7c1';"+nl;
const prepared=withoutGuard.replace(anchor,anchor+setting);
// Exact inverse: no other change to any DDL, assertion, instrumentation or byte.
assert.equal(prepared.replace(setting,''),withoutGuard);
assert.ok(!prepared.includes('DO $attachment_approval_guard$'));
assert.ok(prepared.trimEnd().endsWith('ROLLBACK;'));
const outside=prepared.replace(/--[^\r\n]*/g,'').replace(/(\$[a-zA-Z_0-9]*\$)[\s\S]*?\1/g,'$BODY$');
assert.ok(!/\bCOMMIT\b/i.test(outside));
assert.ok(!/\b(?:SELECT|PERFORM)\s+(?:public\.)?(?:send_chat|reserve_chat|get_or_create_chat|mark_chat)\w*\s*\(/i.test(outside));
assert.deepEqual([...outside.matchAll(/\bINSERT INTO\s+([\w.]+)/gi)].map(m=>m[1]),[
 'jobmate_chat_private.basic_attachment_release','storage.buckets',
]);
assert.ok(!/\b(?:UPDATE|DELETE|TRUNCATE)\s+(?:public\.|storage\.|jobmate_chat_private\.)/i.test(outside));
for(const value of ['BEGIN ISOLATION LEVEL READ COMMITTED;',"lock_timeout = '1s'","statement_timeout = '15s'",
 "idle_in_transaction_session_timeout = '60s'","transaction_timeout = '90s'",'check_function_bodies = on;'])assert.ok(outside.includes(value),value);
assert.ok(prepared.includes('IF v_metadata IS NULL OR v_release IS NULL THEN'));
const marker=prepared.slice(prepared.indexOf("SELECT 'CHAT_ATTACHMENTS_CATALOG_ASSERTIONS_PASSED_ROLLBACK_PENDING'"));
assert.ok(marker.includes('pg_catalog.pg_backend_pid() AS validation_pid'));
assert.ok(marker.includes('AS attachment_trial_catalogue;'));
assert.ok(marker.includes("pg_catalog.to_regclass('jobmate_chat_private.basic_attachment_release')"));
assert.ok(!/'(?:public\.chat_basic_attachments|jobmate_chat_private\.basic_attachment_release)'::regclass/.test(prepared));
const path=new URL('tmp/chat_basic_rollback_validation_r1_APPROVED_20261113.sql',root);
if(existsSync(path))assert.equal(readFileSync(path).toString('utf8'),prepared,'Existing execution copy differs; do not overwrite');
else writeFileSync(path,prepared,{flag:'wx',encoding:'utf8'});
assert.equal(readFileSync(path).toString('utf8'),prepared);
for(const [path,hash] of Object.entries(manifest.files))assert.equal(sha(read(path)),hash,path);
for(const [path,hash] of Object.entries(protectedFiles))assert.equal(sha(read(path)),hash,path);
const report={
 preparation:'PASS',execution_path:fileURLToPath(path),execution_sha256:sha(readFileSync(path)),
 approved_bundle_sha256:manifest.backend_bundle_sha256,source_sha256:sha(sourceBytes),
 supplied_recovery_evidence:{observer_pid:2907205,other_client_open_or_unknown_transactions:[],possible_failed_trial_backends:[],
 record_count:2652,unique_key_count:2652,five_absences:'PASS',baseline_md5:'9117d06648f2fe2c85ac5d3131faee1f',
 routine_count:10,reviewed_backend_md5:'a5d682393de3f9ffc66f01c5264ec7c1',complete_exports_compared:'CH reports parsed contents match exactly'},
 evidence_status:'Reported by CH; no independent Codex live verification or export inspection',
 approval_match:'Explicit joint r1 approval; hashes, recovery evidence and scope match incident report',
 only_changes:['Remove new approval guard from separate execution copy','Insert reviewed transaction-local backend MD5'],
 preserved:'Every other byte, including DDL/preflight/assertions/timeouts/runtime OIDs/fail-closed checks/consolidated PID/catalogue/marker/ROLLBACK',
 executable_COMMIT:false,business_RPC_invocations:false,original_artifacts_and_failed_copy:'unchanged',live_SQL_executed:false,
};
const audit=new URL('tmp/chat_basic_rollback_validation_r1_preparation_20261113.json',root);
const json=JSON.stringify(report,null,2)+'\n';
if(existsSync(audit))assert.equal(readFileSync(audit).toString('utf8'),json,'Existing preparation audit differs');
else writeFileSync(audit,json,{flag:'wx'});
console.log(json);

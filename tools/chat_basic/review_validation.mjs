// READ ONLY LOCAL REVIEW. Does not regenerate manifests, SQL or execution copies.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
const root=new URL('../../',import.meta.url);
const bytes=p=>readFileSync(new URL(p,root));
const text=p=>bytes(p).toString('utf8').replaceAll('\r\n','\n');
const sha=b=>createHash('sha256').update(b).digest('hex');
const manifest=JSON.parse(text('docs/chat_basic_attachment_hashes.json'));
for(const [path,expected] of Object.entries(manifest.files)) assert.equal(sha(bytes(path)),expected,path);
assert.equal(sha(JSON.stringify(manifest.files)),manifest.backend_bundle_sha256,'bundle hash');
const future=JSON.parse(text('docs/chat_phase6b_artifact_hashes.json'));
for(const [path,expected] of Object.entries(future.files)) assert.equal(sha(bytes(path)),expected,path);
const protectedFiles={
 'supabase/migrations/20261112000100_chat_backend_foundation_candidate.sql':'8704715e62de895324a651c41bfd55cc2a756d2c739fded85b624fb4ab5fa0e7',
 'supabase/diagnostics/chat_phase2_rollback_validation_candidate.sql':'84ddf9ab9f30b2fc1930c3f68cfe7371b730c0ae1adfeceba859d070368ec099',
};
for(const [path,expected] of Object.entries(protectedFiles)) assert.equal(sha(bytes(path)),expected,path);
const migration=text('supabase/candidates/chat_basic_attachment_migration.sql');
const trial=text('supabase/candidates/chat_basic_rollback_validation_candidate.sql');
assert.ok(trial.includes(migration.slice(migration.indexOf('BEGIN ISOLATION LEVEL')).replace(/COMMIT;\s*$/,'')),'exact guarded migration body');
assert.match(trial,/DO \$attachment_approval_guard\$\s+BEGIN\s+RAISE EXCEPTION/);
assert.match(trial,/BEGIN ISOLATION LEVEL READ COMMITTED;/);
for(const setting of ["lock_timeout = '1s'","statement_timeout = '15s'","idle_in_transaction_session_timeout = '60s'","transaction_timeout = '90s'","check_function_bodies = on"]) assert.ok(trial.includes(setting),setting);
const outside=trial.replace(/--[^\n]*/g,'').replace(/(\$[a-zA-Z_0-9]*\$)[\s\S]*?\1/g,'$BODY$');
assert.ok(!/\bCOMMIT\b/i.test(outside),'no executable COMMIT');
assert.ok(!/\b(?:SELECT|PERFORM)\s+(?:public\.)?(?:send_chat|reserve_chat|get_or_create_chat|mark_chat)\w*\s*\(/i.test(outside),'no business RPC invocation');
assert.match(trial,/'CHAT_ATTACHMENTS_CATALOG_ASSERTIONS_PASSED_ROLLBACK_PENDING'[\s\S]*ROLLBACK;\s*$/);
assert.match(outside,/ROLLBACK;\s*$/);
assert.equal((trial.match(/CREATE FUNCTION public\./g)??[]).length,10);
const baseline=text('supabase/diagnostics/chat_basic_rollback_baseline.sql');
assert.ok(!/^\s*(?:INSERT|UPDATE|DELETE|ALTER|CREATE|DROP|CALL|DO|GRANT|REVOKE)\b/im.test(baseline.replace(/--[^\n]*/g,'')),'baseline SELECT/CTE only');
assert.ok(!/\bFROM\s+storage\.objects\b/i.test(baseline));
assert.ok(baseline.includes('CASE WHEN pg_catalog.cardinality(r.acl)>0 THEN r.acl ELSE NULL::aclitem[] END'));
console.log(JSON.stringify({result:'PASS',reviewed_artifacts:Object.keys(manifest.files).length,
 bundle_sha256:manifest.backend_bundle_sha256,rollback_sha256:manifest.files['supabase/candidates/chat_basic_rollback_validation_candidate.sql'],
 baseline_sha256:sha(bytes('supabase/diagnostics/chat_basic_rollback_baseline.sql')),
 protected_originals:'unchanged',execution_copy:'not prepared',live_SQL:'not executed'},null,2));

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const root = new URL('../../', import.meta.url);
const read = path => readFileSync(new URL(path, root), 'utf8').replaceAll('\r\n', '\n');
const sql = read('supabase/diagnostics/chat_basic_cleanup_http_compatibility.sql');
const executable = sql.replace(/--[^\n]*/g, '');
test('compatibility inspection cannot register a job, mutate SQL or issue HTTP', () => {
  assert.match(executable.trimStart(), /^SELECT\b/);
  assert.ok(!/\b(?:INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|GRANT|REVOKE|TRUNCATE|CALL|DO)\s/i.test(executable));
  assert.ok(!/\b(?:cron\.(?:schedule|alter_job|unschedule)|(?:extensions\.|net\.)http\w*|set_config)\s*\(/i.test(executable));
});
test('inspection emits metadata without Vault values, queue contents or cron commands', () => {
  assert.ok(!/\b(?:FROM|JOIN)\s+(?:vault\.decrypted_secrets|net\.)/i.test(executable));
  assert.ok(!/\b(?:j\.)?command\b/i.test(executable));
  assert.ok(!/SELECT\s+\*/i.test(executable));
  assert.ok(executable.includes('FROM vault.secrets'));
  assert.ok(executable.includes("'decrypted_secret','SELECT'"));
  assert.ok(executable.includes("'logging_settings'"));
  assert.ok(!/current_setting\('(?!log_min_messages|client_min_messages|log_parameter_max_length_on_error|pgaudit\.log_parameter|auto_explain\.log_min_duration|auto_explain\.log_verbose)/.test(executable));
});
test('original pg_net precheck remains fail closed and new transport is explicitly blocked', () => {
  const activation = read('docs/chat_basic_activation.md');
  const originalGuard = activation.slice(activation.indexOf('DO $cleanup_precheck$'), activation.indexOf('$cleanup_precheck$;') + '$cleanup_precheck$;'.length);
  assert.ok(originalGuard.includes("pg_catalog.has_schema_privilege(role_name,'net','USAGE')"));
  assert.ok(originalGuard.includes("pg_catalog.has_table_privilege(role_name,'net.http_request_queue','SELECT')"));
  assert.ok(originalGuard.includes("RAISE EXCEPTION 'Scheduler secret access boundary requires review.'"));
  const review = read('docs/chat_basic_cleanup_http_review.md');
  assert.ok(review.includes('No runnable registration script has been created.'));
  assert.ok(review.includes('CURLOPT_FOLLOWLOCATION=1'));
  assert.ok(review.includes('DEBUG2'));
  assert.ok(review.includes('https://ibbyejgpjboearzhvwlr.supabase.co/functions/v1/chat-basic-attachments?op=cleanup'));
});

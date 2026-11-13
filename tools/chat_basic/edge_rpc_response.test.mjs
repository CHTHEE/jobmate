// Actual Edge entry point, Node's native TS stripping, injected offline HTTP only.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
const base = 'https://jobmate.invalid';
const actor = 'test-user-token-not-a-real-credential';
const service = 'test-service-token-not-a-real-credential';
let handler;
globalThis.Deno = {
  env: { get: name => ({ SUPABASE_URL: base, SUPABASE_ANON_KEY: 'test-anon',
    SUPABASE_SERVICE_ROLE_KEY: service, CHAT_BASIC_ATTACHMENTS_ENABLED: 'true',
    CHAT_BASIC_CLEANUP_SECRET: 'test-only-cleanup-secret-32-characters' })[name] },
  serve: value => { handler = value; },
};
await import('../../supabase/functions/chat-basic-attachments/index.ts');
const originalFetch = globalThis.fetch;
const id = '00000000-0000-4000-8000-000000000001';
const pdf = Buffer.from('%PDF-1.7\n/Type /Catalog\n/Type /Pages\n%%EOF\n');
const prefix = `${id}/${id}/${id}/`;
function fixture({ finishStatus = 204, finishBody = null, contextBody, contextStatus = 200 } = {}) {
  const row = { attachment_id: id, conversation_id: id, sender_id: id,
    client_request_id: id, state: 'pending', can_upload: true, size_bytes: pdf.length,
    original_name: 'test.pdf', mime_type: 'application/pdf',
    expected_sha256: createHash('sha256').update(pdf).digest('hex') };
  const calls = [], state = { finalWrites: 0, finalizations: 0, claims: 0 };
  globalThis.fetch = async (url, options = {}) => {
    assert.ok(String(url).startsWith(base + '/'), 'Never perform real network requests');
    const path = new URL(url).pathname;
    calls.push(path);
    if (path === '/auth/v1/user') return Response.json({ id });
    if (path.startsWith('/rest/v1/rpc/')) {
      const name = path.split('/').at(-1);
      if (name === 'get_chat_attachment_basic_v1') {
        if (contextBody !== undefined || contextStatus !== 200) {
          return new Response(contextBody ?? null, { status: contextStatus });
        }
        return Response.json(row);
      }
      if (name === 'prepare_chat_attachment_validation_basic_v1') {
        state.claims++; row.state = 'validating';
        return Response.json({ ...row, validation_token: id });
      }
      if (name === 'finish_chat_attachment_validation_basic_v1') {
        assert.equal(options.headers.Authorization, `Bearer ${service}`);
        if (finishStatus >= 200 && finishStatus < 300) {
          state.finalizations++; row.state = 'validated';
        }
        return new Response(finishBody, { status: finishStatus });
      }
    }
    if (path === `/storage/v1/object/jobmate-chat-basic-files/${prefix}part.0`) {
      assert.equal(options.headers.Authorization, `Bearer ${service}`);
      return new Response(pdf);
    }
    if (path === `/storage/v1/object/jobmate-chat-basic-files/${prefix}file` && options.method === 'POST') {
      state.finalWrites++;
      return new Response(null, { status: 201 });
    }
    throw Error('Unexpected offline HTTP route');
  };
  return { row, calls, state, invoke: () => handler(new Request(`${base}/functions/v1/chat-basic-attachments?op=validate`, {
    method: 'POST', body: '{}', headers: { Authorization: `Bearer ${actor}`, 'x-attachment-id': id },
  })) };
}
test.afterEach(() => { globalThis.fetch = originalFetch; });
for (const [status, body] of [[204, null], [200, ''], [200, 'null']]) {
  test(`actual Edge finalization accepts successful void response ${status}/${body ?? 'no body'}`, async () => {
    const f = fixture({ finishStatus: status, finishBody: body });
    const result = await f.invoke();
    assert.equal(result.status, 200);
    assert.equal((await result.json()).state, 'validated');
    assert.equal(f.state.finalizations, 1);
    assert.equal(f.state.finalWrites, 1);
    // Same attachment retry only reconciles status; no new claim/file write.
    assert.equal((await f.invoke()).status, 200);
    assert.equal(f.state.finalizations, 1);
    assert.equal(f.state.claims, 1);
    assert.equal(f.state.finalWrites, 1);
  });
}
for (const [status, body] of [[204, null], [200, ''], [200, '{bad JSON']]) {
  test(`JSON-returning context RPC rejects ${status}/${body ?? 'no body'}`, async () => {
    const f = fixture({ contextStatus: status, contextBody: body });
    assert.equal((await f.invoke()).status, 503);
    assert.equal(f.state.claims, 0);
    assert.equal(f.state.finalizations, 0);
  });
}
test('failed empty void response is not accepted as success', async () => {
  const f = fixture({ finishStatus: 403, finishBody: '' });
  assert.equal((await f.invoke()).status, 503);
  assert.equal(f.row.state, 'validating');
  assert.equal(f.state.finalizations, 0);
});

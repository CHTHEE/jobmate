import assert from 'node:assert/strict';
import test from 'node:test';

const jobId = '2a7b498f-02be-4dac-9c3a-353374f0c92f';
const seekerId = '00000000-0000-0000-0000-000000000001';
const base = 'https://supabase.example';
const origin = 'http://localhost:54321';
const requestBody = JSON.stringify({ job_ids: [jobId], insights_version: 1 });
const revisionHeader = 'x-jobmate-recommendation-revision';
const rejectionHeader = 'x-jobmate-recommendation-rejection';
const upstreamHeader = 'x-jobmate-recommendation-upstream-status';
const revision = 'recommendation-insights-v1-reliability';
const choices = {
  strong: { why: 's', consider: 'r', next: 'p' },
  partial: { why: 'b', consider: 'g', next: 'u' },
  limited: { why: '0', consider: 'l', next: 'r' },
};

let instance = 0;
const completed = text => ({ status: 'completed', steps: [{
  type: 'model_output', content: [{ type: 'text', text }],
}] });

async function boot(t, {
  enabled = true, role = 'job_seeker', deadline = '2099-12-31', applied = false,
  emptyRange = '*/0', template = 's', demoUserId, providerResponse, authResponse,
  ids = [jobId], legacy = false, model = 'gemini-3.5-flash-lite',
} = {}) {
  const calls = [];
  let handle;
  t.mock.method(globalThis, 'fetch', async (target, options) => {
    const url = new URL(target);
    calls.push(url.pathname);
    if (url.href === 'https://generativelanguage.googleapis.com/v1/interactions') {
      const body = JSON.parse(options.body);
      const input = JSON.parse(body.input);
      assert.equal(body.store, false);
      assert.equal(body.generation_config.max_output_tokens, legacy ? 512 : 1024);
      assert.equal(body.generation_config.thinking_level,
        !legacy && model === 'gemini-3.5-flash-lite' ? 'minimal' : undefined);
      assert.deepEqual(Object.keys(input).sort(), legacy
        ? ['instructions', 'jobs'] : ['catalog', 'catalog_version', 'instructions', 'jobs']);
      assert.deepEqual(input.jobs.map(job => job.job_id), ids.map((_, i) => `job-${i + 1}`));
      for (const job of input.jobs) {
        assert.deepEqual(Object.keys(job).sort(), legacy
          ? ['approved_explanations', 'employment_type', 'job_id', 'work_arrangement']
          : ['employment_type', 'job_id', 'work_arrangement']);
        assert.equal(job.employment_type, 'full_time');
        assert.equal(job.work_arrangement, 'remote');
      }
      assert.doesNotMatch(options.body, new RegExp(`${jobId}|${seekerId}|fixture-jwt|fixture-private`));
      if (providerResponse) return providerResponse(options);
      const output = legacy
        ? { explanations: input.jobs.map(job => ({ job_id: job.job_id, explanation: job.approved_explanations[0] })) }
        : { insights: input.jobs.map(job => ({ job_id: job.job_id, ...choices, strong: { ...choices.strong, why: template } })) };
      return Response.json(completed(JSON.stringify(output)));
    }
    assert.equal(url.origin, base);
    assert.equal(options.headers.Authorization, 'Bearer fixture-jwt');
    assert.equal(options.headers.apikey, 'fixture-anon');
    if (url.pathname === '/auth/v1/user') return authResponse ? authResponse(options) : Response.json({ id: seekerId });
    if (url.pathname === '/rest/v1/users') {
      assert.equal(url.searchParams.get('user_id'), `eq.${seekerId}`);
      return Response.json([{ role, status: 'active' }]);
    }
    assert.equal(options.headers.Prefer, 'count=exact');
    assert.equal(url.searchParams.get('job_id'), `in.(${ids.join(',')})`);
    if (url.pathname === '/rest/v1/rpc/list_published_jobs') {
      assert.equal(url.searchParams.get('select'), 'job_id,application_deadline,employment_type,work_arrangement');
      return Response.json(ids.map(id => ({
        job_id: id, application_deadline: deadline, employment_type: 'full_time',
        work_arrangement: 'remote', original_description: 'fixture-private',
      })), { headers: { 'Content-Range': `0-${ids.length - 1}/${ids.length}` } });
    }
    assert.equal(url.pathname, '/rest/v1/rpc/list_my_job_applications');
    assert.equal(url.searchParams.get('select'), 'job_id');
    return Response.json(applied ? [{ job_id: jobId }] : [], {
      headers: { 'Content-Range': applied ? '0-0/1' : emptyRange },
    });
  });
  const env = {
    SUPABASE_URL: base, SUPABASE_ANON_KEY: 'fixture-anon',
    JOBMATE_RECOMMENDATION_GEMINI_ENABLED: String(enabled),
    JOBMATE_RECOMMENDATION_GEMINI_MODEL: model,
    JOBMATE_RECOMMENDATION_GEMINI_DEMO_USER_ID: demoUserId,
    GEMINI_API_KEY: 'fixture-key',
  };
  globalThis.Deno = { env: { get: name => env[name] }, serve: handler => { handle = handler; } };
  try {
    await import(`./index.ts?fixture=${++instance}`);
  } finally {
    delete globalThis.Deno;
  }
  return { calls, run: (body = requestBody, { method = 'POST', token = 'fixture-jwt' } = {}) =>
    handle(new Request(`${base}/functions/v1/recommendation-insights`, {
      method, body: method === 'POST' ? body : undefined,
      headers: { 'Content-Type': 'application/json', Origin: origin,
        ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    })) };
}

test('single-file entrypoint serves the exact v1 request and rate limits repeats', async t => {
  const { run, calls } = await boot(t);
  const preflight = await run(undefined, { method: 'OPTIONS', token: null });
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get('access-control-allow-origin'), origin);
  assert.deepEqual(calls, []);
  const response = await run();
  assert.equal(response.status, 200);
  assert.equal(response.headers.get(revisionHeader), revision);
  assert.equal(response.headers.has(rejectionHeader), false);
  assert.deepEqual(await response.json(), { insights_version: 1, insights: [{ job_id: jobId, ...choices }] });
  assert.deepEqual(calls, ['/auth/v1/user', '/rest/v1/users', '/rest/v1/rpc/list_published_jobs',
    '/rest/v1/rpc/list_my_job_applications', '/v1/interactions']);
  assert.equal((await run()).status, 429);
  assert.equal(calls.filter(path => path === '/v1/interactions').length, 1);
});

test('shortlist diagnostics expose fixed categories before outbound reads', async t => {
  const { run, calls } = await boot(t);
  for (const [body, category] of [
    [null, 'body_read'], ['{', 'json_parse'],
    [JSON.stringify({ job_ids: [jobId], private_extra: true }), 'request_fields'],
    [JSON.stringify({ job_ids: [jobId], insights_version: '1' }), 'request_version'],
    [JSON.stringify({ job_ids: Array(6).fill(jobId), insights_version: 1 }), 'shortlist_shape'],
    [JSON.stringify({ job_ids: [jobId.toUpperCase()], insights_version: 1 }), 'job_uuid'],
    [JSON.stringify({ job_ids: [jobId, jobId], insights_version: 1 }), 'duplicate_jobs'],
  ]) {
    const response = await run(body);
    assert.equal(response.status, 400);
    assert.equal(response.headers.get(revisionHeader), revision);
    assert.equal(response.headers.get(rejectionHeader), category);
    assert.deepEqual(await response.json(), { error: 'invalid_shortlist' });
  }
  const unsigned = await run(undefined, { token: null });
  assert.equal(unsigned.status, 401);
  assert.deepEqual(calls, []);
});

for (const [options, status, category] of [
  [{ enabled: false }, 503, 'unavailable'],
  [{ role: 'employer' }, 403, 'forbidden'],
  [{ demoUserId: 'invalid' }, 503, 'unavailable'],
  [{ deadline: '2000-01-01' }, 422, 'ineligible_shortlist'],
  [{ applied: true }, 422, 'ineligible_shortlist'],
  [{ emptyRange: '*/*' }, 503, 'unavailable'],
  [{ template: 'fixture-private' }, 502, 'provider_template_invalid'],
]) {
  test(`fails closed for ${Object.keys(options)[0]}`, async t => {
    const { run, calls } = await boot(t, options);
    const response = await run();
    assert.equal(response.status, status);
    assert.equal(response.headers.get(rejectionHeader), category);
    assert.deepEqual(await response.json(), { error: status === 502 ? 'provider_unavailable' : category });
    assert.equal(calls.includes('/v1/interactions'), status === 502);
  });
}

test('five jobs receive complete structured plans', async t => {
  const ids = Array.from({ length: 5 }, (_, i) => `00000000-0000-0000-0000-00000000001${i}`);
  const { run } = await boot(t, { ids, model: 'gemini-fixture' });
  const response = await run(JSON.stringify({ job_ids: ids, insights_version: 1 }));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { insights_version: 1, insights: ids.map(id => ({ job_id: id, ...choices })) });
});

test('legacy job_ids-only clients receive the same approved sentences', async t => {
  const { run } = await boot(t, { legacy: true });
  const response = await run(JSON.stringify({ job_ids: [jobId] }));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { explanations: [{ job_id: jobId, explanation: 'This posting lists full-time employment.' }] });
});

test('duplicate provider aliases reject the whole response', async t => {
  const ids = [jobId, '00000000-0000-0000-0000-000000000002'];
  const { run } = await boot(t, { ids, providerResponse: () => Response.json(completed(JSON.stringify({
    insights: ids.map(() => ({ job_id: 'job-1', ...choices })),
  }))) });
  const response = await run(JSON.stringify({ job_ids: ids, insights_version: 1 }));
  assert.equal(response.status, 502);
  assert.equal(response.headers.get(rejectionHeader), 'provider_alias_invalid');
});

for (const [now, status] of [['2026-11-26T15:59:59Z', 200], ['2026-11-26T16:00:00Z', 422]]) {
  test(`checks date-only deadlines at Kuala Lumpur midnight (${status})`, async t => {
    t.mock.timers.enable({ apis: ['Date'], now: new Date(now) });
    const { run, calls } = await boot(t, { deadline: '2026-11-26' });
    assert.equal((await run()).status, status);
    assert.equal(calls.includes('/v1/interactions'), status === 200);
  });
}

for (const [category, upstream, status, providerResponse] of [
  ['provider_http', 400, 502, () => new Response('fixture-private', { status: 400 })],
  ['provider_http', 503, 502, () => new Response('fixture-private', { status: 503 })],
  ['provider_http', 429, 429, () => new Response('fixture-private', { status: 429 })],
  ['provider_transport', null, 502, () => { throw Error('fixture-private'); }],
  ['provider_response_json', null, 502, () => new Response('{fixture-private')],
  ['provider_response_too_large', null, 502, () => new Response('x'.repeat(65_537))],
  ['provider_incomplete', null, 502, () => Response.json({ status: 'incomplete', steps: ['fixture-private'] })],
  ['provider_response_shape', null, 502, () => Response.json({ status: 'completed', steps: [] })],
  ['provider_output_json', null, 502, () => Response.json(completed('{"insights":['))],
  ['provider_output_shape', null, 502, () => Response.json(completed('{"insights":[]}'))],
  ['provider_alias_invalid', null, 502, () => Response.json(completed(JSON.stringify({ insights: [{ job_id: 'job-2', ...choices }] })))],
]) {
  test(`sanitizes ${category}${upstream ?? ''}`, async t => {
    const { run, calls } = await boot(t, { providerResponse });
    const response = await run();
    assert.equal(response.status, status);
    assert.equal(response.headers.get(rejectionHeader), category);
    assert.equal(response.headers.get(upstreamHeader), upstream?.toString() ?? null);
    assert.deepEqual(await response.json(), { error: status === 429 ? 'rate_limited' : 'provider_unavailable' });
    assert.equal(calls.filter(path => path === '/v1/interactions').length, 1);
  });
}

for (const category of ['provider_timeout', 'handler_timeout']) {
  test(`distinguishes ${category} and keeps the configured budgets`, async t => {
    const budgets = [];
    const timeout = AbortSignal.timeout.bind(AbortSignal);
    t.mock.method(AbortSignal, 'timeout', ms => {
      budgets.push(ms);
      const expiresFirst = category === 'provider_timeout' ? 12_000 : 16_000;
      return timeout(ms === expiresFirst ? 20 : 2000);
    });
    const stall = () => new Promise(() => {});
    const { run } = await boot(t, { providerResponse: stall });
    // AbortSignal.timeout uses an unreferenced timer in Node.
    const keepAlive = setTimeout(() => {}, 500);
    t.after(() => clearTimeout(keepAlive));
    const response = await run();
    assert.equal(response.status, 504);
    assert.deepEqual(budgets, [16_000, 12_000]);
    assert.equal(response.headers.get(rejectionHeader), category);
    assert.deepEqual(await response.json(), { error: 'timeout' });
  });
}

test('the handler deadline also covers Auth before any Gemini call', async t => {
  const timeout = AbortSignal.timeout.bind(AbortSignal);
  t.mock.method(AbortSignal, 'timeout', ms => {
    assert.equal(ms, 16_000);
    return timeout(20);
  });
  const { run, calls } = await boot(t, { authResponse: () => new Promise(() => {}) });
  const keepAlive = setTimeout(() => {}, 500);
  t.after(() => clearTimeout(keepAlive));
  const response = await run();
  assert.equal(response.status, 504);
  assert.equal(response.headers.get(rejectionHeader), 'handler_timeout');
  assert.deepEqual(calls, ['/auth/v1/user']);
});

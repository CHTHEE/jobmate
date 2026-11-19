import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { jobDiscoverySearchHandler } from './handler.mjs';

const id = '12345678-1234-1234-1234-123456789012';
const place = { country_code: 'my', name: 'Example building', formatted: 'Kuala Lumpur, Malaysia', lat: 3.1, lon: 101.7 };

function fixture({
  auth = 200, profile = [{ role: 'job_seeker', status: 'active' }],
  quota = 'reserved', quotaStatus = 200, upstream = 200,
  results = [place], timeout = false, anonymous = false,
} = {}) {
  const calls = [];
  const handler = jobDiscoverySearchHandler({
    base: 'https://supabase.example', anon: 'test-anon', service: 'test-service',
    key: 'test-provider-key', origin: 'https://jobmate.example',
    async request(value, init) {
      const url = new URL(value);
      calls.push(url.pathname);
      switch (url.pathname) {
        case '/auth/v1/user':
          assert.equal(init.headers.Authorization, 'Bearer test-user');
          return Response.json({ id, is_anonymous: anonymous }, { status: auth });
        case '/rest/v1/users':
          assert.equal(url.searchParams.get('user_id'), `eq.${id}`);
          assert.equal(init.headers.Authorization, 'Bearer test-user');
          return Response.json(profile);
        case '/rest/v1/rpc/reserve_job_discovery_place_search':
          assert.equal(init.headers.Authorization, 'Bearer test-service');
          assert.deepEqual(JSON.parse(init.body), { p_job_seeker_id: id });
          return Response.json(quota, { status: quotaStatus });
        case '/v1/geocode/search':
          assert.equal(url.searchParams.get('filter'), 'countrycode:my');
          assert.equal(url.searchParams.get('limit'), '5');
          assert.equal(url.searchParams.get('text'), 'Example place');
          assert.equal(init.redirect, 'error');
          if (timeout) throw new DOMException('Mock timeout', 'TimeoutError');
          return Response.json({ results }, { status: upstream });
        default:
          assert.fail('Unexpected request');
      }
    },
  });
  return { handler, calls, run(body = { query: ' Example place ' }, token = 'test-user') {
    return handler(new Request('https://edge.example', {
      method: 'POST', body: JSON.stringify(body),
      headers: token ? { Authorization: `Bearer ${token}` } : {},
    }));
  } };
}

test('verified Job Seeker receives only valid Malaysian result fields', async () => {
  const { run, calls } = fixture({ results: [
    { ...place, lat: 91 }, { ...place, lon: '101' },
    { ...place, country_code: 'sg' }, { ...place, extra: 'unused' },
  ] });
  const response = await run();
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { places: [{
    name: place.name, address: place.formatted, latitude: 3.1, longitude: 101.7,
  }] });
  assert.equal(calls.length, 4);
});

test('missing or invalid authentication cannot reserve capacity', async () => {
  const { run, calls } = fixture({ auth: 401 });
  assert.equal((await run(undefined, '')).status, 401);
  assert.deepEqual(calls, []);
  assert.equal((await run()).status, 401);
  assert.deepEqual(calls, ['/auth/v1/user']);
});

test('inactive Job Seeker and other roles cannot reserve capacity', async () => {
  for (const profile of [
    [{ role: 'employer', status: 'active' }],
    [{ role: 'admin', status: 'active' }],
    [],
    [{ role: 'job_seeker', status: 'suspended' }],
  ]) {
    const { run, calls } = fixture({ profile });
    assert.equal((await run()).status, 403);
    assert.equal(calls.length, 2);
  }
});

test('Supabase anonymous sessions cannot reserve capacity', async () => {
  const { run, calls } = fixture({ anonymous: true });
  assert.equal((await run()).status, 401);
  assert.deepEqual(calls, ['/auth/v1/user']);
});

test('invalid search input never reserves quota', async () => {
  const { run, calls } = fixture();
  for (const body of [{ query: ' ' }, { query: 42 }, { query: 'a'.repeat(121) }, { query: 'ok', role: 'job_seeker' }]) {
    assert.equal((await run(body)).status, 400);
  }
  assert.deepEqual(calls, []);
});

test('quota denial, outage and unknown response fail closed', async () => {
  for (const [options, status] of [
    [{ quota: 'rate_limited' }, 429], [{ quota: 'forbidden' }, 403],
    [{ quota: 'unknown' }, 503], [{ quotaStatus: 500 }, 503],
  ]) {
    const { run, calls } = fixture(options);
    assert.equal((await run()).status, status);
    assert.equal(calls.length, 3);
  }
});

test('upstream errors, timeouts and malformed data return safe errors', async () => {
  for (const [options, status] of [
    [{ upstream: 429 }, 429], [{ timeout: true }, 504],
    [{ upstream: 500 }, 503], [{ results: [{ ...place, lon: 181 }] }, 503],
    [{ results: {} }, 503],
  ]) {
    const { run, calls } = fixture(options);
    const response = await run();
    assert.equal(response.status, status);
    assert.equal(calls.length, 4);
    assert.doesNotMatch(await response.text(), /test-provider-key|Example place/);
  }
});

test('empty search results are successful', async () => {
  assert.deepEqual(await (await fixture({ results: [] }).run()).json(), { places: [] });
});

test('CORS accepts configured and local web origins and denies others before auth', async () => {
  const { handler, calls } = fixture();
  for (const origin of ['https://jobmate.example', 'http://localhost:54321', 'http://127.0.0.1:8080']) {
    const response = await handler(new Request('https://edge.example', {
      method: 'OPTIONS', headers: { origin },
    }));
    assert.equal(response.status, 204);
    assert.equal(response.headers.get('Access-Control-Allow-Origin'), origin);
  }
  for (const origin of ['https://unrelated.example', 'http://127.1:8080', 'null']) {
    const response = await handler(new Request('https://edge.example', {
      method: 'POST', headers: { origin },
    }));
    assert.equal(response.status, 403);
    assert.equal(response.headers.get('Access-Control-Allow-Origin'), null);
  }
  assert.deepEqual(calls, []);
});

const read = async (path) =>
  (await readFile(new URL(path, import.meta.url), 'utf8')).replaceAll('\r\n', '\n').trimEnd();

test('Dashboard bundle contains the same handler, startup and shared CORS/body helpers', async () => {
  const [handler, startup, protocol, dashboard] = await Promise.all([
    read('./handler.mjs'), read('./index.ts'), read('../_shared/chat_basic/protocol.mjs'),
    read('../../dashboard/search-job-discovery-places/index.ts'),
  ]);
  assert.ok(dashboard.includes(handler.slice(handler.indexOf('const responseLimit'))));
  assert.ok(dashboard.endsWith(startup.slice(startup.indexOf('Deno.serve'))));
  for (const name of ['export async function boundedBody', 'export function allowedBrowserOrigin']) {
    const start = protocol.indexOf(name);
    assert.ok(start >= 0);
    assert.ok(dashboard.includes(protocol.slice(start, protocol.indexOf('\n}', start) + 2)));
  }
});

test('both reservation functions use identical accounting, lock and grants', async () => {
  const [employer, seeker, rollback] = await Promise.all([
    read('../../migrations/20261118000100_workplace_place_search_quota.sql'),
    read('../../migrations/20261119000100_job_discovery_place_search_quota.sql'),
    read('../../rollback/20261119000100_job_discovery_place_search_quota_rollback.sql'),
  ]);
  const expected = employer.slice(employer.indexOf('CREATE FUNCTION'))
    .replaceAll('reserve_workplace_place_search', 'reserve_job_discovery_place_search')
    .replaceAll('p_employer_id', 'p_job_seeker_id')
    .replace("role = 'employer'", "role = 'job_seeker'")
    .replace('Workplace search requires', 'Place search requires');
  assert.ok(seeker.startsWith('BEGIN;'));
  assert.equal(seeker.slice(seeker.indexOf('CREATE FUNCTION')), expected);
  assert.doesNotMatch(seeker, /CREATE\s+(?:TABLE|SCHEMA)|ALTER\s+TABLE/i);
  assert.match(seeker, /FROM PUBLIC, anon, authenticated, service_role;\s+GRANT EXECUTE[\s\S]+TO service_role;/);
  assert.deepEqual(rollback.split('\n').filter((line) => !line.startsWith('--') && line.trim()), [
    'BEGIN;', 'DROP FUNCTION IF EXISTS public.reserve_job_discovery_place_search(uuid);', 'COMMIT;',
  ]);
});

import assert from 'node:assert/strict';
import test from 'node:test';
import { workplaceSearchHandler } from './handler.mjs';

const id = '12345678-1234-1234-1234-123456789012';
const place = { country_code: 'my', name: 'Example building', formatted: 'Kuala Lumpur, Malaysia', lat: 3.1, lon: 101.7 };

function fixture({
  auth = 200, profile = [{ role: 'employer', status: 'active' }],
  quota = 'reserved', quotaStatus = 200, upstream = 200,
  results = [place], timeout = false,
} = {}) {
  const calls = [];
  const handler = workplaceSearchHandler({
    base: 'https://supabase.example', anon: 'test-anon', service: 'test-service',
    key: 'test-provider-key', origin: 'https://jobmate.example',
    async request(value, init) {
      const url = new URL(value);
      calls.push(url.pathname);
      switch (url.pathname) {
        case '/auth/v1/user':
          assert.equal(init.headers.Authorization, 'Bearer test-user');
          return Response.json({ id }, { status: auth });
        case '/rest/v1/users':
          assert.equal(url.searchParams.get('user_id'), `eq.${id}`);
          assert.equal(init.headers.Authorization, 'Bearer test-user');
          return Response.json(profile);
        case '/rest/v1/rpc/reserve_workplace_place_search':
          assert.equal(init.headers.Authorization, 'Bearer test-service');
          assert.deepEqual(JSON.parse(init.body), { p_employer_id: id });
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
  return { calls, run(body = { query: ' Example place ' }, token = 'test-user') {
    return handler(new Request('https://edge.example', {
      method: 'POST', body: JSON.stringify(body),
      headers: token ? { Authorization: `Bearer ${token}` } : {},
    }));
  } };
}

test('verified employer receives only valid Malaysian result fields', async () => {
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

test('inactive employer and other roles cannot reserve capacity', async () => {
  for (const profile of [
    [{ role: 'job_seeker', status: 'active' }],
    [{ role: 'employer', status: 'suspended' }],
  ]) {
    const { run, calls } = fixture({ profile });
    assert.equal((await run()).status, 403);
    assert.equal(calls.length, 2);
  }
});

test('invalid search input never reserves quota', async () => {
  const { run, calls } = fixture();
  for (const body of [{ query: ' ' }, { query: 42 }, { query: 'a'.repeat(121) }, { query: 'ok', role: 'employer' }]) {
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

import { setTimeout as delay } from 'node:timers/promises';
import { configuredGeminiProvider } from '../../supabase/functions/explain-job-recommendations/gemini_provider.mjs';
import {
  instructions,
  publicPostingFacts,
  recommendationExplanationHandler,
} from '../../supabase/functions/explain-job-recommendations/handler.mjs';

const model = 'gemini-3.5-flash-lite';
const endpoint = 'https://generativelanguage.googleapis.com/v1/interactions';
const extendedTimeouts = { providerTimeoutMs: 15_000, handlerTimeoutMs: 17_000 };
const fixtureOrigin = 'https://jobmate-fixture.invalid';
const seekerId = '00000000-0000-0000-0000-000000000001';
const postings = [
  { job_id: '00000000-0000-0000-0000-000000000002', employment_type: 'contract', work_arrangement: 'hybrid' },
  { job_id: '00000000-0000-0000-0000-000000000003', employment_type: 'internship', work_arrangement: 'remote' },
];
const expectedJobs = postings.map((job, index) => ({
  job_id: `job-${index + 1}`,
  ...publicPostingFacts(job.employment_type, job.work_arrangement),
}));

// All Supabase reads are synthetic and in memory. This transport never
// delegates to fetch, even when running the Gemini request live.
async function fixtureRequest(value) {
  const url = new URL(value);
  if (url.origin !== fixtureOrigin) throw Error('unexpected_fixture_origin');
  switch (url.pathname) {
    case '/auth/v1/user':
      return Response.json({ id: seekerId });
    case '/rest/v1/users':
      return Response.json([{ role: 'job_seeker', status: 'active' }]);
    case '/rest/v1/rpc/list_published_jobs':
      return Response.json(postings.map(job => ({
        ...job, application_deadline: '2026-11-23',
      })), { headers: { 'Content-Range': '0-1/2' } });
    case '/rest/v1/rpc/list_my_job_applications':
      return Response.json([], { headers: { 'Content-Range': '*/0' } });
    default:
      throw Error('unexpected_fixture_request');
  }
}

function sameJson(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

const transportCodes = new Map([
  ['ENOTFOUND', 'dns_failure'],
  ['EAI_AGAIN', 'dns_failure'],
  ['ECONNREFUSED', 'connection_failure'],
  ['ECONNRESET', 'connection_failure'],
  ['CERT_HAS_EXPIRED', 'tls_certificate_failure'],
  ['UNABLE_TO_VERIFY_LEAF_SIGNATURE', 'tls_certificate_failure'],
  ['ERR_TLS_CERT_ALTNAME_INVALID', 'tls_certificate_failure'],
  ['DEPTH_ZERO_SELF_SIGNED_CERT', 'tls_certificate_failure'],
  ['SELF_SIGNED_CERT_IN_CHAIN', 'tls_certificate_failure'],
  ['UND_ERR_PRX_TLS', 'proxy_failure'],
  ['UND_ERR_SOCKS', 'proxy_failure'],
  ['ENETUNREACH', 'network_failure'],
  ['EHOSTUNREACH', 'network_failure'],
  ['UND_ERR_SOCKET', 'network_failure'],
  ['ETIMEDOUT', 'network_timeout'],
  ['UND_ERR_CONNECT_TIMEOUT', 'network_timeout'],
  ['UND_ERR_HEADERS_TIMEOUT', 'network_timeout'],
  ['UND_ERR_ABORT', 'transport_abort'],
  ['UND_ERR_ABORTED', 'transport_abort'],
]);

function describeTransportRejection(error, signal) {
  const cause = error?.cause;
  if (signal.aborted && signal.reason?.name === 'TimeoutError') {
    return { category: 'provider_deadline_expired' };
  }
  if (signal.aborted || error?.name === 'AbortError' || cause?.name === 'AbortError') {
    return { category: 'transport_abort' };
  }
  // Node fetch commonly wraps a network error in cause, and a dual-stack
  // connection failure can carry an AggregateError with individual codes.
  const candidates = [
    error, cause, cause?.cause,
    ...(Array.isArray(cause?.errors) ? cause.errors.slice(0, 8) : []),
  ];
  for (const candidate of candidates) {
    const code = candidate?.code;
    const category = transportCodes.get(code);
    if (category) return { category, code };
  }
  return { category: 'transport_unknown' };
}

async function run(key, transport, { providerTimeoutMs, handlerTimeoutMs } = {}) {
  let attempts = 0;
  let upstreamStatus = null;
  let handlerSignal;
  let transportDiagnostic = { category: 'not_attempted' };
  const provider = configuredGeminiProvider(name => ({
    // Only this process-local provider instance is enabled. No environment
    // flag is set and the Edge entrypoint is never imported.
    JOBMATE_RECOMMENDATION_GEMINI_ENABLED: 'true',
    JOBMATE_RECOMMENDATION_GEMINI_MODEL: model,
    GEMINI_API_KEY: key,
  })[name], {
    timeoutMs: providerTimeoutMs,
    async request(url, options) {
      if (attempts !== 0 || url !== endpoint || options.method !== 'POST' ||
          options.redirect !== 'error') throw Error('unexpected_provider_request');
      const body = JSON.parse(options.body);
      // Check the entire content-bearing input before allowing network I/O.
      if (body.model !== model || body.store !== false ||
          !sameJson(JSON.parse(body.input), { instructions, jobs: expectedJobs })) {
        throw Error('unexpected_provider_payload');
      }
      attempts++;
      let response;
      try {
        response = await transport(url, options);
      } catch (error) {
        transportDiagnostic = describeTransportRejection(error, options.signal);
        throw error;
      }
      upstreamStatus = response.status;
      transportDiagnostic = { category: 'http_response_received' };
      return response;
    },
  });
  if (!provider) return { ok: false, reason: 'missing_or_invalid_key', attempts, transportDiagnostic };

  const handler = recommendationExplanationHandler({
    base: fixtureOrigin,
    anon: 'fixture-anon',
    origin: undefined,
    demoUserId: seekerId,
    provider,
    request(url, options) {
      handlerSignal = options.signal;
      return fixtureRequest(url);
    },
    now: () => new Date('2026-11-23T04:00:00Z'),
    timeoutMs: handlerTimeoutMs,
  });
  const response = await handler(new Request('http://localhost/smoke', {
    method: 'POST',
    headers: { Authorization: 'Bearer fixture-seeker' },
    body: JSON.stringify({ job_ids: postings.map(job => job.job_id) }),
  }));
  const output = await response.json();
  const mapped = output.explanations;
  const ok = response.ok && attempts === 1 && Array.isArray(mapped) &&
    mapped.length === postings.length && postings.every((job, index) =>
      mapped.filter(row => row.job_id === job.job_id &&
        expectedJobs[index].approved_explanations.includes(row.explanation)).length === 1,
    );
  const reason = ok ? 'validated'
    : response.status === 504 ? 'timeout'
    : upstreamStatus === 429 ? 'quota'
    : upstreamStatus === 401 || upstreamStatus === 403 ? 'provider_access_denied'
    : upstreamStatus === 404 ? 'model_or_endpoint_unavailable'
    : upstreamStatus === 400 ? 'provider_rejected_request'
    : 'request_or_validation_failed';
  // The handler signal is observable through its in-memory request transport.
  // A timeout before reaching that transport also belongs to the handler.
  if (reason === 'timeout') {
    transportDiagnostic = {
      category: handlerSignal?.aborted || attempts === 0
        ? 'handler_deadline_expired'
        : 'provider_deadline_expired',
    };
  }
  return { ok, reason, attempts, upstreamStatus, handlerStatus: response.status, transportDiagnostic };
}

function runLiveMode(mode, key, transport) {
  return run(key, transport, mode === '--run-live-extended' ? extendedTimeouts : undefined);
}

async function captureTimeouts(runMock) {
  const original = AbortSignal.timeout;
  const timeouts = [];
  AbortSignal.timeout = milliseconds => {
    timeouts.push(milliseconds);
    return original.call(AbortSignal, milliseconds);
  };
  try {
    return { timeouts, result: await runMock() };
  } finally {
    AbortSignal.timeout = original;
  }
}

async function offlineCheck() {
  const completedFixture = async () => Response.json({
    status: 'completed',
    steps: [
      { type: 'thought' },
      { type: 'model_output', content: [{ type: 'text', text: JSON.stringify({
        explanations: [...expectedJobs].reverse().map(job => ({
          job_id: job.job_id, explanation: job.approved_explanations[0],
        })),
      }) }] },
    ],
  });
  const normal = await captureTimeouts(() => runLiveMode('--run-live', 'fixture-key', completedFixture));
  const extended = await captureTimeouts(() => runLiveMode('--run-live-extended', 'fixture-key', completedFixture));
  const extendedRejection = await runLiveMode('--run-live-extended', 'fixture-key', async () => {
    throw Error('fixture fetch rejection');
  });
  const stalledFixture = async (_, { signal }) => {
    await delay(1000, undefined, { signal });
    throw Error('expected_abort');
  };
  const timeout = await run('fixture-key', stalledFixture, { providerTimeoutMs: 50 });
  const handlerTimeout = await run('fixture-key', stalledFixture, {
    providerTimeoutMs: 500, handlerTimeoutMs: 50,
  });
  const rejectionCases = [
    ['dns', new TypeError('fixture', { cause: { code: 'ENOTFOUND' } }), 'dns_failure', 'ENOTFOUND'],
    ['connection', new AggregateError([{ code: 'ECONNREFUSED' }]), 'connection_failure', 'ECONNREFUSED'],
    ['reset', { code: 'ECONNRESET' }, 'connection_failure', 'ECONNRESET'],
    ['tls', { code: 'CERT_HAS_EXPIRED' }, 'tls_certificate_failure', 'CERT_HAS_EXPIRED'],
    ['proxy', { code: 'UND_ERR_PRX_TLS' }, 'proxy_failure', 'UND_ERR_PRX_TLS'],
    ['network', { code: 'ENETUNREACH' }, 'network_failure', 'ENETUNREACH'],
    ['networkTimeout', { code: 'ETIMEDOUT' }, 'network_timeout', 'ETIMEDOUT'],
    ['abort', new DOMException('fixture', 'AbortError'), 'transport_abort'],
    ['unknown', { code: 'UNRECOGNIZED_FIXTURE', message: 'Never report this fixture' }, 'transport_unknown'],
  ];
  const rejections = {};
  let rejectionsPassed = true;
  for (const [name, error, category, code] of rejectionCases) {
    const result = await run('fixture-key', async () => {
      throw new TypeError('fixture fetch rejection', { cause: error });
    });
    rejections[name] = result;
    rejectionsPassed &&= !result.ok && result.attempts === 1 &&
      result.upstreamStatus === null && result.handlerStatus === 502 &&
      sameJson(result.transportDiagnostic, code ? { category, code } : { category });
  }
  const valid = normal.result;
  const ok = sameJson(normal.timeouts, [6500, 4000]) &&
    sameJson(extended.timeouts, [17_000, 15_000]) &&
    valid.ok && valid.transportDiagnostic.category === 'http_response_received' &&
    extended.result.ok && extended.result.attempts === 1 &&
    !extendedRejection.ok && extendedRejection.attempts === 1 &&
    extendedRejection.transportDiagnostic.category === 'transport_unknown' &&
    timeout.reason === 'timeout' && timeout.attempts === 1 &&
    timeout.transportDiagnostic.category === 'provider_deadline_expired' &&
    handlerTimeout.reason === 'timeout' && handlerTimeout.attempts === 1 &&
    handlerTimeout.transportDiagnostic.category === 'handler_deadline_expired' &&
    rejectionsPassed;
  return {
    ok, completedInteraction: valid, timeout, rejections,
    normalTimeouts: normal.timeouts, extended, extendedRejection, handlerTimeout,
  };
}

async function main() {
  const [mode, ...rest] = process.argv.slice(2);
  if (rest.length || !['--offline', '--run-live', '--run-live-extended'].includes(mode)) {
    console.error('Usage: node tools/recommendations/gemini-smoke.mjs --offline | --run-live | --run-live-extended (live modes require separate approval)');
    process.exitCode = 2;
    return;
  }
  const result = mode === '--offline' ? await offlineCheck()
    : await runLiveMode(mode, process.env.JOBMATE_GEMINI_SMOKE_KEY, fetch);
  console.log(JSON.stringify({ mode, model, ...result }));
  if (!result.ok) process.exitCode = 1;
}

main().catch(() => {
  console.error('Smoke check failed unexpectedly. Details withheld.');
  process.exitCode = 1;
});

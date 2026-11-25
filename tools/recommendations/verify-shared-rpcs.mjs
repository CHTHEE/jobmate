import { boundedBody, uuid } from '../../supabase/functions/_shared/chat_basic/protocol.mjs';
import { publicPostingFacts } from '../../supabase/functions/explain-job-recommendations/handler.mjs';

const rpcFields = {
  list_published_jobs: ['job_id', 'application_deadline', 'employment_type', 'work_arrangement'],
  list_my_job_applications: ['job_id'],
};
const dateFormat = new Intl.DateTimeFormat('sv-SE', {
  timeZone: 'Asia/Kuala_Lumpur', year: 'numeric', month: '2-digit', day: '2-digit',
});

function jwtRole(token) {
  try {
    const parts = token.split('.');
    if (parts.length !== 3 || !parts.every(part => /^[\w-]+$/.test(part))) return null;
    return JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8')).role;
  } catch {
    return null;
  }
}

function validDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().startsWith(value);
}

async function inspect({ base, key, token }, rpc, fixtures) {
  const fields = rpcFields[rpc];
  const url = new URL(`/rest/v1/rpc/${rpc}`, base);
  url.search = new URLSearchParams({
    select: fields.join(','),
    job_id: `in.(${[...fixtures.keys()].join(',')})`,
  });
  const report = { rpc, status: null, contentRange: null, rows: [], issues: [] };
  let response;
  try {
    response = await fetch(url, {
      method: 'POST',
      headers: {
        apikey: key, Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json', Prefer: 'count=exact',
      },
      body: '{}',
      redirect: 'error',
      signal: AbortSignal.timeout(6500),
    });
  } catch {
    report.issues.push('Request failed or timed out.');
    return report;
  }
  report.status = response.status;
  const range = response.headers.get('content-range');
  report.contentRange = range === null || /^(?:\*|\d+-\d+)\/(?:\*|\d+)$/.test(range)
    ? range : '[redacted invalid header]';
  if (!response.ok) {
    void response.body?.cancel().catch(() => {});
    report.issues.push('RPC returned an error. Response body withheld.');
    return report;
  }
  let rows;
  try {
    const bytes = await boundedBody(response, 16_384);
    rows = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
  } catch {
    report.issues.push('Unreadable, oversized, or invalid JSON response.');
    return report;
  }
  if (!Array.isArray(rows)) {
    report.issues.push('Expected an array of rows.');
    return report;
  }
  const expected = rows.length === 0 ? '*/0' : `0-${rows.length - 1}/${rows.length}`;
  report.rowCount = rows.length;
  report.countMatchesHandler = range === expected;
  if (!report.countMatchesHandler) {
    report.issues.push(`Handler expects ${expected}. Header is missing, incomplete, or invalid.`);
  }
  for (const row of rows) {
    if (!row || typeof row !== 'object' || !fields.every(field => Object.hasOwn(row, field))) {
      report.issues.push('A row is missing one or more selected columns.');
      continue;
    }
    if (Object.keys(row).length !== fields.length) {
      report.issues.push('Unexpected columns in the response. Extra values withheld.');
    }
    const job = fixtures.get(row.job_id);
    if (!job) {
      report.issues.push('A row contains an unexpected or invalid job ID.');
      continue;
    }
    if (rpc === 'list_my_job_applications') {
      report.rows.push({ job });
      continue;
    }
    const date = validDate(row.application_deadline) ? row.application_deadline : null;
    const facts = publicPostingFacts(row.employment_type, row.work_arrangement);
    if (!date) report.issues.push('A published job has a missing or invalid date-only deadline.');
    if (facts.approved_explanations.length === 0) {
      report.issues.push('A published job has no recognized posting-note fields.');
    }
    report.rows.push({
      job, applicationDeadline: date,
      employmentType: facts.employment_type, workArrangement: facts.work_arrangement,
    });
  }
  if (rpc === 'list_published_jobs' &&
      new Set(report.rows.map(row => row.job)).size !== report.rows.length) {
    report.issues.push('The published feed returned duplicate job IDs.');
  }
  return report;
}

async function main() {
  const [mode, eligible, applied, ...extra] = process.argv.slice(2);
  if (mode !== '--run-shared' || !uuid(eligible) || !uuid(applied) || eligible === applied || extra.length) {
    console.error('Usage after approval: node tools/recommendations/verify-shared-rpcs.mjs --run-shared ELIGIBLE_JOB_UUID APPLIED_JOB_UUID');
    process.exitCode = 2;
    return;
  }
  const base = process.env.JOBMATE_VERIFY_SUPABASE_URL;
  const key = process.env.JOBMATE_VERIFY_PUBLIC_KEY ?? '';
  const token = process.env.JOBMATE_VERIFY_USER_JWT ?? '';
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(base ?? '') ||
      !(/^sb_publishable_[\w-]+$/.test(key) || jwtRole(key) === 'anon') ||
      jwtRole(token) !== 'authenticated') {
    console.error('Provide the approved hosted project URL, a publishable or anon key, and an authenticated user JWT through the documented environment variables.');
    process.exitCode = 2;
    return;
  }
  const credentials = { base, key, token };
  const today = dateFormat.format(new Date());
  const cases = [
    { name: 'eligible and zero applications', fixtures: new Map([[eligible, 'eligible']]), hasApplication: false },
    { name: 'previously applied', fixtures: new Map([[applied, 'applied']]), hasApplication: true },
    { name: 'mixed shortlist', fixtures: new Map([[eligible, 'eligible'], [applied, 'applied']]), hasApplication: true },
  ];
  const reports = [];
  for (const { name, fixtures, hasApplication } of cases) {
    const [published, applications] = await Promise.all(
      Object.keys(rpcFields).map(rpc => inspect(credentials, rpc, fixtures)),
    );
    if (fixtures.has(eligible) &&
        !published.rows.some(row => row.job === 'eligible' && row.applicationDeadline >= today)) {
      published.issues.push('The eligible fixture is absent or does not have an open deadline.');
    }
    if (applications.rows.some(row => row.job === 'eligible') ||
        applications.rows.some(row => row.job === 'applied') !== hasApplication) {
      applications.issues.push('Application presence differs from the expected fixture state.');
    }
    reports.push({ case: name, published, applications });
  }
  console.log(JSON.stringify({ businessDate: today, reports }, null, 2));
  if (reports.some(({ published, applications }) =>
    published.issues.length > 0 || applications.issues.length > 0)) process.exitCode = 1;
}

main().catch(() => {
  console.error('Verification stopped unexpectedly. Error details withheld.');
  process.exitCode = 1;
});

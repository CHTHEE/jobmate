// Run manually in the approved, signed-in localhost Flutter Chrome tab.
// The next My Applications refresh supplies the existing session headers.
(() => {
  const project = 'https://ibbyejgpjboearzhvwlr.supabase.co';
  const prefix = '/rest/v1/rpc/';
  const apps = 'list_my_job_applications';
  const feed = 'list_published_jobs';
  const eligible = '2a7b498f-02be-4dac-9c3a-353374f0c92f';
  const applied = 'f35f1dc7-a54c-41a6-986c-84cd2e8faf2c';
  const jobFields = ['job_id', 'application_deadline', 'employment_type', 'work_arrangement'];
  const types = ['full_time', 'part_time', 'contract', 'internship', 'temporary'];
  const arrangements = ['on_site', 'hybrid', 'remote'];
  if (!/^http:\/\/(?:localhost|127\.0\.0\.1)(?::\d+)?$/.test(location.origin)) {
    console.log('Open the signed-in localhost Flutter tab first.');
    return;
  }

  const original = window.fetch;
  function restore() {
    clearTimeout(timer);
    if (window.fetch === capture) window.fetch = original;
  }
  async function inspect(rpc, ids, headers) {
    const fields = rpc === feed ? jobFields : ['job_id'];
    const url = new URL(prefix + rpc, project);
    url.search = new URLSearchParams({ select: fields.join(','), job_id: `in.(${ids.join(',')})` });
    const response = await original.call(window, url, {
      method: 'POST', headers, body: '{}', redirect: 'error',
      signal: AbortSignal.timeout(6500),
    });
    const range = response.headers.get('content-range');
    const result = {
      rpc, status: response.status,
      contentRange: range === null || /^(?:\*|\d+-\d+)\/(?:\*|\d+)$/.test(range)
        ? range : 'invalid',
    };
    if (!response.ok) return { ...result, pass: false };
    const rows = await response.json();
    if (!Array.isArray(rows)) return { ...result, pass: false };
    const expected = rows.length ? `0-${rows.length - 1}/${rows.length}` : '*/0';
    let pass = range === expected && rows.every(row => row && ids.includes(row.job_id) &&
      Object.keys(row).length === fields.length && fields.every(field => Object.hasOwn(row, field)));
    const jobIds = rows.map(row => row?.job_id);
    if (rpc === apps) {
      pass &&= !jobIds.includes(eligible) && jobIds.includes(applied) === ids.includes(applied);
    } else {
      const today = new Intl.DateTimeFormat('sv-SE', {
        timeZone: 'Asia/Kuala_Lumpur', year: 'numeric', month: '2-digit', day: '2-digit',
      }).format(new Date());
      pass &&= new Set(jobIds).size === rows.length &&
        (!ids.includes(eligible) || rows.some(row => row.job_id === eligible &&
          /^\d{4}-\d{2}-\d{2}$/.test(row.application_deadline) &&
          new Date(row.application_deadline + 'T00:00:00Z').toJSON()?.slice(0, 10) === row.application_deadline &&
          row.application_deadline >= today &&
          (types.includes(row.employment_type) || arrangements.includes(row.work_arrangement))));
    }
    return { ...result, pass, rowCount: rows.length };
  }

  async function verify(headers) {
    const cases = [[eligible], [applied], [eligible, applied]];
    for (const [index, ids] of cases.entries()) {
      const report = await Promise.all([feed, apps].map(async rpc => {
        try {
          return await inspect(rpc, ids, headers);
        } catch {
          return { rpc, pass: false, error: 'Request or response could not be read' };
        }
      }));
      console.log(['Eligible only', 'Applied only', 'Mixed shortlist'][index], report);
    }
  }

  function capture(input, init) {
    try {
      const url = new URL(input instanceof Request ? input.url : input, location.href);
      if (url.origin === project && url.pathname === prefix + apps) {
        const source = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
        const token = source.get('authorization');
        const key = source.get('apikey');
        if (token?.startsWith('Bearer ') && key) {
          restore();
          void verify({
            Authorization: token, apikey: key,
            'Content-Type': 'application/json', Prefer: 'count=exact',
          });
        }
      }
    } catch {
      // An unrelated fetch must continue normally.
    }
    return original.call(this, input, init);
  }

  const timer = setTimeout(() => {
    restore();
    console.log('No matching session request captured. Reopen My Applications or use the existing harness.');
  }, 30_000);
  window.fetch = capture;
  console.log('Within 30 seconds, refresh My Applications using the in-app refresh control.');
})();

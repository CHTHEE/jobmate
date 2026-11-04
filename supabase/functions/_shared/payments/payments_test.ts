import { BillplzSandbox } from "./billplz.ts";
import {
  eligibility,
  PaymentError,
  verifiedStatus,
  verifyBinding,
} from "./domain.ts";
import type {
  Actor,
  Assignment,
  Attempt,
  BillplzGateway,
  PaymentStore,
  VerifiedBill,
} from "./domain.ts";
import { paymentHttp, paymentWebhookHttp } from "./http.ts";
import { PaymentService } from "./service.ts";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, received ${
        JSON.stringify(actual)
      }`,
    );
  }
}
async function rejects(action: () => unknown, code?: string) {
  try {
    await action();
  } catch (error) {
    if (code && (!(error instanceof PaymentError) || error.code !== code)) {
      throw error;
    }
    return;
  }
  throw new Error("Expected rejection.");
}
const employer: Actor = { id: "employer", role: "employer", status: "active" };
const worker: Actor = { id: "worker", role: "job_seeker", status: "active" };
const admin: Actor = { id: "admin", role: "administrator", status: "active" };
const assignmentId = "11111111-1111-4111-8111-111111111111";
const requestId = "22222222-2222-4222-8222-222222222222";
function terms(): Assignment {
  return {
    assignment_id: assignmentId,
    employer_id: employer.id,
    job_seeker_id: worker.id,
    job_title: "Cafe shift",
    company_name: "Test Cafe",
    worker_name: "Test Worker",
    employment_type: "part_time",
    accepted: true,
    completed: true,
    work_verified: true,
    payment_blocked: false,
    employer_authorized: true,
    amount_minor: 10000,
    currency: "MYR",
    terms_version: "accepted-v1",
    payer_name: "Test Employer",
    payer_email: "payer@example.test",
  };
}
function attempt(): Attempt {
  return {
    payment_id: requestId,
    assignment_id: assignmentId,
    employer_id: employer.id,
    job_seeker_id: worker.id,
    agreed_amount_minor: 10000,
    bonus_minor: 0,
    amount_minor: 10000,
    currency: "MYR",
    terms_version: "accepted-v1",
    status: "PENDING",
    provider_payment_id: null,
    checkout_url: null,
    payment_method: null,
    failure_reason: null,
    created_at: "2026-11-04T00:00:00Z",
    confirmed_at: null,
  };
}
function bill(payment = attempt()): VerifiedBill {
  return {
    id: "bill_test",
    reference: payment.payment_id,
    collection: "test_collection",
    amount: payment.amount_minor,
    paidAmount: 0,
    paid: false,
    state: "due",
    url: "https://www.billplz-sandbox.com/bills/bill_test",
    method: null,
  };
}

/** Test-only atomic store. It is never imported by either Edge Function. */
class MemoryStore implements PaymentStore {
  rows: Attempt[] = [];
  events = new Set<string>();
  notifications = 0;
  async attempts(id: string) {
    return this.rows.filter((a) => a.assignment_id === id).toReversed();
  }
  async byId(id: string) {
    const row = this.rows.find((a) => a.payment_id === id);
    if (!row) throw new PaymentError("NOT_FOUND", "Not found", 404);
    return row;
  }
  async reserve(
    actor: Actor,
    assignment: Assignment,
    id: string,
    bonus: number,
  ) {
    const prior = this.rows.find((a) => a.payment_id === id);
    if (prior) {
      if (
        prior.assignment_id !== assignment.assignment_id ||
        prior.bonus_minor !== bonus
      ) throw new PaymentError("ID_REUSED", "ID already used", 409);
      return { attempt: prior, created: false };
    }
    const all = this.rows.filter((a) =>
      a.assignment_id === assignment.assignment_id
    );
    const active = all.find((a) =>
      ["PENDING", "PROCESSING"].includes(a.status)
    );
    if (active) return { attempt: active, created: false };
    const reason = eligibility(actor, assignment, all);
    if (reason) throw new PaymentError("NOT_ELIGIBLE", reason, 403);
    const row = {
      ...attempt(),
      payment_id: id,
      bonus_minor: bonus,
      amount_minor: assignment.amount_minor + bonus,
    };
    this.rows.push(row);
    return { attempt: row, created: true };
  }
  async attachCheckout(id: string, provider: VerifiedBill) {
    const row = await this.byId(id);
    verifyBinding(row, provider);
    row.provider_payment_id = provider.id;
    row.checkout_url = provider.url;
    return row;
  }
  async rejectCreation(id: string, reason: string) {
    const row = await this.byId(id);
    if (row.status !== "PENDING" || row.provider_payment_id) {
      throw new PaymentError("STALE", "Already bound", 409);
    }
    row.status = "FAILED";
    row.failure_reason = reason;
  }
  async applyVerified(id: string, provider: VerifiedBill, eventId: string) {
    const row = await this.byId(id);
    verifyBinding(row, provider);
    if (this.events.has(eventId)) return;
    this.events.add(eventId);
    row.provider_payment_id = provider.id;
    row.checkout_url = provider.url;
    const status = verifiedStatus(provider);
    if (row.status === "SUCCEEDED") return;
    if (status === "SUCCEEDED") {
      if (
        this.rows.some((a) =>
          a !== row && a.assignment_id === row.assignment_id &&
          a.status === "SUCCEEDED"
        )
      ) throw new PaymentError("DUPLICATE_SUCCESS", "Already paid", 409);
      row.confirmed_at = "2026-11-04T01:00:00Z";
      this.notifications += 2;
    }
    row.status = status;
  }
}
function fixture() {
  const assignment = terms(), store = new MemoryStore();
  let creates = 0;
  const gateway: BillplzGateway = {
    create: async (payment) => {
      creates++;
      return bill(payment);
    },
    retrieve: async () => bill(store.rows[0]),
    verifyCallback: async () => ({
      billId: "bill_test",
      paymentId: requestId,
      eventId: "event-1",
    }),
  };
  const service = new PaymentService(
    { get: async () => assignment, list: async () => [assignment] },
    store,
    gateway,
  );
  return { assignment, store, gateway, service, creates: () => creates };
}

Deno.test("Base/bonus: authoritative agreed minimum plus nonnegative optional bonus", async () => {
  const f = fixture();
  await f.service.create(employer, assignmentId, requestId, 2500);
  equal(f.store.rows[0].amount_minor, 12500);
  equal(f.store.rows[0].agreed_amount_minor, 10000);
  equal(f.store.rows[0].bonus_minor, 2500);
  for (const invalid of [-1, 0.1, NaN, Infinity, 1000000000000]) {
    await rejects(
      () =>
        fixture().service.create(employer, assignmentId, requestId, invalid),
      "INVALID_AMOUNT",
    );
  }
});
for (
  const key of [
    "accepted",
    "completed",
    "work_verified",
    "employer_authorized",
  ] as const
) {
  Deno.test(`Eligibility rejects ${key}=false before gateway creation`, async () => {
    const f = fixture();
    f.assignment[key] = false;
    await rejects(
      () => f.service.create(employer, assignmentId, requestId, 0),
      "NOT_ELIGIBLE",
    );
    equal(f.creates(), 0);
  });
}
Deno.test("Full-time and unresolved work dispute are blocked", async () => {
  const f = fixture();
  f.assignment.employment_type = "full_time";
  await rejects(
    () => f.service.create(employer, assignmentId, requestId, 0),
    "NOT_ELIGIBLE",
  );
  f.assignment.employment_type = "temporary";
  f.assignment.payment_blocked = true;
  await rejects(
    () => f.service.create(employer, assignmentId, requestId, 0),
    "NOT_ELIGIBLE",
  );
  equal(f.creates(), 0);
});
Deno.test("Worker/Admin are read-only; wrong parties and inactive users cannot access payments", async () => {
  const f = fixture();
  await f.service.get(worker, assignmentId);
  await f.service.get(admin, assignmentId);
  for (
    const actor of [worker, admin, { ...employer, id: "wrong" }, {
      ...employer,
      status: "suspended",
    }]
  ) {
    await rejects(() => f.service.create(actor, assignmentId, requestId, 0));
  }
  await rejects(
    () => f.service.get({ ...worker, id: "wrong" }, assignmentId),
    "FORBIDDEN",
  );
  equal(f.creates(), 0);
});
Deno.test("Concurrent checkout requests create at most one bill", async () => {
  const f = fixture();
  let release!: () => void;
  const waiting = new Promise<void>((resolve) => release = resolve);
  let calls = 0;
  f.gateway.create = async (payment) => {
    calls++;
    await waiting;
    return bill(payment);
  };
  const first = f.service.create(employer, assignmentId, requestId, 0);
  await new Promise((resolve) => setTimeout(resolve, 0));
  await rejects(
    () =>
      f.service.create(
        employer,
        assignmentId,
        "33333333-3333-4333-8333-333333333333",
        0,
      ),
    "PAYMENT_UNCERTAIN",
  );
  release();
  await first;
  await f.service.create(employer, assignmentId, requestId, 0);
  equal(calls, 1);
  equal(f.store.rows.length, 1);
});
Deno.test("Active checkout cannot silently charge a different Bonus, and a new dispute blocks resume", async () => {
  const f = fixture();
  await f.service.create(employer, assignmentId, requestId, 500);
  await rejects(
    () =>
      f.service.create(
        employer,
        assignmentId,
        "33333333-3333-4333-8333-333333333333",
        1000,
      ),
    "ACTIVE_AMOUNT_LOCKED",
  );
  equal(f.creates(), 1);
  equal(
    (await f.service.get(employer, assignmentId)).can_resume_checkout,
    true,
  );
  equal(
    (await f.service.get(worker, assignmentId)).attempts[0].checkout_url,
    null,
  );
  f.assignment.payment_blocked = true;
  equal(
    (await f.service.get(employer, assignmentId)).can_resume_checkout,
    false,
  );
  await rejects(
    () => f.service.create(employer, assignmentId, requestId, 500),
    "NOT_ELIGIBLE",
  );
});
Deno.test("Lost create response remains pending and is not blindly retried", async () => {
  const f = fixture();
  let calls = 0;
  f.gateway.create = async () => {
    calls++;
    throw new Error("Connection lost");
  };
  await rejects(() => f.service.create(employer, assignmentId, requestId, 0));
  await rejects(
    () =>
      f.service.create(
        employer,
        assignmentId,
        "33333333-3333-4333-8333-333333333333",
        0,
      ),
    "PAYMENT_UNCERTAIN",
  );
  equal(calls, 1);
  equal(f.store.rows[0].status, "PENDING");
  equal(f.store.notifications, 0);
});
Deno.test("Definite request rejection permits retry while retaining failed history", async () => {
  const f = fixture();
  f.gateway.create = async () => {
    throw new PaymentError("CHECKOUT_REJECTED", "Rejected", 422);
  };
  await rejects(
    () => f.service.create(employer, assignmentId, requestId, 0),
    "CHECKOUT_REJECTED",
  );
  equal(f.store.rows[0].status, "FAILED");
  f.gateway.create = async (payment) => bill(payment);
  await f.service.create(
    employer,
    assignmentId,
    "33333333-3333-4333-8333-333333333333",
    500,
  );
  equal(f.store.rows.length, 2);
  equal(f.store.rows[0].status, "FAILED");
  equal(f.store.notifications, 0);
});
Deno.test("Verified success is idempotent, notified once, never downgraded or repaid", async () => {
  const f = fixture();
  await f.service.create(employer, assignmentId, requestId, 0);
  f.gateway.retrieve = async () => ({
    ...bill(),
    paid: true,
    state: "paid",
    paidAmount: 10000,
  });
  await f.service.webhook(new Request("https://callback.test"));
  await f.service.webhook(new Request("https://callback.test"));
  equal(f.store.rows[0].status, "SUCCEEDED");
  equal(f.store.notifications, 2);
  f.gateway.retrieve = async () => bill();
  await f.service.webhook(new Request("https://callback.test"));
  equal(f.store.rows[0].status, "SUCCEEDED");
  await rejects(() =>
    f.service.create(
      employer,
      assignmentId,
      "33333333-3333-4333-8333-333333333333",
      0,
    )
  );
  equal(f.creates(), 1);
});
Deno.test("Callback before checkout attachment can bind only the exact payment and total", async () => {
  const f = fixture();
  f.store.rows.push(attempt());
  f.gateway.retrieve = async () => ({
    ...bill(),
    paid: true,
    state: "paid",
    paidAmount: 10000,
  });
  await f.service.webhook(new Request("https://callback.test"));
  equal(f.store.rows[0].status, "SUCCEEDED");
  equal(f.store.notifications, 2);
  const wrong = fixture();
  wrong.store.rows.push(attempt());
  wrong.gateway.retrieve = async () => ({ ...bill(), amount: 9000 });
  await rejects(
    () => wrong.service.webhook(new Request("https://callback.test")),
    "PROVIDER_MISMATCH",
  );
  equal(wrong.store.notifications, 0);
});
Deno.test("Billplz due after transaction failure remains Pending, not a new payable attempt", async () => {
  equal(verifiedStatus({ ...bill(), state: "due", paid: false }), "PENDING");
  equal(
    verifiedStatus({ ...bill(), state: "deleted", paid: false }),
    "CANCELLED",
  );
});
Deno.test("Browser cannot submit agreed amount/status/owner; missing integrations do not return success", async () => {
  const f = fixture();
  const request = (body: object) =>
    new Request("https://edge.test", {
      method: "POST",
      body: JSON.stringify(body),
    });
  equal(
    (await paymentHttp(
      request({
        action: "create_checkout",
        assignment_id: assignmentId,
        request_id: requestId,
        amount_minor: 1,
      }),
      employer,
      f.service,
    )).status,
    400,
  );
  equal(
    (await paymentHttp(
      request({
        action: "create_checkout",
        assignment_id: assignmentId,
        request_id: requestId,
      }),
      worker,
      f.service,
    )).status,
    403,
  );
  equal(
    (await paymentHttp(request({ action: "list_assignments" }), employer))
      .status,
    501,
  );
  equal(
    (await paymentWebhookHttp(
      new Request("https://edge.test", { method: "POST" }),
    )).status,
    501,
  );
});

const config = {
  apiKey: "fixture-key",
  signatureKey: "fixture-signature",
  collectionId: "test_collection",
  callbackUrl: "https://project.example.test/payment-webhook",
  returnUrl: "http://localhost:8080/payments/return",
};
async function signedCallback(fields: Record<string, string>) {
  const source = Object.entries(fields).map(([k, v]) => k + v).sort((a, b) =>
    a.toLowerCase() < b.toLowerCase() ? -1 : 1
  ).join("|");
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(config.signatureKey),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = [
    ...new Uint8Array(
      await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(source)),
    ),
  ].map((b) => b.toString(16).padStart(2, "0")).join("");
  return new URLSearchParams({ ...fields, x_signature: signature });
}
Deno.test("Billplz adapter uses Sandbox, integer sen, server URLs and immutable reference", async () => {
  const gateway = new BillplzSandbox(config, async (input, init) => {
    equal(String(input), "https://www.billplz-sandbox.com/api/v3/bills");
    equal(init?.redirect, "error");
    const data = new URLSearchParams(init?.body as URLSearchParams);
    equal(data.get("amount"), "10000");
    equal(data.get("reference_1"), requestId);
    equal(
      new URL(data.get("callback_url")!).searchParams.get("payment_id"),
      requestId,
    );
    return Response.json({
      id: "bill_test",
      reference_1: requestId,
      collection_id: "test_collection",
      amount: 10000,
      paid_amount: 0,
      paid: false,
      state: "due",
      url: bill().url,
    });
  });
  equal((await gateway.create(attempt(), terms())).amount, 10000);
});
Deno.test("Flutter hash URLs retain the payment ID inside the route fragment", async () => {
  const gateway = new BillplzSandbox({
    ...config,
    returnUrl: "http://localhost:8080/#/payments/return",
  }, async (_input, init) => {
    const data = new URLSearchParams(init?.body as URLSearchParams);
    const redirect = new URL(data.get("redirect_url")!);
    equal(redirect.hash, `#/payments/return?payment_id=${requestId}`);
    return Response.json({
      id: "bill_test",
      reference_1: requestId,
      collection_id: "test_collection",
      amount: 10000,
      paid_amount: 0,
      paid: false,
      state: "due",
      url: bill().url,
    });
  });
  await gateway.create(attempt(), terms());
});
Deno.test("Billplz HMAC rejects tampering, duplicate fields, missing signatures and oversized bodies", async () => {
  const gateway = new BillplzSandbox(config);
  const form = await signedCallback({
    id: "bill_test",
    paid: "true",
    state: "paid",
    amount: "10000",
    paid_amount: "10000",
  });
  const callback = (body: string) =>
    new Request(`${config.callbackUrl}?payment_id=${requestId}`, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body,
    });
  equal(
    (await gateway.verifyCallback(callback(form.toString()))).billId,
    "bill_test",
  );
  await rejects(
    () =>
      gateway.verifyCallback(
        callback(form.toString().replace("amount=10000", "amount=1")),
      ),
    "INVALID_SIGNATURE",
  );
  await rejects(
    () => gateway.verifyCallback(callback(form.toString() + "&id=other")),
    "INVALID_CALLBACK",
  );
  await rejects(
    () => gateway.verifyCallback(callback("id=bill_test")),
    "INVALID_SIGNATURE",
  );
  await rejects(
    () => gateway.verifyCallback(callback("x".repeat(32769))),
    "INVALID_CALLBACK",
  );
});
Deno.test("Production checkout URLs and mismatched Collection IDs are rejected", async () => {
  for (
    const mismatch of [{ url: "https://www.billplz.com/bills/x" }, {
      collection_id: "other",
    }]
  ) {
    const gateway = new BillplzSandbox(
      config,
      async () =>
        Response.json({
          id: "bill_test",
          reference_1: requestId,
          collection_id: "test_collection",
          amount: 10000,
          paid_amount: 0,
          paid: false,
          state: "due",
          url: bill().url,
          ...mismatch,
        }),
    );
    await rejects(() => gateway.retrieve("bill_test"), "BAD_PROVIDER_RESPONSE");
  }
});

import {
  billplzSandboxFromEnvironment,
  paymentSecretNames,
  readBillplzSandboxConfig,
} from "./config.ts";
import { PaymentError } from "./domain.ts";
import { paymentHttp } from "./http.ts";

const values: Record<string, string> = {
  BILLPLZ_SANDBOX_API_KEY: "fixture-api-key",
  BILLPLZ_SANDBOX_X_SIGNATURE_KEY: "fixture-signature-key",
  BILLPLZ_SANDBOX_COLLECTION_ID: "fixture-collection",
  JOBMATE_PAYMENT_RETURN_URL: "http://localhost:8080/#/payments/return",
  SUPABASE_URL: "https://project.example.test",
};
function equal(actual: unknown, expected: unknown) {
  if (actual !== expected) throw new Error("Configuration assertion failed.");
}
function rejected(config: Record<string, string>, forbiddenText?: string) {
  try {
    readBillplzSandboxConfig((name) => config[name]);
  } catch (error) {
    if (
      !(error instanceof PaymentError) || error.code !== "INVALID_CONFIGURATION"
    ) throw error;
    if (forbiddenText && error.message.includes(forbiddenText)) {
      throw new Error("Configuration error exposed a value.");
    }
    return;
  }
  throw new Error("Expected invalid configuration to be rejected.");
}

Deno.test("Server configuration matches named secrets and the existing webhook route", () => {
  const config = readBillplzSandboxConfig((name) => values[name]);
  equal(config.apiKey, values.BILLPLZ_SANDBOX_API_KEY);
  equal(config.signatureKey, values.BILLPLZ_SANDBOX_X_SIGNATURE_KEY);
  equal(config.collectionId, values.BILLPLZ_SANDBOX_COLLECTION_ID);
  equal(
    config.callbackUrl,
    "https://project.example.test/functions/v1/payment-webhook",
  );
  equal(config.returnUrl, values.JOBMATE_PAYMENT_RETURN_URL);
});

for (const name of [...Object.values(paymentSecretNames), "SUPABASE_URL"]) {
  Deno.test(`Missing or blank ${name} fails without exposing other values`, () => {
    for (const value of ["", "   "]) {
      rejected({ ...values, [name]: value }, values.BILLPLZ_SANDBOX_API_KEY);
    }
  });
}

Deno.test("Clipboard whitespace is trimmed", () => {
  const config = readBillplzSandboxConfig((name) => `  ${values[name]}\n`);
  equal(config.apiKey, values.BILLPLZ_SANDBOX_API_KEY);
  equal(config.signatureKey, values.BILLPLZ_SANDBOX_X_SIGNATURE_KEY);
});

Deno.test("Malformed URLs, URL credentials and unsafe nonlocal HTTP are rejected safely", () => {
  for (
    const value of [
      "secret-pasted-into-url",
      "javascript:alert(1)",
      "http://example.test/payments/return",
      "https://user:private@example.test/payments/return",
      "https://example.test/wrong-page",
    ]
  ) {
    rejected({ ...values, JOBMATE_PAYMENT_RETURN_URL: value }, value);
  }
  for (
    const value of [
      "http://localhost:54321",
      "https://project.example.test/auth/v1",
      "https://project.example.test?key=private",
    ]
  ) {
    rejected({ ...values, SUPABASE_URL: value }, value);
  }
});

Deno.test("HTTPS path return URLs are supported alongside Flutter hash routing", () => {
  const config = readBillplzSandboxConfig((name) =>
    ({
      ...values,
      JOBMATE_PAYMENT_RETURN_URL:
        "https://jobmate.example.test/payments/return",
    })[name]
  );
  equal(config.returnUrl, "https://jobmate.example.test/payments/return");
});

Deno.test("Configuration alone does not call Billplz or enable payment creation", async () => {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = () => {
    calls++;
    throw new Error("Unexpected network call.");
  };
  try {
    billplzSandboxFromEnvironment((name) => values[name]);
    const response = await paymentHttp(
      new Request("https://edge.example.test", {
        method: "POST",
        body: JSON.stringify({
          action: "create_checkout",
          assignment_id: "id",
          request_id: "id",
        }),
      }),
      { id: "employer", role: "employer", status: "active" },
    );
    equal(response.status, 501);
    equal(calls, 0);
  } finally {
    globalThis.fetch = original;
  }
});

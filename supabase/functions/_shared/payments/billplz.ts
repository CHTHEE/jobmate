import { PaymentError, verifyBinding } from "./domain.ts";
import type {
  Assignment,
  Attempt,
  BillplzGateway,
  VerifiedBill,
} from "./domain.ts";

export interface BillplzSandboxConfig {
  apiKey: string;
  signatureKey: string;
  collectionId: string;
  callbackUrl: string;
  returnUrl: string;
}
const base = "https://www.billplz-sandbox.com/api/v3/bills";
function checkoutUrl(value: unknown): string {
  if (typeof value !== "string") {
    throw new PaymentError(
      "BAD_PROVIDER_RESPONSE",
      "Missing checkout URL.",
      502,
    );
  }
  const url = new URL(value);
  if (
    url.protocol !== "https:" || url.hostname !== "www.billplz-sandbox.com" ||
    url.port || url.username || url.password
  ) {
    throw new PaymentError(
      "BAD_PROVIDER_RESPONSE",
      "Only sandbox checkout URLs are accepted.",
      502,
    );
  }
  return url.toString();
}
function endpoint(value: string, localAllowed = false) {
  const url = new URL(value);
  if (
    (url.protocol !== "https:" &&
      !(localAllowed && url.protocol === "http:" &&
        url.hostname === "localhost")) || url.username || url.password
  ) {
    throw new PaymentError(
      "INVALID_CONFIGURATION",
      "Invalid server-owned payment URL.",
      503,
    );
  }
  return url;
}

/** Fixed Sandbox host. Inject secrets only on the server; no live mode switch. */
export class BillplzSandbox implements BillplzGateway {
  constructor(
    private config: BillplzSandboxConfig,
    private fetcher: typeof fetch = fetch,
  ) {
    if (!config.apiKey || !config.signatureKey || !config.collectionId) {
      throw new PaymentError(
        "INVALID_CONFIGURATION",
        "Sandbox credentials are not configured.",
        503,
      );
    }
    endpoint(config.callbackUrl);
    endpoint(config.returnUrl, true);
  }
  private async api(
    url: string,
    init: RequestInit = {},
  ): Promise<VerifiedBill> {
    const response = await this.fetcher(url, {
      ...init,
      redirect: "error",
      signal: AbortSignal.timeout(15000),
      headers: {
        "Authorization": `Basic ${btoa(this.config.apiKey + ":")}`,
        "Content-Type": "application/x-www-form-urlencoded",
        ...init.headers,
      },
    });
    if (!response.ok) {
      if (
        init.method === "POST" && [400, 401, 403, 422].includes(response.status)
      ) {
        throw new PaymentError(
          "CHECKOUT_REJECTED",
          "The sandbox checkout request was rejected. Please check payment details or gateway configuration.",
          422,
        );
      }
      throw new PaymentError(
        "PROVIDER_UNAVAILABLE",
        "Billplz could not confirm the request. Check payment status.",
        502,
      );
    }
    const bill = await response.json();
    if (
      typeof bill.id !== "string" || !bill.id ||
      bill.collection_id !== this.config.collectionId ||
      !Number.isSafeInteger(bill.amount) || bill.amount <= 0 ||
      !Number.isSafeInteger(bill.paid_amount) || bill.paid_amount < 0 ||
      typeof bill.paid !== "boolean" ||
      !["due", "paid", "deleted"].includes(bill.state) ||
      typeof bill.reference_1 !== "string"
    ) {
      throw new PaymentError(
        "BAD_PROVIDER_RESPONSE",
        "Billplz returned inconsistent payment data.",
        502,
      );
    }
    return {
      id: bill.id,
      reference: bill.reference_1,
      collection: bill.collection_id,
      amount: bill.amount,
      paidAmount: bill.paid_amount,
      paid: bill.paid,
      state: bill.state,
      url: checkoutUrl(bill.url),
      method: null,
    }; // A method is not guessed when absent.
  }
  async create(attempt: Attempt, assignment: Assignment) {
    const callback = endpoint(this.config.callbackUrl);
    callback.searchParams.set("payment_id", attempt.payment_id);
    const redirect = endpoint(this.config.returnUrl, true);
    if (redirect.hash.startsWith("#/")) {
      const route = new URL(
        redirect.hash.substring(1),
        "https://jobmate.invalid",
      );
      route.searchParams.set("payment_id", attempt.payment_id);
      redirect.hash = route.pathname + route.search;
    } else {
      redirect.searchParams.set("payment_id", attempt.payment_id);
    }
    const body = new URLSearchParams({
      collection_id: this.config.collectionId,
      name: assignment.payer_name,
      email: assignment.payer_email,
      amount: String(attempt.amount_minor),
      description: "JobMate sandbox assignment payment",
      reference_1_label: "JobMate payment ID",
      reference_1: attempt.payment_id,
      callback_url: callback.toString(),
      redirect_url: redirect.toString(),
    });
    const bill = await this.api(base, { method: "POST", body });
    verifyBinding(attempt, bill);
    return bill;
  }
  async retrieve(billId: string) {
    if (!/^[A-Za-z0-9_-]{1,100}$/.test(billId)) {
      throw new PaymentError(
        "INVALID_REFERENCE",
        "Invalid provider reference.",
      );
    }
    return this.api(`${base}/${encodeURIComponent(billId)}`, { method: "GET" });
  }
  async verifyCallback(request: Request) {
    if (request.method !== "POST") {
      throw new PaymentError("METHOD_NOT_ALLOWED", "POST required.", 405);
    }
    if (
      !request.headers.get("content-type")?.toLowerCase().startsWith(
        "application/x-www-form-urlencoded",
      )
    ) {
      throw new PaymentError(
        "INVALID_CALLBACK",
        "Unsupported callback format.",
        415,
      );
    }
    const reader = request.body?.getReader();
    if (!reader) {
      throw new PaymentError("INVALID_CALLBACK", "Missing callback body.");
    }
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      size += next.value.byteLength;
      if (size > 32768) {
        await reader.cancel();
        throw new PaymentError(
          "INVALID_CALLBACK",
          "Callback is too large.",
          413,
        );
      }
      chunks.push(next.value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    const fields = new URLSearchParams(new TextDecoder().decode(bytes));
    const keys = [...fields.keys()];
    if (new Set(keys).size !== keys.length) {
      throw new PaymentError(
        "INVALID_CALLBACK",
        "Duplicate callback fields.",
        400,
      );
    }
    const signature = fields.get("x_signature") ?? "";
    if (!/^[0-9a-f]{64}$/i.test(signature)) {
      throw new PaymentError(
        "INVALID_SIGNATURE",
        "Invalid callback signature.",
        401,
      );
    }
    const source = [...fields].filter(([key]) => key !== "x_signature").map((
      [key, value],
    ) => key + value)
      .sort((a, b) =>
        a.toLowerCase() < b.toLowerCase()
          ? -1
          : a.toLowerCase() > b.toLowerCase()
          ? 1
          : 0
      ).join("|");
    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(this.config.signatureKey),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"],
    );
    const digest = Uint8Array.from(
      signature.match(/../g)!,
      (pair) => parseInt(pair, 16),
    );
    if (
      !await crypto.subtle.verify(
        "HMAC",
        key,
        digest,
        new TextEncoder().encode(source),
      )
    ) {
      throw new PaymentError(
        "INVALID_SIGNATURE",
        "Invalid callback signature.",
        401,
      );
    }
    const billId = fields.get("id") ?? "";
    const paymentId = new URL(request.url).searchParams.get("payment_id") ?? "";
    if (
      !/^[A-Za-z0-9_-]{1,100}$/.test(billId) ||
      !/^[0-9a-f-]{36}$/i.test(paymentId)
    ) {
      throw new PaymentError("INVALID_CALLBACK", "Missing payment reference.");
    }
    // A modified callback query cannot bind a different payment: the service
    // also verifies Billplz's server-read reference_1, amount and Collection ID.
    return { billId, paymentId, eventId: `billplz:${signature.toLowerCase()}` };
  }
}

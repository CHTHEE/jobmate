import { BillplzSandbox } from "./billplz.ts";
import type { BillplzSandboxConfig } from "./billplz.ts";
import { PaymentError } from "./domain.ts";

export type PaymentEnvironmentReader = (name: string) => string | undefined;

/** NEW server configuration names. No values are stored in the repository.
 * SUPABASE_URL is injected by the deployed Supabase Edge runtime, not a new
 * custom secret. The Flutter client must never read these Billplz settings. */
export const paymentSecretNames = {
  apiKey: "BILLPLZ_SANDBOX_API_KEY",
  signatureKey: "BILLPLZ_SANDBOX_X_SIGNATURE_KEY",
  collectionId: "BILLPLZ_SANDBOX_COLLECTION_ID",
  returnUrl: "JOBMATE_PAYMENT_RETURN_URL",
} as const;

function required(read: PaymentEnvironmentReader, name: string): string {
  const value = read(name)?.trim();
  if (!value) {
    throw new PaymentError(
      "INVALID_CONFIGURATION",
      `Missing server setting: ${name}.`,
      503,
    );
  }
  return value;
}

function parseUrl(value: string, name: string, localAllowed: boolean): URL {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    // Never include the original input in errors: a value could have been
    // pasted into the wrong setting, including a credential.
    throw new PaymentError(
      "INVALID_CONFIGURATION",
      `Invalid URL in server setting: ${name}.`,
      503,
    );
  }
  const localWeb = localAllowed && url.protocol === "http:" &&
    url.hostname === "localhost";
  if (
    (!localWeb && url.protocol !== "https:") || !url.hostname || url.username ||
    url.password
  ) {
    throw new PaymentError(
      "INVALID_CONFIGURATION",
      `Use HTTPS (or localhost HTTP for Web return) in: ${name}.`,
      503,
    );
  }
  return url;
}

export function readBillplzSandboxConfig(
  read: PaymentEnvironmentReader,
): BillplzSandboxConfig {
  const apiKey = required(read, paymentSecretNames.apiKey);
  const signatureKey = required(read, paymentSecretNames.signatureKey);
  const collectionId = required(read, paymentSecretNames.collectionId);
  const project = parseUrl(
    required(read, "SUPABASE_URL"),
    "SUPABASE_URL",
    false,
  );
  if (project.pathname !== "/" || project.search || project.hash) {
    throw new PaymentError(
      "INVALID_CONFIGURATION",
      "SUPABASE_URL must be the project API origin.",
      503,
    );
  }
  const returnUrl = parseUrl(
    required(read, paymentSecretNames.returnUrl),
    paymentSecretNames.returnUrl,
    true,
  );
  // Match the existing GoRouter return route in both hash and path modes.
  const route = returnUrl.hash.startsWith("#/")
    ? returnUrl.hash.substring(1).split("?")[0]
    : returnUrl.pathname;
  if (route !== "/payments/return") {
    throw new PaymentError(
      "INVALID_CONFIGURATION",
      "JOBMATE_PAYMENT_RETURN_URL must open the /payments/return route.",
      503,
    );
  }
  return {
    apiKey,
    signatureKey,
    collectionId,
    callbackUrl: new URL("/functions/v1/payment-webhook", project).toString(),
    returnUrl: returnUrl.toString(),
  };
}

/** Instantiate on the server only after the durable adapters are ready.
 * Loading configuration alone does not enable checkout or make an API call. */
export function billplzSandboxFromEnvironment(
  read: PaymentEnvironmentReader = (name) => Deno.env.get(name),
): BillplzSandbox {
  return new BillplzSandbox(readBillplzSandboxConfig(read));
}

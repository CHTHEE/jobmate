import { active, amount, PaymentError, pendingIntegration } from "./domain.ts";
import type { Actor } from "./domain.ts";
import type { PaymentApplication } from "./service.ts";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const id = (value: unknown): string => {
  if (typeof value !== "string" || !uuid.test(value)) {
    throw new PaymentError(
      "INVALID_ID",
      "A valid payment or assignment ID is required.",
    );
  }
  return value;
};
const reply = (body: object, status = 200) =>
  Response.json({ environment: "sandbox", ...body }, { status });
export async function paymentHttp(
  request: Request,
  actor: Actor,
  app?: PaymentApplication,
): Promise<Response> {
  try {
    active(actor);
    if (request.method !== "POST") {
      throw new PaymentError("METHOD_NOT_ALLOWED", "POST required.", 405);
    }
    let body;
    try {
      body = await request.json();
    } catch {
      throw new PaymentError("INVALID_BODY", "Invalid request body.");
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      throw new PaymentError("INVALID_BODY", "Invalid request body.");
    }
    const allowed: Record<string, string[]> = {
      list_assignments: ["action", "offset", "limit"],
      get_assignment: ["action", "assignment_id"],
      get_payment: ["action", "payment_id"],
      refresh_status: ["action", "assignment_id"],
      create_checkout: ["action", "assignment_id", "request_id", "bonus_minor"],
    };
    if (
      typeof body.action !== "string" || !Object.hasOwn(allowed, body.action) ||
      Object.keys(body).some((key) => !allowed[body.action].includes(key))
    ) {
      throw new PaymentError(
        "INVALID_BODY",
        "Unsupported action or fields. Agreed amounts and ownership come from the server.",
      );
    }
    if (body.action === "create_checkout" && actor.role !== "employer") {
      throw new PaymentError(
        "FORBIDDEN",
        "Only an assignment employer can start checkout.",
        403,
      );
    }
    if (!app) throw pendingIntegration();
    switch (body.action) {
      case "list_assignments": {
        const offset = body.offset ?? 0, limit = body.limit ?? 21;
        if (
          !Number.isSafeInteger(offset) || offset < 0 ||
          !Number.isSafeInteger(limit) || limit < 1 || limit > 101
        ) {
          throw new PaymentError(
            "INVALID_PAGE",
            "Invalid page size or offset.",
          );
        }
        return reply({ assignments: await app.list(actor, offset, limit) });
      }
      case "get_assignment":
        return reply({
          assignment: await app.get(actor, id(body.assignment_id)),
        });
      case "get_payment":
        return reply({
          assignment: await app.forPayment(actor, id(body.payment_id)),
        });
      case "refresh_status":
        return reply({
          assignment: await app.refresh(actor, id(body.assignment_id)),
        });
      case "create_checkout":
        return reply(
          await app.create(
            actor,
            id(body.assignment_id),
            id(body.request_id),
            amount(body.bonus_minor ?? 0, true),
          ),
        );
      default:
        throw new PaymentError("INVALID_BODY", "Unknown action.");
    }
  } catch (error) {
    if (error instanceof PaymentError) {
      return reply({ code: error.code, error: error.message }, error.status);
    }
    return reply({
      code: "PAYMENT_UNCERTAIN",
      error:
        "Unable to confirm the payment operation. Check status before retrying.",
    }, 502);
  }
}

export async function paymentWebhookHttp(
  request: Request,
  app?: PaymentApplication,
): Promise<Response> {
  try {
    if (request.method !== "POST") {
      throw new PaymentError("METHOD_NOT_ALLOWED", "POST required.", 405);
    }
    if (!app) throw pendingIntegration(); // Non-2xx: never acknowledge an unprocessed callback.
    await app.webhook(request);
    return reply({ received: true });
  } catch (error) {
    if (error instanceof PaymentError) {
      return reply({ code: error.code, error: error.message }, error.status);
    }
    return reply({
      code: "CALLBACK_UNPROCESSED",
      error: "Callback has not been committed.",
    }, 503);
  }
}

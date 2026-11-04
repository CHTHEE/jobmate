import { paymentWebhookHttp } from "../_shared/payments/http.ts";

// This endpoint intentionally returns non-2xx until a DURABLE PaymentService is
// connected. Future deployment needs gateway access without a user JWT and must
// retain Billplz HMAC verification. Do not point a Billplz callback here yet.
Deno.serve((request) => paymentWebhookHttp(request));

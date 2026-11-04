import { withSupabase } from "npm:@supabase/server@1";
import { paymentHttp } from "../_shared/payments/http.ts";

// Safe integration entry point, not an operational checkout deployment.
// Wire a PaymentService with the team's durable source/store only after the
// JobAssignment FK, completion, membership and dispute contracts are confirmed.
// Never inject a sample/in-memory store here, even when using Sandbox credentials.
export default {
  fetch: withSupabase({ auth: "user" }, async (request, ctx) => {
    const actorId = ctx.userClaims?.id;
    if (!actorId) {
      return Response.json({ error: "Please sign in." }, { status: 401 });
    }
    const { data, error } = await ctx.supabase.from("users").select(
      "role, status",
    )
      .eq("user_id", actorId).maybeSingle();
    if (error) {
      return Response.json({ error: "Unable to check payment access." }, {
        status: 503,
      });
    }
    return paymentHttp(request, {
      id: actorId,
      role: data?.role ?? "",
      status: data?.status ?? "",
    });
  }),
};

import { billingWebhook } from "../app-api/billing.ts";
import { RestServiceStore } from "../app-api/deletion.ts";
const env = (name: string) => Deno.env.get(name) ?? "";
Deno.serve(async (request) => {
  if (!env("SUPABASE_SERVICE_ROLE_KEY"))
    return Response.json(
      { error: { code: "STORE_WEBHOOK_NOT_CONFIGURED" } },
      { status: 503 },
    );
  return billingWebhook({
    apiKey: env("REVENUECAT_API_KEY"),
    webhookAuthorization: env("REVENUECAT_WEBHOOK_AUTHORIZATION"),
    signingSecret: env("REVENUECAT_WEBHOOK_SIGNING_SECRET"),
    environment:
      env("REVENUECAT_ENVIRONMENT") === "SANDBOX" ? "SANDBOX" : "PRODUCTION",
    entitlementKeys: env("REVENUECAT_ENTITLEMENT_KEYS")
      .split(",")
      .filter(Boolean),
    service: new RestServiceStore(
      env("SUPABASE_URL"),
      env("SUPABASE_SERVICE_ROLE_KEY"),
    ),
  })(request);
});

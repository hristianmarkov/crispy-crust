import { createRouter, RestBackend } from "./router.ts";
import { RestServiceStore } from "./deletion.ts";
import { RestMediaService } from "./media.ts";
import { RevenueCatService } from "./billing.ts";
const env = (name: string) => Deno.env.get(name) ?? "";
const url = env("SUPABASE_URL");
const key = env("SUPABASE_SERVICE_ROLE_KEY");
const backend = new RestBackend(url, env("SUPABASE_ANON_KEY"));
const service = key ? new RestServiceStore(url, key) : undefined;
Deno.serve(
  createRouter({
    backend,
    allowedOrigins: env("APP_ALLOWED_ORIGINS").split(",").filter(Boolean),
    coachEnabled: env("AI_JOBS_ENABLED") === "true",
    importEnabled: env("IMPORT_JOBS_ENABLED") === "true",
    imageEnabled: env("IMAGE_JOBS_ENABLED") === "true" && Boolean(key),
    media:
      service && env("MEDIA_UPLOADS_ENABLED") === "true"
        ? new RestMediaService(backend, service, url, key)
        : undefined,
    billing:
      service && env("REVENUECAT_API_KEY")
        ? new RevenueCatService({
            apiKey: env("REVENUECAT_API_KEY"),
            environment:
              env("REVENUECAT_ENVIRONMENT") === "SANDBOX"
                ? "SANDBOX"
                : "PRODUCTION",
            entitlementKeys: env("REVENUECAT_ENTITLEMENT_KEYS")
              .split(",")
              .filter(Boolean),
            service,
          })
        : undefined,
  }),
);

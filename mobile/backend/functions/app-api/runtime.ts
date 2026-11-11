import { RestBackend, type RouterConfig } from "./router.ts";
import { RestServiceStore } from "./deletion.ts";
import { RestMediaService } from "./media.ts";
import { RevenueCatService } from "./billing.ts";
export type Environment = (name: string) => string | undefined;
/** Build server-only adapters from deployment env. No secret enters router responses. */
export function runtimeConfig(environment: Environment): RouterConfig {
  const env = (name: string) => environment(name) ?? "";
  const enabled = (name: string) => env(name) === "true";
  const url = env("SUPABASE_URL");
  const privateKey = env("SUPABASE_SERVICE_ROLE_KEY");
  const backend = new RestBackend(url, env("SUPABASE_ANON_KEY"));
  const service = privateKey
    ? new RestServiceStore(url, privateKey)
    : undefined;
  return {
    backend,
    allowedOrigins: env("APP_ALLOWED_ORIGINS")
      .split(",")
      .map((x) => x.trim())
      .filter(Boolean),
    coachEnabled: enabled("AI_JOBS_ENABLED") && Boolean(service),
    importEnabled: enabled("IMPORT_JOBS_ENABLED") && Boolean(service),
    imageEnabled: enabled("IMAGE_JOBS_ENABLED") && Boolean(service),
    media:
      service && enabled("MEDIA_UPLOADS_ENABLED")
        ? new RestMediaService(backend, service, url, privateKey)
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
              .map((x) => x.trim())
              .filter(Boolean),
            service,
          })
        : undefined,
  };
}

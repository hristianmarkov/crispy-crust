import { createRouter } from "./router.ts";
import { runtimeConfig } from "./runtime.ts";
// Supabase's default server credentials stay in the function process. Auth/API
// commands retain caller JWTs; privileged media/billing adapters run only after
// their authenticated, membership-checked command paths.
Deno.serve(createRouter(runtimeConfig((name) => Deno.env.get(name))));

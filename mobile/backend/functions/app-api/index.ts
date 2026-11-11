import { createRouter, RestBackend } from "./router.ts";
// Supabase gateway verification is disabled only because this handler verifies the
// incoming access token with Auth and forwards it to RLS, never a service key.
Deno.serve(
  createRouter({
    backend: new RestBackend(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
    ),
    allowedOrigins: (Deno.env.get("APP_ALLOWED_ORIGINS") ?? "")
      .split(",")
      .filter(Boolean),
    coachEnabled: Deno.env.get("AI_JOBS_ENABLED") === "true",
    importEnabled: Deno.env.get("IMPORT_JOBS_ENABLED") === "true",
  }),
);

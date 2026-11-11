import { RestMediaService } from "../app-api/media.ts";
import { RestBackend } from "../app-api/router.ts";
import { RestServiceStore } from "../app-api/deletion.ts";
import { runJobs, type Job } from "../app-api/jobs.ts";
const env = (n: string) => Deno.env.get(n) ?? "";
const url = env("SUPABASE_URL");
const key = env("SUPABASE_SERVICE_ROLE_KEY");
async function rpc(name: string, body: unknown) {
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: key,
      authorization: `Bearer ${key}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error("WORKER_BACKEND_UNAVAILABLE");
  return response.json();
}
Deno.serve(async (request) => {
  const secret = env("JOB_WORKER_SECRET");
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`)
    return new Response("Unauthorized", { status: 401 });
  if (request.method !== "POST")
    return new Response("Method not allowed", { status: 405 });
  const result = await runJobs(
    {
      claim: () => rpc("cc_worker_claim", { p_limit: 1 }),
      finish: (job: Job, result, error, retry) =>
        rpc("cc_worker_finish", {
          p_job: job.id,
          p_lease: job.lease_token,
          p_result: result,
          p_error: error,
          p_retry: retry,
        }),
    },
    {
      apiKey: env("OPENAI_API_KEY"),
      service: new RestServiceStore(url, key),
      media: new RestMediaService(
        new RestBackend(url, env("SUPABASE_ANON_KEY")),
        new RestServiceStore(url, key),
        url,
        key,
      ),
      enabledKinds: [
        "delete_account",
        "export",
        ...(env("AI_JOBS_ENABLED") === "true" ? ["coach"] : []),
        ...(env("IMPORT_JOBS_ENABLED") === "true" ? ["import"] : []),
        ...(env("IMAGE_JOBS_ENABLED") === "true" ? ["image"] : []),
      ],
      model: env("COACH_MODEL"),
      allowedImportHosts: env("IMPORT_ALLOWED_HOSTS")
        .split(",")
        .filter(Boolean),
      resolve: async (host) => {
        const results = await Promise.allSettled([
          Deno.resolveDns(host, "A"),
          Deno.resolveDns(host, "AAAA"),
        ]);
        return results.flatMap((r) =>
          r.status === "fulfilled" ? r.value : [],
        );
      },
    },
  );
  return Response.json({ results: result });
});

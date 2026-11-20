export interface WorkerHandlerOptions {
  authorizeJobs(request: Request): Promise<boolean>;
  authorizeHeartbeat(request: Request): Promise<boolean>;
  processJobs(): Promise<unknown>;
}
/** Health routing never reaches processJobs, even with queued destructive jobs. */
export function createWorkerHandler(options: WorkerHandlerOptions) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST")
      return new Response("Method not allowed", { status: 405 });
    const pathname = new URL(request.url).pathname;
    const route = pathname.replace(
      /^\/(?:functions\/v1\/)?job-worker(?=\/|$)/,
      "",
    );
    if (route === "/health") {
      if (!(await options.authorizeHeartbeat(request)))
        return new Response("Unauthorized", { status: 401 });
      // No body/query mode is read. No claim, processing, provider or deletion call.
      return Response.json(
        { ok: true, mode: "heartbeat" },
        { headers: { "cache-control": "no-store" } },
      );
    }
    if (route !== "" && route !== "/")
      return new Response("Not found", { status: 404 });
    if (!(await options.authorizeJobs(request)))
      return new Response("Unauthorized", { status: 401 });
    return Response.json(
      { results: await options.processJobs() },
      { headers: { "cache-control": "no-store" } },
    );
  };
}

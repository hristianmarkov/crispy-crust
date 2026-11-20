import { ApiError, type Json } from "./router.ts";
import type { Job } from "./jobs.ts";
export interface ServiceStore {
  rpc(name: string, params: Json): Promise<unknown>;
  removeObjects(keys: string[]): Promise<void>;
  removeAuthUser(userId: string): Promise<void>;
}
/** Retry-safe order: remove private blobs, scrub application state, then Auth. */
export async function deleteAccount(
  job: Job & { user_id?: string },
  service: ServiceStore,
): Promise<Json> {
  if (!job.user_id) throw new ApiError("DELETION_OWNER_MISSING", 422);
  const keys = (await service.rpc("cc_worker_deletion_keys", {
    p_user: job.user_id,
  })) as string[];
  if (!Array.isArray(keys) || keys.some((x) => typeof x !== "string"))
    throw new ApiError("DELETION_KEYS_INVALID", 502);
  for (let i = 0; i < keys.length; i += 100)
    await service.removeObjects(keys.slice(i, i + 100));
  const result = (await service.rpc("cc_worker_delete_data", {
    p_user: job.user_id,
    p_job: job.id,
  })) as Json;
  await service.removeAuthUser(job.user_id);
  return {
    ...result,
    auth_deleted: true,
    private_objects_deleted: keys.length,
    provider_note:
      "Coach requests use store:false; provider retention follows configured processing terms.",
  };
}
export class RestServiceStore implements ServiceStore {
  constructor(
    private url: string,
    private key: string,
    private fetcher: typeof fetch = fetch,
  ) {
    if (!key) throw new Error("Service key is required");
  }
  private async request(path: string, method: string, body?: Json) {
    const r = await this.fetcher(this.url + path, {
      method,
      headers: {
        apikey: this.key,
        authorization: `Bearer ${this.key}`,
        "content-type": "application/json",
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(15000),
    });
    if (!r.ok && r.status !== 404)
      throw new ApiError("DELETION_DEPENDENCY_UNAVAILABLE", 503);
    if (r.status === 404 || r.status === 204) return null;
    return r.json();
  }
  rpc(name: string, params: Json) {
    return this.request("/rest/v1/rpc/" + name, "POST", params);
  }
  async removeObjects(keys: string[]) {
    if (keys.length)
      await this.request("/storage/v1/object/kitchen-media", "DELETE", {
        prefixes: keys,
      });
  }
  async removeAuthUser(userId: string) {
    await this.request(
      "/auth/v1/admin/users/" + encodeURIComponent(userId),
      "DELETE",
    );
  }
}

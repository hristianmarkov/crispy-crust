/** Authorise only a private configured token or a short-lived Vault capability. */
export async function authorizeWorker(
  request: Request,
  configuredSecret: string,
  verifyVault: (token: string) => Promise<unknown>,
): Promise<boolean> {
  const header = request.headers.get("authorization");
  if (!header?.startsWith("Bearer ")) return false;
  const token = header.slice(7);
  // A heartbeat capability can never be promoted via the optional legacy key.
  if (token.startsWith("v2.heartbeat.")) return false;
  if (token.length > 240) return false;
  // Optional legacy explicit server secret. It is not needed by Vault scheduling.
  if (configuredSecret) {
    const a = new TextEncoder().encode(token),
      b = new TextEncoder().encode(configuredSecret);
    if (a.length === b.length) {
      let difference = 0;
      for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
      if (difference === 0) return true;
    }
  }
  if (
    !/^v1\.\d{10}\.[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.[0-9a-f]{64}$/.test(
      token,
    )
  )
    return false;
  // RPC is service_role-only and consumes the dispatch nonce atomically. Never
  // log the capability or include it in an error. DB/network failure fails closed.
  try {
    return (await verifyVault(token)) === true;
  } catch {
    return false;
  }
}

/** Dedicated v2 heartbeat capability. It cannot authorise the jobs route. */
export async function authorizeHeartbeat(
  request: Request,
  verifyVault: (token: string) => Promise<unknown>,
): Promise<boolean> {
  const header = request.headers.get("authorization");
  if (!header?.startsWith("Bearer ")) return false;
  const token = header.slice(7);
  if (
    token.length > 240 ||
    !/^v2\.heartbeat\.\d{10}\.[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.[0-9a-f]{64}$/.test(
      token,
    )
  )
    return false;
  try {
    return (await verifyVault(token)) === true;
  } catch {
    return false;
  }
}

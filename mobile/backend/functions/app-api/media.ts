import { ApiError, type Backend, type Json } from "./router.ts";
import type { ServiceStore } from "./deletion.ts";
export interface Asset {
  id: string;
  object_key: string;
  sha256: string;
  bytes: number;
  mime_type: string;
  width: number;
  height: number;
  status: string;
  verified_at?: string;
}
export interface MediaService {
  prepare(body: Json, operation: string, token: string): Promise<Json>;
  complete(asset: string, token: string): Promise<Json>;
  read(asset: string, token: string): Promise<Json>;
  remove(asset: string, token: string): Promise<Json>;
  download(asset: Asset): Promise<Uint8Array>;
}
const MAX_BYTES = 2097152;
export async function hashBytes(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new Uint8Array(bytes));
  return [...new Uint8Array(digest)]
    .map((x) => x.toString(16).padStart(2, "0"))
    .join("");
}
function dimensions(width: number, height: number) {
  if (
    width < 1 ||
    height < 1 ||
    width > 4096 ||
    height > 4096 ||
    width * height > 16777216
  )
    throw new ApiError("MEDIA_DIMENSIONS_INVALID", 422);
  return { width, height };
}
/** Bounded container validation, not a claim of full pixel decoding/food diagnosis. */
export function inspectImage(
  bytes: Uint8Array,
  mime: string,
): { width: number; height: number } {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const ascii = (i: number, n: number) =>
    String.fromCharCode(...bytes.slice(i, i + n));
  if (bytes.length < 12 || bytes.length > MAX_BYTES)
    throw new ApiError("MEDIA_SIZE_MISMATCH", 422);
  if (mime === "image/png") {
    if (ascii(0, 8) !== "\x89PNG\r\n\x1a\n")
      throw new ApiError("MEDIA_TYPE_MISMATCH", 422);
    let p = 8,
      width = 0,
      height = 0,
      idat = false,
      end = false,
      count = 0;
    while (p + 12 <= bytes.length && count++ < 2048) {
      const length = view.getUint32(p),
        kind = ascii(p + 4, 4);
      if (p + 12 + length > bytes.length)
        throw new ApiError("MEDIA_CONTAINER_INVALID", 422);
      if (["eXIf", "tEXt", "zTXt", "iTXt"].includes(kind))
        throw new ApiError("MEDIA_METADATA_REJECTED", 422);
      if (count === 1) {
        if (kind !== "IHDR" || length !== 13)
          throw new ApiError("MEDIA_CONTAINER_INVALID", 422);
        width = view.getUint32(p + 8);
        height = view.getUint32(p + 12);
      }
      if (kind === "IDAT") idat = true;
      p += length + 12;
      if (kind === "IEND") {
        end = true;
        break;
      }
    }
    if (!idat || !end || p !== bytes.length)
      throw new ApiError("MEDIA_CONTAINER_INVALID", 422);
    return dimensions(width, height);
  }
  if (mime === "image/jpeg") {
    if (
      bytes[0] !== 255 ||
      bytes[1] !== 216 ||
      bytes.at(-2) !== 255 ||
      bytes.at(-1) !== 217
    )
      throw new ApiError("MEDIA_TYPE_MISMATCH", 422);
    let p = 2,
      count = 0,
      width = 0,
      height = 0;
    while (p + 4 < bytes.length && count++ < 10000) {
      if (bytes[p] !== 255) throw new ApiError("MEDIA_CONTAINER_INVALID", 422);
      while (p < bytes.length && bytes[p] === 255) p++;
      if (p + 3 > bytes.length)
        throw new ApiError("MEDIA_CONTAINER_INVALID", 422);
      const marker = bytes[p++];
      if (marker === 0xda) {
        if (!width) throw new ApiError("MEDIA_CONTAINER_INVALID", 422);
        return dimensions(width, height);
      }
      if (marker === 0xd9) break;
      if (marker >= 0xd0 && marker <= 0xd7) continue;
      const length = view.getUint16(p);
      if (length < 2 || p + length > bytes.length)
        throw new ApiError("MEDIA_CONTAINER_INVALID", 422);
      if (
        marker === 0xe1 ||
        marker === 0xe2 ||
        marker === 0xed ||
        marker === 0xfe ||
        (marker >= 0xe3 && marker <= 0xef && marker !== 0xee)
      )
        throw new ApiError("MEDIA_METADATA_REJECTED", 422);
      if ([0xc0, 0xc1, 0xc2].includes(marker)) {
        if (length < 8) throw new ApiError("MEDIA_CONTAINER_INVALID", 422);
        height = view.getUint16(p + 3);
        width = view.getUint16(p + 5);
      }
      p += length;
    }
    throw new ApiError("MEDIA_CONTAINER_INVALID", 422);
  }
  if (mime === "image/webp") {
    if (
      ascii(0, 4) !== "RIFF" ||
      ascii(8, 4) !== "WEBP" ||
      view.getUint32(4, true) + 8 !== bytes.length
    )
      throw new ApiError("MEDIA_TYPE_MISMATCH", 422);
    let p = 12,
      width = 0,
      height = 0,
      image = false,
      count = 0;
    while (p + 8 <= bytes.length && count++ < 2048) {
      const kind = ascii(p, 4),
        length = view.getUint32(p + 4, true),
        d = p + 8;
      if (d + length > bytes.length)
        throw new ApiError("MEDIA_CONTAINER_INVALID", 422);
      if (["EXIF", "XMP "].includes(kind))
        throw new ApiError("MEDIA_METADATA_REJECTED", 422);
      if (kind === "VP8X") {
        if (length < 10 || (bytes[d] & 0x0c) !== 0)
          throw new ApiError("MEDIA_METADATA_REJECTED", 422);
        width = 1 + bytes[d + 4] + (bytes[d + 5] << 8) + (bytes[d + 6] << 16);
        height = 1 + bytes[d + 7] + (bytes[d + 8] << 8) + (bytes[d + 9] << 16);
      }
      if (kind === "VP8 ") {
        if (length < 10 || ascii(d + 3, 3) !== "\x9d\x01\x2a")
          throw new ApiError("MEDIA_CONTAINER_INVALID", 422);
        width = view.getUint16(d + 6, true) & 0x3fff;
        height = view.getUint16(d + 8, true) & 0x3fff;
        image = true;
      }
      if (kind === "VP8L") {
        if (length < 5 || bytes[d] !== 0x2f)
          throw new ApiError("MEDIA_CONTAINER_INVALID", 422);
        width = 1 + bytes[d + 1] + ((bytes[d + 2] & 0x3f) << 8);
        height =
          1 +
          (bytes[d + 2] >> 6) +
          (bytes[d + 3] << 2) +
          ((bytes[d + 4] & 15) << 10);
        image = true;
      }
      p = d + length + (length % 2);
    }
    if (!image || p !== bytes.length)
      throw new ApiError("MEDIA_CONTAINER_INVALID", 422);
    return dimensions(width, height);
  }
  throw new ApiError("MEDIA_TYPE_UNSUPPORTED", 422);
}
async function readBytes(response: Response, max: number): Promise<Uint8Array> {
  if (!response.ok || !response.body)
    throw new ApiError("MEDIA_STORAGE_UNAVAILABLE", 503);
  if (Number(response.headers.get("content-length") || 0) > max)
    throw new ApiError("MEDIA_SIZE_MISMATCH", 422);
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.length;
      if (total > max) {
        await reader.cancel();
        throw new ApiError("MEDIA_SIZE_MISMATCH", 422);
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let at = 0;
  for (const c of chunks) {
    bytes.set(c, at);
    at += c.length;
  }
  return bytes;
}
export class RestMediaService implements MediaService {
  constructor(
    private backend: Backend,
    private service: ServiceStore,
    private origin: string,
    private key: string,
    private fetcher: typeof fetch = fetch,
  ) {}
  private objectUrl(key: string) {
    return (
      this.origin +
      "/storage/v1/object/kitchen-media/" +
      key.split("/").map(encodeURIComponent).join("/")
    );
  }
  async prepare(body: Json, operation: string, token: string): Promise<Json> {
    const asset = (await this.backend.rpc(
      "cc_media_prepare",
      {
        p_kitchen: body.kitchen_id,
        p_target: body.attachment_target,
        p_operation: operation,
        p_hash: body.sha256,
        p_bytes: body.bytes,
        p_mime: body.mime_type,
        p_width: body.width,
        p_height: body.height,
      },
      token,
    )) as Json;
    const response = await this.fetcher(
      this.origin +
        "/storage/v1/object/upload/sign/kitchen-media/" +
        String(asset.object_key).split("/").map(encodeURIComponent).join("/"),
      {
        method: "POST",
        headers: {
          apikey: this.key,
          authorization: `Bearer ${this.key}`,
          "content-type": "application/json",
          "x-upsert": "false",
        },
        body: "{}",
        signal: AbortSignal.timeout(15000),
      },
    );
    if (!response.ok) throw new ApiError("MEDIA_STORAGE_UNAVAILABLE", 503);
    const signed = (await response.json()) as { url?: string };
    if (!signed.url) throw new ApiError("MEDIA_SIGNING_FAILED", 503);
    const upload = new URL("/storage/v1" + signed.url, this.origin);
    if (
      upload.origin !== new URL(this.origin).origin ||
      !upload.pathname.startsWith("/storage/v1/object/upload/sign/")
    )
      throw new ApiError("MEDIA_SIGNING_FAILED", 503);
    return {
      ...asset,
      upload_url: upload.href,
      required_headers: { "content-type": body.mime_type },
      max_bytes: MAX_BYTES,
    };
  }
  async download(asset: Asset): Promise<Uint8Array> {
    const response = await this.fetcher(this.objectUrl(asset.object_key), {
      headers: { apikey: this.key, authorization: `Bearer ${this.key}` },
      signal: AbortSignal.timeout(15000),
    });
    return readBytes(response, MAX_BYTES);
  }
  async read(id: string, token: string): Promise<Json> {
    const asset = (await this.backend.rpc(
      "cc_media_for_read",
      { p_asset: id },
      token,
    )) as unknown as Asset;
    const response = await this.fetcher(
      this.origin +
        "/storage/v1/object/sign/kitchen-media/" +
        asset.object_key.split("/").map(encodeURIComponent).join("/"),
      {
        method: "POST",
        headers: {
          apikey: this.key,
          authorization: `Bearer ${this.key}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ expiresIn: 60 }),
        signal: AbortSignal.timeout(15000),
      },
    );
    if (!response.ok) throw new ApiError("MEDIA_STORAGE_UNAVAILABLE", 503);
    const data = (await response.json()) as { signedURL?: string };
    if (!data.signedURL) throw new ApiError("MEDIA_SIGNING_FAILED", 503);
    const url = new URL("/storage/v1" + data.signedURL, this.origin);
    if (
      url.origin !== new URL(this.origin).origin ||
      !url.pathname.startsWith("/storage/v1/object/sign/")
    )
      throw new ApiError("MEDIA_SIGNING_FAILED", 503);
    return { asset_id: id, url: url.href, expires_in: 60 };
  }
  async remove(id: string, token: string): Promise<Json> {
    const asset = (await this.backend.rpc(
      "cc_media_for_delete",
      { p_asset: id },
      token,
    )) as unknown as Asset;
    await this.service.removeObjects([asset.object_key]);
    if (
      !(await this.service.rpc("cc_worker_media_status", {
        p_asset: id,
        p_hash: asset.sha256,
        p_status: "deleted",
      }))
    )
      throw new ApiError("MEDIA_ACCESS_REVOKED", 403);
    return {
      asset_id: id,
      status: "deleted",
      cached_signed_url_max_seconds: 60,
    };
  }
  async complete(id: string, token: string): Promise<Json> {
    const asset = (await this.backend.rpc(
      "cc_media_for_verify",
      { p_asset: id },
      token,
    )) as unknown as Asset;
    if (asset.status === "uploaded" && asset.verified_at)
      return { asset_id: id, status: "uploaded" };
    try {
      const bytes = await this.download(asset);
      if (
        bytes.length !== Number(asset.bytes) ||
        (await hashBytes(bytes)) !== asset.sha256
      )
        throw new ApiError("MEDIA_HASH_MISMATCH", 422);
      const measured = inspectImage(bytes, asset.mime_type);
      if (measured.width !== asset.width || measured.height !== asset.height)
        throw new ApiError("MEDIA_DIMENSIONS_MISMATCH", 422);
      if (
        !(await this.service.rpc("cc_worker_media_status", {
          p_asset: id,
          p_hash: asset.sha256,
          p_status: "uploaded",
        }))
      )
        throw new ApiError("MEDIA_ACCESS_REVOKED", 403);
      return { asset_id: id, status: "uploaded", ...measured };
    } catch (error) {
      if (error instanceof ApiError && error.status < 500) {
        await this.service.rpc("cc_worker_media_status", {
          p_asset: id,
          p_hash: asset.sha256,
          p_status: "quarantined",
        });
        await this.service.removeObjects([asset.object_key]);
      }
      throw error;
    }
  }
}

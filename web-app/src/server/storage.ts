import "server-only";
import { createHash, randomUUID } from "node:crypto";
import { gzipSync, gunzipSync } from "node:zlib";
import { S3Client, GetObjectCommand, PutObjectCommand, DeleteObjectCommand, ListObjectVersionsCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { MAX_ASSET_BYTES, MAX_PAGE_BYTES, pageContentSchema, type CloudFile } from "@/lib/cloud";
import { serviceClient } from "./service";
import { HttpError } from "./http";

export function b2() {
  const { B2_ENDPOINT: endpoint, B2_REGION: region, B2_BUCKET_NAME: bucket, B2_APPLICATION_KEY_ID: accessKeyId, B2_APPLICATION_KEY: secretAccessKey } = process.env;
  if (!endpoint || !region || !bucket || !accessKeyId || !secretAccessKey) throw new HttpError(503, "Configure the private B2 bucket and server application key.");
  const url = new URL(endpoint);
  if (url.protocol !== "https:" && !["127.0.0.1", "localhost"].includes(url.hostname)) throw new HttpError(503, "Invalid B2 endpoint.");
  const client = new S3Client({ endpoint, region, forcePathStyle: true, maxAttempts: 1, credentials: { accessKeyId, secretAccessKey }, requestChecksumCalculation: "WHEN_REQUIRED", responseChecksumValidation: "WHEN_REQUIRED" });
  return { client, bucket };
}
export const sha256 = (data: Uint8Array | string) => createHash("sha256").update(data).digest("hex");
export function stableId(value: string) {
  const bytes = createHash("sha256").update(value).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 15) | 0x50; bytes[8] = (bytes[8] & 63) | 0x80;
  const h = bytes.toString("hex"); return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
export async function uploadURL(owner: string, operation: string, file: Omit<CloudFile, "key">, id: string) {
  const { client, bucket } = b2();
  const key = `staging/${owner}/${operation}/${id}/${file.sha256}`;
  const url = await getSignedUrl(client, new PutObjectCommand({ Bucket: bucket, Key: key, ContentType: "application/octet-stream", ContentLength: file.bytes }), { expiresIn: 300 });
  return { ...file, key, url, headers: { "Content-Type": "application/octet-stream" } };
}
async function readBytes(key: string, max: number, versionId?: string) {
  const { client, bucket } = b2();
  const response = await client.send(new GetObjectCommand({ Bucket: bucket, Key: key, VersionId: versionId }), { abortSignal: AbortSignal.timeout(30_000) });
  if (!response.Body || (response.ContentLength ?? 0) > max) throw new HttpError(413, "Cloud file exceeds the supported size.");
  const chunks: Uint8Array[] = []; let bytes = 0;
  for await (const chunk of response.Body as AsyncIterable<Uint8Array>) { bytes += chunk.length; if (bytes > max) throw new HttpError(413, "Cloud file exceeds the supported size."); chunks.push(chunk); }
  return { bytes: Buffer.concat(chunks), versionId: response.VersionId };
}
export async function publishFile(owner: string, file: CloudFile): Promise<CloudFile> {
  if (!file.key.startsWith(`staging/${owner}/`)) {
    const { data, error } = await serviceClient().from("cloud_objects").select("key,sha256,bytes,kind,state").eq("owner_id", owner).eq("key", file.key).maybeSingle();
    if (error || !data || data.state !== "ready" || data.sha256 !== file.sha256 || data.bytes !== file.bytes || data.kind !== file.kind) throw new HttpError(410, "A referenced cloud file is unavailable. Upload the local page again.");
    return file;
  }
  const segments = file.key.split("/");
  if (segments.length !== 5 || !/^[0-9a-fA-F-]{36}$/.test(segments[2]) || !/^[0-9a-fA-F-]{36}$/.test(segments[3]) || segments[4] !== file.sha256) throw new HttpError(400, "Invalid staging object key.");
  const max = file.kind === "page" ? MAX_PAGE_BYTES : MAX_ASSET_BYTES;
  const staged = await readBytes(file.key, max);
  const bytes = staged.bytes;
  if (bytes.length !== file.bytes || sha256(bytes) !== file.sha256) throw new HttpError(400, "Uploaded file checksum or size does not match.");
  const stored = await storeFile(owner, bytes, file.kind);
  if (staged.versionId) {
    const { client, bucket } = b2();
    await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: file.key, VersionId: staged.versionId })).catch(() => undefined);
  }
  return stored;
}
export async function verifyReferences(owner: string, files: CloudFile[]) {
  const service = serviceClient();
  for (let offset = 0; offset < files.length; offset += 50) {
    const batch = files.slice(offset, offset + 50);
    const { data, error } = await service.from("cloud_objects").select("key,sha256,bytes,kind,state").eq("owner_id", owner).in("key", batch.map(file => file.key));
    if (error) throw new HttpError(503, "Unable to verify cloud references.");
    for (const file of batch) {
      if (!data?.some(row => row.key === file.key && row.state === "ready" && row.sha256 === file.sha256 && row.bytes === file.bytes && row.kind === file.kind)) throw new HttpError(410, "A referenced file expired. Reupload the local page.");
    }
  }
}
export async function storeFile(owner: string, bytes: Uint8Array, kind: CloudFile["kind"]): Promise<CloudFile> {
  if (bytes.length > (kind === "page" ? MAX_PAGE_BYTES : MAX_ASSET_BYTES)) throw new HttpError(413, "File exceeds its transfer limit.");
  const raw = Buffer.from(bytes);
  if (kind === "page") {
    try { pageContentSchema.parse(JSON.parse(raw.toString("utf8"))); } catch { throw new HttpError(400, "Invalid page document."); }
  } else if (kind === "image/png" ? raw.subarray(0, 8).toString("hex") !== "89504e470d0a1a0a" : raw.subarray(0, 3).toString("hex") !== "ffd8ff") throw new HttpError(400, "Invalid image data.");
  const { client, bucket } = b2();
  const key = `users/${owner}/objects/${randomUUID()}${kind === "page" ? ".json.gz" : kind === "image/png" ? ".png" : ".jpg"}`;
  const body = kind === "page" ? gzipSync(bytes) : bytes;
  const file = { key, sha256: sha256(bytes), bytes: bytes.length, kind };
  // Reserve metadata before the external write. Even a lost PUT response or
  // a database outage afterward leaves a discoverable cleanup record.
  const service = serviceClient();
  const { error } = await service.from("cloud_objects").insert({ ...file, owner_id: owner, stored_bytes: body.length, state: "uploading" });
  if (error) throw new HttpError(503, "Cloud metadata is not configured. Apply 002_cloud_storage.sql.");
  const result = await client.send(new PutObjectCommand({ Bucket: bucket, Key: key, Body: body, ContentType: kind === "page" ? "application/json" : kind, ContentEncoding: kind === "page" ? "gzip" : undefined }), { abortSignal: AbortSignal.timeout(30000) });
  if (!result.VersionId) throw new HttpError(503, "B2 did not return an immutable file version.");
  const finalized = await service.from("cloud_objects").update({ state: "ready", version_id: result.VersionId }).eq("owner_id", owner).eq("key", key).eq("state", "uploading").select("key");
  if (finalized.error || finalized.data?.length !== 1) throw new HttpError(503, "The uploaded file could not be finalized. Retry; its cleanup record is retained.");
  return file;
}
export async function fileURL(owner: string, file: CloudFile) {
  const { data, error } = await serviceClient().from("cloud_objects").select("version_id").eq("owner_id", owner).eq("key", file.key).eq("state", "ready").maybeSingle();
  if (error || !data) throw new HttpError(404, "Cloud file unavailable.");
  const { client, bucket } = b2();
  return getSignedUrl(client, new GetObjectCommand({ Bucket: bucket, Key: file.key, VersionId: data.version_id }), { expiresIn: 300 });
}
export async function fileData(owner: string, file: CloudFile) {
  const { data } = await serviceClient().from("cloud_objects").select("version_id").eq("owner_id", owner).eq("key", file.key).eq("state", "ready").maybeSingle();
  if (!data) throw new HttpError(404, "Cloud file unavailable.");
  const raw = await readBytes(file.key, MAX_PAGE_BYTES + 100000, data.version_id);
  const bytes = file.kind === "page" ? gunzipSync(raw.bytes, { maxOutputLength: MAX_PAGE_BYTES }) : raw.bytes;
  if (sha256(bytes) !== file.sha256 || bytes.length !== file.bytes) throw new HttpError(503, "Cloud file integrity check failed.");
  return bytes;
}
export async function cleanupObjects(owner: string) {
  const service = serviceClient();
  const { data, error } = await service.rpc("cloud_cleanup_candidates", { p_owner: owner });
  if (error) throw new HttpError(503, "Unable to inspect obsolete cloud files.");
  const { client, bucket } = b2(); let removed = 0;
  for (const file of data ?? []) {
    let versions = file.version_id ? [file.version_id as string] : [];
    if (!file.version_id) {
      const listed = await client.send(new ListObjectVersionsCommand({ Bucket: bucket, Prefix: file.key, MaxKeys: 1000 }));
      if (listed.IsTruncated) throw new HttpError(503, "An incomplete upload needs extended version cleanup.");
      versions = [...(listed.Versions ?? []), ...(listed.DeleteMarkers ?? [])].filter(version => version.Key === file.key && version.VersionId).map(version => version.VersionId!);
    }
    for (const version of versions) {
      try { await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: file.key, VersionId: version }), { abortSignal: AbortSignal.timeout(15000) }); }
      catch (error) { if ((error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode !== 404) throw error; }
    }
    const result = await service.from("cloud_objects").delete().eq("owner_id", owner).eq("key", file.key).eq("state", "deleting");
    if (result.error) throw new HttpError(503, "Cleanup metadata could not be completed. Retry cleanup.");
    removed++;
  }
  return { removed };
}

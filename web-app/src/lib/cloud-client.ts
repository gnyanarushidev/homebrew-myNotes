import { api, ApiError } from "./api";
import { MAX_ASSET_BYTES, MAX_PAGE_BYTES, pageContentSchema, type CloudFile, type CloudManifest, type CloudReceipt, type CloudRecord } from "./cloud";
import type { NotebookDocument, NotebookRecord } from "./notebook";

const hash = async (data: Uint8Array<ArrayBuffer>) => [...new Uint8Array(await crypto.subtle.digest("SHA-256", data))].map(value => value.toString(16).padStart(2, "0")).join("");
let lastCleanup = 0;
function base64(bytes: Uint8Array) { let value = ""; for (let i = 0; i < bytes.length; i += 16384) value += String.fromCharCode(...bytes.subarray(i, i + 16384)); return btoa(value); }
async function read(file: CloudFile, url: string) {
  const response = await fetch(url, { cache: "no-store", credentials: "omit" });
  if (!response.ok) throw new ApiError("Cloud file download failed. Reload to refresh access.", response.status);
  const data = new Uint8Array(await response.arrayBuffer());
  if (data.length !== file.bytes || await hash(data) !== file.sha256) throw new Error("Downloaded page integrity check failed.");
  return data;
}
export async function loadCloudNotebook(id: string, accountId?: string): Promise<NotebookRecord> {
  const { record, urls } = await api<{ record: CloudRecord; urls: Record<string, string> }>(`/api/v1/sync/notebooks/${id}?downloads=1`, { headers: accountId ? { "X-MyNotes-Account": accountId } : {} });
  if (record.manifest.pages.reduce((sum, page) => sum + page.content.bytes + (page.image?.bytes ?? 0), 0) > 128_000_000) throw new Error("This notebook exceeds the initial 128 MB editor limit.");
  const pages: NotebookDocument["pages"] = [];
  for (const page of record.manifest.pages) {
    const content = pageContentSchema.parse(JSON.parse(new TextDecoder().decode(await read(page.content, urls[page.content.key]))));
    const image = page.image ? { mimeType: page.image.kind as "image/png" | "image/jpeg", data: base64(await read(page.image, urls[page.image.key])) } : undefined;
    pages.push({ id: page.id, size: page.size, template: page.template, color: page.color, inheritsStyle: page.inheritsStyle, strokes: content.strokes, text: content.text, ...(image ? { image } : {}) });
  }
  return { id, revision: record.revision, mutation_id: record.mutation_id, created_at: record.created_at, updated_at: record.updated_at, storage: record.manifest, document: { schemaVersion: 1, title: record.manifest.title, template: record.manifest.template, color: record.manifest.color, pages } };
}
export async function saveCloudNotebook(id: string, document: NotebookDocument, revision: number, operationId: string, baseline?: CloudManifest, accountId?: string): Promise<NotebookRecord> {
  const cloudApi = <T>(path: string, options: RequestInit = {}) => api<T>(path, { ...options, headers: { ...options.headers, ...(accountId ? { "X-MyNotes-Account": accountId } : {}) } });
  async function upload(data: Uint8Array<ArrayBuffer>, kind: CloudFile["kind"], previous?: CloudFile): Promise<CloudFile> {
    if (data.length > (kind === "page" ? MAX_PAGE_BYTES : MAX_ASSET_BYTES)) throw new Error("A page exceeds the 16 MB drawing or 8 MB image transfer limit.");
    const sha256 = await hash(data);
    if (previous?.sha256 === sha256 && previous.kind === kind) return previous;
    const result = await cloudApi<{ files: (CloudFile & { url: string; headers: Record<string, string> })[] }>("/api/v1/sync/uploads", { method: "POST", body: JSON.stringify({ operationId, files: [{ id: crypto.randomUUID(), sha256, bytes: data.length, kind }] }) });
    const ticket = result.files[0];
    const response = await fetch(ticket.url, { method: "PUT", headers: ticket.headers, body: data, credentials: "omit" });
    if (!response.ok) throw new Error("Page upload failed. Your local draft is retained.");
    const finalized = await cloudApi<{ files: CloudFile[] }>("/api/v1/sync/files", { method: "POST", body: JSON.stringify({ files: [{ key: ticket.key, sha256, bytes: data.length, kind }] }) });
    return finalized.files[0];
  }
  async function attempt(base?: CloudManifest) {
    const manifest: CloudManifest = { version: 1, title: document.title, template: document.template, color: document.color, pages: [] };
    for (const page of document.pages) {
      const previous = base?.pages.find(item => item.id === page.id);
      const content = await upload(new TextEncoder().encode(JSON.stringify({ version: 1, strokes: page.strokes, text: page.text })), "page", previous?.content);
      const image = page.image ? await upload(Uint8Array.from(atob(page.image.data), c => c.charCodeAt(0)), page.image.mimeType, previous?.image) : undefined;
      manifest.pages.push({ id: page.id, size: page.size, template: page.template, color: page.color, inheritsStyle: page.inheritsStyle, content, ...(image ? { image } : {}) });
    }
    return cloudApi<CloudReceipt>("/api/v1/sync/commit", { method: "POST", body: JSON.stringify({ id, operationId, baseRevision: revision, manifest, keepBoth: false, deleted: false }) });
  }
  let receipt: CloudReceipt;
  try { receipt = await attempt(baseline); }
  catch (error) { if (!(error instanceof ApiError) || error.status !== 410) throw error; receipt = await attempt(); }
  // The commit receipt is authoritative even if this optional refresh fails.
  const latest = await cloudApi<CloudRecord>(`/api/v1/sync/notebooks/${id}`).catch(() => undefined);
  if (Date.now() - lastCleanup > 30000) { lastCleanup = Date.now(); void cloudApi("/api/v1/sync/cleanup", { method: "POST", body: "{}" }).catch(() => undefined); }
  // A later cloud edit must not be acknowledged as the base of this snapshot.
  return { id, document, revision: receipt.revision, mutation_id: operationId, created_at: latest?.created_at ?? new Date().toISOString(), updated_at: latest?.updated_at ?? new Date().toISOString(), storage: latest?.revision === receipt.revision ? latest.manifest : undefined };
}

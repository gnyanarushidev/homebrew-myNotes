import "server-only";
import { z } from "zod";
import { filesIn, manifestSchema, pageContentSchema, type CloudManifest, type CloudRecord, type CloudReceipt } from "@/lib/cloud";
import { documentSchema, type NotebookDocument, type NotebookRecord } from "@/lib/notebook";
import { serviceClient } from "./service";
import { HttpError } from "./http";
import { fileData, fileURL, publishFile, sha256, stableId, storeFile, verifyReferences } from "./storage";

export const commitSchema = z.object({ id: z.uuid().toLowerCase(), operationId: z.uuid().toLowerCase(), baseRevision: z.number().int().min(0), manifest: manifestSchema, deleted: z.boolean().default(false), keepBoth: z.boolean().default(false) });
const fields = "id,manifest,revision,change_seq,deleted,updated_at,created_at,mutation_id";
async function boundedMap<T, U>(values: T[], operation: (value: T) => Promise<U>) {
  const result: U[] = [];
  for (let offset = 0; offset < values.length; offset += 5) result.push(...await Promise.all(values.slice(offset, offset + 5).map(operation)));
  return result;
}
function db(error: { code?: string; message?: string } | null) {
  if (!error) return;
  if (error.message?.includes("REVISION_CONFLICT")) throw new HttpError(409, "The cloud notebook changed or was deleted. Preserve your edits as a conflict copy.");
  if (error.message?.includes("OPERATION_REUSED")) throw new HttpError(409, "An operation ID cannot be reused for different edits.");
  if (error.message?.includes("OBJECT_UNAVAILABLE")) throw new HttpError(410, "A file expired. Reupload the local page.");
  throw new HttpError(503, "Cloud metadata is unavailable. Apply supabase/migrations/002_cloud_storage.sql and check server settings.");
}
export async function getCloud(owner: string, id: string, includeDeleted = false): Promise<CloudRecord> {
  const { data, error } = await serviceClient().from("cloud_notebooks").select(fields).eq("owner_id", owner).eq("id", id).maybeSingle();
  db(error);
  if (!data || (data.deleted && !includeDeleted)) throw new HttpError(404, "Notebook not found.");
  return data as CloudRecord;
}
export async function listCloud(owner: string, search = "") {
  const result: CloudRecord[] = [];
  for (let offset = 0; ; offset += 100) {
    const { data, error } = await serviceClient().from("cloud_notebooks").select(fields).eq("owner_id", owner).eq("deleted", false).order("updated_at", { ascending: false }).order("id").range(offset, offset + 99);
    db(error); result.push(...data as CloudRecord[]);
    if (data!.length < 100) break;
  }
  return result.filter(row => row.manifest.title.toLowerCase().includes(search.toLowerCase()));
}
export async function changes(owner: string, cursor: number) {
  const service = serviceClient();
  const clock = await service.from("cloud_accounts").select("sequence").eq("owner_id", owner).maybeSingle(); db(clock.error);
  const high = clock.data?.sequence ?? 0;
  if (cursor > high) throw new HttpError(409, "Reset the synchronization cursor and reconcile this account.");
  const { data, error } = await service.from("cloud_notebooks").select(fields).eq("owner_id", owner).gt("change_seq", cursor).lte("change_seq", high).order("change_seq").limit(51);
  db(error);
  const records = data!.slice(0, 50);
  return { records, cursor: data!.length > 50 ? records.at(-1)!.change_seq : high, more: data!.length > 50 };
}
export async function downloads(owner: string, id: string) {
  const record = await getCloud(owner, id);
  const urls: Record<string, string> = {};
  await boundedMap(filesIn(record.manifest), async file => { urls[file.key] = await fileURL(owner, file); });
  return { record, urls };
}
export async function commitCloud(owner: string, input: z.infer<typeof commitSchema>): Promise<CloudReceipt> {
  const checked = commitSchema.safeParse(input);
  if (!checked.success) throw new HttpError(400, "Invalid notebook metadata.");
  input = checked.data;
  if (!input.deleted && !input.manifest.pages.length) throw new HttpError(400, "A notebook needs at least one page.");
  const semantic = { ...input, manifest: { ...input.manifest, pages: input.manifest.pages.map(page => ({ ...page, content: { ...page.content, key: "" }, ...(page.image ? { image: { ...page.image, key: "" } } : {}) })) } };
  const hash = sha256(JSON.stringify(input.deleted ? { id: input.id, operationId: input.operationId, baseRevision: input.baseRevision, deleted: true, keepBoth: input.keepBoth } : semantic));
  const service = serviceClient();
  const prior = await service.from("cloud_operations").select("request_hash,receipt").eq("owner_id", owner).eq("operation_id", input.operationId).maybeSingle(); db(prior.error);
  if (prior.data) {
    if (prior.data.request_hash !== hash) throw new HttpError(409, "An operation ID cannot be reused for different edits.");
    return { ...prior.data.receipt, duplicate: true };
  }
  const manifest = structuredClone(input.manifest);
  if (!input.deleted) {
    if (filesIn(manifest).filter(file => file.key.startsWith("staging/")).length > 10) throw new HttpError(400, "Finalize page files in bounded batches before committing metadata.");
    for (const page of manifest.pages) {
      if (page.content.key.startsWith("staging/")) page.content = await publishFile(owner, page.content);
      if (page.image?.key.startsWith("staging/")) page.image = await publishFile(owner, page.image);
    }
    await verifyReferences(owner, filesIn(manifest));
  }
  const conflictId = stableId(`${owner}:${input.operationId}:conflict`);
  const conflictManifest = { ...manifest, title: `${manifest.title.slice(0, 100)} (conflict copy)`, pages: manifest.pages.map(page => ({ ...page, id: stableId(`${conflictId}:${page.id.toLowerCase()}`) })) };
  const { data, error } = await service.rpc("cloud_commit", { p_owner: owner, p_id: input.id, p_operation: input.operationId, p_hash: hash, p_base: input.baseRevision, p_manifest: manifest, p_deleted: input.deleted, p_keep_both: input.keepBoth, p_conflict_id: conflictId, p_conflict_manifest: conflictManifest });
  db(error); return data;
}
export async function assemble(owner: string, record: CloudRecord): Promise<NotebookRecord> {
  const pages = await boundedMap(record.manifest.pages, async page => {
    const content = pageContentSchema.parse(JSON.parse((await fileData(owner, page.content)).toString("utf8")));
    const image = page.image ? { mimeType: page.image.kind as "image/png" | "image/jpeg", data: (await fileData(owner, page.image)).toString("base64") } : undefined;
    return { id: page.id, size: page.size, template: page.template, color: page.color, inheritsStyle: page.inheritsStyle, strokes: content.strokes, text: content.text, ...(image ? { image } : {}) };
  });
  const { title, template, color } = record.manifest;
  return { id: record.id, document: { schemaVersion: 1, title, template, color, pages }, revision: record.revision, mutation_id: record.mutation_id, created_at: record.created_at, updated_at: record.updated_at };
}
export async function storeDocument(owner: string, id: string, document: NotebookDocument, operationId: string, revision: number, keepBoth = false) {
  // Legacy/small-client compatibility. New clients transfer pages directly to B2.
  const parsed = documentSchema.parse(document);
  const manifest: CloudManifest = { version: 1, title: parsed.title, template: parsed.template, color: parsed.color, pages: [] };
  manifest.pages = await boundedMap(parsed.pages, async page => {
    const content = await storeFile(owner, Buffer.from(JSON.stringify({ version: 1, strokes: page.strokes, text: page.text })), "page");
    const image = page.image ? await storeFile(owner, Buffer.from(page.image.data, "base64"), page.image.mimeType) : undefined;
    return { id: page.id, size: page.size, template: page.template, color: page.color, inheritsStyle: page.inheritsStyle, content, ...(image ? { image } : {}) };
  });
  const receipt = await commitCloud(owner, { id, manifest, operationId, baseRevision: revision, deleted: false, keepBoth });
  return { ...await assemble(owner, await getCloud(owner, receipt.id)), duplicate: receipt.duplicate ?? false };
}
export async function legacyCount(owner: string) {
  const { data, error } = await serviceClient().from("mynotes_notebooks").select("id").eq("owner_id", owner).limit(1);
  if (error && ["PGRST205", "42P01"].includes(error.code)) return { available: false };
  db(error); return { available: Boolean(data?.length) };
}
export async function cloudUsage(owner: string) {
  const { data, error } = await serviceClient().rpc("cloud_usage", { p_owner: owner }); db(error); return data;
}
export async function migrateLegacyCloud(owner: string) {
  const service = serviceClient();
  const { data, error } = await service.from("mynotes_notebooks").select("id,document,mutation_id,revision").eq("owner_id", owner).order("id").limit(3);
  if (error && ["PGRST205", "42P01"].includes(error.code)) return { migrated: 0, more: false };
  db(error); let migrated = 0;
  for (const row of data ?? []) {
    await storeDocument(owner, row.id, documentSchema.parse(row.document), stableId(`${owner}:${row.id}:${row.mutation_id}:legacy-cloud`), 0, true);
    // Objects were verified and the operation receipt is durable. Retire only
    // the exact legacy revision we read, preserving concurrent legacy edits.
    const removed = await service.from("mynotes_notebooks").delete().eq("owner_id", owner).eq("id", row.id).eq("revision", row.revision).eq("mutation_id", row.mutation_id).select("id");
    db(removed.error); migrated += removed.data?.length ?? 0;
  }
  return { migrated, more: (await legacyCount(owner)).available };
}

import { NextRequest } from "next/server";
import { z } from "zod";
import { documentSchema } from "@/lib/notebook";
import { authorized, apiJson, apiFailure, HttpError, readJson } from "@/server/http";
import { assemble, commitCloud, getCloud, listCloud, storeDocument } from "@/server/cloud";
import { stableId } from "@/server/storage";
export const dynamic = "force-dynamic";
type Context = { params: Promise<{ path?: string[] }> };
async function notebookId(context: Context) {
  const { path = [] } = await context.params;
  if (path.length > 1 || (path[0] && !z.uuid().safeParse(path[0]).success)) throw new HttpError(404, "Notebook not found.");
  return path[0];
}
export async function GET(request: NextRequest, context: Context) {
  try {
    const auth = await authorized(request), id = await notebookId(context);
    if (id) {
      const record = await getCloud(auth.user.id, id);
      if (record.manifest.pages.reduce((size, page) => size + page.content.bytes + (page.image?.bytes ?? 0), 0) > 3_000_000) throw new HttpError(413, "Use the page-download API for this large notebook.");
      const result = await assemble(auth.user.id, record);
      if (Buffer.byteLength(JSON.stringify(result)) > 3_000_000) throw new HttpError(413, "Use the page-download API for this large notebook.");
      return auth.finish(apiJson(result));
    }
    const rows = await listCloud(auth.user.id, (request.nextUrl.searchParams.get("search") ?? "").slice(0, 200));
    return auth.finish(apiJson(rows.map(row => ({ id: row.id, title: row.manifest.title, template: row.manifest.template, color: row.manifest.color, pageCount: row.manifest.pages.length, updated_at: row.updated_at, text: "" }))));
  } catch (error) { return apiFailure(error, request); }
}
async function write(request: NextRequest, context: Context, creating: boolean) {
  try {
    const auth = await authorized(request), id = await notebookId(context);
    const input = z.object({ id: z.uuid(), document: documentSchema, mutationId: z.uuid(), revision: z.number().int().positive().optional() }).safeParse(await readJson(request));
    if (!input.success) throw new HttpError(400, "Invalid notebook document.");
    if (creating ? Boolean(id) : id !== input.data.id) throw new HttpError(400, "Notebook ID does not match.");
    if (!creating) await getCloud(auth.user.id, input.data.id);
    const result = await storeDocument(auth.user.id, input.data.id, input.data.document, input.data.mutationId, creating ? 0 : input.data.revision ?? 0);
    return auth.finish(apiJson(result, creating && !result.duplicate ? 201 : 200));
  } catch (error) { return apiFailure(error, request); }
}
export const POST = (request: NextRequest, context: Context) => write(request, context, true);
export const PUT = (request: NextRequest, context: Context) => write(request, context, false);
export async function DELETE(request: NextRequest, context: Context) {
  try {
    const auth = await authorized(request), id = await notebookId(context);
    const input = z.object({ revision: z.number().int().positive() }).safeParse(await readJson(request, 1024));
    if (!id || !input.success) throw new HttpError(400, "A notebook and revision are required.");
    const record = await getCloud(auth.user.id, id, true).catch(error => { if (error instanceof HttpError && error.status === 404) throw new HttpError(409, "Notebook unavailable or already deleted."); throw error; });
    await commitCloud(auth.user.id, { id, operationId: stableId(`${auth.user.id}:${id}:${input.data.revision}:delete`), baseRevision: input.data.revision, manifest: record.manifest, deleted: true, keepBoth: false });
    return auth.finish(apiJson({ deleted: true }));
  } catch (error) { return apiFailure(error, request); }
}

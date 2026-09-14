import { NextRequest } from "next/server";
import { z } from "zod";
import { documentSchema } from "@/lib/notebook";
import { authorized, apiJson, apiFailure, HttpError, readJson } from "@/server/http";
import { serviceClient } from "@/server/service";

export const dynamic = "force-dynamic";
type Context = { params: Promise<{ path?: string[] }> };
const fields = "id,document,revision,mutation_id,created_at,updated_at";
const inputSchema = z.object({ id: z.uuid(), document: documentSchema, mutationId: z.uuid(), revision: z.number().int().positive().optional() });
function dbError(error: { code?: string } | null) {
  if (!error) return;
  if (error.code === "PGRST205" || error.code === "42P01") throw new HttpError(503, "Notebook storage is not configured. Run supabase/migrations/001_notebooks.sql in the Supabase SQL Editor.");
  throw new HttpError(503, "The notebook could not be saved or loaded. Please retry.");
}
async function notebookId(context: Context) {
  const { path = [] } = await context.params;
  if (path.length > 1 || (path[0] && !z.uuid().safeParse(path[0]).success)) throw new HttpError(404, "Notebook not found.");
  return path[0];
}

export async function GET(request: NextRequest, context: Context) {
  try {
    const auth = await authorized(request);
    const id = await notebookId(context);
    const query = serviceClient().from("mynotes_notebooks").select(fields).eq("owner_id", auth.user.id);
    if (id) {
      const { data, error } = await query.eq("id", id).maybeSingle();
      dbError(error);
      if (!data) throw new HttpError(404, "Notebook not found.");
      return auth.finish(apiJson(data));
    }
    // Fetch bounded batches so a large library cannot be silently truncated by PostgREST.
    const rows = [];
    const search = (request.nextUrl.searchParams.get("search") ?? "").trim().slice(0, 200);
    for (let offset = 0; ; offset += 100) {
      let listing = serviceClient().from("mynotes_notebooks").select("id,title,template,color,page_count,updated_at").eq("owner_id", auth.user.id).order("updated_at", { ascending: false }).order("id").range(offset, offset + 99);
      if (search) listing = listing.ilike("search_text", `%${search.replace(/[\\%_]/g, value => `\\${value}`)}%`);
      const { data, error } = await listing;
      dbError(error);
      rows.push(...(data ?? []));
      if (!data || data.length < 100) break;
    }
    return auth.finish(apiJson(rows.map(row => ({ ...row, pageCount: row.page_count, text: "" }))));
  } catch (error) { return apiFailure(error); }
}

async function write(request: NextRequest, context: Context, creating: boolean) {
  try {
    const auth = await authorized(request);
    const id = await notebookId(context);
    const parsed = inputSchema.safeParse(await readJson(request));
    if (!parsed.success) throw new HttpError(400, "The notebook document is invalid.");
    const input = parsed.data;
    if (creating ? Boolean(id) : id !== input.id) throw new HttpError(400, "Notebook ID does not match the request.");
    const service = serviceClient();
    const { data: existing, error: readError } = await service.from("mynotes_notebooks").select(fields).eq("id", input.id).eq("owner_id", auth.user.id).maybeSingle();
    dbError(readError);
    if (existing?.mutation_id === input.mutationId) return auth.finish(apiJson(existing));
    if (creating) {
      if (existing) throw new HttpError(409, "A notebook with this ID already exists.");
      const { data, error } = await service.from("mynotes_notebooks").insert({ id: input.id, owner_id: auth.user.id, document: input.document, mutation_id: input.mutationId }).select(fields).single();
      if (error?.code === "23505") {
        const { data: retried, error: retryError } = await service.from("mynotes_notebooks").select(fields).eq("id", input.id).eq("owner_id", auth.user.id).maybeSingle();
        dbError(retryError);
        if (retried?.mutation_id === input.mutationId) return auth.finish(apiJson(retried));
        throw new HttpError(409, "This notebook already exists. Reload your library.");
      }
      dbError(error);
      return auth.finish(apiJson(data, 201));
    }
    if (!existing) throw new HttpError(404, "This notebook was deleted or is unavailable. Your local draft can be exported or saved as a new notebook.");
    if (!input.revision || existing.revision !== input.revision) return auth.finish(apiJson({ error: "This notebook changed on another device. Save your draft as a conflict copy to preserve both versions.", conflict: true }, 409));
    const { data, error } = await service.from("mynotes_notebooks").update({ document: input.document, revision: input.revision + 1, mutation_id: input.mutationId, updated_at: new Date().toISOString() }).eq("id", input.id).eq("owner_id", auth.user.id).eq("revision", input.revision).select(fields).maybeSingle();
    dbError(error);
    if (!data) {
      const { data: retried, error: retryError } = await service.from("mynotes_notebooks").select(fields).eq("id", input.id).eq("owner_id", auth.user.id).maybeSingle();
      dbError(retryError);
      if (retried?.mutation_id === input.mutationId) return auth.finish(apiJson(retried));
      return auth.finish(apiJson({ error: "A newer version was saved. Preserve your edits as a conflict copy.", conflict: true }, 409));
    }
    return auth.finish(apiJson(data));
  } catch (error) { return apiFailure(error); }
}
export const POST = (request: NextRequest, context: Context) => write(request, context, true);
export const PUT = (request: NextRequest, context: Context) => write(request, context, false);

export async function DELETE(request: NextRequest, context: Context) {
  try {
    const auth = await authorized(request);
    const id = await notebookId(context);
    const parsed = z.object({ revision: z.number().int().positive() }).safeParse(await readJson(request, 1024));
    if (!id || !parsed.success) throw new HttpError(400, "A notebook and revision are required.");
    const { data, error } = await serviceClient().from("mynotes_notebooks").delete().eq("id", id).eq("owner_id", auth.user.id).eq("revision", parsed.data.revision).select("id");
    dbError(error);
    if (!data?.length) throw new HttpError(409, "The notebook changed or was already deleted. Reload before deleting.");
    return auth.finish(apiJson({ deleted: true }));
  } catch (error) { return apiFailure(error); }
}

import { createHash } from "node:crypto";
import { NextRequest } from "next/server";
import { z } from "zod";
import { parseNotebookImport } from "@/lib/notebook-import";
import { authorized, apiFailure, apiJson, HttpError, readJson } from "@/server/http";
import { serviceClient } from "@/server/service";

export async function POST(request: NextRequest) {
  try {
    const auth = await authorized(request);
    const input = z.object({ value: z.unknown(), filename: z.string().max(255), id: z.uuid(), mutationId: z.uuid() }).safeParse(await readJson(request));
    if (!input.success) throw new HttpError(400, "Invalid import request.");
    let imported;
    try { imported = parseNotebookImport(input.data.value, input.data.filename); }
    catch (error) { throw new HttpError(400, (error as Error).message); }
    let id = input.data.id;
    if (imported.sourceId) {
      // Content-addressed within the verified account: retries never overwrite
      // cloud edits, and a changed local export becomes a separate notebook.
      const bytes = createHash("sha256").update(`${auth.user.id}:mac:${imported.sourceId}:${JSON.stringify(imported.document)}`).digest().subarray(0, 16);
      bytes[6] = (bytes[6] & 15) | 0x50; bytes[8] = (bytes[8] & 63) | 0x80;
      const hex = bytes.toString("hex");
      id = `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
    }
    const service = serviceClient();
    const fields = "id,document,revision,mutation_id,created_at,updated_at";
    const { data, error } = await service.from("mynotes_notebooks").insert({ id, owner_id: auth.user.id, document: imported.document, mutation_id: input.data.mutationId }).select(fields).single();
    if (!error) return auth.finish(apiJson(data, 201));
    if (error.code === "23505") {
      const { data: existing, error: readError } = await service.from("mynotes_notebooks").select(fields).eq("id", id).eq("owner_id", auth.user.id).maybeSingle();
      if (!readError && existing && (imported.sourceId || existing.mutation_id === input.data.mutationId)) return auth.finish(apiJson(existing));
      throw new HttpError(409, "This import ID is already in use. Reopen the import dialog.");
    }
    throw new HttpError(503, "Import could not be saved. Check notebook database setup and retry the same file.");
  } catch (error) { return apiFailure(error); }
}

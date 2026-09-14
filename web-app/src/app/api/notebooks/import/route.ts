import { createHash } from "node:crypto";
import { NextRequest } from "next/server";
import { z } from "zod";
import { parseNotebookImport } from "@/lib/notebook-import";
import { authorized, apiFailure, apiJson, HttpError, readJson } from "@/server/http";
import { assemble, getCloud, storeDocument } from "@/server/cloud";

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
    const existing = await getCloud(auth.user.id, id, true).catch(error => { if (error instanceof HttpError && error.status === 404) return null; throw error; });
    if (existing && !existing.deleted && (imported.sourceId || existing.mutation_id === input.data.mutationId)) return auth.finish(apiJson(await assemble(auth.user.id, existing)));
    const record = await storeDocument(auth.user.id, id, imported.document, input.data.mutationId, 0, existing?.deleted ?? false);
    return auth.finish(apiJson(record, 201));
  } catch (error) { return apiFailure(error, request); }
}

import { NextRequest } from "next/server";
import { z } from "zod";
import { apiFailure, apiJson, authorized, HttpError, readJson } from "@/server/http";
import { changes, cloudUsage, commitCloud, commitSchema, downloads, getCloud, legacyCount, listCloud, migrateLegacyCloud } from "@/server/cloud";
import { cleanupObjects, publishFile, uploadURL } from "@/server/storage";
import { fileSchema, MAX_ASSET_BYTES } from "@/lib/cloud";

export const dynamic = "force-dynamic";
export const maxDuration = 60;
type Context = { params: Promise<{ path?: string[] }> };
export async function GET(request: NextRequest, context: Context) {
  try {
    const auth = await authorized(request); const { path = [] } = await context.params;
    if (path.length === 1 && path[0] === "legacy") return auth.finish(apiJson(await legacyCount(auth.user.id)));
    if (path.length === 1 && path[0] === "usage") return auth.finish(apiJson(await cloudUsage(auth.user.id)));
    if (path.length === 0) {
      const cursor = z.coerce.number().int().nonnegative().safeParse(request.nextUrl.searchParams.get("cursor") ?? "0");
      if (!cursor.success) throw new HttpError(400, "Invalid cursor.");
      return auth.finish(apiJson(await changes(auth.user.id, cursor.data)));
    }
    if (path[0] === "notebooks" && path.length === 1) return auth.finish(apiJson(await listCloud(auth.user.id)));
    if (path[0] === "notebooks" && path.length === 2 && z.uuid().safeParse(path[1]).success) return auth.finish(apiJson(request.nextUrl.searchParams.has("downloads") ? await downloads(auth.user.id, path[1]) : await getCloud(auth.user.id, path[1], true)));
    throw new HttpError(404, "Unknown synchronization endpoint.");
  } catch (error) { return apiFailure(error, request); }
}
export async function POST(request: NextRequest, context: Context) {
  try {
    const auth = await authorized(request); const { path = [] } = await context.params;
    if (path.length !== 1) throw new HttpError(404, "Unknown synchronization endpoint.");
    const body = await readJson(request, 500_000);
    if (path[0] === "files") {
      const input = z.object({ files: z.array(fileSchema).min(1).max(10) }).safeParse(body);
      if (!input.success) throw new HttpError(400, "Invalid file descriptors.");
      const files = [];
      for (const file of input.data.files) files.push(await publishFile(auth.user.id, file));
      return auth.finish(apiJson({ files }));
    }
    if (path[0] === "legacy") return auth.finish(apiJson(await migrateLegacyCloud(auth.user.id)));
    if (path[0] === "uploads") {
      const input = z.object({ operationId: z.uuid(), files: z.array(fileSchema.omit({ key: true }).extend({ id: z.uuid() })).min(1).max(50) }).safeParse(body);
      if (!input.success) throw new HttpError(400, "Invalid upload descriptors.");
      if (input.data.files.some(file => file.kind !== "page" && file.bytes > MAX_ASSET_BYTES)) throw new HttpError(413, "An image exceeds the 8 MB limit.");
      await cloudUsage(auth.user.id); // Fail before issuing uploads if the migration is missing.
      const files = [];
      for (const file of input.data.files) files.push({ id: file.id, ...await uploadURL(auth.user.id, input.data.operationId, file, file.id) });
      return auth.finish(apiJson({ files }));
    }
    if (path[0] === "commit") {
      const input = commitSchema.safeParse(body);
      if (!input.success) throw new HttpError(400, "Invalid notebook metadata.");
      return auth.finish(apiJson(await commitCloud(auth.user.id, input.data)));
    }
    if (path[0] === "cleanup") return auth.finish(apiJson(await cleanupObjects(auth.user.id)));
    throw new HttpError(404, "Unknown synchronization endpoint.");
  } catch (error) { return apiFailure(error, request); }
}
